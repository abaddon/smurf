#!/usr/bin/env python3
"""Wiki lint — runs as part of close-loop.py and writes docs/wiki/health.md.

Three checks:

1. Cite-check
   - Walks docs/adr/*.md `## Context` and docs/stories/**/*.feature
     `## Source` blocks. Extracts every referenced repo path. `test -e`
     each.
   - Missing cite on an ADR with `Status: accepted`  → FAIL
   - Missing cite on a `proposed` / `superseded` ADR → WARN
   - Missing cite on a story → WARN

2. Port-conflict
   - Extracts the first port name (text before the first colon on the
     first `- ` bullet) from each non-superseded ADR's
     `## Ports / Adapters` section. If two different ADRs declare the
     same port name with different one-line descriptions and neither
     supersedes the other → WARN.

3. Orphan stories
   - Story files with `Status: proposed` whose mtime is older than
     `wiki.lint_orphan_days` (default 30) → INFO. Stories under
     `docs/stories/bootstrap-*/` are exempt.

Exit codes:
   0  written; no FAIL findings (or wiki.enabled=false)
   2  written; at least one FAIL finding
   1  IO / parse error
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
PLUGIN_ROOT = Path(os.environ.get("CLAUDE_PLUGIN_ROOT", Path(__file__).resolve().parent.parent))

from _policy import load_policy  # shared policy parser (same dir)




# ---------------- ADR parsing ----------------

ADR_PATH_RE = re.compile(r"`([^`]+)`|(?:^|\s)((?:src|tests|docs|plugin|scripts|cmd|app|lib)/[\w./\-]+)")


def parse_adr(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    status = "unknown"
    supersedes = None
    for line in text.splitlines()[:20]:
        m = re.match(r"\*\*Status\*\*:\s*(.+?)\s*$", line)
        if m:
            v = m.group(1).strip()
            status = v.split()[0]
            sup = re.match(r"superseded\s+by\s+(\S+)", v, re.IGNORECASE)
            if sup:
                supersedes = sup.group(1)
    context = _extract_section(text, "Context")
    ports_section = _extract_section(text, "Ports / Adapters") or _extract_section(text, "Ports") or _extract_section(text, "Ports / Adapters / Modules")
    cite_paths = _extract_paths(context)
    ports = _extract_first_port(ports_section)
    return {
        "path": path,
        "status": status,
        "supersedes": supersedes,
        "cite_paths": cite_paths,
        "ports": ports,
    }


def _extract_section(text: str, name: str) -> str:
    pattern = re.compile(rf"^##\s+{re.escape(name)}\s*$", re.MULTILINE)
    m = pattern.search(text)
    if not m:
        return ""
    start = m.end()
    next_h = re.search(r"^##\s+", text[start:], re.MULTILINE)
    end = start + next_h.start() if next_h else len(text)
    return text[start:end]


def _extract_paths(block: str) -> list[str]:
    out: list[str] = []
    for m in ADR_PATH_RE.finditer(block):
        for grp in m.groups():
            if not grp:
                continue
            if "/" in grp and "." in grp.rsplit("/", 1)[-1]:
                out.append(grp.strip().rstrip(".,;)"))
    seen, dedup = set(), []
    for p in out:
        if p not in seen:
            seen.add(p)
            dedup.append(p)
    return dedup


def _extract_first_port(block: str) -> list[tuple[str, str]]:
    """Return list of (port_name, description) tuples from the section."""
    ports = []
    for raw in block.splitlines():
        line = raw.strip()
        if line.startswith("- "):
            body = line[2:]
            if ":" in body:
                name, _, rest = body.partition(":")
                name = name.strip().strip("`")
                desc = rest.strip()
                if name:
                    ports.append((name, desc))
    return ports


# ---------------- Story parsing ----------------


def parse_story(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    status = "unknown"
    in_status = False
    for raw in text.splitlines():
        line = raw.rstrip()
        if line.lower().startswith("## status"):
            in_status = True
            continue
        if in_status:
            s = line.strip()
            if not s:
                continue
            if s.startswith("- "):
                status = s[2:].strip().split()[0]
            break
    source_section = _extract_section(text, "Source")
    cite_paths = _extract_paths(source_section)
    return {
        "path": path,
        "status": status,
        "cite_paths": cite_paths,
        "mtime": path.stat().st_mtime,
    }


# ---------------- Checks ----------------


def check_cites(adrs: list[dict], stories: list[dict]) -> list[dict]:
    findings: list[dict] = []
    for a in adrs:
        for c in a["cite_paths"]:
            target = PROJECT_ROOT / c
            if target.exists():
                continue
            severity = "FAIL" if a["status"] == "accepted" else "WARN"
            findings.append({
                "severity": severity,
                "category": "cite",
                "where": str(a["path"].relative_to(PROJECT_ROOT)),
                "message": f"missing cited path `{c}` (ADR status={a['status']})",
            })
    for s in stories:
        for c in s["cite_paths"]:
            target = PROJECT_ROOT / c
            if target.exists():
                continue
            findings.append({
                "severity": "WARN",
                "category": "cite",
                "where": str(s["path"].relative_to(PROJECT_ROOT)),
                "message": f"missing cited path `{c}` (story status={s['status']})",
            })
    return findings


def check_port_conflicts(adrs: list[dict]) -> list[dict]:
    findings: list[dict] = []
    active = [a for a in adrs if a["status"] != "superseded" and not a["supersedes"]]
    seen: dict[str, list[tuple[Path, str]]] = {}
    for a in active:
        for name, desc in a["ports"]:
            seen.setdefault(name, []).append((a["path"], desc))
    for name, entries in seen.items():
        if len(entries) < 2:
            continue
        descs = {d for _, d in entries}
        if len(descs) <= 1:
            continue
        paths = ", ".join(sorted(str(p.relative_to(PROJECT_ROOT)) for p, _ in entries))
        findings.append({
            "severity": "WARN",
            "category": "port-conflict",
            "where": paths,
            "message": f"port `{name}` declared with differing descriptions across active ADRs",
        })
    return findings


def check_orphan_stories(stories: list[dict], days: int, now: float | None = None) -> list[dict]:
    findings: list[dict] = []
    now = now or time.time()
    cutoff = now - days * 86400
    for s in stories:
        if s["status"] != "proposed":
            continue
        if "bootstrap-" in str(s["path"]):
            continue
        if s["mtime"] > cutoff:
            continue
        age_days = int((now - s["mtime"]) // 86400)
        findings.append({
            "severity": "INFO",
            "category": "orphan",
            "where": str(s["path"].relative_to(PROJECT_ROOT)),
            "message": f"Status: proposed for {age_days} days (threshold {days})",
        })
    return findings


# ---------------- Render ----------------


def render(findings: list[dict], counts: dict) -> str:
    buckets = {"FAIL": [], "WARN": [], "INFO": []}
    for f in findings:
        buckets[f["severity"]].append(f)

    out = ["# Smurf — wiki health", ""]
    out.append("Auto-generated by `scripts/wiki_lint.py`. Re-run via `/smurf:close-loop`.")
    out.append(f"Inputs scanned: ADRs={counts['adrs']} stories={counts['stories']}")
    out.append("")
    out.append(f"Summary: FAIL={len(buckets['FAIL'])} WARN={len(buckets['WARN'])} INFO={len(buckets['INFO'])}")
    out.append("")
    for sev in ("FAIL", "WARN", "INFO"):
        out.append(f"## {sev}")
        out.append("")
        if not buckets[sev]:
            out.append("_none_")
            out.append("")
            continue
        for f in sorted(buckets[sev], key=lambda x: (x["category"], x["where"])):
            out.append(f"- [{f['category']}] `{f['where']}` — {f['message']}")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


# ---------------- Entry point ----------------


def run_lint() -> tuple[list[dict], dict]:
    adr_dir = PROJECT_ROOT / "docs" / "adr"
    story_dir = PROJECT_ROOT / "docs" / "stories"
    adrs = [parse_adr(p) for p in sorted(adr_dir.glob("*.md"))] if adr_dir.is_dir() else []
    stories = [parse_story(p) for p in sorted(story_dir.glob("*/*.feature"))] if story_dir.is_dir() else []

    policy = load_policy(PROJECT_ROOT, PLUGIN_ROOT)
    wiki = policy.get("wiki") if isinstance(policy.get("wiki"), dict) else {}
    days = (wiki or {}).get("lint_orphan_days", 30)

    findings = []
    findings.extend(check_cites(adrs, stories))
    findings.extend(check_port_conflicts(adrs))
    findings.extend(check_orphan_stories(stories, days))
    return findings, {"adrs": len(adrs), "stories": len(stories)}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", help="override health.md output path (for tests)")
    p.add_argument("--dry-run", action="store_true",
                   help="print findings to stdout, do not write file")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    policy = load_policy(PROJECT_ROOT, PLUGIN_ROOT)
    wiki = policy.get("wiki") if isinstance(policy.get("wiki"), dict) else {}
    if wiki and wiki.get("enabled") is False:
        print("[wiki-lint] wiki.enabled=false; skipping")
        return 0

    findings, counts = run_lint()
    rendered = render(findings, counts)

    out_rel = args.out or (wiki or {}).get("health_path", "docs/wiki/health.md")
    out_path = Path(args.out) if args.out and os.path.isabs(args.out) else PROJECT_ROOT / out_rel

    if args.dry_run:
        sys.stdout.write(rendered)
    else:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = out_path.with_suffix(out_path.suffix + ".tmp")
        tmp.write_text(rendered, encoding="utf-8")
        os.replace(tmp, out_path)
        print(f"[wiki-lint] wrote {out_path.relative_to(PROJECT_ROOT) if out_path.is_relative_to(PROJECT_ROOT) else out_path}")

    fail_count = sum(1 for f in findings if f["severity"] == "FAIL")
    if fail_count:
        print(f"[wiki-lint] {fail_count} FAIL finding(s); exit 2", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

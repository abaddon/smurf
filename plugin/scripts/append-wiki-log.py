#!/usr/bin/env python3
"""Append one digest row to docs/wiki/log.md.

Called by the orchestrator at the end of every run, by autonomous-run.sh
as an interrupted-run fallback, and by the escalation path in
orchestrator.md. Idempotent: if a row with the same <ts> already exists,
the script exits 0 with "skipped" and writes nothing.

Race safety: the row is built entirely in memory, then issued as a
single os.write() to a file descriptor opened with O_APPEND. POSIX
guarantees writes <PIPE_BUF (4096B) under O_APPEND are atomic, so two
concurrent runs with distinct <ts> values produce two distinct,
non-interleaved rows. Same <ts> can never occur (timestamps are run-dir
names, unique per run).

Usage:
    append-wiki-log.py --ts 20260517T120000Z \\
                       --goal "Add scripts/version.sh" \\
                       --waves "1,2,3,4,5,6,7" \\
                       --qa-iterations 1 \\
                       --status green \\
                       --pr-url https://github.com/.../pull/42 \\
                       --head-sha abc1234

Status values (free-form, but conventionally one of):
    green      — all waves succeeded
    red        — QA red after max_qa_iterations
    escalated  — orchestrator wrote escalation.md and exited
    interrupted — autonomous-run.sh watchdog or SIGTERM
    terminated — close-loop fallback path

Exit codes:
    0  appended or skipped (idempotent no-op); also when wiki.enabled=false
    1  argparse / IO error
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
PLUGIN_ROOT = Path(os.environ.get("CLAUDE_PLUGIN_ROOT", Path(__file__).resolve().parent.parent))

HEADER = (
    "# Smurf — run log\n"
    "\n"
    "Append-only digest. One row per orchestrator run. Maintained by\n"
    "`scripts/append-wiki-log.py`; see `docs/specs/15-wiki.md`.\n"
    "\n"
    "| ts | goal | waves | qa_iterations | status | pr_url | head_sha |\n"
    "|---|---|---|---|---|---|---|\n"
)


def load_policy() -> dict:
    """Resolve wiki.* from project override, falling back to plugin default."""
    candidates = [
        PROJECT_ROOT / ".claude" / "policy.yaml",
        PLUGIN_ROOT / "policy.yaml",
    ]
    for p in candidates:
        if p.is_file():
            try:
                import yaml  # type: ignore
                return yaml.safe_load(p.read_text()) or {}
            except ImportError:
                return _parse_minimal_yaml(p.read_text())
    return {}


def _parse_minimal_yaml(text: str) -> dict:
    """Extract just the wiki: block without depending on PyYAML."""
    wiki: dict = {}
    in_wiki = False
    for raw in text.splitlines():
        if raw.startswith("wiki:"):
            in_wiki = True
            continue
        if in_wiki:
            if raw and not raw.startswith(("  ", "\t")):
                break
            if ":" in raw:
                k, _, v = raw.strip().partition(":")
                v = v.strip().strip('"').strip("'")
                if v.lower() in ("true", "false"):
                    wiki[k] = v.lower() == "true"
                elif v.isdigit():
                    wiki[k] = int(v)
                elif v:
                    wiki[k] = v
    return {"wiki": wiki} if wiki else {}


def truncate_goal(goal: str, limit: int = 80) -> str:
    """Single-line, escaped for markdown table, ≤limit chars."""
    one_line = " ".join(goal.split())
    one_line = one_line.replace("|", "\\|")
    if len(one_line) > limit:
        one_line = one_line[: limit - 1].rstrip() + "…"
    return one_line


def already_logged(log_path: Path, ts: str) -> bool:
    if not log_path.is_file():
        return False
    marker = f"| {ts} |"
    with log_path.open("r", encoding="utf-8") as f:
        for line in f:
            if line.startswith(marker):
                return True
    return False


def ensure_header(log_path: Path) -> None:
    if log_path.is_file():
        return
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(HEADER, encoding="utf-8")


def append_row(log_path: Path, row: str) -> None:
    """Single atomic write under O_APPEND (POSIX guarantees <PIPE_BUF atomicity)."""
    data = row.encode("utf-8")
    fd = os.open(log_path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ts", required=True)
    p.add_argument("--goal", required=True)
    p.add_argument("--waves", default="-")
    p.add_argument("--qa-iterations", default="0")
    p.add_argument("--status", required=True)
    p.add_argument("--pr-url", default="-")
    p.add_argument("--head-sha", default="-")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    policy = load_policy()
    wiki = (policy.get("wiki") or {}) if isinstance(policy.get("wiki"), dict) else {}
    if wiki.get("enabled") is False:
        print("[append-wiki-log] wiki.enabled=false; skipping")
        return 0

    log_rel = wiki.get("log_path", "docs/wiki/log.md")
    log_path = PROJECT_ROOT / log_rel

    if already_logged(log_path, args.ts):
        print(f"[append-wiki-log] row for ts={args.ts} already present; skipping")
        return 0

    ensure_header(log_path)

    row = "| {ts} | {goal} | {waves} | {qa} | {status} | {pr} | {sha} |\n".format(
        ts=args.ts,
        goal=truncate_goal(args.goal),
        waves=args.waves or "-",
        qa=args.qa_iterations or "0",
        status=args.status,
        pr=args.pr_url or "-",
        sha=args.head_sha or "-",
    )

    append_row(log_path, row)
    print(f"[append-wiki-log] appended ts={args.ts} to {log_rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

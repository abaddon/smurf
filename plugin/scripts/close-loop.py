#!/usr/bin/env python3
"""Cross-run feedback loop.

Invoked at the end of `autonomous-run.sh` (or manually via `/close-loop`).
Shells out to `claude -p` with read-only access to MCP servers (github,
sentry, linear). The single Claude call writes
`docs/feedback/<YYYY-MM-DD>.md` and exits.

Why shell out instead of calling APIs directly?
- MCP servers are accessible only inside a Claude Code session.
- A direct REST approach would duplicate auth + retry + rate-limit logic.
- A scoped Claude call inherits the same allowedTools fence we use for
  the orchestrator, so blast radius is identical.

The product-owner reads the resulting file at the start of the next run.

Usage:
    python3 scripts/close-loop.py [--window 7d] [--dry-run]

Exit codes:
    0  success (file written, or skipped because today's file already exists)
    1  preflight failure (claude not on PATH, etc.)
    2  claude returned non-zero
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
from pathlib import Path

# Run inside the user's project so MCP servers and feedback files land
# in the right place. CLAUDE_PROJECT_DIR is set by Claude Code; fall back
# to the current working directory if invoked manually.
PROJECT_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
FEEDBACK_DIR = PROJECT_ROOT / "docs" / "feedback"

# Deliberate script-level constants, not policy.yaml keys: close-loop is a
# fixed-scope digest (one file out, read-only sources), not an orchestrator
# run governed by the policy caps. smurf.md's "caps live in policy.yaml"
# rule applies to agent/orchestrator runs.
CLAUDE_MAX_TURNS = "20"
CLAUDE_BUDGET_USD = "1.50"

PROMPT_TEMPLATE = """Read-only analytics summary for the last {window}.

Write a single markdown file at docs/feedback/{date}.md with this exact
structure (replace placeholders; if a section has no data, write
"unknown — needs <instrumentation>"):

# Feedback digest — last {window}

## Top 5 issues
| # | source | title | link | rationale |

(Source the data from `mcp__github` `list_issues` ordered by reaction
count; include only issues opened or updated in the window. If the MCP
server is unavailable, write "unknown — github MCP not configured".)

## Top 3 churn / error signals
- (Source from `mcp__sentry` if configured; else "unknown".)

## Adoption deltas
- MAU: unknown — needs analytics MCP
- Conversion: unknown — needs analytics MCP

## Top support themes
- (Source from `mcp__linear` if configured; else "unknown".)

## Suggested next-sprint priorities
- P1: <one-line story seed grounded in the data above>
- P2: ...
- P3: ...

Constraints:
- Do NOT modify any file other than docs/feedback/{date}.md.
- Do NOT call any write/POST tools on external systems.
- Cite the source URL or query for every datum.
- Keep the file under 200 lines.
"""


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--window", default="7d",
                   help="time window (e.g. 7d, 14d, 30d)")
    p.add_argument("--dry-run", action="store_true",
                   help="print the prompt and exit; don't call claude")
    p.add_argument("--force", action="store_true",
                   help="overwrite today's feedback file if it exists")
    return p.parse_args()


def run_wiki_lint() -> int:
    """Invoke wiki_lint.py in-process. Returns its exit code (0 or 2)."""
    here = Path(__file__).resolve().parent
    lint_script = here / "wiki_lint.py"
    if not lint_script.is_file():
        return 0  # no lint script means feature not deployed; not an error
    try:
        return subprocess.run(
            [sys.executable, str(lint_script)],
            cwd=PROJECT_ROOT,
            env=os.environ.copy(),
        ).returncode
    except Exception as exc:  # noqa: BLE001
        print(f"[close-loop] wiki_lint invocation failed: {exc}", file=sys.stderr)
        return 0  # don't let lint errors mask the rest of close-loop


def main() -> int:
    args = parse_args()
    today = dt.date.today().isoformat()
    out_path = FEEDBACK_DIR / f"{today}.md"

    # Wiki lint runs first (cheap, deterministic, no network). Its FAIL
    # exit propagates to our own exit at the end. We do NOT abort the
    # LLM digest on lint findings — both artifacts are useful.
    lint_rc = run_wiki_lint()

    if out_path.exists() and not args.force:
        print(f"[close-loop] {out_path} already exists; skipping LLM digest (use --force to overwrite)")
        return 2 if lint_rc == 2 else 0

    FEEDBACK_DIR.mkdir(parents=True, exist_ok=True)

    prompt = PROMPT_TEMPLATE.format(window=args.window, date=today)

    if args.dry_run:
        print(prompt)
        return 2 if lint_rc == 2 else 0

    if shutil.which("claude") is None:
        print("[close-loop] ERROR: 'claude' not on PATH", file=sys.stderr)
        return 1

    cmd = [
        "claude", "-p", prompt,
        # Read-only MCP surface: name the specific github read tools instead
        # of the whole server (which includes write tools the contract bans).
        # sentry/linear stay server-level: their tool names depend on the
        # user-supplied server config, and both are read-oriented sources.
        "--allowedTools",
        "Read,Write,"
        "mcp__github__list_issues,mcp__github__get_issue,mcp__github__search_issues,"
        "mcp__sentry,mcp__linear",
        "--max-turns", CLAUDE_MAX_TURNS,
        "--max-budget-usd", CLAUDE_BUDGET_USD,
        "--output-format", "stream-json",
        "--verbose",  # required by `claude -p` whenever output-format is stream-json
    ]

    print(f"[close-loop] writing {out_path}")
    rc = subprocess.run(cmd, cwd=PROJECT_ROOT, env=os.environ.copy()).returncode

    if rc != 0:
        print(f"[close-loop] claude exited {rc}", file=sys.stderr)
        return 2

    if not out_path.exists():
        print(f"[close-loop] WARNING: claude exited 0 but {out_path} was not written", file=sys.stderr)
        # Don't fail hard — the run still produced something.

    return 2 if lint_rc == 2 else 0


if __name__ == "__main__":
    sys.exit(main())

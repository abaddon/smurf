---
description: Run scripts/close-loop.py to gather analytics + GitHub issue signal into docs/feedback/<date>.md, consumed by product-owner at the next kickoff.
argument-hint: [--window 7d]
---

The close-loop script (Phase 7+) shells out to `claude -p` with read-only
access to MCP servers (github, sentry, linear) and writes a single
`docs/feedback/<YYYY-MM-DD>.md`. The product-owner reads this at the
start of the next run.

Run it:

!`python3 scripts/close-loop.py $ARGUMENTS`

After completion, print the path of the new feedback file and a 5-line
summary of its top items.

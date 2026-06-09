---
description: Run scripts/close-loop.py to gather analytics + GitHub issue signal into docs/feedback/<date>.md, consumed by product-owner at the next kickoff.
argument-hint: [--window 7d]
---

The close-loop script (Phase 7+) shells out to `claude -p` with read-only
access to MCP servers (github, sentry, linear) and writes a single
`docs/feedback/<YYYY-MM-DD>.md`. The product-owner reads this at the
start of the next run. It also runs the wiki lint, which rewrites
`docs/wiki/health.md`.

## Run it

Invoke the script with the **Bash tool** — not as a `!`-prefixed
expansion. The nested `claude -p` call can run for several minutes,
longer than an inline expansion should block; use a generous timeout or
run it in the background and wait for completion:

```
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-loop.py" $ARGUMENTS
```

## When it finishes

- Print the path of the new feedback file and a 5-line summary of its
  top items.
- Exit code 2 means the wiki lint found FAIL-level findings — read
  `docs/wiki/health.md` and surface them to the user.

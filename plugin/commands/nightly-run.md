---
description: Trigger an autonomous run — reads the goal from .claude/runs/next-goal.md and runs scripts/autonomous-run.sh in the background.
---

`autonomous-run.sh` reads `.claude/runs/next-goal.md` in the current
project and runs Claude Code headless with the orchestrator. It applies
the watchdog (timeout 4h + SIGTERM partial summary), the budget cap from
`.claude/policy.yaml` (project override) or the plugin default
`${CLAUDE_PLUGIN_ROOT}/policy.yaml`, and writes everything to
`.claude/runs/<ts>/` in the project.

## Run it

Invoke the script with the **Bash tool, in the background** — not as a
`!`-prefixed expansion. The script blocks until the run finishes (up to
the 4h watchdog), far longer than a foreground tool call can wait, so it
must run backgrounded:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/autonomous-run.sh"
```

`autonomous-run.sh` spawns a headless `claude -p` orchestrator loop,
which auto permission mode gates. `/smurf:init` adds an allow rule for it
to this project's `.claude/settings.local.json`. If the command is still
denied, run `/smurf:init` once in this project, or approve the command
when prompted.

## When the run finishes

Summarize from `.claude/runs/<latest>/summary.md` — or
`partial-summary.json` if the watchdog fired:
- goal
- waves executed
- qa_iterations
- final status (green / red / escalated)
- cost
- PR URL (if any)

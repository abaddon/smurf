---
description: Trigger an autonomous run by reading the goal from .claude/runs/next-goal.md and invoking scripts/autonomous-run.sh in the background.
---

The autonomous-run.sh script (Phase 5+) reads `.claude/runs/next-goal.md`
in the current project and runs Claude Code headless with the
orchestrator. It applies the watchdog (timeout 4h + SIGTERM partial
summary), budget cap from `.claude/policy.yaml` (project override) or
the plugin default `${CLAUDE_PLUGIN_ROOT}/policy.yaml`, and writes
everything to `.claude/runs/<ts>/` in the project.

Run it now:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/autonomous-run.sh"`

After the run completes, summarize from `.claude/runs/<latest>/summary.md`:
- goal
- waves executed
- qa_iterations
- final status (green / red / escalated)
- cost
- PR URL (if any)

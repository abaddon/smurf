---
description: Trigger an autonomous run by reading the goal from .claude/runs/next-goal.md and invoking scripts/autonomous-run.sh in the background.
---

The autonomous-run.sh script (Phase 5+) reads `.claude/runs/next-goal.md`
and runs Claude Code headless with the orchestrator. It applies the
watchdog (timeout 4h + SIGTERM partial summary), budget cap from
`.claude/policy.yaml`, and writes everything to `.claude/runs/<ts>/`.

Run it now:

!`bash scripts/autonomous-run.sh`

After the run completes, summarize from `.claude/runs/<latest>/summary.md`:
- goal
- waves executed
- qa_iterations
- final status (green / red / escalated)
- cost
- PR URL (if any)

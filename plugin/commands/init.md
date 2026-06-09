---
description: Scaffold the project-side files smurf needs (verify.sh, docs/rigor-level.md, .claude/runs/next-goal.md). Idempotent — running twice is a no-op.
---

Smurf is loaded by reference from the installed plugin. The plugin
itself does not copy any file into your project. This command creates
the **minimum required project-side stubs** so the orchestrator can
operate. Existing files are never overwritten.

Run it now:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" "${CLAUDE_PROJECT_DIR:-$PWD}"`

After this completes:

1. Replace the no-op `verify.sh` body with your stack's
   tests/build (npm test, pytest, cargo test, mvn verify, etc.).
2. Optionally copy `${CLAUDE_PLUGIN_ROOT}/policy.yaml` to
   `.claude/policy.yaml` and edit `forbidden_paths` /
   `forbidden_patterns` for your project. Without an override the
   plugin's defaults are used.
3. Optionally enable Agent Teams mode by adding
   `"env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" }` to
   `.claude/settings.local.json`.
4. Write your first goal to `.claude/runs/next-goal.md` and run
   `/smurf:kickoff-team "<goal>"`.

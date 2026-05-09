---
description: Decompose a goal into a wave-based DAG and execute via subagents (default mode — workers do not communicate peer-to-peer).
argument-hint: <goal description>
---

@orchestrator: $ARGUMENTS

Use **subagent mode** for this run. For wave 3 (implement), spawn one
`developer` subagent per story sequentially or up to `max_parallel_subagents`
in parallel for independent stories. Workers report back to you, not to
each other. QA runs after all developers report green.

Do NOT spawn an Agent Team for this run, even if the goal contains
parallel features. Use `/kickoff-team` for explicit team mode.

Follow the wave DAG defined in `.claude/agents/orchestrator.md`. Apply
caps from `.claude/policy.yaml`. Branch on `docs/rigor-level.md`.

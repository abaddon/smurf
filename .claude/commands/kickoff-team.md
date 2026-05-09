---
description: Decompose a goal into a wave-based DAG; run wave 3 as an Agent Team so developers, qa, and an architect-advisor can communicate peer-to-peer via SendMessage.
argument-hint: <goal description with parallel features>
---

@orchestrator: $ARGUMENTS

Use **Agent Teams mode** for wave 3. The env var
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is already set in
`.claude/settings.json`, so `Teammate.spawnTeam` and `SendMessage` are
available to you.

For wave 3 specifically:
1. Call `Teammate.spawnTeam` with these teammates:
   - `developer` × N (one per parallel story; each in `isolation: worktree`)
   - `qa-engineer` × 1
   - `architect` × 1, prompted as **architect-advisor** (set `advisor: true`
     in the prompt; this triggers the advisor branch in `architect.md` —
     idle, replies only to SendMessage, max 8 turns, never edits files)
2. Distribute stories via `TaskCreate` (one task per story, assigned to a
   developer).
3. Monitor `TaskList`; let developers `SendMessage architect` for design
   clarifications and `SendMessage developer` (from qa) for failure
   detail.
4. When all tasks reach `done`, `Teammate.cleanup`.
5. Use `budget_usd_team` from `.claude/policy.yaml` (higher than
   subagent-mode budget — Agent Teams burn 7-15× tokens per research §1.7).

All other waves (1, 2, 4, 5) remain subagent mode.

Apply caps from `.claude/policy.yaml`. Branch on `docs/rigor-level.md`.

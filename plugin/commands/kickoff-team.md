---
description: Decompose a goal into a wave-based DAG; run wave 3 as an Agent Team so developers, qa, and an architect-advisor can communicate peer-to-peer via SendMessage.
argument-hint: <goal description with parallel features>
---

@orchestrator: $ARGUMENTS

Use **Agent Teams mode** for wave 3. This requires the env var
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to be set in the user's
`.claude/settings.json` (or `.claude/settings.local.json`). The smurf
plugin manifest cannot set env vars on your behalf — if `TeamCreate`
errors out as unavailable, bail with: "Agent Teams mode requires
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your project's
`.claude/settings.local.json` — set it and re-run." If the tools are
available, `TeamCreate` and `SendMessage` proceed normally.

For wave 3 specifically:
1. Call `TeamCreate` with these teammates:
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
4. When all tasks reach `done`, call `TeamDelete` to release the team.
5. Use `budget_usd_team` from the project's `.claude/policy.yaml` if
   present, otherwise from `${CLAUDE_PLUGIN_ROOT}/policy.yaml` (higher
   than subagent-mode budget — Agent Teams burn 7-15× tokens per
   research §1.7).

All other waves (1, 2, 4, 5, 6, 7) remain subagent mode.

Wave 7 (regenerate `docs/wiki/index.md`) runs at the end in the
orchestrator's main session — never as a teammate. It indexes what has
landed on the project's main branch by that point. Worktree-side
commits that have not yet merged are intentionally invisible: the
index reflects ground truth, not in-flight work. See
`docs/specs/15-wiki.md`.

Apply caps from project's `.claude/policy.yaml` (override) or the plugin
default at `${CLAUDE_PLUGIN_ROOT}/policy.yaml`. Branch on
`docs/rigor-level.md`.

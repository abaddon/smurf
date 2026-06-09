---
description: Default kickoff. Decompose a goal into a wave-based DAG and execute via subagents; wave 3 runs as an Agent Team (peer-to-peer SendMessage) when the host supports it, otherwise degrades to subagent mode.
argument-hint: <goal description>
---

@orchestrator: $ARGUMENTS

This is the **default** smurf kickoff. The baseline execution model is
**subagent mode**: every wave delegates to specialist subagents that report
back to the orchestrator, not to each other. Waves 1, 2, 4, 5, 6, and 7
always run in subagent mode.

For **wave 3 (implement)** the orchestrator ATTEMPTS **Agent Teams mode** so
developers, qa, and an architect-advisor can communicate peer-to-peer via
`SendMessage`. Agent Teams require:
- The env var `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set in the
  user's `.claude/settings.json` (or `.claude/settings.local.json`).
- A host CLI that exposes the FULL Agent-Teams dispatch surface
  in the orchestrator's session — not just `TeamCreate`.

The smurf plugin manifest cannot set env vars on your behalf.

**Capability probe — run BEFORE `TeamCreate`.** Verify every one of
these tools is callable in the current session: `TeamCreate`,
`TeamDelete`, `SendMessage`, `TaskCreate`, `TaskUpdate`, `TaskList`,
`TaskGet`. A partial surface (e.g. `TeamCreate` present but `Task*`
missing) silently degrades wave 3 to sequential inline execution, so
treat any missing tool as "Agent Teams unavailable".

**On a probe miss — DEGRADE, do not bail.** Because this command is the
default kickoff, an unavailable Agent-Teams surface is not a fatal error:
run wave 3 in **subagent mode** instead (spawn one `developer` subagent
per story sequentially or up to `max_parallel_subagents` in parallel for
independent stories; workers report to the orchestrator, not to each
other; QA runs after all developers report green). Make the degradation
visible by logging it to `.claude/runs/<ts>/orchestrator.log` as
`wave-3 agent-teams unavailable missing=<list> action=degrade-to-subagent`,
and note it in the run summary. Use the `budget_usd_subagent` tier for the
degraded wave 3. If the user specifically needs peer-to-peer wave 3, the
log line tells them to set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and use
a host CLI exposing the full `Task*` surface, then re-run
`/smurf:kickoff-team`.

**On a probe pass — wave 3 as an Agent Team:**
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
   than subagent-mode budget — Agent Teams burn 7-15× the tokens).

All other waves (1, 2, 4, 5, 6, 7) remain subagent mode.

Wave 7 (regenerate `docs/wiki/index.md`) runs at the end in the
orchestrator's main session — never as a teammate. It indexes what has
landed on the project's main branch by that point. Worktree-side
commits that have not yet merged are intentionally invisible: the
index reflects ground truth, not in-flight work. See
`docs/specs/15-wiki.md`.

Apply caps from project's `.claude/policy.yaml` (override) or the plugin
default at `${CLAUDE_PLUGIN_ROOT}/policy.yaml`. Branch on
`docs/rigor-level.md` (must exist in the project — run `/smurf:init`
first if not).

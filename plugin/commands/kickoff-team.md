---
description: Default kickoff. Decompose a goal into a wave-based DAG and execute via subagents; wave 3 runs as an Agent Team (peer-to-peer SendMessage) when the host supports it, otherwise degrades to subagent mode.
argument-hint: <goal description>
---

You — the MAIN session — are the smurf orchestrator for this run. Read
`${CLAUDE_PLUGIN_ROOT}/agents/orchestrator.md` now and follow it as your
operating instructions. Do NOT delegate the orchestrator role itself to
a subagent: subagents cannot spawn other subagents, so an @-mentioned
orchestrator could never dispatch its waves.

Goal: $ARGUMENTS

This is the **default** smurf kickoff. The baseline execution model is
**subagent mode**: every wave delegates to specialist subagents that
report back to you, not to each other. Waves 1, 2, 4, 5, 6, and 7
always run in subagent mode.

For **wave 3 (implement)**, ATTEMPT **Agent Teams mode** (peer-to-peer
`SendMessage` between developers, qa-engineer, and an
architect-advisor). The canonical wave-3 procedure lives in
orchestrator.md — the Agent-Teams requirements, the capability probe to
run BEFORE `TeamCreate`, the roster/`TaskCreate` choreography on a
probe pass, and the degrade-to-subagent path on a probe miss are all
defined there; follow them exactly rather than improvising variants.
The contract in one breath:

- Agent Teams needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the
  project's `.claude/settings.json` or `.claude/settings.local.json`
  (the plugin cannot set it for the user) AND the full dispatch
  surface: `TeamCreate`, `TeamDelete`, `SendMessage`, `TaskCreate`,
  `TaskUpdate`, `TaskList`, `TaskGet`.
- Probe miss → DEGRADE to subagent mode for wave 3, visibly (log line
  + run summary note, `budget_usd_subagent` tier). Never bail, never
  degrade silently.
- Probe pass → run wave 3 as the team roster defined in
  orchestrator.md, with the `budget_usd_team` tier (Agent Teams burn
  7-15× the tokens of subagent mode).

Wave 7 (regenerate `docs/wiki/index.md`) runs at the end in your main
session — never as a teammate. It indexes what has landed on the
project's main branch by that point; worktree-side commits not yet
merged are intentionally invisible (the index reflects ground truth,
not in-flight work). See `docs/specs/15-wiki.md`.

Apply caps from the project's `.claude/policy.yaml` (override) or the
plugin default at `${CLAUDE_PLUGIN_ROOT}/policy.yaml`. Branch on
`docs/rigor-level.md` (must exist in the project — run `/smurf:init`
first if not).

---
description: Run wave 3 as a host Dynamic Workflow when a goal has many independent parallel features; gated, additive mode alongside /kickoff-team.
argument-hint: <goal with many independent parallel features>
---

You — the MAIN session — are the smurf orchestrator for this run. Read
`${CLAUDE_PLUGIN_ROOT}/agents/orchestrator.md` now and follow it as your
operating instructions. Do NOT delegate the orchestrator role itself to
a subagent: subagents cannot spawn other subagents.

Goal: $ARGUMENTS

Use **Dynamic Workflows mode (wave 3 only)**. Dynamic Workflows is a
host CLI + model feature, triggered by the `workflow` keyword in a
prompt. The smurf plugin cannot implement, bundle, or enable it — it
can only gate, wrap, and delegate to it.

Run the canonical Dynamic-Workflows gate from orchestrator.md wave 3
BEFORE delegating the fan-out: settings check (`disableWorkflows`), env
check (`CLAUDE_CODE_DISABLE_WORKFLOWS`), and `claude --version`
>= 2.1.111 on Opus 4.8. That gate is settings/version-based, NOT a tool
probe — Dynamic Workflows exposes no tool surface to verify against
(unlike Agent Teams). One read-only bash command per call.

**On ANY gate miss:** bail VISIBLY with the verbatim user-facing
message defined in orchestrator.md and append
`wave-3 dynamic-workflow unavailable reason=<...> action=bail` to
`.claude/runs/<ts>/orchestrator.log`. Do NOT silently fall through to
subagent mode — the user explicitly asked for Dynamic Workflows.

**On gate pass:** express WAVE 3 ONLY as a dynamic workflow — compose a
wave-3 prompt containing the literal keyword `workflow` plus the story
DAG (one node per independent story, with dependency edges), so the
host runtime authors and runs the orchestration script. Workflow
scripts live in `.claude/workflows/`; never ship one in the plugin
tree. Apply the engage rule (fan-out only pays when story count >
`max_parallel_subagents`; otherwise plain subagent fan-out is cheaper),
the `budget_usd_workflow` tier, and the advisory
`max_workflow_subagents` cap from the resolved policy.

All other waves (1, 2, 4, 5, 6, 7) remain subagent mode — same as
`/smurf:kickoff-team`. Wave 7 runs at the end in your main session,
never inside a workflow; it indexes only what has landed on the main
branch (see `docs/specs/15-wiki.md`).

Apply caps from the project's `.claude/policy.yaml` (override) or the
plugin default at `${CLAUDE_PLUGIN_ROOT}/policy.yaml`. Branch on
`docs/rigor-level.md` (must exist in the project — run `/smurf:init`
first if not).

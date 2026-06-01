---
description: Run wave 3 as a host Dynamic Workflow when a goal has many independent parallel features; gated, additive 3rd mode alongside /kickoff and /kickoff-team.
argument-hint: <goal with many independent parallel features>
---

@orchestrator: $ARGUMENTS

Use **Dynamic Workflows mode (wave 3 only)**. Dynamic Workflows is a host
CLI + model feature, triggered by the `workflow` keyword in a prompt. The
smurf plugin manifest cannot implement, bundle, or enable it — it can only
gate, wrap, and delegate to it.

**Gate — run BEFORE delegating the wave-3 fan-out.** All checks are
read-only, one bash command per call (the PreToolUse hook rejects compound
commands):

1. Read `${CLAUDE_PROJECT_DIR}/.claude/settings.json` AND
   `${CLAUDE_PROJECT_DIR}/.claude/settings.local.json` → FAIL the gate if
   either contains `"disableWorkflows": true`.
2. `Bash("printenv CLAUDE_CODE_DISABLE_WORKFLOWS")` → FAIL the gate if it
   prints 1.
3. `Bash("claude --version")` → FAIL the gate if below 2.1.111.

The CLI gate = require `claude --version` >= 2.1.111 AND model == Opus 4.8.
2.1.111 is the concrete, honest proxy for "workflows-capable line"; treat
this as a **version proxy, not a tool probe**.

**This gate is settings/version-based, NOT a tool probe.** Unlike Agent
Teams (which exposes probeable `Task*`/`Team*` tools), Dynamic Workflows is
triggered by the `workflow` keyword in a prompt and has NO tool surface to
verify against. The gate is therefore necessarily settings/env/version-based,
not a hard capability contract.

**On ANY gate miss:** make the failure VISIBLE. Bail with: "Dynamic-Workflows
mode requires (1) workflows not disabled — no `disableWorkflows: true` in
your project settings and no `CLAUDE_CODE_DISABLE_WORKFLOWS=1` in your
environment — and (2) a workflows-capable host CLI (Claude Code >= 2.1.111)
on Opus 4.8. This gate is settings/version-based, not a tool probe: Dynamic
Workflows has no tool surface to verify against (unlike Agent Teams). Reason:
<reason>. Re-run with `/smurf:kickoff-team` (the default — subagent mode,
escalating wave 3 to an Agent Team when your host supports it); or enable
workflows and re-run `/smurf:kickoff-workflow`." Append to
`.claude/runs/<ts>/orchestrator.log`:
`wave-3 dynamic-workflow unavailable reason=<...> action=bail`.
Do NOT silently fall through to subagent mode — the user explicitly asked for
Dynamic Workflows; make the failure visible.

**On gate pass — wave 3 only:** express WAVE 3 as a dynamic workflow. Compose
a wave-3 prompt that INCLUDES the literal keyword `workflow` plus the story
DAG (one node per independent story, with dependency edges), so the host
runtime generates and runs the orchestration script. Do NOT ship a JS
workflow script in the plugin tree — workflow scripts live in
`.claude/workflows/` and the runtime authors them.

Apply the **engage rule**: dynamic-workflow wave-3 fan-out is only worth it
when story count > `max_parallel_subagents`; otherwise prefer plain subagent
fan-out (cheaper). Apply the `budget_usd_workflow` tier and the advisory
`max_workflow_subagents` cap, read from the project's `.claude/policy.yaml`
override if present, otherwise from `${CLAUDE_PLUGIN_ROOT}/policy.yaml`:

    budget_usd_workflow: 60
    max_workflow_subagents: 64
    review:
      ultrareview: auto      # auto = run when host supports it; off = never

All other waves (1, 2, 4, 5, 6, 7) remain subagent mode — same as
`/kickoff-team`.

Wave 7 (regenerate `docs/wiki/index.md`) runs at the end in the
orchestrator's main session — never inside a workflow. It indexes what has
landed on the project's main branch by that point. Worktree-side commits
that have not yet merged are intentionally invisible: the index reflects
ground truth, not in-flight work. See `docs/specs/15-wiki.md`.

Apply caps from project's `.claude/policy.yaml` (override) or the plugin
default at `${CLAUDE_PLUGIN_ROOT}/policy.yaml`. Branch on
`docs/rigor-level.md` (must exist in the project — run `/smurf:init` first
if not).

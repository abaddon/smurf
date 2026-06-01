# 16 — Dynamic Workflows + `/ultrareview`

Two host CLI + model features, neither owned by smurf. Dynamic
Workflows and `/ultrareview` are research previews shipped by the
Claude Code host, not by this plugin. smurf only **gates, wraps, and
delegates** to them — exactly as it does for Agent Teams (see
`plugin/commands/kickoff-team.md`).

A plugin cannot implement, bundle, or enable either feature. The
workflow scripts live under `.claude/workflows/`, never in the plugin
tree, and their JS API is undocumented. This spec is the contract for
the thin gate-and-delegate layer around them: what it must do, what it
produces, what it must never do.

## Dynamic Workflows

### The command

A new, additive command: `/smurf:kickoff-workflow`. It does NOT replace
the existing wave-3 fan-out. It is a dispatch mode alongside
`/smurf:kickoff-team` (the default: subagent baseline, with peer-to-peer
Agent Team for wave 3). Wave 3 only.

Delegation is by the **`workflow` keyword** in the orchestrator's
prompt — the host triggers a dynamic workflow when that keyword
appears. There is no `Workflow*` tool surface to call.

### The gate (read-only)

Before delegating, the command runs a read-only gate. All checks are
read-only — no file is written, no env var is set.

CLI gate = require `claude --version` >= 2.1.111 AND model == Opus 4.8.
(2.1.111 is the concrete, honest proxy for "workflows-capable line";
the command/spec must note this is a version proxy, not a tool probe.)

Disable checks, all read-only:

1. Read `${CLAUDE_PROJECT_DIR}/.claude/settings.json` AND
   `${CLAUDE_PROJECT_DIR}/.claude/settings.local.json` -> FAIL the gate
   if either contains `"disableWorkflows": true`.
2. `Bash("printenv CLAUDE_CODE_DISABLE_WORKFLOWS")` -> FAIL the gate if
   it prints 1.
3. `Bash("claude --version")` -> FAIL the gate if below 2.1.111.

### On gate miss: visible bail

The command bails (it never silently falls through to subagent mode —
the user explicitly asked for workflows; make the failure visible),
emitting verbatim:

> Dynamic-Workflows mode requires (1) workflows not disabled — no
> `disableWorkflows: true` in your project settings and no
> `CLAUDE_CODE_DISABLE_WORKFLOWS=1` in your environment — and (2) a
> workflows-capable host CLI (Claude Code >= 2.1.111) on Opus 4.8. This
> gate is settings/version-based, not a tool probe: Dynamic Workflows
> has no tool surface to verify against (unlike Agent Teams). Reason:
> <reason>. Re-run with `/smurf:kickoff-team` for peer-to-peer wave 3
> (or subagent mode when Agent Teams are unavailable); or enable
> workflows and re-run `/smurf:kickoff-workflow`.

And it logs to `.claude/runs/<ts>/orchestrator.log`, verbatim:

```
wave-3 dynamic-workflow unavailable reason=<...> action=bail
```

### When to engage

Dynamic-workflow wave-3 fan-out is only worth it when story count >
`max_parallel_subagents`; otherwise prefer plain subagent fan-out
(cheaper). Apply the `budget_usd_workflow` tier + advisory
`max_workflow_subagents` cap.

### `policy.yaml` knobs

```yaml
budget_usd_workflow: 60
max_workflow_subagents: 64
```

`budget_usd_workflow` is the cost ceiling for workflow mode (workflows
fan out wider and burn more than subagent or team mode).
`max_workflow_subagents` is an **advisory** cap — the host owns the
real parallelism; smurf cannot enforce it, only request it.

All other waves (1, 2, 4, 5, 6, 7) remain subagent mode regardless.

## `/ultrareview`

An OPTIONAL wave-4 step inside `qa-engineer`. When available, the
qa-engineer may invoke `/ultrareview` to obtain a deeper, model-driven
review pass over the changes under test.

### Resolution

- Resolved policy `review.ultrareview` (`auto` | `off`):
  ```yaml
  review:
    ultrareview: auto      # auto = run when host supports it; off = never
  ```
  `auto` runs `/ultrareview` when the host supports it; `off` never
  runs it.
- Requires host CLI >= 2.1.111.

### What it produces, what it does not decide

- `/ultrareview` findings are surfaced as **advisory** notes,
  `ULTRAREVIEW:`-prefixed, in the qa report. They inform; they do not
  gate.
- `verify.sh` + the acceptance criteria remain the **sole** GREEN/RED
  authority. `/ultrareview` never overrides them. A run is GREEN iff
  `verify.sh` and the criteria say so, regardless of what
  `/ultrareview` reported.

### On unavailability: silent skip

If `review.ultrareview: off`, or the host CLI is too old, or the
invocation path is absent, the step is skipped silently — it never
fails the wave. It logs to `.claude/runs/<ts>/orchestrator.log`,
verbatim:

```
wave-4b ultrareview unavailable reason=<...> action=skip
```

## Two honesty caveats

**CAVEAT 1 — settings/version gate, not a tool probe (weaker than
Agent Teams).** Agent Teams exposes probeable tools (`Task*`/`Team*`),
so its gate is a hard capability contract: probe the surface, bail if
incomplete. Dynamic Workflows is triggered by the `workflow` keyword in
a prompt and has **no tool surface to probe**. Its gate is therefore
necessarily settings/env/version-based, not a hard capability contract.
The bail prose says so explicitly. A passing gate means "the host most
likely supports workflows," not "the workflow surface is verified
present."

**CAVEAT 2 — uncertain subagent invocation -> orchestrator fallback;
both paths skip silently.** A subagent cannot "type" a slash command.
Programmatic `/ultrareview` invocation depends on the host exposing a
`SlashCommand`-style tool. If that tool is present, the qa-engineer
invokes it directly. If it is absent, an orchestrator-level fallback
applies (the orchestrator drives the review instead). If neither path
is available, the step skips silently — it NEVER fails the wave. Both
paths skip silently.

## Fallbacks

| Condition | Behavior |
|---|---|
| Workflow-gate miss | **Visible bail** — emit the verbatim bail message + `action=bail` log line. NEVER silently fall through to subagent mode. |
| `/ultrareview` unavailable | **Silent skip** — emit the `action=skip` log line. NEVER fail the wave. |

The asymmetry is intentional. A workflow-gate miss means the user asked
for a mode they cannot have, so the failure must be loud. An
`/ultrareview` miss only costs an optional, advisory pass, so it
degrades quietly.

## It must never

- **Never re-implement either feature.** Both are host CLI + model
  features; smurf gates and delegates only.
- **Never ship a JS workflow script in the plugin tree.** Workflow
  scripts live in `.claude/workflows/`; their API is undocumented.
- **Never set env vars or enable previews on the user's behalf.** The
  plugin manifest cannot, and the gate must not. The user enables
  workflows; smurf only checks whether they did.
- **Never let `/ultrareview` override `verify.sh` or the acceptance
  criteria.** Those remain the sole GREEN/RED authority; ultrareview
  output is advisory.
- **Never silently fall through the workflow gate to subagent mode.** A
  gate miss is a visible bail.
- **Never replace the existing wave-3 fan-out.**
  `/smurf:kickoff-workflow` is additive — a command beside the
  `/smurf:kickoff-team` default.

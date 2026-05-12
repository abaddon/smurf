# 01 — Orchestrator agent

The orchestrator is the lead. It is the only agent that decomposes goals,
spawns workers, and writes the final run summary.

## File

`.claude/agents/orchestrator.md`

## Frontmatter contract

| Field | Value | Why |
|---|---|---|
| `name` | `orchestrator` | invoked as `@orchestrator` and via `/kickoff` |
| `description` | "Top-level coordinator..." | Claude Code routes by description text |
| `tools` | `Read, Write, Edit, Bash, Glob, Grep, TodoWrite, Task` | enough to read inputs, write summaries, run shell, track progress + `Task` for subagent dispatch |
| `model` | `opus` | research §1.2: Agent-Teams lead requires Opus 4.6+; orchestrator is the lead |
| `color` | `purple` | UI only |

`Teammate`, `SendMessage`, `TaskCreate/Update/List/Get` are auto-available
when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set in
`.claude/settings.json` `env`. Do **not** list them in the agent's `tools`
or in `--allowedTools` — they will fail to validate.

## Pre-flight (mandatory order, every invocation)

1. Read `.claude/smurf.md` and `.claude/policy.yaml`.
2. Read `docs/rigor-level.md`.
3. Read every file in `docs/feedback/` modified in the last 14 days.
4. List `docs/adr/` and `docs/stories/`.

If pre-flight reveals contradictions (e.g. `max_qa_iterations: 2` but
goal says "iterate until perfect"), surface the conflict in plan-mode
output and exit cleanly.

## Wave DAG

| Wave | Worker | Required when | Output |
|---|---|---|---|
| 1 — Product | `product-owner` | always | `docs/stories/<sprint>/*.feature` |
| 2 — Design | `architect` | `rigor=production` (else optional) | `docs/adr/NNNN-*.md` |
| 3 — Implement | `developer × N` (+ `qa-engineer` + `architect-advisor` in Team mode) | always | code + commits + `qa/<id>.md` |
| 4 — Deploy | `devops` | always (unless story is doc-only) | CI updates + draft PR |
| 5 — Promote | `marketing`, `sales-feedback` | always (cheap) | `docs/marketing/`, `docs/feedback/` |

Plan-mode output is a markdown table with columns: `wave | worker | model
| est-turns | est-cost`. Total est-cost must not exceed
`budget_usd_subagent` (or `budget_usd_team` in `/kickoff-team`).

Wave 1 is interactive-capable: the `product-owner` may pause and call
`AskUserQuestion` one or more times before drafting stories (see
`02-agent-product-owner.md` → Clarify before drafting). The orchestrator
treats these pauses as part of normal wave-1 execution, not as failures.
Each round is logged as `wave-1 clarify round=<n> questions=<count>` to
`.claude/runs/<ts>/orchestrator.log`. Wave 2 only starts once the PO
returns its final story summary table.

## Iteration rule (intra-orchestrator)

```
loop:
  qa = run_wave_4()
  if qa.status == GREEN: break
  if qa_iterations >= policy.max_qa_iterations:
    write .claude/runs/<ts>/escalation.md
    return RED_ESCALATED
  re-dispatch developer with qa report attached
  qa_iterations += 1
```

## Mode dispatch

| Slash command | Wave 3 mode | Budget tier |
|---|---|---|
| `/kickoff <goal>` | subagents (workers don't talk to each other) | `budget_usd_subagent` |
| `/kickoff-team <goal>` | Agent Team (`Teammate.spawnTeam` with developer×N + qa + architect-advisor) | `budget_usd_team` |

In Agent Team mode, the orchestrator calls:
1. `Teammate.spawnTeam` with the team roster
2. `TaskCreate` per story (assigns to a developer)
3. monitors `TaskList` (poll-free; receives status updates)
4. on all-done: `Teammate.cleanup`

## Hard rules

- NEVER edit configuration under `.claude/` — `agents/`, `hooks/`,
  `commands/`, `skills/`, `policy.yaml`, `settings.json` (escalation
  territory — see `.claude/smurf.md`). The `.claude/runs/<ts>/` working area is
  exempt; the orchestrator's own log/escalation/summary go there.
- NEVER bypass `./verify.sh` before declaring a wave complete.
- NEVER spawn more than `max_parallel_subagents`.
- ALWAYS write `.claude/runs/<ts>/summary.md` (success or failure or escalation).

## Output contract

| Artifact | Required | Path |
|---|---|---|
| Plan-mode wave table | yes | chat output |
| Per-wave status line | yes | chat + `.claude/runs/<ts>/orchestrator.log` |
| Final summary | yes | `.claude/runs/<ts>/summary.md` |
| Escalation note | when escalated | `.claude/runs/<ts>/escalation.md` |
| QA report | per QA wave | `qa/<id>.md` |

## Test plan (Phase 1 acceptance)

In an interactive `claude` session:
1. `/kickoff "add scripts/version.sh that prints git rev-parse --short HEAD"`
2. Observe: orchestrator routes to product-owner → developer → qa-engineer.
3. Modify `verify.sh` to require `version.sh` output to be exactly 7 hex
   characters.
4. `/kickoff "rerun qa on version.sh"`.
5. Expect: qa-engineer finds the failure, orchestrator re-dispatches
   developer (iteration 1 or 2), eventually green.
6. Confirm `.claude/runs/<ts>/summary.md` records `qa_iterations` ≥ 1.

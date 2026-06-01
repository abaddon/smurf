# 14 — Iteration mechanism + budget tiers

The system iterates at three layers. Without iteration, this is just a
fan-out tree of one-shot calls; with iteration, it's a closed loop.

## Three layers

### Layer 1: intra-wave (Agent Teams only)

Wave 3 in team mode spawns developers, qa-engineer, and an
architect-advisor as peer teammates. Communication uses `SendMessage`:

| From | To | When | Cap |
|---|---|---|---|
| developer | architect-advisor | "is this port shape what you intended?" | 5 messages per developer per story (soft) |
| developer | qa-engineer | "I think AC-3 is unclear, what counts as success?" | 3 per developer (soft) |
| qa-engineer | developer | "AC-2 fails: empty input returns null, expected []" | unbounded (1 per failure) |
| architect-advisor | (passive) | only replies; never initiates | 8 turns total |

The architect-advisor's `maxTurns: 8` is a hard cap. If exceeded, it
sends `shutdown_response` and the orchestrator must fall back to
re-invoking the architect as a full subagent (which loses the team
context).

In subagent mode (`/kickoff-team`'s baseline), Layer 1 doesn't exist —
workers report to the orchestrator only.

### Layer 2: inter-wave (both modes)

After QA's wave produces a RED report, the orchestrator re-dispatches
the developer with the QA report attached:

```
loop:
  qa = run_wave_4()
  if qa.status == GREEN: break
  if qa_iterations >= policy.max_qa_iterations:
    write .claude/runs/<ts>/escalation.md
    return RED_ESCALATED
  re-dispatch developer with qa/<id>.md as prompt context
  qa_iterations += 1
```

`max_qa_iterations` defaults to **2** in `.claude/policy.yaml`. After
the second failed attempt, the orchestrator escalates rather than
spinning indefinitely.

The escalation note records:
- the goal
- which acceptance criteria failed both times
- the developer's last commit SHA per attempt
- a one-line hypothesis (e.g. "AC-3 is contradictory with NFR-1")

### Layer 3: cross-run (overnight)

`scripts/close-loop.py` (Phase 7) runs at the end of every autonomous
run and writes `docs/feedback/<YYYY-MM-DD>.md`. It pulls:

- top GitHub issues by reaction count
- top Sentry error signatures (if MCP configured)
- Linear ticket priority distribution (if MCP configured)
- support themes from the past 7 days

The next run's `product-owner` reads `docs/feedback/*.md` modified in
the last 14 days as its first pre-flight step. Stories cite feedback
files by path, so the chain of causation is traceable in `git log`:

```
goal "improve perf" (run N)
  ↓ produces
docs/feedback/2026-05-09.md  (close-loop after run N)
  ↓ consumed by
product-owner in run N+1
  ↓ produces
docs/stories/2026-05-10-rate-limit/01-per-tenant.feature
   (cites docs/feedback/2026-05-09.md as source)
  ↓ implemented by
developer in wave 3 of run N+1
```

## Budget tiers

`.claude/policy.yaml` declares two tiers:

| Mode | Default | Why |
|---|---|---|
| `budget_usd_subagent` | 12 USD | Research §1.7 baseline (one Claude session) |
| `budget_usd_team` | 25 USD | Research §1.7: Agent Teams burn 7-15× tokens |

`autonomous-run.sh` selects the tier from `MODE`:

```bash
MODE=subagent bash scripts/autonomous-run.sh   # → 12 USD cap
MODE=team     bash scripts/autonomous-run.sh   # → 25 USD cap
```

Override per-run with `BUDGET_OVERRIDE=<usd>` (intended for tests; not
expected to be used in production cron).

The cap is passed to Claude Code as `--max-budget-usd $BUDGET`. Under
subscription billing this is best-effort; under pay-per-token it is
enforced. **Pair with `--max-turns 200` (in `autonomous-run.sh`) as
the deterministic ceiling.**

## When the budget is hit

Claude Code returns a "budget exceeded" stop reason. The Stop hook
(`on-stop-summary.sh`) writes `summary.md` with status "interrupted —
budget". The next run does NOT automatically resume (per Agent Teams
caveat — see operations.md). To complete the work:

1. Read the partial summary; identify what was done.
2. Refine the goal: scope it down, or split into multiple goals.
3. Re-run.

## Iteration knobs

All knobs live in `.claude/policy.yaml`:

| Knob | Default | Effect |
|---|---|---|
| `max_qa_iterations` | 2 | Layer 2 cap |
| `max_parallel_subagents` | 4 | Wave-3 fan-out cap (subagent mode) |
| `max_turns_orchestrator` | 60 | per-orchestrator-invocation tool calls |
| `max_turns_subagent` | 30 | per-subagent tool calls |
| `budget_usd_subagent` | 12 | Layer-2-mode cost ceiling |
| `budget_usd_team` | 25 | Layer-1-mode cost ceiling |

`.claude/smurf.md` cites `policy.yaml` rather than hard-coding numbers, so
agents read live values at pre-flight.

## Test plan (Phase 6a acceptance)

1. **Layer 2 (inter-wave) — subagent mode**:
   ```bash
   echo "Add scripts/sort.sh that sorts stdin alphabetically. \
   Acceptance: empty input must produce empty output (no error)." \
     > .claude/runs/next-goal.md
   bash scripts/autonomous-run.sh
   ```
   The first developer attempt typically errors on empty input; QA
   reports RED on the empty-input AC; orchestrator re-dispatches; second
   attempt fixes. Confirm `summary.md` records `qa_iterations_observed: 1`.

2. **Layer 1 (intra-wave) — team mode**:
   ```bash
   echo "Add scripts/version.sh AND scripts/changelog.sh in parallel. \
   These are independent and can be developed concurrently." \
     > .claude/runs/next-goal.md
   MODE=team bash scripts/autonomous-run.sh
   ```
   Inspect `~/.claude/teams/<name>/messages/` (path may differ across
   Claude Code versions — fallback: grep the `run.ndjson` for
   `SendMessage` events). Expect:
   - ≥1 `SendMessage` from a developer to architect-advisor
   - ≥1 `SendMessage` from qa-engineer to a developer (if any AC failed)

3. **Layer 3 (cross-run)** — Phase 7 acceptance, see `13-feedback-loop.md`.

## Known limits

- **Agent Teams `/resume` does not restore teammates** (research §1.2).
  Cron treats each run as fresh.
- **Skills/MCP in subagent frontmatter aren't applied to teammates**
  (research §1.2). Skills are auto-discovered from `.claude/skills/` so
  this is a non-issue for us; MCP servers in `.mcp.json` are loaded
  project-wide.
- **architect-advisor's `maxTurns: 8` is a hard ceiling**. Long
  conversations exhaust it; orchestrator must re-spawn the architect as
  a full subagent in that case (rare, but document in summary.md).
- **Task status lag** (research §1.2): a teammate may not close its
  task before exiting. The orchestrator's wave-3 completion check
  should poll `TaskList` with a 30s timeout and force-fail rather than
  hang.

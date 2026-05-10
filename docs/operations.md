# Smurf — Operations guide

How to run, monitor, and recover the orchestrator.

## Daily flow (autonomous)

1. Before you go to bed (or any time before the cron schedule):
   ```bash
   echo "Add scripts/version.sh that prints git rev-parse --short HEAD" \
     > .claude/runs/next-goal.md
   ```
2. Cron at 01:00 fires `scripts/autonomous-run.sh`.
3. In the morning, inspect `.claude/runs/<latest>/summary.md`.
4. If a draft PR exists, review and merge.
5. The same nightly run produces `docs/feedback/<date>.md` (Phase 7+);
   the next run's product-owner consumes it.

## Manual run

```bash
echo "<your goal>" > .claude/runs/next-goal.md
bash scripts/autonomous-run.sh                    # subagent mode
MODE=team bash scripts/autonomous-run.sh          # Agent Teams mode
BUDGET_OVERRIDE=2 bash scripts/autonomous-run.sh  # cheap test run
WATCHDOG_OVERRIDE=10s bash scripts/autonomous-run.sh  # verify SIGTERM trap
```

## Cron management

```bash
bash scripts/install-cron.sh             # install at 01:00 (default)
bash scripts/install-cron.sh "0 2 * * *" # custom schedule
bash scripts/install-cron.sh --status    # show current entry
bash scripts/install-cron.sh --remove    # uninstall
```

The installer is idempotent — re-running with the same schedule is a
no-op. The marker comment `# smurf-orchestrator (autonomous-run.sh)`
identifies our line in the crontab.

## Health check

```bash
bash scripts/doctor.sh
```

Run before the first autonomous run and whenever the system misbehaves.
Exits non-zero if any required file/tool is missing.

## Budgets

`policy.yaml` defines two tiers:

| Mode | Budget cap | Why |
|---|---|---|
| `subagent` | `budget_usd_subagent` (default 12 USD) | research §1.7 baseline |
| `team` | `budget_usd_team` (default 25 USD) | Agent Teams burn 7-15× tokens |

The `--max-budget-usd` flag is best-effort under subscription billing;
`--max-turns 200` is the real ceiling. Override with `BUDGET_OVERRIDE`
for testing.

## Watchdog

`autonomous-run.sh` wraps `claude -p` in `timeout 4h`. On SIGTERM, the
trap writes `.claude/runs/<ts>/partial-summary.json` and exits 124.

Override the watchdog for testing:

```bash
WATCHDOG_OVERRIDE=10s bash scripts/autonomous-run.sh
# expect: rc=124, partial-summary.json present
```

## `--continue` / `--resume` policy

Not used. Agent Teams `/resume` does **not** restore teammates (research
§1.2), so a resumed session would have an empty team and produce
inconsistent state. Each nightly run is independent.

If a run is interrupted mid-wave:
- worktrees under `.claude/worktrees/<id>/` survive (gitignored locally
  but valid git worktrees).
- the next run starts fresh and can reference the leftover branch by
  name in its goal: `"resume the rate-limit work in worktree feat-rl"`.

## Anthropic outage failover

If Anthropic is degraded, redirect via OpenRouter Anthropic Skin:

```bash
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
unset ANTHROPIC_API_KEY
bash scripts/autonomous-run.sh
```

The autonomous-run script honors `ANTHROPIC_BASE_URL` if exported. Note:
OpenRouter's compatibility is guaranteed only with the Anthropic
first-party provider — non-Anthropic models may break tool-use.

## Where state lives

| Location | What | Gitignored |
|---|---|---|
| `.claude/runs/<ts>/` | per-run NDJSON, summary, logs | yes |
| `.claude/worktrees/<id>/` | parallel-developer worktrees | yes |
| `~/.claude/teams/<name>/` | Agent Team shared task list and messages | n/a (user home) |
| `docs/feedback/<date>.md` | nightly feedback digest | no |
| `docs/stories/<sprint>/*.feature` | product-owner stories | no |
| `docs/adr/NNNN-*.md` | architect decisions | no |
| `qa/<id>.md` | QA reports | no |

## Common failure modes and recovery

| Symptom | Likely cause | Recovery |
|---|---|---|
| Run exits at < 1 minute, empty `summary.md` | Pre-flight failure or bad `next-goal.md` | Check `.claude/runs/<ts>/run.err`. |
| Run hits budget cap | Goal too ambitious for `prototype` rigor | Split goal; OR set `production` rigor and use `MODE=team`. |
| QA loop never ends | `max_qa_iterations` cap not enforced | Inspect `summary.md` for `qa_iterations` field; raise `policy.yaml` if intentional. |
| Cron not firing | Wrong crontab user, or `claude` not on PATH for cron's environment | `bash scripts/install-cron.sh --status`; ensure cron uses `bash -lc` (the installer does) so login env is loaded. |
| Hook blocks normal dev work | `bash_allowlist` too tight | Edit `policy.yaml` (broaden) or add personal override in `.claude/settings.local.json`. |
| Orchestrator skips the architect wave despite `production` rigor | Stale `docs/rigor-level.md` content | `cat docs/rigor-level.md` (must literally be `production`); restart run. |

## Escalation

The orchestrator writes `.claude/runs/<ts>/escalation.md` and exits when
it hits a hard rule (new external dep, security change, public API
contract change, >100 LOC delete, `.claude/` modification request).

Escalations are not failures — they're the system saying "this needs a
human". Read the escalation note and either:
- approve manually (commit the change yourself),
- refine the goal so the agent doesn't need to escalate,
- adjust the `ESCALATION` rules in `.claude/smurf.md` if they're too tight.

## Cost dashboard (manual)

Until we wire up structured cost tracking:

```bash
# Approximate cost from NDJSON
jq -r 'select(.cost_usd) | .cost_usd' < .claude/runs/<ts>/run.ndjson \
  | paste -sd+ | bc
```

A future spec (`docs/specs/15-observability.md`) will formalize this.

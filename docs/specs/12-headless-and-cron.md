# 12 — Headless run + cron + watchdog

How the orchestrator runs unattended.

## Files

- `scripts/autonomous-run.sh` — cron entrypoint
- `scripts/install-cron.sh` — idempotent crontab manager
- `scripts/doctor.sh` — pre-flight health check
- `scripts/test-hooks.sh` — hook smoke test (Phase 3)

## `autonomous-run.sh` contract

### Inputs

| Source | Field | Required |
|---|---|---|
| `.claude/runs/next-goal.md` | the goal text | yes (non-empty) |
| `.claude/policy.yaml` | `budget_usd_subagent` / `budget_usd_team` | yes |
| `verify.sh` | executable | yes |
| env `MODE` | `subagent` (default) or `team` | no |
| env `BUDGET_OVERRIDE` | dollar amount | no |
| env `WATCHDOG_OVERRIDE` | duration string (e.g. `10s`, `30m`) | no |
| env `ANTHROPIC_BASE_URL` | outage failover | no |
| env `SLACK_WEBHOOK` | URL for run-summary post | no |

### Outputs

| Path | What |
|---|---|
| `.claude/runs/<ts>/goal.md` | copy of the goal that ran |
| `.claude/runs/<ts>/meta.txt` | mode, budget, watchdog, git head, branch |
| `.claude/runs/<ts>/run.ndjson` | full Claude Code transcript (stream-json) |
| `.claude/runs/<ts>/run.err` | stderr |
| `.claude/runs/<ts>/summary.md` | written by `on-stop-summary.sh` (Stop hook) |
| `.claude/runs/<ts>/agents.log` | one line per subagent (SubagentStop hook) |
| `.claude/runs/<ts>/partial-summary.json` | only if watchdog fires |
| `.claude/runs/<ts>/close-loop.{out,err}` | Phase 7+, if `close-loop.py` is present |

### Exit codes

| Code | Meaning |
|---|---|
| 0 | run completed (success or graceful budget/turn cap) |
| 1 | preflight failure |
| 124 | watchdog fired (SIGTERM) |
| other | claude-internal failure (see `run.err`) |

### Why no `--bare`

Research §1.5: `--bare` suppresses `.mcp.json` auto-load and the
discovery of project-local `~/.claude` settings. That would break
`mcp__github` (which the devops agent needs for `gh pr create`-equivalent
calls) and disable our hooks. Reproducibility tradeoff is accepted: the
project root is the source of truth and is git-pinned anyway.

### Why `--max-turns 200` instead of relying on `--max-budget-usd`

Under subscription billing, `--max-budget-usd` is best-effort (the
subscription's monthly cap is the real spending ceiling). `--max-turns`
is the deterministic upper bound on time and computation. We pass both;
the budget flag is the *intent*, the turns flag is the *enforcement*.

## `install-cron.sh` contract

| Invocation | Effect |
|---|---|
| `bash scripts/install-cron.sh` | install at `0 1 * * *` if absent; no-op if already present |
| `bash scripts/install-cron.sh "<spec>"` | install at custom 5-field spec |
| `bash scripts/install-cron.sh --remove` | remove our line |
| `bash scripts/install-cron.sh --status` | print current line, no changes |

The marker comment `# smurf-orchestrator (autonomous-run.sh)` identifies
our line. Other crontab entries are preserved.

The installed line uses `bash -lc` so the cron environment loads the
user's login shell config (necessary for `claude` and `gh` on PATH).

Output is appended to `.claude/runs/cron.log`.

## `doctor.sh` contract

42 checks across 8 sections:
- Files and structure
- Agents (8 files)
- Skills (5 directories)
- Hooks (6 executables)
- Slash commands (4)
- Settings (env, hook registration)
- Hook smoke test (delegates to `scripts/test-hooks.sh`)
- Tools available (jq, yq, python3, git, timeout, claude, gh, curl)
- MCP

Run `doctor` before:
- the first autonomous run on a new machine
- after upgrading Claude Code
- after editing `policy.yaml` or `settings.json`
- when reporting a bug

Exit 0 if all required checks pass; exit 1 if any FAIL. WARNs (e.g.
missing `gh`) don't fail the script but are surfaced.

## Test plan (Phase 5 acceptance)

1. **Smoke run** (default settings):
   ```bash
   echo "Add a HELLO file at the repo root containing 'hi'" \
     > .claude/runs/next-goal.md
   bash scripts/autonomous-run.sh
   ```
   - Expect: rc=0, `summary.md` non-empty, `run.ndjson` parses with `jq`,
     `HELLO` file created, optional Slack notification posted.

2. **Budget override**:
   ```bash
   BUDGET_OVERRIDE=0.10 bash scripts/autonomous-run.sh
   ```
   - Expect: graceful exit (claude reports budget hit), `summary.md`
     records partial work.

3. **Watchdog**:
   ```bash
   WATCHDOG_OVERRIDE=10s bash scripts/autonomous-run.sh
   ```
   - Expect: rc=124 (or wrapped 124 from `timeout`), no orphan claude
     process, `partial-summary.json` written.

4. **Cron install idempotency**:
   ```bash
   bash scripts/install-cron.sh
   crontab -l | grep -c smurf-orchestrator   # → 1
   bash scripts/install-cron.sh
   crontab -l | grep -c smurf-orchestrator   # → 1 (still)
   bash scripts/install-cron.sh --remove
   crontab -l | grep -c smurf-orchestrator   # → 0
   ```

5. **Doctor on healthy setup**:
   ```bash
   bash scripts/doctor.sh
   echo $?    # 0
   ```

## Out of scope (Phase 5)

- Cost dashboard / structured cost tracking — manual `jq` for now;
  formalized in a future `docs/specs/15-observability.md`.
- Multi-host (e.g. Proxmox) — single-machine cron only.
- Alert escalation beyond Slack — no PagerDuty/Opsgenie integration.

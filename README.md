# smurf

Self-agentic orchestrator distributed as a Claude Code plugin. A team
of specialist subagents (product-owner, architect, developer,
qa-engineer, devops, marketing, sales-feedback) plans, implements,
verifies, and reports on goals you write into
`.claude/runs/next-goal.md` in your host project.

The system iterates: QA failures re-dispatch the developer (capped); a
nightly `close-loop.py` writes `docs/feedback/<date>.md` consumed by the
product-owner at the next kickoff.

## Install

Smurf ships as a plugin — its agents, hooks, skills, commands,
`policy.yaml`, and operating manual all live inside the plugin
directory and are loaded by reference at runtime. The plugin is never
copied into your project.

Clone the repo, then register it as a local marketplace and install
the plugin from inside Claude Code:

```bash
git clone https://github.com/abaddon/smurf.git ~/src/smurf
cd /path/to/your-project
claude
> /plugin marketplace add ~/src/smurf
> /plugin install smurf@smurf
```

The repo root holds `.claude-plugin/marketplace.json`; the plugin
itself lives under `plugin/` (canonical Claude Code marketplace
layout). Local-path marketplaces resolve live, so edits in `~/src/smurf`
take effect immediately — no copying. Once installed, every `/smurf:*`
slash command becomes available.

Inside your project, scaffold the project-side stubs:

```bash
cd /path/to/your-project
claude
> /smurf:init
```

`/smurf:init` runs `scripts/init-project.sh` and creates only what is
missing: `verify.sh` (no-op shim), `docs/rigor-level.md` (`prototype`
by default), `.claude/runs/next-goal.md` (empty), gitignore lines
for `.claude/runs/`, `.claude/worktrees/`, `.claude/settings.local.json`,
and an allow rule in `.claude/settings.local.json` so `/smurf:nightly-run`
can launch `autonomous-run.sh` without an auto-mode permission denial.
Existing files are never overwritten — the allow rule is merged into any
existing `.claude/settings.local.json`, and the host project's
`CLAUDE.md` is never touched.

### Adopting smurf into an established codebase

If you are installing smurf into a project that already has code,
follow `/smurf:init` with:

```bash
> /smurf:bootstrap
```

`/smurf:bootstrap` is a one-shot reverse-engineering run. It spawns
the standard specialist subagents (`developer`, `devops`,
`sales-feedback`, `product-owner`, `architect`, `qa-engineer`) in
BOOTSTRAP MODE — they read the existing code instead of a goal and
produce:

- `docs/bootstrap/tech-stack.md` + `docs/bootstrap/ci-inventory.md`
  — what the project is built with and how it ships
- `docs/feedback/<date>-bootstrap.md` — seed digest from open
  GitHub issues (skip with `--no-feedback`)
- `docs/stories/bootstrap-<date>/NN-*.feature` — backfilled Gherkin
  stories for capabilities the project already provides
  (`Status: proposed`)
- `docs/adr/NNNN-*.md` — ADRs extracted from the architecture already
  embedded in the code (`Status: proposed`)
- `qa/bootstrap-<date>.md` — cross-check that the new docs cite real
  source paths
- `docs/bootstrap/rigor-level-recommendation.md` — suggested rigor
  level based on detected tests + CI (you still write the final
  value into `docs/rigor-level.md` yourself)

Each wave is committed as `docs(bootstrap): wave <A-E>: …`. Review
the artifacts, flip `Status: proposed` → `accepted` on the docs you
agree with, then write your first goal to `.claude/runs/next-goal.md`
and run `/smurf:kickoff`.

Flags: `--no-feedback` (skip sales-feedback), `--rigor
prototype|production` (override detection).

After scaffolding:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

`doctor.sh` runs 40+ checks split between `[plugin]` (must pass) and
`[project]` (warnings only). It exits non-zero if the plugin install
is broken.

Replace the no-op `verify.sh` body with your stack's tests (`npm test`,
`pytest`, `cargo test`, `mvn verify`, …) and then write your first
goal to `.claude/runs/next-goal.md`.

## Operate

Interactive (any time):

```bash
claude
> /smurf:kickoff "<your goal>"
```

Autonomous:

```bash
echo "<your goal>" > .claude/runs/next-goal.md
claude
> /smurf:nightly-run
```

Or schedule it from cron:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-cron.sh"
```

The cron installer is idempotent and uses
`CLAUDE_PROJECT_DIR=<your project>` plus
`CLAUDE_PLUGIN_ROOT=<plugin location>` so the headless run resolves
the plugin correctly.

Force Agent-Teams (peer-to-peer wave 3):

```bash
> /smurf:kickoff-team "<goal with parallel features>"
```

Agent Teams mode requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in
your project's `.claude/settings.local.json`.

## Configure

- `${CLAUDE_PLUGIN_ROOT}/smurf.md` — Smurf's operating manual.
  Hand-written. Agents read it at pre-flight from the plugin root.
  Don't let an agent rewrite it.
- `${CLAUDE_PLUGIN_ROOT}/policy.yaml` — plugin default caps and
  allowlists. Single source of truth unless overridden.
- `.claude/policy.yaml` in your host project — **optional override**.
  When present, every cap and pattern in it wins over the plugin
  default. Copy the plugin file as a starting point if you want
  project-specific allowlists.
- `docs/rigor-level.md` — `prototype` (skip architect + integration QA)
  or `production`.
- `verify.sh` — your project's test/build entrypoint. Replace the no-op
  default.
- `.mcp.json` — MCP servers for the project (`github` is the default).

### Wiki layer

Enabled by default (`wiki.enabled: true` in `policy.yaml`). On every
run, smurf:

- regenerates `docs/wiki/index.md` (wave 7) — a topic-bucketed index
  of ADRs, stories, and feedback that product-owner and architect
  read at pre-flight in the next run;
- appends one row to `docs/wiki/log.md` — append-only audit trail
  (committed; survives gitignored `.claude/runs/`);
- on each `close-loop`, writes `docs/wiki/health.md` with cite-check,
  port-conflict, and orphan-story findings. A missing cite on a
  `Status: accepted` ADR is a **FAIL** (close-loop exits 2).

See `docs/specs/15-wiki.md`. To opt out, set `wiki.enabled: false` in
your project's `.claude/policy.yaml`.

## Extend

- New project rule? Add a regex to `forbidden_patterns` in your host's
  `.claude/policy.yaml` (override).
- New role or skill? Contribute it to the plugin: drop
  `agents/<name>.md` or `skills/<name>/SKILL.md` inside the plugin
  repo and reinstall.

## First-run goals (suggestions)

If you've just installed smurf and don't know what to point it at,
start with one of these:

```bash
# 1. Self-test: prove the loop works end-to-end on something trivial.
echo "Add scripts/version.sh that prints git rev-parse --short HEAD;
extend verify.sh so it asserts the script's output is exactly 7 hex chars." \
  > .claude/runs/next-goal.md

# 2. Tighten the policy with a new project rule.
echo "Add a forbidden_pattern to .claude/policy.yaml that blocks any
file containing 'TODO' without a referenced ticket id." \
  > .claude/runs/next-goal.md

# 3. Multi-feature run (use /smurf:kickoff-team for parallelism).
echo "Add scripts/version.sh AND scripts/changelog.sh — independent
features, can be developed in parallel." > .claude/runs/next-goal.md
# then in claude:  > /smurf:kickoff-team "implement next-goal.md"
```

## Status

All 7 phases shipped:
- Phase 1: orchestrator + developer + qa-engineer minimal loop.
- Phase 2: full subagent suite + slash commands.
- Phase 3: 6 hooks + policy.yaml + 13/13 hook smoke tests pass.
- Phase 4: 5 skills + rigor-level branching.
- Phase 5: `autonomous-run.sh` + watchdog + `install-cron.sh` + `doctor.sh`.
- Phase 6a: Agent Teams wave-3 with architect-advisor.
- Phase 6b: OpenRouter shell-out for marketing/sales.
- Phase 7: `close-loop.py` cross-run feedback + 14 specs.

See `docs/specs/00-overview.md` for the spec index and
`docs/operations.md` for runbooks.

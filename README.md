# smurf

**Self-agentic orchestrator, distributed as a Claude Code plugin** (v1.0.20).

You write a goal into `.claude/runs/next-goal.md`; a team of specialist
subagents — product-owner, architect, developer, qa-engineer, devops,
marketing, sales-feedback — plans, implements, verifies, ships, and reports
on it. The system iterates: a failing QA report re-dispatches the developer
(capped), and a periodic `close-loop` writes `docs/feedback/<date>.md` that
the product-owner reads at the next kickoff.

Smurf ships as a plugin: its agents, hooks, skills, commands, `policy.yaml`,
and operating manual all live inside the plugin directory and load by
reference at runtime. **Nothing is ever copied into your project** except the
small project-side stubs `/smurf:init` scaffolds.

## How it works — the wave model

A kickoff decomposes the goal into a wave-based DAG. Each wave delegates to a
specialist subagent that reports back to the orchestrator (the main session):

| Wave | Role | Output | Rigor |
|------|------|--------|-------|
| 1 — Product | `product-owner` | Gherkin user stories in `docs/stories/<sprint>/*.feature` | always |
| 2 — Design | `architect` | ADR in `docs/adr/NNNN-*.md` (ports/adapters) | **production** only |
| 3 — Implement | `developer` ×N | the code (one story per worker) | always |
| 4 — Verify | `qa-engineer` | `qa/<id>.md` — acceptance criteria + `verify.sh` | always (integration QA on **production**) |
| 5 — Deploy | `devops` | CI/CD updates (never prod without human approval) | always |
| 6 — Promote | `marketing` + `sales-feedback` | release notes + data summary | always |
| 7 — Index | _(no subagent)_ | regenerated `docs/wiki/index.md` | when `wiki.enabled` |

`docs/rigor-level.md` (`prototype` | `production`) decides whether waves 2 and
the integration-QA half of wave 4 run. Wave 3 has three execution paths —
plain subagents (baseline), an **Agent Team** (peer-to-peer), or a **Dynamic
Workflow** — selected per the Operate section below.

## Install

Clone the repo, register it as a local marketplace, and install the plugin
from inside Claude Code:

```bash
git clone https://github.com/abaddon/smurf.git ~/src/smurf
cd /path/to/your-project
claude
> /plugin marketplace add ~/src/smurf
> /plugin install smurf@smurf
```

The repo root holds `.claude-plugin/marketplace.json`; the plugin itself
lives under `plugin/` (canonical Claude Code marketplace layout). Local-path
marketplaces resolve live, so edits in `~/src/smurf` take effect
immediately — no copying. Once installed, every `/smurf:*` slash command
becomes available.

## Initialize a project (`/smurf:init`)

```bash
cd /path/to/your-project
claude
> /smurf:init
```

`/smurf:init` runs `scripts/init-project.sh` and creates only what is
missing:

- `verify.sh` — a no-op shim (replace its body with your stack's tests:
  `npm test`, `pytest`, `cargo test`, `mvn verify`, …);
- `docs/rigor-level.md` — `prototype` by default;
- `.claude/runs/next-goal.md` — empty, ready for your first goal;
- gitignore lines for `.claude/runs/`, `.claude/worktrees/`,
  `.claude/settings.local.json`;
- an allow rule in `.claude/settings.local.json` so `/smurf:nightly-run` can
  launch `autonomous-run.sh` without an auto-mode permission denial.

Existing files are never overwritten; the allow rule is merged into any
existing `.claude/settings.local.json`, and your `CLAUDE.md` is never touched.

Then sanity-check the install:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

`doctor.sh` runs 40+ checks split between `[plugin]` (must pass) and
`[project]` (warnings only). It exits non-zero if the plugin install is
broken.

### Adopting smurf into an established codebase (`/smurf:bootstrap`)

If the project already has code, follow `/smurf:init` with a one-shot
reverse-engineering run:

```bash
> /smurf:bootstrap
```

It spawns the standard specialists in BOOTSTRAP MODE — they read the existing
code instead of a goal — and produce: `docs/bootstrap/tech-stack.md` +
`ci-inventory.md`, `docs/feedback/<date>-bootstrap.md` (seed digest from open
GitHub issues), backfilled `docs/stories/bootstrap-<date>/*.feature` and
`docs/adr/NNNN-*.md` (both `Status: proposed`), a `qa/bootstrap-<date>.md`
cite-check, and a `rigor-level-recommendation.md`. Each wave is committed as
`docs(bootstrap): wave <A–E>: …`. Review the artifacts, flip
`Status: proposed → accepted` on the ones you agree with, then write your
first goal and run `/smurf:kickoff-team`.

Flags: `--no-feedback` (skip sales-feedback), `--rigor prototype|production`
(override detection).

## Operate

**Interactive** (any time):

```bash
claude
> /smurf:kickoff-team "<your goal>"
```

**Autonomous** (headless, from the goal file):

```bash
echo "<your goal>" > .claude/runs/next-goal.md
claude
> /smurf:nightly-run
```

`/smurf:nightly-run` runs `autonomous-run.sh`: a headless `claude -p`
orchestrator loop with a 4h watchdog (SIGTERM → partial summary), the
resolved budget cap, and a full run record under `.claude/runs/<ts>/`.

**Scheduled** (cron):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-cron.sh"
```

The installer is idempotent and exports `CLAUDE_PROJECT_DIR=<your project>`
and `CLAUDE_PLUGIN_ROOT=<plugin location>` so the headless run resolves the
plugin correctly.

**Peer-to-peer wave 3 (Agent Teams).** `/smurf:kickoff-team` *attempts* an
Agent Team for wave 3 (developers, qa-engineer, and an architect-advisor
talking via `SendMessage`) and degrades to plain subagent mode when the host
doesn't support it. To enable it, set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
in your project's `.claude/settings.local.json` — the plugin cannot set this
for you. The host must also expose the full `Team*`/`Task*`/`SendMessage`
dispatch surface; a probe runs before `TeamCreate` and degrades visibly on a
miss.

**Dynamic Workflows (experimental):**

```bash
> /smurf:kickoff-workflow "<goal with many independent parallel features>"
```

Research-preview. The gate is settings/version-based (not a tool probe):
workflows must not be disabled (no `disableWorkflows` in project settings, no
`CLAUDE_CODE_DISABLE_WORKFLOWS=1` in the environment) and the host CLI must be
workflows-capable (Claude Code ≥ 2.1.111) on Opus 4.8. On a miss it bails with
a precise reason rather than degrading silently.

## Commands

| Command | What it does |
|---------|--------------|
| `/smurf:init` | Scaffold project stubs (idempotent; never overwrites). |
| `/smurf:bootstrap` | Reverse-engineer an existing codebase into stories/ADRs/feedback/tech-stack docs. Flags: `--no-feedback`, `--rigor prototype\|production`. |
| `/smurf:kickoff-team "<goal>"` | **Default kickoff.** Subagent waves; wave 3 attempts an Agent Team, degrades to subagents if unsupported. |
| `/smurf:kickoff-workflow "<goal>"` | Experimental. Expresses wave 3 as a host Dynamic Workflow (settings/version-gated). |
| `/smurf:nightly-run` | Headless autonomous run from `.claude/runs/next-goal.md` via `autonomous-run.sh`. |
| `/smurf:close-loop` | Cross-run feedback digest → `docs/feedback/<date>.md` + wiki health lint. Arg: `[--window 7d]`. |

## Configuration

### Precedence — project override wins, **whole file**

Smurf resolves policy from exactly one file: your project's
`.claude/policy.yaml` if it exists, otherwise the plugin default at
`${CLAUDE_PLUGIN_ROOT}/policy.yaml`.

> ⚠️ **The override is whole-file, not per-key.** When a project
> `.claude/policy.yaml` is present, smurf reads *only* that file. Keys you
> omit do **not** fall back to the plugin's value — they fall back to each
> consumer's built-in default (e.g. `autonomous-run.sh` defaults budget to
> `12` and turns to `200`). So **copy the plugin `policy.yaml` as your
> starting point and edit it**, rather than writing a partial file.

### `policy.yaml` parameters

Every key, with its shipped default. (Source of truth:
`${CLAUDE_PLUGIN_ROOT}/policy.yaml`.)

**Guardrails**

| Key | Default | Purpose |
|-----|---------|---------|
| `forbidden_paths` | `[".git/**", ".env", ".claude/runs/next-goal.md"]` | Glob paths agents may never write to (enforced by the policy-guard hook). |
| `forbidden_patterns` | `[]` | Regexes blocked in file *content* on write. Add your domain rules here (secrets, banned APIs). |
| `verify_command` | `"./verify.sh"` | The single verify entrypoint. The pre-commit-verify hook runs it and blocks the commit on non-zero exit. |

**Caps & concurrency**

| Key | Default | Purpose |
|-----|---------|---------|
| `max_qa_iterations` | `2` | Max times the orchestrator re-dispatches `developer` after a failing QA report before it escalates. |
| `max_parallel_subagents` | `4` | Max subagents in flight at once (token-burn guard). |
| `max_turns_orchestrator` | `200` | **Enforced** — passed as the headless session's `--max-turns`. |
| `max_turns_subagent` | `30` | Advisory per-subagent turn cap used at dispatch. |
| `max_workflow_subagents` | `64` | Advisory fan-out cap passed into the Dynamic-Workflow wave-3 prompt (host enforces its own ~16-concurrent / 1,000-total limit). |

**Budgets** (USD ceilings for autonomous runs)

| Key | Default | Purpose |
|-----|---------|---------|
| `budget_usd_subagent` | `12` | Cost ceiling for subagent-mode runs. |
| `budget_usd_team` | `25` | Cost ceiling for Agent-Teams runs (peer-to-peer burns 7–15× the tokens of subagent mode). |
| `budget_usd_workflow` | `60` | Cost ceiling for Dynamic-Workflow runs (can fan out to ~1,000 subagents). |

**Wiki layer** (`wiki.*` — see `docs/specs/15-wiki.md`)

| Key | Default | Purpose |
|-----|---------|---------|
| `wiki.enabled` | `true` | Master switch for the wiki layer (index + log + health). Set `false` to opt out entirely. |
| `wiki.index_path` | `"docs/wiki/index.md"` | Topic-bucketed index of ADRs/stories/feedback, regenerated by wave 7. |
| `wiki.log_path` | `"docs/wiki/log.md"` | Append-only run log, one row per run. |
| `wiki.health_path` | `"docs/wiki/health.md"` | Lint report (cite-check, port-conflict, orphan-story), overwritten at each close-loop. |
| `wiki.lint_orphan_days` | `30` | `Status: proposed` stories older than this are flagged INFO (`docs/stories/bootstrap-*/` are exempt). |

**Supplementary review** (`review.*` — see `docs/specs/16-workflows-and-ultrareview.md`)

| Key | Default | Purpose |
|-----|---------|---------|
| `review.ultrareview` | `auto` | `auto` = run `/ultrareview` when the host supports it (CLI ≥ 2.1.111). `off` = never. **Caveat:** `/ultrareview` sends code off-box to a cloud multi-agent reviewer. |

### Example project override (`.claude/policy.yaml`)

A complete, copy-and-edit override that tightens spend, narrows parallelism,
adds project guardrails, and opts out of the off-box reviewer. Keys left at
the plugin default are shown for completeness — remember the override is
whole-file:

```yaml
# .claude/policy.yaml — project override (read in full; copy from the plugin
# default and edit). Any key omitted here falls back to the consuming
# script's built-in default, NOT to the plugin policy.yaml.

forbidden_paths:
  - ".git/**"
  - ".env"
  - ".claude/runs/next-goal.md"
  - "infra/secrets/**"          # project-specific: never let an agent touch secrets

forbidden_patterns:
  - "AKIA[0-9A-Z]{16}"          # block AWS access key ids in file content
  - "-----BEGIN [A-Z ]*PRIVATE KEY-----"

verify_command: "./verify.sh"

max_qa_iterations: 3            # allow one extra fix cycle
max_parallel_subagents: 2      # smaller machine / tighter token budget
max_turns_orchestrator: 200
max_turns_subagent: 30
max_workflow_subagents: 64

budget_usd_subagent: 8         # lower nightly ceiling for this repo
budget_usd_team: 25
budget_usd_workflow: 60

wiki:
  enabled: true
  index_path: "docs/wiki/index.md"
  log_path: "docs/wiki/log.md"
  health_path: "docs/wiki/health.md"
  lint_orphan_days: 30

review:
  ultrareview: off             # don't send this codebase off-box
```

### Environment variables

**Credentials** — copy `.env.example` → `.env` (gitignored) and fill in:

| Var | Required? | Purpose |
|-----|-----------|---------|
| `ANTHROPIC_API_KEY` | optional | Leave empty under Claude Code subscription auth; set for raw API auth. |
| `GITHUB_TOKEN` | for GitHub MCP | PAT for the `github` MCP server. Scopes: `repo`, `read:org`, `read:user`. |
| `OPENROUTER_API_KEY` | for marketing/sales | Cheap-LLM provider used by the `marketing` and `sales-feedback` agents. |
| `SLACK_WEBHOOK` | optional | If set, `autonomous-run.sh` posts the run summary to Slack. |
| `ANTHROPIC_BASE_URL` | optional | Failover base URL (e.g. OpenRouter Anthropic Skin) when first-party Anthropic is degraded. |
| `ANTHROPIC_AUTH_TOKEN` | with `BASE_URL` | Auth token for the failover base URL. |

**Run tuning & feature flags** — set in the shell/cron env or
`.claude/settings.local.json` as noted:

| Var | Default | Purpose |
|-----|---------|---------|
| `MODE` | `subagent` | `subagent` or `team` — selects which `budget_usd_*` tier `autonomous-run.sh` uses. |
| `BUDGET_OVERRIDE` | _(policy)_ | Override the resolved budget for one run (USD). |
| `WATCHDOG_OVERRIDE` | `4h` | Override the autonomous-run watchdog timeout (e.g. `30m`, `10s`). |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | _(unset)_ | Set to `1` (in `.claude/settings.local.json`) to enable the Agent-Teams wave-3 path. |
| `CLAUDE_CODE_DISABLE_WORKFLOWS` | _(unset)_ | If `1`, the Dynamic-Workflows gate fails and `/smurf:kickoff-workflow` bails. |

### Project-side files

| Path | What it is |
|------|------------|
| `.claude/runs/next-goal.md` | The goal text autonomous runs read. |
| `.claude/policy.yaml` | Optional whole-file policy override (above). |
| `.claude/settings.local.json` | Per-user settings: the autonomous-run allow rule, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, etc. Gitignored. |
| `docs/rigor-level.md` | `prototype` (skip architect + integration QA) or `production`. |
| `verify.sh` | Your test/build entrypoint. Replace the no-op default. |
| `.mcp.json` | MCP servers for the project (`github` is the default). |
| `qa/<id>.md` | QA reports, written by the qa-engineer in wave 4 and committed for traceability. |
| `${CLAUDE_PLUGIN_ROOT}/smurf.md` | Smurf's hand-written operating manual. Agents read it at pre-flight; don't let an agent rewrite it. |

## Wiki layer

Enabled by default. On every run smurf:

- regenerates `docs/wiki/index.md` (wave 7) — a topic-bucketed index of ADRs,
  stories, and feedback that product-owner and architect read at pre-flight;
- appends one row to `docs/wiki/log.md` — an append-only audit trail
  (committed, so it survives the gitignored `.claude/runs/`);
- on each `close-loop`, writes `docs/wiki/health.md` with cite-check,
  port-conflict, and orphan-story findings. A missing cite on a
  `Status: accepted` ADR is a **FAIL** (`close-loop` exits 2).

Opt out with `wiki.enabled: false`. See `docs/specs/15-wiki.md`.

## Agents & skills

**Agents** (`${CLAUDE_PLUGIN_ROOT}/agents/`): `orchestrator` (the main-session
coordinator — never a subagent), `product-owner`, `architect` (also runs as
`architect-advisor` in Agent Teams), `developer`, `qa-engineer`, `devops`,
`marketing`, `sales-feedback`.

**Skills** (`${CLAUDE_PLUGIN_ROOT}/skills/`): `adr-template`, `code-quality`,
`conventional-commits`, `gherkin-stories`, `openrouter-curl`.

## Extend

- **New project rule?** Add a regex to `forbidden_patterns` (or a glob to
  `forbidden_paths`) in your host's `.claude/policy.yaml` override.
- **New role or skill?** Contribute it to the plugin: drop `agents/<name>.md`
  or `skills/<name>/SKILL.md` inside the plugin repo and reinstall.

## First-run goals (suggestions)

If you've just installed smurf and don't know what to point it at:

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

## Version & status

**v1.0.20.** All phases shipped:

- Phase 1: orchestrator + developer + qa-engineer minimal loop.
- Phase 2: full subagent suite + slash commands.
- Phase 3: hooks + `policy.yaml` + hook smoke-test suite (`tests/`).
- Phase 4: skills + rigor-level branching.
- Phase 5: `autonomous-run.sh` + watchdog + `install-cron.sh` + `doctor.sh`.
- Phase 6a: Agent Teams wave-3 with architect-advisor.
- Phase 6b: OpenRouter shell-out for marketing/sales.
- Phase 7: `close-loop.py` cross-run feedback + specs.
- Phase 8: wiki layer (`docs/wiki/` index + run log + lint health report).
- Phase 9: Dynamic Workflows (`/smurf:kickoff-workflow`) + `/ultrareview` QA
  integration (experimental, research-preview).

See `docs/specs/00-overview.md` for the spec index and `docs/operations.md`
for runbooks.

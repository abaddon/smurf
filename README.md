# smurf

Self-agentic orchestrator built on Claude Code. A team of specialist
subagents (product-owner, architect, developer, qa-engineer, devops,
marketing, sales-feedback) plans, implements, verifies, and reports on
goals you write into `.claude/runs/next-goal.md`.

The system iterates: QA failures re-dispatch the developer (capped); a
nightly `close-loop.py` writes `docs/feedback/<date>.md` consumed by the
product-owner at the next kickoff.

## Install in another project

```bash
git clone https://github.com/<you>/smurf.git /tmp/smurf
bash /tmp/smurf/scripts/install.sh /path/to/your-project
cd /path/to/your-project
bash scripts/doctor.sh
```

The installer is idempotent — running it twice is a no-op. It copies the
portable parts (`.claude/agents`, `hooks`, `skills`, `commands`,
`policy.yaml`, `settings.json`, `.claude/smurf.md`, `docs/specs/`, the
orchestrator scripts) and scaffolds project-specific stubs only when
they are missing (`docs/rigor-level.md`, `verify.sh`,
`.claude/runs/next-goal.md`, `.mcp.json`). It never touches your
project's `CLAUDE.md`.

Smurf's manual lives at `.claude/smurf.md`, not `CLAUDE.md`, so it
never collides with your project's existing instructions. To inherit
Smurf's house rules in every Claude Code session (not just Smurf agent
runs), append `@.claude/smurf.md` to your `CLAUDE.md`.

After install: replace the no-op `verify.sh` body with your stack's
tests, extend `bash_allowlist` and `forbidden_patterns` in
`.claude/policy.yaml`, then write your first goal to
`.claude/runs/next-goal.md`.

## Operate

Interactive (any time):

```bash
claude
> /kickoff "<your goal>"
```

Autonomous (Phase 5+):

```bash
echo "<your goal>" > .claude/runs/next-goal.md
bash scripts/autonomous-run.sh
# or install cron:
bash scripts/install-cron.sh
```

Force Agent-Teams (peer-to-peer wave 3, Phase 6a+):

```bash
> /kickoff-team "<goal with parallel features>"
```

## Configure

- `.claude/smurf.md` — Smurf's operating manual. Hand-written. Don't let an agent rewrite it. Lives under `.claude/` so it never collides with a host project's own `CLAUDE.md`.
- `.claude/policy.yaml` — every cap and allowlist. Single source of truth.
- `docs/rigor-level.md` — `prototype` (skip architect+integration QA) or `production`.
- `verify.sh` — your project's test/build entrypoint. Replace the no-op default.
- `.mcp.json` — MCP servers. Defaults to `github`; uncomment placeholders as needed.

## Extend

- New project rule? Add a regex to `forbidden_patterns` in `.claude/policy.yaml`.
- New tooling? Extend `bash_allowlist` in `.claude/policy.yaml`.
- New role? Drop a `.claude/agents/<name>.md` file with frontmatter + system prompt.
- New cross-cutting knowledge? Drop a skill at `.claude/skills/<name>/SKILL.md`.

## First-run goals (suggestions)

If you've just installed smurf and don't know what to point it at,
start with one of these:

```bash
# 1. Self-test: prove the loop works end-to-end on something trivial.
echo "Add scripts/version.sh that prints git rev-parse --short HEAD;
extend verify.sh so it asserts the script's output is exactly 7 hex chars." \
  > .claude/runs/next-goal.md

# 2. Extend the orchestrator's policy with a new project rule.
echo "Add a forbidden_pattern to .claude/policy.yaml that blocks any
file containing 'TODO' without a referenced ticket id, then update
docs/specs/09-hooks-and-policy.md to document the new rule." \
  > .claude/runs/next-goal.md

# 3. Multi-feature run (use /kickoff-team for parallelism).
echo "Add scripts/version.sh AND scripts/changelog.sh — independent
features, can be developed in parallel." > .claude/runs/next-goal.md
MODE=team bash scripts/autonomous-run.sh
```

## Status

All 7 phases shipped:
- Phase 1: orchestrator + developer + qa-engineer minimal loop.
- Phase 2: full subagent suite + slash commands.
- Phase 3: 6 hooks + policy.yaml + 13/13 hook smoke tests pass.
- Phase 4: 5 skills + rigor-level branching.
- Phase 5: `autonomous-run.sh` + watchdog + `install-cron.sh` + `doctor.sh` (44 checks).
- Phase 6a: Agent Teams wave-3 with architect-advisor.
- Phase 6b: OpenRouter shell-out for marketing/sales.
- Phase 7: `close-loop.py` cross-run feedback + 14 specs.

See `docs/specs/00-overview.md` for the spec index, `docs/operations.md`
for runbooks, and `docs/research.md` for the research that informed it.

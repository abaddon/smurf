# Smurf — Operating Manual

Smurf is a self-agentic orchestrator distributed as a Claude Code
plugin. A team of specialist subagents plans, implements, verifies,
and reports on goals written into `.claude/runs/next-goal.md` in the
host project. The system iterates on its own output (QA → developer
re-dispatch) and on its own backlog (cross-run feedback file consumed
at next kickoff).

Architecture and design background: see the smurf development repo's
`docs/research.md` (recommended Architecture A) and
`docs/specs/00-overview.md`.

## RIGOR_LEVEL

Read from `docs/rigor-level.md`. Two values:

- **prototype** — skip the architect wave; QA may stop at unit tests; ADRs
  are optional. Use this for spikes and throwaway code.
- **production** — force the architect wave; QA includes integration tests
  via `./verify.sh`; every new bounded concept gets an ADR in `docs/adr/`.

## PROJECT_INVARIANTS

Smurf is project-agnostic. Project-specific invariants belong in
`.claude/policy.yaml` (`forbidden_patterns`) inside the host project.
The plugin ships only sane defaults.

## AGENT_CONTRACT

Operational caps live in `policy.yaml`. Resolution order:

1. Project override: `${CLAUDE_PROJECT_DIR}/.claude/policy.yaml` (if present).
2. Plugin default: `${CLAUDE_PLUGIN_ROOT}/policy.yaml`.

Current keys:

- `max_parallel_subagents`, `max_turns_orchestrator`, `max_turns_subagent`
- `budget_usd_subagent`, `budget_usd_team`, `max_qa_iterations`
- `forbidden_paths`, `forbidden_patterns`, `verify_command`
- `wiki.{enabled,index_path,log_path,health_path,lint_orphan_days}` — see
  `docs/specs/15-wiki.md`. When `wiki.enabled: true` (the shipped default),
  wave 7 regenerates the index, every run appends a row to the log, and
  `close-loop.py` writes a lint health report.

Edit `policy.yaml`, never hard-code numbers in agent prompts or scripts.

## WIKI ETIQUETTE

Agents do NOT speculatively author or edit anything under `docs/wiki/`.
That directory is owned by three scripts (`build-wiki-index.py`,
`append-wiki-log.py`, `wiki_lint.py`) and the orchestrator's wave 7. The
product-owner and architect READ `docs/wiki/index.md` and
`docs/wiki/health.md` at pre-flight; nobody else reads them and nobody
writes them by hand. This is consistent with house rule #3 (touch only
what you must).

## PRE-FLIGHT (every agent, every run)

1. Read `${CLAUDE_PROJECT_DIR}/docs/rigor-level.md`.
2. Read every file in `${CLAUDE_PROJECT_DIR}/docs/feedback/` modified in
   the last 14 days.
3. Read `policy.yaml` (project override or plugin default) for current caps.
4. Plan before edit. Use plan mode for non-trivial work.

## ESCALATION (stop and request human review)

- New external dependency (npm package, API integration, infra service)
- Security-related change (auth, crypto, secret handling)
- Public API contract change (route/method signature touching consumers)
- Deletion of more than 100 lines in a single change
- Any modification to the smurf plugin tree at `${CLAUDE_PLUGIN_ROOT}/`

When escalating, write a one-paragraph summary to
`${CLAUDE_PROJECT_DIR}/.claude/runs/<ts>/escalation.md` and exit cleanly.

## TONE / STYLE

The four house rules below apply to every agent:

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

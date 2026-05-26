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

## HOUSE RULES

These four rules apply to every agent. They bias toward caution over
speed. Agents cite them by number elsewhere in the plugin (e.g.
`developer.md` references rule #2 and #3), so renumbering breaks refs.

### 1. Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:
- State assumptions explicitly. If uncertain, ask via `AskUserQuestion`
  (or escalate per ESCALATION above if non-interactive).
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Minimum code that solves the problem. Nothing speculative.

- No features beyond the acceptance criteria in the assigned story.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you wrote 200 lines and it could be 50, rewrite it. Measurable
  complexity ceilings live in the `code-quality` skill.

Ask yourself: "would a senior engineer say this is overcomplicated?"
If yes, simplify.

### 3. Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd write it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the assigned
story or the user's request.

### 4. Define success criteria. Loop until verified.

Every wave has explicit success criteria — acceptance criteria in
Gherkin stories, ADR ports/adapters, `./verify.sh` exit 0. Read them
before starting. Loop locally until they pass — don't return for
clarification on a check you can run yourself.

Strong success criteria let you loop independently. Weak criteria
("make it work") require constant clarification — when you find
yourself with weak criteria, surface that (rule #1) before coding.

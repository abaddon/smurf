# Smurf — Operating Manual

This repo hosts a self-agentic orchestrator built on Claude Code. A team of
specialist subagents plans, implements, verifies, and reports on goals
written into `.claude/runs/next-goal.md`. The system iterates on its own
output (QA → developer re-dispatch) and on its own backlog (cross-run
feedback file consumed at next kickoff).

Architecture: see `docs/research.md` (the recommended Architecture A) and
`docs/specs/00-overview.md` (this project's adaptation).

## RIGOR_LEVEL

Read from `docs/rigor-level.md`. Two values:

- **prototype** — skip the architect wave; QA may stop at unit tests; ADRs
  are optional. Use this for spikes and throwaway code.
- **production** — force the architect wave; QA includes integration tests
  via `./verify.sh`; every new bounded concept gets an ADR in `docs/adr/`.

## PROJECT_INVARIANTS

This is a generic orchestrator host. Project-specific invariants belong in
`.claude/policy.yaml` (`forbidden_patterns`) and as bullets here once the
project grows real code:

- (none yet — fill in as the project takes shape)

## AGENT_CONTRACT

All operational caps live in `.claude/policy.yaml` — single source of
truth. Agents must read that file before acting. Current keys:

- `max_parallel_subagents`, `max_turns_orchestrator`, `max_turns_subagent`
- `budget_usd_subagent`, `budget_usd_team`, `max_qa_iterations`
- `bash_allowlist`, `forbidden_paths`, `forbidden_patterns`, `verify_command`

Edit `policy.yaml`, never hard-code numbers in agent prompts or scripts.

## PRE-FLIGHT (every agent, every run)

1. Read `docs/rigor-level.md`.
2. Read every file in `docs/feedback/` modified in the last 14 days.
3. Read `.claude/policy.yaml` for current caps.
4. Plan before edit. Use plan mode for non-trivial work.

## ESCALATION (stop and request human review)

- New external dependency (npm package, API integration, infra service)
- Security-related change (auth, crypto, secret handling)
- Public API contract change (route/method signature touching consumers)
- Deletion of more than 100 lines in a single change
- Any modification to the `.claude/` tree itself

When escalating, write a one-paragraph summary to
`.claude/runs/<ts>/escalation.md` and exit cleanly.

## TONE / STYLE

The four house rules below apply to every agent:

1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.

# Smurf — Domain Glossary

Ubiquitous language for the orchestrator itself. Add entries as the
project's domain grows. Each entry: term — definition (one paragraph).

- **Goal** — A natural-language task written into `.claude/runs/next-goal.md`
  and consumed by the orchestrator on `/smurf:kickoff` or by
  `autonomous-run.sh`. One goal per run.

- **Wave** — A discrete phase of a single run: Product, Design, Implement,
  Verify, Deploy, Promote. Waves are sequential at the orchestrator level;
  individual workers within a wave may run in parallel (subagent fan-out
  or Agent Team).

- **Run** — One end-to-end execution from goal to summary. State lives
  under `.claude/runs/<timestamp>/`. Each run is independent; cron does
  not resume across runs (Agent Teams caveat — see `docs/specs/14-iteration-and-budgets.md`).

- **Story** — A Gherkin-format feature spec produced by the product-owner,
  stored under `docs/stories/<sprint>/`. One story = one developer
  invocation.

- **Iteration** — A QA → developer re-dispatch cycle within a single wave.
  Capped by `max_qa_iterations` in the resolved policy file (project
  override `.claude/policy.yaml` if present, otherwise plugin default
  `${CLAUDE_PLUGIN_ROOT}/policy.yaml`).

- **Feedback file** — A markdown digest written nightly by `close-loop.py`
  to `docs/feedback/<date>.md`. Consumed by the product-owner at the start
  of the next run to inform new stories.

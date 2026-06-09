---
description: Analyze an existing project and reverse-engineer the docs smurf relies on (ADRs, stories, feedback seed, tech-stack & CI inventories, rigor-level recommendation). Run once when adopting smurf into an established codebase.
argument-hint: [--no-feedback] [--rigor prototype|production]
---

# Smurf — Bootstrap an existing project

This is a **one-shot reverse-engineering run**, not a forward goal. You,
the invoking session, act as a temporary **bootstrap-orchestrator**. You
spawn the standard smurf specialist subagents (`developer`, `devops`,
`sales-feedback`, `product-owner`, `architect`, `qa-engineer`) with
explicit BOOTSTRAP-MODE prompts that override their default
`next-goal.md`-driven contracts. When you finish, the project has the
artifacts smurf needs to make good decisions on the next `/smurf:kickoff-team`.

The bootstrap targets `${CLAUDE_PROJECT_DIR:-$PWD}`. Treat the source
tree as read-only ground truth. Do not refactor code. Do not invent
features. Cite source paths verbatim.

## 0. Pre-flight (do this yourself, sequentially)

1. Read `${CLAUDE_PLUGIN_ROOT}/smurf.md` and the active policy
   (`${CLAUDE_PROJECT_DIR}/.claude/policy.yaml` if it exists, else
   `${CLAUDE_PLUGIN_ROOT}/policy.yaml`). Note caps:
   `max_parallel_subagents`, `max_qa_iterations`,
   `max_turns_orchestrator`.
2. Check that `${CLAUDE_PROJECT_DIR}/docs/rigor-level.md` exists. If
   it does not, stop immediately and tell the user:
   "Run `/smurf:init` first — bootstrap requires the project stubs."
3. Inventory what is already there with `Glob`:
   - `docs/adr/*.md` — highest existing ADR number → next ADR is N+1
   - `docs/stories/**/*.feature` — existing story ids/sprints
   - `docs/feedback/*.md` — most recent feedback file
   - `docs/bootstrap/**` — if present, this command has run before
4. Detect signals to recommend a rigor level (used in Wave E):
   - tests present? (`tests/`, `__tests__/`, `*_test.go`, `*.spec.*`, etc.)
   - CI config? (`.github/workflows/*.yml`, `.circleci/`, `.gitlab-ci.yml`)
   - container files? (`Dockerfile`, `docker-compose*.yml`)
   If a `--rigor` flag is in `$ARGUMENTS`, honour it verbatim. Otherwise
   recommend `production` only if tests **and** CI both exist.
5. Compute a bootstrap sprint id: `bootstrap-YYYY-MM-DD` from today's
   date. Compute a run id `bootstrap-<ts>` where `<ts>` is
   `date +%Y%m%d-%H%M%S`. Create `.claude/runs/<run-id>/` and
   `docs/bootstrap/`.

Announce the plan in chat (one short paragraph) and proceed —
this command is non-interactive by default. If you intend to skip
sales-feedback (because `--no-feedback` is in `$ARGUMENTS` or the
project has no git remote configured), say so explicitly.

## 1. Wave plan

All waves spawn smurf subagents via `Task`. Apply
`max_parallel_subagents` from policy when fanning out. Each agent's
default PRE-FLIGHT still runs — the BOOTSTRAP-MODE block in the prompt
body replaces only its CONTRACT. After every wave, commit the new files
with separate `git add <paths>` and
`git commit -m 'docs(bootstrap): <wave>: <summary>'` calls (one Bash
call per command — no compound commands).

### Wave A — Inventory (parallel, read-only)

Spawn these three subagents in parallel:

**A1. `developer` — tech-stack inventory**
```
BOOTSTRAP MODE — read-only inventory, do NOT implement.

Override your default CONTRACT: there is no story file. Your task is
to read the existing project and write a single inventory document
at `docs/bootstrap/tech-stack.md` with these sections:

## Languages and runtimes
- list each language with its declared version (parse package.json,
  pyproject.toml, go.mod, Cargo.toml, pom.xml, Gemfile, etc.)

## Frameworks and key libraries
- one bullet per major framework/library, cite the manifest line

## Test runner and conventions
- how `./verify.sh` should call the project's tests
- existing test directory layout

## Build / run commands
- the actual command(s) a contributor uses today

## Conventions detected
- formatter / linter configs found (.editorconfig, .prettierrc, ruff.toml, ...)
- commit message style if a CHANGELOG or git log makes it obvious
- directory layout (src/, app/, lib/, cmd/, ...)

Rules:
- Do NOT edit any source file. Do NOT run `./verify.sh`.
- Cite the manifest path for every claim.
- If a section has no signal, write exactly: "unknown — needs human input".
- Skip the conventional-commits step. Skip the verify.sh requirement.
  Do NOT call TaskUpdate (this run is subagent-mode, not Agent Teams).

Output: the single file above. Final chat message: one-line summary
of languages + frameworks detected.
```

**A2. `devops` — CI / container / observability inventory**
```
BOOTSTRAP MODE — read-only inventory, do NOT modify CI or open a PR.

Override your default CONTRACT. Your task is to inventory existing
DevOps configuration and write `docs/bootstrap/ci-inventory.md`:

## CI workflows
- one section per `.github/workflows/*.yml`, `.circleci/config.yml`,
  `.gitlab-ci.yml`, `Jenkinsfile`, etc. Cite the file path. Summarize
  stages (lint / test / build / deploy) in 2-3 lines each.

## Container / packaging
- Dockerfiles: base image + final stage's CMD/ENTRYPOINT
- docker-compose services with their port maps
- Helm charts / k8s manifests if present

## Observability hooks
- OpenTelemetry, Sentry, Prometheus, log shipping config detected

## Deploy targets
- read from CI files: where does this project deploy today?

Rules:
- NEVER run `gh pr create`. NEVER edit any workflow.
- If a section has no signal, write exactly: "none detected".

Output: the single file. Final chat message: one-line summary.
```

**A3. `sales-feedback` — seed feedback digest**

If `--no-feedback` is in `$ARGUMENTS`, skip this subagent entirely.
Otherwise prompt:
```
BOOTSTRAP MODE — seed run, time window: last 90 days.

Run your normal CONTRACT but write to
`docs/feedback/<today>-bootstrap.md` (note the `-bootstrap` suffix)
so the file is identifiable. Limit yourself to:
- top 10 open GitHub issues by reactions (skip cleanly if `gh` is
  unauthenticated or no remote is configured — write a file
  containing only `# Feedback digest — bootstrap\n\n_no signal
  available; populate via /smurf:close-loop after configuring
  MCP servers_` and exit GREEN)
- top 5 closed-recently issues that look like requests, not bugs
- a single "Suggested next-sprint priorities" section with at most
  3 items, each linking to the issue
- omit MAU / churn / Sentry sections — those require live MCP data
  the bootstrap run cannot assume.

All other rules in your default CONTRACT apply.
```

After A1–A3 return, stage and commit (three separate Bash calls —
no compound commands):

1. `git add docs/bootstrap/tech-stack.md docs/bootstrap/ci-inventory.md`
   (omit any path the corresponding subagent did NOT write). If A3 ran
   and produced `docs/feedback/<today>-bootstrap.md`, add that too.
2. `git commit -m "docs(bootstrap): wave A — tech-stack, CI, and feedback seed"`
3. `git status` (sanity).

### Wave B — Backfill user stories

Spawn `product-owner` once with this prompt:
```
BOOTSTRAP MODE — reverse-engineer stories from existing code.

Override your CONTRACT and your CLARIFY BEFORE DRAFTING block.
There is no goal. You will NOT call AskUserQuestion in this run —
the goal is fixed: describe what the project already does, in
Gherkin, so smurf can plan future changes against it.

Inputs to read before drafting:
- `docs/bootstrap/tech-stack.md` (wave A output)
- `docs/bootstrap/ci-inventory.md` (wave A output)
- `docs/feedback/<today>-bootstrap.md` if it exists
- The project README and any `docs/` user-facing content
- Top-level source directories — list with Glob, then read entry
  points (main.go, src/index.ts, app.py, cmd/*, routes/*, etc.)
- Existing tests — they often encode acceptance criteria; map them
  back to user-visible behaviours.

Produce one `.feature` file per coherent user-visible capability
under `docs/stories/bootstrap-<YYYY-MM-DD>/<NN>-<slug>.feature`.
Aim for 5–12 stories total; coalesce micro-features. Each story:

- **Status: proposed** (header in trailing markdown block)
- **Source: bootstrap** plus the source-file path(s) you derived
  it from (verbatim)
- **NFR**: write `unknown — needs sales-feedback` for any metric
  you cannot derive from the code or feedback file
- **Priority**: `must` for stories whose code is on the critical
  path, `should` otherwise. Never invent `wont`.
- **Clarifications**: omit (no clarification round runs in
  bootstrap mode).

Rules from your default CONTRACT that STILL apply:
- Never propose implementation details inside a story.
- Never delete existing stories. If a story you would write
  duplicates an existing one in `docs/stories/`, skip it and
  mention the duplicate in your final chat summary.
- After writing the files, `git add` them yourself but do NOT
  commit — the bootstrap-orchestrator will commit the wave.

Output: the new story files. Final chat message: the standard
table (id | title | priority | source) and the count of stories
created vs. skipped-as-duplicate.
```

After PO returns, commit:
`docs(bootstrap): wave B — backfill stories from existing code`

### Wave C — Extract architecture decisions

Spawn `architect` once with this prompt:
```
BOOTSTRAP MODE — extract implicit decisions from existing code.

Override your CONTRACT. There is no new feature being designed.
Your task is to identify the major design decisions ALREADY
embedded in the codebase and record them as ADRs so smurf can
reason about them on future runs.

Inputs to read:
- `docs/bootstrap/tech-stack.md`, `docs/bootstrap/ci-inventory.md`
- Every `.feature` file under `docs/stories/bootstrap-<YYYY-MM-DD>/`
  (wave B output)
- Existing `docs/adr/` (highest number → next ADR is N+1)
- Source structure — focus on: persistence layer choice, transport
  layer (HTTP / gRPC / queues), authentication approach, async
  boundaries, error-handling strategy, deployment topology,
  observability stack, multi-tenant boundaries if any.

Produce 4–10 ADRs at `docs/adr/<NNNN>-<slug>.md` using the standard
template (see `${CLAUDE_PLUGIN_ROOT}/skills/adr-template/SKILL.md`)
with these adjustments:

- **Status: proposed** (the team must confirm — the code is
  evidence but the decision rationale is inferred).
- **Date**: today's date.
- **Stories**: cite the bootstrap story ids that depend on this
  decision; cite all bootstrap stories under
  `docs/stories/bootstrap-<YYYY-MM-DD>/` as a comma-separated list
  if the ADR is foundational.
- **Context** must reference the source files that prove the
  decision is in force (verbatim paths).
- **Consequences**: split positive / negative / neutral as usual,
  but base every bullet on observed behaviour, not speculation.
- **Ports / Adapters**: list the actual modules — do not propose
  refactors.
- **Sequence diagram**: only if the existing code makes one
  derivable; otherwise omit the section.

Rules from your default CONTRACT that STILL apply:
- Numbering: sequential from highest existing, never reused.
- Never edit src/.
- After writing the files, `git add` them yourself but do NOT
  commit — the bootstrap-orchestrator will commit the wave.

Output: the new ADR files. Final chat message: the standard list
of ADR ids and their port/adapter names.
```

After architect returns, commit:
`docs(bootstrap): wave C — extract ADRs from existing code`

### Wave D — Verify the bootstrap output

Spawn `qa-engineer` once with this prompt:
```
BOOTSTRAP MODE — cross-check the bootstrap artifacts, do NOT run
`./verify.sh`.

Override your CONTRACT. There is no PR. Your task is to verify
internal consistency of the bootstrap output:

- For every story under `docs/stories/bootstrap-<YYYY-MM-DD>/`,
  confirm the `Source:` paths exist in the repo (`test -e`).
- For every ADR added in this run, confirm the `Context:` source
  paths exist.
- Confirm every ADR's `Stories:` ids correspond to actual story
  files.
- Confirm no story duplicates an earlier `docs/stories/` story by
  title (case-insensitive).
- Confirm `docs/bootstrap/tech-stack.md` and
  `docs/bootstrap/ci-inventory.md` exist and are non-empty.

Write a report at `qa/bootstrap-<YYYY-MM-DD>.md` with sections:
"Stories", "ADRs", "Inventories", each as a small table with
PASS / FAIL / WARN per item.

Rules:
- Do NOT call `./verify.sh` (you are verifying docs, not code).
- Do NOT modify any story or ADR — only report. The
  bootstrap-orchestrator decides whether to re-dispatch wave B/C.
- Do NOT call TaskUpdate (subagent mode, not Agent Teams).

Output: the report file. Final chat message: one line —
`GREEN` or `RED: N items failing, see qa/bootstrap-<YYYY-MM-DD>.md`.
```

If QA returns RED: re-dispatch the relevant wave (B or C) at most
**once** with the QA findings appended to the prompt. If it is still
RED after one re-dispatch, write
`.claude/runs/<run-id>/escalation.md` and stop. Do NOT loop
`max_qa_iterations` times for bootstrap — a second RED here means
the codebase is too ambiguous for automated extraction and a human
must triage.

After QA returns GREEN (or after the single re-dispatch lands
GREEN), stage and commit (three separate Bash calls):

1. `git add qa/bootstrap-<YYYY-MM-DD>.md` (substitute the actual date
   slug used in the QA prompt).
2. `git commit -m "docs(bootstrap): wave D — QA cross-check"`
3. `git status` (sanity).

### Wave E — Recommendations (you, the orchestrator, do this directly)

No subagent. Using the signals from step 0.4 and the wave outputs:

1. Write `docs/bootstrap/rigor-level-recommendation.md` with the
   recommended value (`prototype` or `production`), the reasoning,
   and an explicit instruction line: "To accept, replace the body
   of `docs/rigor-level.md` with the single word above." Do NOT
   overwrite `docs/rigor-level.md` yourself — that file is the
   user's call.
2. The bash guard (`pre-tool-bash-guard.sh`) permits all tooling by
   default — it blocks only a denylist of destructive patterns — so no
   per-project tooling allowlist is needed. If the project warrants a
   `forbidden_paths` / `forbidden_patterns` override, note that in the
   summary; do NOT write `.claude/policy.yaml` directly.
3. Write `.claude/runs/<run-id>/summary.md` with:
   - the goal: "bootstrap smurf in an existing project"
   - waves executed (A, B, C, D, E, F) with one line each
   - counts: stories created, ADRs created, QA verdict
   - recommended rigor level + path to the recommendation file
   - any escalation notes
   - next step: "Review `docs/bootstrap/`, accept ADRs/stories by
     editing `Status: proposed` → `accepted`, then write your
     first goal to `.claude/runs/next-goal.md` and run
     `/smurf:kickoff-team`."

Stage and commit (three separate Bash calls; do NOT add
`.claude/runs/<run-id>/summary.md` — `.claude/runs/` is gitignored):

1. `git add docs/bootstrap/rigor-level-recommendation.md`. If
   `docs/bootstrap/policy-override-suggested.yaml` was written in
   step 2, add that path too in the same `git add` call.
2. `git commit -m "docs(bootstrap): wave E — recommendations and summary"`
3. `git status` (sanity).

### Wave F — Index the bootstrap artifacts (you, the orchestrator, do this directly)

The bootstrap just produced ADRs, stories, and a feedback file —
exactly what `build-wiki-index.py` scans. Without this wave, the
wiki index stays empty until the user's first `/smurf:kickoff-team`. Run
it now so the user has a populated `docs/wiki/` to navigate
immediately.

Skip this wave entirely if `wiki.enabled: false` in the resolved
policy (project override or plugin default).

Issue these Bash calls in order — one per call, no compound commands:

1. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/build-wiki-index.py"`
2. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/append-wiki-log.py"
   `--ts "<run-id>"` (the `bootstrap-<ts>` value from step 0.5)
   `--goal "bootstrap smurf in existing project"`
   `--waves "A,B,C,D,E,F"` `--qa-iterations 0`
   `--status bootstrap` `--pr-url -` `--head-sha "$(git rev-parse --short HEAD)"`
   (one Bash call; arguments shown across lines for readability)

Then commit-only-if-changed using three separate Bash calls. We use
`git diff --cached --name-only` (which always exits 0 — printing
staged paths or nothing) instead of `git diff --cached --quiet`
(which uses exit code 1 as a sentinel and shows up as `Error: Exit
code 1` in the transcript):

3. `git add docs/wiki/index.md docs/wiki/log.md`
4. `git diff --cached --name-only docs/wiki/index.md docs/wiki/log.md`
5. If step 4 printed any path (non-empty stdout), run
   `git commit -m "docs(bootstrap): wave F — index artifacts"`.
   Otherwise run `git reset HEAD docs/wiki/index.md docs/wiki/log.md`
   to unstage and skip the commit (the indexer is idempotent — if it
   ran inside a re-run with nothing new to index, there's nothing to
   commit).

Do NOT run `wiki_lint.py` in bootstrap — wave D already cite-checks
the bootstrap-scoped artifacts; running lint at project scope here
would emit FAIL on the same legitimately-broken cites the bootstrap
is supposed to surface (pre-existing accepted-ADR-equivalents the
bootstrap promoted from code). Lint runs on its normal cadence via
`/smurf:close-loop`.

## 2. Guardrails

- NEVER edit anything under `${CLAUDE_PLUGIN_ROOT}/`.
- NEVER overwrite `docs/rigor-level.md` — recommend, don't decide.
- NEVER overwrite an existing ADR or story file. If your sprint id
  collides with a pre-existing `bootstrap-<date>` directory, append
  `-rerun` to the new sprint id and proceed.
- NEVER call `./verify.sh` — bootstrap is a docs-only run; the
  project's tests may not even pass right now and that is fine.
- NEVER spawn more than `max_parallel_subagents` workers (relevant
  only for wave A's parallel fan-out).
- NEVER push, NEVER open a PR. Bootstrap is a local operation —
  wave F's `git commit` is local-only.

## 3. Argument handling

- `--no-feedback`: skip subagent A3 (sales-feedback).
- `--rigor prototype|production`: bypass detection, use this value
  verbatim in wave E's recommendation file.
- Unknown flags: ignore and proceed; the bootstrap should not fail
  on user typos.

`$ARGUMENTS` is the raw arg string. Parse it yourself with simple
`Grep`-style checks before wave A.

## 4. Idempotency

If `docs/bootstrap/` already exists when you start, you are in a
re-run. Behaviour:
- New sprint id: `bootstrap-<YYYY-MM-DD>-rerun` (append `-rerun-2`
  on a third pass, etc.).
- Inventory files in `docs/bootstrap/` are overwritten in place.
- Existing ADRs and stories are never touched. The new sprint
  directory is independent.
- The QA cross-check (wave D) runs only against artifacts produced
  in **this** run.

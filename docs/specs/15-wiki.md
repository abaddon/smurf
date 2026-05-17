# 15 — Wiki layer (index + log + lint)

A bookkeeping layer over the artifacts smurf already produces. Three
scripts and one new wave; no new agent, no parallel concept tree.

## Goals

1. **Cross-run decision reuse.** Product-owner and architect read a
   topic-bucketed index on every run instead of re-grepping
   `docs/feedback/`, `docs/stories/`, `docs/adr/` from scratch.
2. **Contradiction detection.** Nightly lint surfaces ADR port-name
   clashes and stale source cites without manual review.
3. **Cheap audit trail.** A committed, append-only run log survives
   the gitignored `.claude/runs/` and the project's `git log`.

## Non-goals

- **No concept pages.** `docs/adr/`, `docs/domain-glossary.md`, and the
  Gherkin stories already cover what a wiki's entity/concept pages
  would say. A parallel tree would just drift.
- **No LLM authorship of wiki files.** Every artifact under
  `docs/wiki/` is produced by deterministic Python. Agents read; only
  the three scripts write.

## Files

| Path | Owner | Frequency |
|---|---|---|
| `plugin/scripts/build-wiki-index.py` | wave 7 | every run |
| `plugin/scripts/append-wiki-log.py` | orchestrator (final step) + autonomous-run fallback | every run |
| `plugin/scripts/wiki_lint.py` | `close-loop.py` | every close-loop |
| `docs/wiki/index.md` | `build-wiki-index.py` | regenerated each wave 7 |
| `docs/wiki/log.md` | `append-wiki-log.py` | one row per run, append-only |
| `docs/wiki/health.md` | `wiki_lint.py` | overwritten each lint pass |

## `policy.yaml` keys

```yaml
wiki:
  enabled: true                    # opt-out by flipping false
  index_path: "docs/wiki/index.md"
  log_path: "docs/wiki/log.md"
  health_path: "docs/wiki/health.md"
  lint_orphan_days: 30
```

All three scripts honor `wiki.enabled: false` as a clean no-op.

## Determinism contract for `build-wiki-index.py`

- Topic-slug rules are filename-derived only (no LLM, no content
  parsing for keywords).
- Output is sorted by stable keys: ADRs by number, stories by
  `(sprint, seq)`, feedback by date descending, topics
  alphabetically.
- The body contains no timestamps. The header refers to the source
  scripts by path only.
- Two consecutive runs on identical inputs produce byte-identical
  output. The script writes only when content actually changed
  (idempotent: no empty commit, no spurious file mtime).

## Race safety for `append-wiki-log.py`

Each row is built in memory, then issued as a **single**
`os.write(fd, line.encode())` on a descriptor opened with `O_APPEND`.
POSIX guarantees writes below `PIPE_BUF` (4096B) under `O_APPEND` are
atomic. A markdown row is well below this.

Two concurrent invocations with distinct `--ts` values therefore
produce two distinct, non-interleaved rows. Same `--ts` cannot occur
in practice because `<ts>` is the run-directory name, unique per run.
The "skip if row exists" check covers retry safety within a single
run (orchestrator re-run, fallback path after crash).

No file lock is needed.

## Cite-check severity

| ADR `Status` | Missing cite |
|---|---|
| `accepted` | **FAIL** (close-loop.py exits 2) |
| `proposed` | WARN |
| `superseded` | WARN |
| unset / unknown | WARN |

Stories: any missing cite is WARN regardless of `Status`.

## Orphan-story threshold

A story is **orphan** if:
- `Status: proposed`,
- `mtime` is older than `wiki.lint_orphan_days` (default 30),
- AND its path does not contain `bootstrap-` (those sprints are seed
  material from `/smurf:bootstrap` and stay `proposed` legitimately
  until the user accepts them).

## Wave 7 contract

After wave 6, **regardless of `/kickoff` vs `/kickoff-team`**, the
orchestrator issues exactly one Bash call:

```
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/build-wiki-index.py"
```

Then commit-only-if-changed (three Bash calls — no compound commands):

1. `git add docs/wiki/index.md`
2. `git diff --cached --quiet docs/wiki/index.md`
3. If step 2 exited non-zero → `git commit -m "docs(wiki): refresh index"`.
   Otherwise `git reset HEAD docs/wiki/index.md` to unstage.

In `/kickoff-team`, wave 7 runs in the orchestrator's main session —
never as a teammate. It indexes what is on the main-branch checkout at
that point. Worktree-side commits not yet merged are intentionally
invisible: the index represents ground truth, not in-flight work.

## Log row schema

```
| ts | goal (≤80 chars) | waves | qa_iterations | status | pr_url | head_sha |
```

`status` ∈ { `green`, `red`, `escalated`, `interrupted`, `terminated`,
`bootstrap` }. The first three are written by the orchestrator on its
happy/sad/escalation paths; `interrupted`/`terminated` by
`autonomous-run.sh`'s fallback when the orchestrator crashed or was
watchdogged; `bootstrap` by `/smurf:bootstrap` wave F.

## Bootstrap interaction

`/smurf:bootstrap` is a one-shot reverse-engineering run, not a
goal-driven orchestrator run. Without explicit indexing it would
produce ADRs / stories / a feedback file that the wiki layer
would not surface until the user's first `/smurf:kickoff`. To
close that gap, bootstrap defines **wave F** (see
`plugin/commands/bootstrap.md`), which runs at the very end and:

1. invokes `build-wiki-index.py` to regenerate `docs/wiki/index.md`,
2. invokes `append-wiki-log.py --status bootstrap --ts <run-id>` to
   add a row to `docs/wiki/log.md`,
3. commits both via `docs(bootstrap): wave F — index artifacts`
   (only if either file actually changed).

Wave F is skipped when `wiki.enabled: false`.

Bootstrap does NOT run `wiki_lint.py`. Wave D already cite-checks
the bootstrap-scoped artifacts; running lint at project scope
would emit FAIL on cites that are legitimately broken (the
bootstrap promotes implicit decisions in code to `Status: proposed`
ADRs — those cites are surfaced by wave D, not the wiki lint).
Lint runs on its normal cadence via `/smurf:close-loop`.

## Test plan

`tests/test-wiki.sh` asserts:

1. `build-wiki-index.py` is byte-deterministic across two consecutive
   runs on the fixture.
2. `append-wiki-log.py` invoked twice with the same `--ts` produces one
   row, never two. A second invocation with a different `--ts` appends
   a second row.
3. `wiki_lint.py` against the fixture produces exactly 1 FAIL, 2 WARN,
   1 INFO. No false positives.
4. `wiki_lint.py` exits 2 when at least one FAIL is present, 0
   otherwise.
5. Bootstrap-sprint stories are exempt from orphan check even when old.
6. `wiki.enabled: false` makes all three scripts no-op cleanly (exit 0,
   no files written, no errors).

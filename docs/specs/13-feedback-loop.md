# 13 — Feedback loop (`close-loop.py`)

The cross-run iteration mechanism (Layer 3 — see `14-iteration-and-budgets.md`).
Without this, the system has no memory across runs and produces the
same kinds of output indefinitely.

## File

`scripts/close-loop.py` — pure stdlib Python; shells out to `claude -p`.

## Trigger

| When | How |
|---|---|
| End of every autonomous run | `autonomous-run.sh` invokes it after the orchestrator completes (best-effort, failures don't fail the run) |
| Manual | `/close-loop` slash command, or `python3 scripts/close-loop.py` |

## Why shell out to `claude -p`

Three reasons:
1. **MCP access** — Sentry/Linear/GitHub MCP servers run inside Claude
   Code sessions. A plain Python script can't reach them.
2. **Single fence** — the same `--allowedTools` mechanism we use
   elsewhere applies. No new auth or rate-limit code to maintain.
3. **Cheap** — `--max-budget-usd 1.50` and `--max-turns 20` cap the
   cost per close-loop run.

The downside is that this script is a thin wrapper, not a real
integration. If MCP availability becomes flaky or we need to deduplicate
across many sources, replace this with a real Python integration.

## Output

`docs/feedback/<YYYY-MM-DD>.md`. Idempotent: if today's file exists,
skip (or overwrite with `--force`).

Structure (templated in the prompt; the LLM fills it):

```markdown
# Feedback digest — last <window>

## Top 5 issues
| # | source | title | link | rationale |

## Top 3 churn / error signals
- ...

## Adoption deltas
- MAU: ...
- Conversion: ...

## Top support themes
- ...

## Suggested next-sprint priorities
- P1: ...
- P2: ...
- P3: ...
```

If a data source is unavailable, the LLM is instructed to write
`"unknown — needs <instrumentation>"` rather than fabricate. This is
the discipline that prevents drift.

## Consumption

`product-owner.md` pre-flight requires reading every file in
`docs/feedback/` modified in the last 14 days. When a story cites
feedback, it pastes the file path verbatim under `## Source`.

This creates a `git log`-traceable chain:

```
docs/feedback/2026-05-09.md            (close-loop after run N)
  ↓ cited by
docs/stories/2026-05-10-rl/01-per-tenant.feature
  ↓ implemented by
commit 9d2f3a1  "feat(rate-limit): per-tenant token bucket"
```

## CLI

```
python3 scripts/close-loop.py            # default: window=7d, write today's file
python3 scripts/close-loop.py --window 14d
python3 scripts/close-loop.py --dry-run  # print the prompt, don't call claude
python3 scripts/close-loop.py --force    # overwrite existing file
```

Exit codes:
- 0 success (or skipped because today's file existed and `--force` not set)
- 1 preflight failure (claude not on PATH)
- 2 claude returned non-zero

## Test plan (Phase 7 acceptance)

1. `--dry-run` prints the prompt without invoking claude.
2. With a stub Linear/Sentry (or none configured), running `close-loop.py`
   produces a feedback file where unavailable sections read "unknown —
   ...".
3. The next run's `product-owner` includes the feedback file's path in
   at least one story's `## Source` block.

## Out of scope

- Cross-day deduplication (each day's file stands alone).
- Sentiment analysis or theme clustering beyond what the LLM does in
  one pass.
- Multi-tenant feedback (one project, one digest).
- Retention policy beyond the 14-day product-owner read window;
  cleanup of old feedback files is not automated.

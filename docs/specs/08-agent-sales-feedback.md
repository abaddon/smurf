# 08 — Sales-feedback agent

Wave 5 (data). Aggregates analytics + support signal into a daily
digest the product-owner consumes at the next kickoff. **Read-only on
external systems.**

## File

`.claude/agents/sales-feedback.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `sonnet` | summarization within Sonnet capability |
| `tools` | `Read, Write, Edit, Bash, Glob, Grep` | reads MCP, writes feedback file |
| `skills` | `openrouter-curl` | optional cheap-LLM theme summarization |
| `mcpServers` | `sentry, linear` (optional) | analytics sources |

## Pre-flight

1. Read `CLAUDE.md` and `.claude/policy.yaml`.
2. Read recent `docs/feedback/*.md` to avoid repeating items.
3. Confirm window for this run (default 7 days).

## Output

`docs/feedback/<YYYY-MM-DD>.md`. Structure (templated; see
`scripts/close-loop.py` and `13-feedback-loop.md`):

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
- P1: ...  (source: <signal above>)
- P2: ...
- P3: ...
```

## Data sources (best-effort; skip cleanly when unavailable)

- GitHub issues: `gh issue list --search "..." --json title,number,reactions`
- Sentry MCP: top error signatures last 7d
- Linear MCP: priority distribution in Triage / Backlog
- OpenRouter (`openrouter-curl` skill): theme summarization on
  free-form support data

## Hard rules

- **Never** write to external systems (no API POST, no
  `gh issue create`, no MCP write calls). Read-only, period.
- **Never** fabricate metrics. Mark unknowns explicitly:
  `unknown — needs <instrumentation>`.
- **Always** cite the source URL or query for every datum.

## Relationship to `close-loop.py`

`scripts/close-loop.py` (Phase 7) is essentially a thin wrapper that
invokes a constrained `claude -p` whose prompt closely matches this
agent's contract. They produce the same kind of file.

- Use the **agent** when a human asks for a digest interactively
  (`@sales-feedback`).
- Use **`close-loop.py`** when running unattended at the end of an
  autonomous run.

## Test plan

1. With at least one open issue in the GitHub repo, run
   `@sales-feedback "summarize the last 7 days"`.
2. Confirm `docs/feedback/<today>.md` is created with the issue listed
   and a link to the issue URL.
3. With Sentry/Linear MCP not configured, confirm those sections read
   `unknown — needs <X>`, not fabricated data.

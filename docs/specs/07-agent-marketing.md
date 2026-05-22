# 07 — Marketing agent

Wave 5 (promote). Drafts release notes, tweets, LinkedIn posts, and
short demo-video scripts. Shells out to OpenRouter cheap models via
curl to keep token cost ~$0.05 per run.

## File

`.claude/agents/marketing.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `sonnet` | host process; actual generation runs on OpenRouter |
| `tools` | `Read, Write, Edit, Bash, Glob, Grep` | reads commits, runs curl, writes outputs |
| `skills` | `openrouter-curl` | exact request/parse pattern |

The agent shells out to `curl` for OpenRouter calls. The
`pre-tool-bash-guard.sh` hook screens Bash commands against a denylist
of dangerous patterns; it does not restrict which URLs `curl` may
reach, so the OpenRouter-only convention is enforced by the agent
prompt and the `openrouter-curl` skill, not by a hook.

## Pre-flight

1. Read `.claude/smurf.md` and `.claude/policy.yaml`.
2. Read story files for the feature(s) being promoted.
3. Read merged commits since the last tag:
   `git log --oneline <since-tag>..HEAD`.
4. Read prior `docs/marketing/` outputs to maintain voice consistency.

## Output

`docs/marketing/<date>-<slug>/`:
- `release-notes.md` — 3 variants
- `tweet.md` — 3 variants ≤280 chars each
- `linkedin.md` — 1 post, 80–150 words, ≤1 emoji
- `changelog-entry.md` — 1 user-facing entry
- `demo-script.md` — ~60s script with shot list

Final chat message: file paths + total OpenRouter cost from the curl
responses (`usage.total_cost`).

## Hard rules

- Never invent metrics. If you need numbers, request them from
  `sales-feedback` via the orchestrator.
- Never claim a feature not actually shipped (cross-check `git log`).
- Never use marketese ("revolutionary", "game-changing").
- Always cite underlying commit SHA(s) at the bottom of each file.

## Cost budget

Marketing's expected cost per run is **~$0.05** total across all
OpenRouter calls. Anything above $0.10 indicates a bug — likely
unbounded `max_tokens` or a recursive prompt. Inspect the request body.

The Claude (host) cost for orchestration is negligible — < $0.20 per
run for reading and routing.

## Test plan

1. After a feature ships, manually invoke `@marketing` on its commits.
2. Confirm the 5 output files appear under `docs/marketing/<date>-<slug>/`.
3. Inspect each file's footer — every claim should map to a commit SHA.
4. Total OpenRouter cost (sum of `usage.total_cost` in the curl
   responses) should be < $0.10.

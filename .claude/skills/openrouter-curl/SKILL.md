---
name: openrouter-curl
description: Pattern for calling OpenRouter from a Bash tool to keep Claude token cost low on tier-3 work (release notes, support summaries). Loaded by marketing, sales-feedback.
---

# OpenRouter shell-out via curl

This pattern lets a Claude Code subagent generate content using a cheap
OpenRouter model **without** routing through Claude. The subagent stays
in Claude (cheap orchestration tokens); the actual generation happens at
Gemini-Flash / Haiku-4.5 prices (~10× cheaper).

## Prerequisites

- `OPENROUTER_API_KEY` exported in the agent's environment.
- Subagent's `tools` includes `Bash` restricted to
  `Bash(curl https://openrouter.ai/api/v1/*)`.
- The shell where the subagent runs has `curl` and `jq`.

## Recommended models

| Use case | Model id | Why |
|---|---|---|
| short-form copy (tweet, release-note) | `google/gemini-2.5-flash` | cheapest, decent voice |
| longer reasoning under 2k tokens | `anthropic/claude-haiku-4.5` | reliable, no jailbreak guardrails to fight |
| code-adjacent prose, technical | `deepseek/deepseek-v4-pro` | strong on technical tone |

Always pin a specific model id — `:latest` aliases drift.

## Request shape

```bash
RESPONSE=$(curl -sS https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/<owner>/<repo>" \
  -H "X-Title: smurf-orchestrator" \
  -d @- <<'JSON'
{
  "model": "google/gemini-2.5-flash",
  "messages": [
    {"role": "system", "content": "You are a developer-relations writer. Tone: technical, accessible. No marketese."},
    {"role": "user",   "content": "Write 3 release-note variants for the change described below.\n\n<feature summary>"}
  ],
  "temperature": 0.5,
  "max_tokens": 600
}
JSON
)
```

## Parse + write

```bash
echo "$RESPONSE" | jq -r '.choices[0].message.content' > docs/marketing/<date>-<slug>/release-notes.md
COST=$(echo "$RESPONSE" | jq -r '.usage.total_cost // 0')
echo "openrouter cost: \$$COST"
```

If the response shape is unexpected (rate limit, auth fail), `jq` returns
`null` — handle by inspecting the raw response:

```bash
if [ "$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')" = "" ]; then
  echo "openrouter call failed:" >&2
  echo "$RESPONSE" | jq . >&2
  exit 1
fi
```

## Rate limits

OpenRouter free tier: ~50 req/day across all models. Paid: per-key cap
configurable. If hit:
- back off 60s, retry once.
- on second failure, write a stub file with a `# TODO: regenerate when
  rate-limit resets` header and exit 0 (don't fail the whole run for a
  tier-3 task).

## Cost expectations per agent run

| Agent | Calls per run | Tokens per call | Cost on Gemini Flash |
|---|---|---|---|
| marketing | 5 (release notes×3, tweet, linkedin, changelog, demo script) | ~600 out / 800 in | <$0.01 total |
| sales-feedback | 1–3 (theme summarization) | ~1500 out / 3000 in | <$0.05 total |

If you see a single curl above $0.10, something is wrong — likely
unbounded `max_tokens` or a recursion. Check the request body.

## Security

- NEVER include the OpenRouter key in any committed file.
- NEVER log the full request headers; redact `Authorization`.
- NEVER POST sensitive customer data — OpenRouter is a third party.
- The MCP system has no equivalent shell-out; this pattern is bash-only
  and stays out of MCP scope.

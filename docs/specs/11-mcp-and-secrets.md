# 11 — MCP servers and secrets

External-system integration via MCP. Per-agent scoping prevents the
marketing agent from reaching Stripe, the developer from reaching the
email gateway, etc.

## Files

- `.mcp.json` — declares MCP servers
- `.env.example` — every required env var, no real values
- `.env` — gitignored, holds real values

## `.mcp.json` schema

```jsonc
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}" }
    }
  }
}
```

Servers we use today:
- `github` — read issues, list PRs, create PRs (devops only).

Servers ready to enable when needed (uncomment in `.mcp.json`):

```jsonc
"linear": {
  "command": "npx", "args": ["-y", "linear-mcp"],
  "env": { "LINEAR_API_KEY": "${LINEAR_API_KEY}" }
},
"sentry": {
  "command": "npx", "args": ["-y", "@sentry/mcp-server"],
  "env": { "SENTRY_AUTH_TOKEN": "${SENTRY_AUTH_TOKEN}" }
},
"slack": {
  "command": "npx", "args": ["-y", "slack-mcp"],
  "env": { "SLACK_BOT_TOKEN": "${SLACK_BOT_TOKEN}" }
},
"postmark": {
  "command": "npx", "args": ["-y", "postmark-mcp"],
  "env": { "POSTMARK_SERVER_TOKEN": "${POSTMARK_SERVER_TOKEN}" }
}
```

## Per-agent MCP scoping

Each agent declares the MCP servers it can use in its frontmatter
`mcpServers:` list. The orchestrator must NEVER pass `mcp__sentry`
permissions to the marketing agent, etc.

| Agent | github | linear | sentry | slack | postmark |
|---|---|---|---|---|---|
| orchestrator | ✓ | ✓ | — | — | — |
| product-owner | — | ✓ | — | — | — |
| architect | — | — | — | — | — |
| developer | ✓ | — | — | — | — |
| qa-engineer | ✓ | — | — | — | — |
| devops | ✓ | — | ✓ (read) | ✓ (read) | — |
| marketing | — | — | — | — | — |
| sales-feedback | ✓ (read) | ✓ (read) | ✓ (read) | — | — |

## Secrets

All secrets in `.env` (gitignored). Never:
- commit a real key to any file
- echo a secret in a log line (Slack notifications scrub by inspection)
- pass a secret in a CLI argument (use env vars or `<<EOF` heredocs)

`.env.example` lists every variable used. Keep it current.

`policy.yaml` `forbidden_paths` includes `.env` to prevent agents from
writing it. The `policy-guard.sh` hook enforces this at PreToolUse(Write|Edit).

## Where local Claude Code reads MCP credentials

Claude Code reads `.mcp.json` from the current project directory at
session start. Env-var references (`${GITHUB_TOKEN}`) are resolved
against the shell's environment — so the user must export them (or
have them in `.env` and source `.env` before launching `claude`).

`autonomous-run.sh` does NOT auto-source `.env`. The cron line uses
`bash -lc 'cd ... && bash autonomous-run.sh'` so the user's login
shell config is what loads env vars. If your `.zshrc`/`.bashrc`
sources `.env`, you're good; if not, add a line to do so.

## Rotation

When rotating a secret:
1. Update `.env` with the new value.
2. Restart any long-running Claude Code sessions (MCP servers cache
   the env at startup).
3. No `.mcp.json` change needed — the env-var reference indirects.

## Test plan

1. With `GITHUB_TOKEN` set, list the available MCP tools in an
   interactive session (`/mcp`). Confirm `github` is reachable.
2. Without `GITHUB_TOKEN`, restart Claude Code and confirm `github` is
   listed but its tool calls fail cleanly (auth error, not crash).
3. `grep -r 'sk-' .` should return nothing (no leaked keys in repo).
4. `cat .gitignore | grep '^\.env'` confirms `.env` is gitignored.

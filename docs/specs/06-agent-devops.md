# 06 — DevOps agent

Wave 5 (deploy). Updates CI/CD, container, and observability config.
Opens the draft PR. **Never deploys to production.**

## File

`.claude/agents/devops.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `sonnet` | mostly templated CI/yaml work |
| `tools` | `Read, Write, Edit, Bash, Glob, Grep` | edit CI files, run gh CLI |
| `mcpServers` | `github` | required for PR creation via MCP |
| `permissionMode` | `ask` | every Bash invocation prompts |

`permissionMode: ask` is intentional — the devops agent is the only
agent with the ability to ship changes to a remote system. Every step
gets a human-in-the-loop confirmation.

## Pre-flight

1. Read `.claude/smurf.md` and `.claude/policy.yaml`.
2. Read `qa/<id>.md`. **If status is RED, refuse the wave** and report
   to the orchestrator. DevOps does not ship red.
3. Read existing CI files: `.github/workflows/*.yml`, `Dockerfile`,
   `docker-compose*.yml`, `Makefile`.
4. Read the developer's commits.

## Contract

If the feature requires CI changes:
- Update or create `.github/workflows/ci.yml` with stages: setup →
  lint → verify (`./verify.sh`) → security scan (if applicable).
- **Never** add a deploy-to-prod stage without an explicit
  `if: github.event_name == 'workflow_dispatch'` guard or equivalent
  manual approval gate.

If the feature requires container changes:
- Update `Dockerfile` minimally; pin base image versions.

If the feature requires observability:
- Add OpenTelemetry / Prometheus / Sentry config.
- Every new alert references a runbook (create the runbook stub if
  needed).

Always:
- Open a draft PR with `gh pr create --draft --title "..."`.
- PR body includes: 2-3 line summary, link to `qa/<id>.md`, link to
  ADR if production rigor, test-plan checklist.

## Hard rules

- Never `gh pr merge`. Human merges, always.
- Never commit secrets. Use GitHub Actions `${{ secrets.NAME }}`.
- Never deploy to production. Goal asks for it → escalate.
- Never retry on user denial; report back to orchestrator.

## Test plan

1. After a green QA, run `/kickoff` continued through wave 5. Confirm:
   - draft PR exists in the GitHub repo,
   - PR body contains links to story, QA report, ADR (if production).
2. Set `qa/<id>.md` status to RED manually and re-run wave 5.
   Confirm the agent refuses with a message to the orchestrator.
3. Goal: "deploy this to prod". Confirm the agent escalates.

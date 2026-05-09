# 10 — Skills

Skills are reusable knowledge packets the agents pull in when relevant.
Unlike subagents, skills don't have their own context window; they're
included in the loading agent's system prompt.

## Files

```
.claude/skills/
├── code-quality/SKILL.md         # SRP/DIP/OCP, complexity ceilings, naming
├── adr-template/SKILL.md         # Architecture Decision Record format
├── gherkin-stories/SKILL.md      # Feature/Scenario format + MoSCoW + NFR
├── conventional-commits/SKILL.md # type(scope): subject + body rules
└── openrouter-curl/SKILL.md      # cheap-LLM shell-out pattern
```

## Discovery

Claude Code auto-discovers project skills from `.claude/skills/<name>/SKILL.md`.
The frontmatter `name:` field is the skill's identifier; agents reference
it from their `skills:` frontmatter list, e.g.:

```yaml
---
name: developer
skills:
  - code-quality
  - conventional-commits
---
```

**Important caveat (research §1.2)**: when an agent runs as a *teammate*
inside an Agent Team, its frontmatter `skills:` list may be ignored —
Claude Code loads project-level skills only. Verified working in our
setup: skills under `.claude/skills/` are picked up automatically and
appear in the session's available-skills list (visible in Claude Code's
status output). No additional registration in `.claude/settings.json` is
required.

## Skill ↔ agent mapping

| Skill | Loaded by |
|---|---|
| `code-quality` | architect, developer, qa-engineer, orchestrator |
| `adr-template` | architect |
| `gherkin-stories` | product-owner |
| `conventional-commits` | developer |
| `openrouter-curl` | marketing, sales-feedback |

The mapping is declared in each agent's `.claude/agents/<name>.md`
frontmatter via the `skills:` list. Skills not listed in an agent's
frontmatter are still discoverable via `/skill <name>` but won't be
auto-suggested.

## When to write a new skill vs. a new agent

| You need | Use |
|---|---|
| Reusable pattern multiple agents apply | skill |
| Domain glossary | not a skill — `docs/domain-glossary.md` |
| Distinct role with own context window and tools | agent |
| Deterministic enforcement that can't be bypassed | hook (not skill) |
| Cross-cutting concern (e.g., commit format) | skill |

## Authoring rules

- One skill per directory. The body file MUST be named `SKILL.md`.
- Frontmatter `name:` matches the directory name.
- Frontmatter `description:` is one sentence — Claude uses it to decide
  whether to surface the skill.
- Body is markdown. Templates and code blocks are encouraged. Avoid
  long prose; agents skim.
- No links to external resources unless they're stable docs (RFCs,
  IETF, language-spec). Tutorials drift.

## Rigor-level interaction

Skills don't branch on rigor-level themselves; the **agents** that load
them do. Example: `code-quality`'s complexity ceilings are warn-only by
default; under `production` rigor the developer's pre-flight bumps the
ceiling enforcement to block-level. This branching lives in the agent's
prompt, not in the skill body.

## Future skills (deferred)

- `pr-description-template` — when smurf grows enough PRs to need a
  consistent template.
- `runbook-template` — when devops produces operational runbooks.
- `release-checklist` — when marketing has a recurring release cadence.

Add as the project demands; don't speculate.

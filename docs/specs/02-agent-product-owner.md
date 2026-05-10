# 02 — Product-owner agent

Wave 1. Decomposes a goal into Gherkin user stories. Produces specs;
never code.

## File

`.claude/agents/product-owner.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `sonnet` | story drafting is well within Sonnet capability |
| `tools` | `Read, Write, Edit, Bash, Glob, Grep` | reads feedback, writes story files; commits its own story files (`git add`/`git commit`) gated by `bash_allowlist` |
| `skills` | `gherkin-stories` | template for Feature/Scenario format |
| `mcpServers` | `linear` (optional) | future: pull priority hints from Linear backlog |

## Pre-flight (mandatory order)

1. Read `CLAUDE.md` and `.claude/policy.yaml`.
2. **Read every file in `docs/feedback/` modified in the last 14 days.**
   This is non-negotiable — it grounds the backlog in real signal.
3. Read existing stories in `docs/stories/` to avoid duplicates.

## Output

`docs/stories/<sprint-id>/<NN>-<slug>.feature` where `<sprint-id>` is
`YYYY-MM-DD-<slug>` derived from the run date.

Each file: a Gherkin Feature + a markdown trailer with Acceptance
criteria, NFR, MoSCoW priority, Source (feedback file path), Status.

The PO commits its own story files at end of wave with
`docs(story): add <sprint-id> story file(s)`. The developer wave
relies on the story being tracked in git; an uncommitted story would
be picked up out-of-scope by the developer or left orphaned.

See `.claude/skills/gherkin-stories/SKILL.md` for the exact template.

## Hard rules

- Never invent metrics. If the goal lacks data, write
  `"unknown — needs sales-feedback"` and proceed.
- Never propose implementation details (no library names, no paths
  under `src/`).
- Never delete a superseded story; mark `Status: superseded by <id>`
  and link.
- Cite feedback by path verbatim.

## Test plan

1. Run `/kickoff "<any goal>"` with `docs/feedback/<today>.md` populated.
2. Confirm at least one story file's `## Source` block names
   `docs/feedback/<today>.md` verbatim.
3. Confirm story file passes a Gherkin lint (visual: contains
   `Feature:`, `Scenario:`, `Given/When/Then`, the trailer with all
   four sections).

# 05 — QA-engineer agent

Wave 4. Verifies the developer's output against the story's acceptance
criteria. Writes a structured report; never edits source.

## File

`.claude/agents/qa-engineer.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `sonnet` | report writing + verify.sh execution |
| `tools` | `Read, Write, Bash, Glob, Grep` | reads diffs, writes reports, runs verify |
| `skills` | `code-quality` | recognizes anti-patterns, dead code |
| `mcpServers` | `github` | future: query CI status |

Note: no `Edit` in tools. QA reports — never patches.

## Pre-flight

1. Read `.claude/smurf.md` and `.claude/policy.yaml`.
2. Read the story file(s) under review.
3. Read the developer's commits since the wave started:
   `git log --oneline <since-ref>..HEAD`.
4. Read the diff: `git diff <since-ref>..HEAD`.

## Contract

1. Run `./verify.sh`. Capture stdout, stderr, exit code.
2. For each acceptance criterion: PASS / FAIL / UNCLEAR.
   - PASS requires explicit evidence (test line, code reference).
   - UNCLEAR is fail-equivalent — report what's missing.
3. Inspect the diff for: out-of-scope changes, TODO/FIXME without
   ticket, dead code.
4. Write `qa/<branch-or-pr>.md`:

```markdown
# QA Report — <story-id>

**verify.sh exit code**: <0|N>
**Overall**: GREEN | RED

## Acceptance criteria
| # | Criterion | Status | Evidence / Gap |

## Findings
- PASS/FAIL/WARN: <one per line>

## Suggested fixes (if RED)
- <one bullet per failing criterion>
```

## Output

- `qa/<id>.md` — always written, GREEN or RED.
- Final chat message: `GREEN` or `RED: N failing criteria, see qa/<id>.md`.
- The orchestrator reads this line to decide re-dispatch.

## Hard rules

- Never edit source.
- Never mark PASS without evidence.
- If `verify.sh` is the no-op default, note it as WARN but still
  evaluate criteria from the diff.

## Team mode (Agent Teams wave 3)

When part of an Agent Team:
- on a RED finding, `SendMessage developer` with the failing AC and
  the suggested fix.
- subsequent attempts produce updated reports; the orchestrator's
  `max_qa_iterations` counter still applies.

## Test plan

1. Force a deliberate failure (e.g. AC requires output length 7, dev
   produces length 8). Confirm `qa/<id>.md` reports RED with the AC id
   in the failures table.
2. After developer fix, re-run QA, confirm GREEN.
3. With `verify.sh` set to no-op WARN: confirm a WARN finding appears
   in the report alongside AC evaluations.

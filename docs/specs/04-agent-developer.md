# 04 — Developer agent

Wave 3 worker. Implements ONE story per invocation. Writes the minimum
code that satisfies acceptance criteria, runs `verify.sh`, commits
atomically.

## File

`.claude/agents/developer.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `sonnet` | implementation is Sonnet's strongest area |
| `tools` | `Read, Write, Edit, Bash, Glob, Grep` | full coding toolkit |
| `skills` | `code-quality, conventional-commits` | quality bar + commit format |
| `mcpServers` | `github` | for `gh` CLI when devops isn't available |
| `isolation` | `worktree` | each invocation gets a fresh worktree |

`isolation: worktree` is critical for parallel developers in subagent
mode (Wave 3, multiple stories). Without it, two developers writing to
the same branch trample each other.

## Pre-flight

1. Read `CLAUDE.md` and `.claude/policy.yaml`.
2. Read the assigned story file (path supplied in prompt).
3. If `rigor-level=production`, read the corresponding ADR. If absent,
   **escalate to the orchestrator** rather than inventing a design.
4. Read existing source files referenced by the story.

## Contract

1. Implement minimum code. Nothing speculative.
2. Match existing project conventions (or pick the simplest one if
   none).
3. Run `./verify.sh` after every logical change.
4. Commit atomically with `<type>(<scope>): <subject>` (see
   `conventional-commits` skill).
5. Stay within the story's stated scope.

## Checklist before declaring done

- [ ] Every acceptance criterion has a corresponding code change.
- [ ] `./verify.sh` exits 0.
- [ ] All commits follow conventional-commits format.
- [ ] No files outside the story's scope were modified.
- [ ] No TODO/FIXME without a ticket reference.
- [ ] `git status --short` shows no untracked files and no unintended modifications. Temporary stubs created for self-testing (e.g. `*.bak`, fixture replacements) must be restored or deleted before exit.

## On QA re-dispatch

When the prompt includes a `qa/<id>.md` report:
1. Read the report; every "FAIL" item is non-negotiable.
2. Address only failing items; do not refactor unrelated code.
3. Re-run `./verify.sh`.
4. Commit `fix(<scope>): address qa <id> findings` listing the AC ids.

## Test plan

1. Story with one happy-path AC: confirm developer creates code,
   verify.sh passes, single commit lands.
2. Story with an AC the first attempt is likely to miss (e.g. empty-
   input edge case): confirm QA re-dispatch loop fires once or twice
   then succeeds. `summary.md` records `qa_iterations_observed >= 1`.
3. Two independent stories in subagent-mode wave 3: confirm each is
   in its own worktree (`.claude/worktrees/<id>/`) and commits don't
   trample.

---
name: conventional-commits
description: Conventional Commits format and rules. Apply when authoring commit messages. Loaded by developer.
---

# Conventional Commits

Format:

```
<type>(<scope>): <subject>

<body — optional, blank line above>

<footer — optional, blank line above>
```

Subject line ≤ 72 characters. Imperative mood ("add", not "added").
No trailing period.

## Types

- `feat` — new feature visible to users.
- `fix` — bug fix.
- `docs` — documentation only.
- `style` — formatting / whitespace; no logic change.
- `refactor` — code change that is neither a fix nor a feature.
- `perf` — performance improvement.
- `test` — adding or updating tests.
- `build` — build system, dependencies, packaging.
- `ci` — CI configuration.
- `chore` — anything else (rare; prefer a more specific type).

## Scope

The smallest noun that locates the change. Examples:

- `feat(version): add scripts/version.sh`
- `fix(qa): correct exit-code propagation in verify.sh`
- `docs(adr): record rate-limit decision (ADR-0042)`
- `refactor(orchestrator): extract wave-DAG builder`

If a change spans multiple scopes, either pick the dominant scope or
split the change into multiple commits (preferred).

## Body

Use the body to explain **why**, not what. The diff already shows what.

```
feat(version): add scripts/version.sh

The orchestrator's autonomous-run.sh records the running commit's
short hash in summary.md. Without a stable script that prints the
hash, every script duplicated `git rev-parse --short HEAD`. This
centralizes it so the format change (7 → 8 chars, e.g.) lives in
one place.
```

## Footer

- Reference issues: `Refs #123`, `Closes #123`.
- Mark breaking changes: `BREAKING CHANGE: <description>` on a new line.
  Optionally add `!` after the type: `feat(api)!: drop /v1 endpoints`.

## Co-authored attribution

When a commit comes out of an orchestrator wave with developer + qa
involvement, tag both:

```
Co-authored-by: qa-engineer <noreply@smurf.local>
```

## Anti-patterns

- `chore: stuff` — uninformative.
- `fix: bug` — unmeaning.
- `WIP` commits in main branches — squash before merge.
- Multiple logical changes in one commit — split.
- Commit messages auto-generated from the diff — write the *why*.

## On QA re-dispatch

When a developer re-runs after a failing QA report, commit format:

```
fix(<scope>): address qa <id> findings

- AC-2: pad short hash to 7 chars
- AC-4: emit non-zero exit when input invalid
```

This makes the QA→fix loop traceable in `git log`.

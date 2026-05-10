---
name: gherkin-stories
description: User story format (Gherkin Feature/Scenario/Given/When/Then) plus MoSCoW priority and NFR fields. Use when producing user stories. Loaded by product-owner.
---

# Gherkin user-story template

User stories live under `docs/stories/<sprint-id>/<NN>-<slug>.feature`
where `<sprint-id>` follows the pattern `YYYY-MM-DD-<slug>` derived from
the run that produced them.

## Anatomy

```gherkin
Feature: <imperative title — what the user can now do>
  As a <role>
  I want <capability>
  So that <value>

  Background:
    Given <preconditions shared by all scenarios>

  Scenario: <happy-path scenario name>
    Given <state>
    When <action>
    Then <observable outcome>
    And <observable outcome>

  Scenario: <edge case>
    Given <state>
    When <action>
    Then <observable outcome>

  Scenario Outline: <parametrized scenario>
    When <action with <param>>
    Then <expected with <param>>

    Examples:
      | param | expected |
      | a     | x        |
      | b     | y        |
```

After the Gherkin block, append a markdown block:

```
## Acceptance criteria
- AC-1: <SMART, testable; reference a Scenario by name if helpful>
- AC-2: ...

## NFR (non-functional requirements)
- latency: <target with units, e.g. p95 < 200ms>
- throughput: <target>
- error budget: <percentage>
- accessibility / i18n / a11y: <if applicable>

## Priority
- MoSCoW: must | should | could | wont

## Source
- feedback: <docs/feedback/<file>.md path or "goal" if direct from kickoff>
- linked stories: <ids if this depends on or extends another story>

## Status
- proposed | accepted | in-progress | done | superseded by <id>
```

## Rules

- **One Feature per file.** Multiple Scenarios per Feature are fine.
- **Acceptance criteria are SMART** — Specific, Measurable, Achievable,
  Relevant, Time-bound. "Fast enough" is not measurable.
- **Never propose implementation details** in a story. No code, no
  library names, no paths under `src/`. Stories say *what*, not *how*.
- **NFR fields may say "unknown — needs sales-feedback"** if the data
  doesn't exist yet. Don't invent metrics.
- **Cite sources verbatim.** If a story comes from a feedback file,
  paste its full path under `## Source`.
- **Status: proposed** is the default. Promote to `accepted` when the
  orchestrator dispatches it for design (wave 2) or implementation
  (wave 3).

## MoSCoW guidance

- **must**: the run is a failure if this story is not delivered.
- **should**: high value, included if budget allows.
- **could**: nice-to-have, included only if there's slack.
- **wont**: explicitly out of scope for this run; documented to prevent
  scope creep within the run.

## Naming the story file

`<NN>-<slug>.feature` where:
- `<NN>` is a 2-digit sequence within the sprint, starting at `01`.
- `<slug>` is kebab-case derived from the Feature title.

Example: `docs/stories/2026-05-09-rate-limit/01-per-tenant-rate-limit.feature`

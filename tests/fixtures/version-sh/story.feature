Feature: Print a short Git SHA via scripts/version.sh and assert its format in verify.sh
  As a developer working in this repository
  I want a dedicated script that prints the current commit's short SHA
  So that any tooling or CI step can reliably retrieve a concise build identifier

  Background:
    Given the repository is a valid Git repository with at least one commit
    And the working tree is on a branch or detached HEAD

  Scenario: version.sh prints the short SHA on the happy path
    Given scripts/version.sh exists and is executable
    When a developer runs scripts/version.sh
    Then standard output contains exactly 7 hexadecimal characters followed by a single newline
    And standard error is empty
    And the exit code is 0

  Scenario: verify.sh passes when version.sh output is a valid 7-char hex SHA
    Given scripts/version.sh produces exactly 7 hexadecimal characters followed by a newline
    When a developer runs ./verify.sh
    Then ./verify.sh exits with code 0

  Scenario: verify.sh fails when version.sh output has the wrong length
    Given scripts/version.sh is replaced with a stub that prints fewer or more than 7 characters followed by a newline
    When a developer runs ./verify.sh
    Then ./verify.sh exits with a non-zero code
    And a clear failure message is written to standard error

  Scenario: verify.sh fails when version.sh output contains non-hexadecimal characters
    Given scripts/version.sh is replaced with a stub that prints exactly 7 characters that include at least one non-hex character followed by a newline
    When a developer runs ./verify.sh
    Then ./verify.sh exits with a non-zero code
    And a clear failure message is written to standard error

  Scenario: verify.sh fails when version.sh output is missing the trailing newline
    Given scripts/version.sh is replaced with a stub that prints exactly 7 hexadecimal characters with no trailing newline
    When a developer runs ./verify.sh
    Then ./verify.sh exits with a non-zero code
    And a clear failure message is written to standard error

## Acceptance criteria
- AC-1: scripts/version.sh exists, is executable, and — when run inside a valid Git repository — prints to stdout exactly the string returned by `git rev-parse --short HEAD` followed by exactly one newline character, with nothing else on stdout and a zero exit code.
- AC-2: ./verify.sh exits 0 when scripts/version.sh produces a 7-character lowercase hexadecimal string followed by exactly one newline and nothing else.
- AC-3: ./verify.sh exits non-zero and emits at least one human-readable failure line on stderr when scripts/version.sh produces any output that is not exactly 7 hexadecimal characters followed by a single newline — including wrong length, any non-hex character, or a missing trailing newline.

## NFR (non-functional requirements)
- latency: scripts/version.sh must complete within 2 seconds on any machine that can run git
- throughput: unknown — needs sales-feedback
- error budget: 0 tolerated failures in CI for a valid Git repo with at least one commit
- dependencies: bash and standard POSIX tools only; no new packages or external services

## Priority
- MoSCoW: must

## Source
- feedback: goal (direct from kickoff — .claude/runs/next-goal.md; no feedback file exists yet)
- linked stories: none

## Status
- proposed

# QA Report — 2026-05-09-version-sh/01

**verify.sh exit code (clean run on HEAD)**: 0
**Overall**: GREEN

## Acceptance criteria

| # | Criterion | Status | Evidence / Gap |
|---|---|---|---|
| AC-1 | version.sh exists, is executable, prints exactly `git rev-parse --short HEAD` + newline, zero exit | PASS | File at `scripts/version.sh`, mode `-rwxr-xr-x`. `scripts/version.sh` output `e226126` matches `git rev-parse --short HEAD` output `e226126`. Script body is `git rev-parse --short HEAD` which inherits git's own trailing newline. Exit code 0. |
| AC-2 | verify.sh exits 0 when version.sh produces valid 7-char hex + newline | PASS | `./verify.sh` run on HEAD exited 0. Only output was the pre-existing WARN line on stderr; all checks in verify.sh passed silently. |
| AC-3 | verify.sh exits non-zero and emits human-readable stderr for each malformation | PASS | Three stubs tested: (a) missing trailing newline → exit 1, stderr "ERROR: scripts/version.sh output is missing a trailing newline"; (b) wrong length (5 chars + newline) → exit 1, stderr "ERROR: scripts/version.sh output has wrong length: expected 7, got 5"; (c) non-hex character ('g' in 7-char string + newline) → exit 1, stderr "ERROR: scripts/version.sh output is not 7 lowercase hex characters: 'abcdefg'". All three stubs reverted via `git checkout HEAD -- scripts/version.sh`; `./verify.sh` confirmed exit 0 post-restoration. |

## Findings

- PASS: `scripts/version.sh` is executable (`-rwxr-xr-x`), 4 lines, no dead code.
- PASS: `verify.sh` sentinel trick (`printf x` appended inside subshell) correctly preserves trailing-newline information that command substitution would otherwise strip.
- PASS: All three failure modes (missing newline, wrong length, non-hex) produce non-zero exit and a human-readable stderr line naming the specific fault.
- PASS: `./verify.sh` exits 0 on clean HEAD after stub restoration.
- WARN: The story file `docs/stories/2026-05-09-version-sh/01-version-sh-and-verify.feature` was committed in a separate commit (`e226126`) from the implementation (`74ac821`). This is not an AC violation but means the story file was added as part of the developer's wave rather than a pre-existing artifact — acceptable given the story status was "proposed".
- WARN (process): The QA prompt notes the developer previously left `scripts/version.sh.bak` in the tree (cleaned up by the orchestrator before this review). The current HEAD is clean — `find` confirms no `.bak` or `.golden` files. However, this indicates the developer did not self-clean their stub during the implementation wave, requiring orchestrator intervention. Process discipline gap.
- WARN (minor logic): The newline-stripping logic `sha="${raw%$'\n'}"` strips only the last `\n` from `raw`. If `version.sh` emits two trailing newlines, `sha` will contain an embedded newline (length > 7), which fails the length check correctly but produces a misleading error message with the embedded newline visible. This is an edge case not covered by the ACs and does not constitute a failing criterion.
- WARN: The `verify.sh` header WARN line ("WARN: verify.sh is the no-op default; replace with real tests/build") remains on stderr even after real tests were added. This is cosmetically misleading — the file is no longer a no-op — but does not affect correctness or any AC.

## Suggested fixes (if RED)

N/A — all ACs pass.

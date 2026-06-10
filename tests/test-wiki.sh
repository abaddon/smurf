#!/usr/bin/env bash
# Smoke + unit tests for the wiki layer:
#   - build-wiki-index.py determinism
#   - append-wiki-log.py idempotency
#   - wiki_lint.py findings (exact counts) and exit codes
#   - wiki.enabled=false respects opt-out everywhere
#
# Mirrors the style of test-hooks.sh: isolated tempdir, no network, no
# Claude shell-out. Asserts via grep/diff/wc.

set +e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO/plugin"

. "$(dirname "$0")/common.sh"

# Set a file's mtime to <days> days ago. GNU `touch -d "N days ago"` is not
# portable (BSD/macOS touch rejects it, leaving fixtures with fresh mtimes
# and silently breaking the orphan-story assertions), so use python3 —
# already a hard dependency of this suite.
backdate() {
  python3 -c '
import os, sys, time
t = time.time() - int(sys.argv[1]) * 86400
os.utime(sys.argv[2], (t, t))
' "$1" "$2"
}

# Build the fixture tree in a tempdir.
seed_fixture() {
  local root="$1"
  mkdir -p "$root/docs/adr"
  mkdir -p "$root/docs/stories/2026-01-01-old"
  mkdir -p "$root/docs/stories/2026-04-15-new"
  mkdir -p "$root/docs/stories/bootstrap-2026-01-01"
  mkdir -p "$root/docs/feedback"
  mkdir -p "$root/src"
  touch "$root/src/cache.ts"

  cat > "$root/docs/adr/0001-cache.md" <<'EOF'
# ADR-0001: cache

**Status**: accepted
**Date**: 2026-01-01
**Stories**: 2026-04-15-new/01-fresh

## Context
Need caching. See `src/cache.ts`.

## Decision
Use Redis.

## Ports / Adapters
- CacheStore: keyed get/set, LRU eviction
- RateLimiter: token-bucket
EOF

  cat > "$root/docs/adr/0002-cache-v2.md" <<'EOF'
# ADR-0002: cache v2

**Status**: accepted
**Date**: 2026-02-01

## Context
Refines caching. See `src/cache.ts`.

## Decision
Add tags.

## Ports / Adapters
- CacheStore: keyed get/set, ARC eviction
- TagIndex: tag-to-key index
EOF

  cat > "$root/docs/adr/0003-gone.md" <<'EOF'
# ADR-0003: removed module

**Status**: accepted
**Date**: 2026-03-01

## Context
Depends on `src/gone.ts`.

## Decision
Use it.
EOF

  cat > "$root/docs/adr/0004-proposed.md" <<'EOF'
# ADR-0004: speculative

**Status**: proposed
**Date**: 2026-04-01

## Context
Speculation about `src/missing.ts`.

## Decision
Maybe later.
EOF

  cat > "$root/docs/stories/2026-01-01-old/01-orphan.feature" <<'EOF'
Feature: orphan thing
  As a user
  I want this
  So that whatever

## Status
- proposed
EOF

  cat > "$root/docs/stories/2026-04-15-new/01-fresh.feature" <<'EOF'
Feature: fresh thing
  As a user
  I want it now

## Priority
- MoSCoW: must

## Source
- feedback: docs/feedback/2026-04-01.md

## Status
- proposed
EOF

  cat > "$root/docs/stories/bootstrap-2026-01-01/01-bootstrap.feature" <<'EOF'
Feature: bootstrap thing

## Status
- proposed
EOF

  cat > "$root/docs/feedback/2026-04-01.md" <<'EOF'
# Feedback digest

## Top 5 issues
- something

## Suggested next-sprint priorities
- P1: cache
EOF

  backdate 31 "$root/docs/stories/2026-01-01-old/01-orphan.feature"
  backdate 90 "$root/docs/stories/bootstrap-2026-01-01/01-bootstrap.feature"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------- build-wiki-index.py ----------------
echo "=== build-wiki-index.py ==="

P1="$TMP/proj1"
seed_fixture "$P1"
CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/build-wiki-index.py" > /dev/null 2>&1
assert_cmd "first invocation creates index.md" test -f "$P1/docs/wiki/index.md"

SHA1=$(sha1sum "$P1/docs/wiki/index.md" | awk '{print $1}')
CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/build-wiki-index.py" > /dev/null 2>&1
SHA2=$(sha1sum "$P1/docs/wiki/index.md" | awk '{print $1}')
assert_cmd "byte-deterministic across runs" test "$SHA1" = "$SHA2"

assert_cmd "index lists all 4 ADRs" \
  test "$(grep -c '^| \[0' "$P1/docs/wiki/index.md")" -eq 4
assert_cmd "index cross-links cache topic to ADRs and stories" \
  bash -c "grep -A4 '^### cache$' '$P1/docs/wiki/index.md' | grep -q 'ADRs:'"

# Opt-out: wiki.enabled=false should produce no file.
P2="$TMP/proj2"
mkdir -p "$P2/.claude"
seed_fixture "$P2"
printf 'wiki:\n  enabled: false\n' > "$P2/.claude/policy.yaml"
CLAUDE_PROJECT_DIR="$P2" python3 "$CLAUDE_PLUGIN_ROOT/scripts/build-wiki-index.py" > /dev/null 2>&1
assert_cmd "wiki.enabled=false: no index.md written" bash -c "! test -e '$P2/docs/wiki/index.md'"

# ---------------- append-wiki-log.py ----------------
echo
echo "=== append-wiki-log.py ==="

CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/append-wiki-log.py" \
  --ts "20260517T120000Z" --goal "test goal one" --status green > /dev/null 2>&1
assert_cmd "first append creates log.md with one row" \
  bash -c "test \$(grep -c '^| 20260517T' '$P1/docs/wiki/log.md') -eq 1"

CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/append-wiki-log.py" \
  --ts "20260517T120000Z" --goal "duplicate goal" --status red > /dev/null 2>&1
assert_cmd "duplicate --ts is idempotent (still one row)" \
  bash -c "test \$(grep -c '^| 20260517T' '$P1/docs/wiki/log.md') -eq 1"

CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/append-wiki-log.py" \
  --ts "20260518T010000Z" --goal "second run" --status escalated > /dev/null 2>&1
assert_cmd "distinct --ts appends a second row" \
  bash -c "test \$(grep -c '^| 2026' '$P1/docs/wiki/log.md') -eq 2"

CLAUDE_PROJECT_DIR="$P2" python3 "$CLAUDE_PLUGIN_ROOT/scripts/append-wiki-log.py" \
  --ts "20260517T120000Z" --goal "should skip" --status green > /dev/null 2>&1
assert_cmd "wiki.enabled=false: no log.md written" bash -c "! test -e '$P2/docs/wiki/log.md'"

# ---------------- wiki_lint.py ----------------
echo
echo "=== wiki_lint.py ==="

LINT_FILE="$TMP/lint-output.txt"
CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/wiki_lint.py" --dry-run > "$LINT_FILE" 2>/dev/null
LINT_RC=$?
assert_cmd "lint exits 2 when a FAIL is present" test "$LINT_RC" -eq 2

count_section() {
  local file="$1" section="$2"
  awk -v sec="## $section" '
    $0 == sec { flag=1; next }
    /^## / { flag=0 }
    flag && /^- / { c++ }
    END { print c+0 }
  ' "$file"
}

assert_cmd "exactly 1 FAIL finding" test "$(count_section "$LINT_FILE" FAIL)" -eq 1
assert_cmd "exactly 2 WARN findings" test "$(count_section "$LINT_FILE" WARN)" -eq 2
assert_cmd "exactly 1 INFO finding" test "$(count_section "$LINT_FILE" INFO)" -eq 1

assert_cmd "FAIL targets the accepted-ADR broken cite (0003)" \
  grep -q '0003-gone' "$LINT_FILE"
assert_cmd "port-conflict WARN names CacheStore" \
  grep -q 'port `CacheStore`' "$LINT_FILE"
assert_cmd "orphan INFO targets the old story (not bootstrap-)" \
  grep -q '2026-01-01-old/01-orphan' "$LINT_FILE"
assert_cmd "bootstrap-sprint story is exempt from orphan check" \
  bash -c "! grep -q 'bootstrap-2026-01-01' '$LINT_FILE'"

# Lint with no FAIL: fix the accepted-ADR cite, verify exit 0.
touch "$P1/src/gone.ts"
CLAUDE_PROJECT_DIR="$P1" python3 "$CLAUDE_PLUGIN_ROOT/scripts/wiki_lint.py" --dry-run > /dev/null 2>&1
assert_cmd "lint exits 0 after FAIL is fixed" test "$?" -eq 0

# Opt-out: wiki.enabled=false should produce no health.md.
CLAUDE_PROJECT_DIR="$P2" python3 "$CLAUDE_PLUGIN_ROOT/scripts/wiki_lint.py" > /dev/null 2>&1
assert_cmd "wiki.enabled=false: no health.md written" bash -c "! test -e '$P2/docs/wiki/health.md'"

echo
test_summary

# Shared assertion helpers for the tests/ suites. Source, don't execute:
#   . "$(dirname "$0")/common.sh"
# Provides PASS/FAIL counters, three assertion styles, and test_summary.

PASS=0
FAIL=0

# assert_exit NAME EXPECTED ACTUAL — exact exit-code comparison.
assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS  $name (exit=$actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $name (expected exit $expected, got $actual)"
    FAIL=$((FAIL+1))
  fi
}

# assert_ok NAME RC — passes when RC is 0.
assert_ok() {
  local name="$1" rc="$2"
  if [ "$rc" = "0" ]; then
    echo "  PASS  $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $name"
    FAIL=$((FAIL+1))
  fi
}

# assert_cmd DESC CMD [ARGS...] — passes when the command succeeds.
assert_cmd() {
  local desc="$1"; shift
  if "$@"; then
    echo "  PASS  $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $desc"
    FAIL=$((FAIL+1))
  fi
}

# test_summary — print the footer and exit 0/1 on the FAIL count.
test_summary() {
  echo
  echo "=== Result ==="
  echo "passed=$PASS  failed=$FAIL"
  [ "$FAIL" = "0" ] || exit 1
  exit 0
}

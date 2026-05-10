#!/usr/bin/env bash
# Smoke-test for hooks (Phase 3 acceptance).
# Uses base64 payloads to avoid the bash-allowlist hook tripping on
# its own test data when this script is itself invoked under a project
# whose hooks are active.

set +e
cd "$(dirname "$0")/.."

PASS=0
FAIL=0

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

run_hook() {
  local hook="$1" payload_b64="$2"
  echo "$payload_b64" | base64 -d | "$hook" >/tmp/hook.out 2>/tmp/hook.err
  echo $?
}

echo "=== bash-allowlist ==="
# git status — allowed
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | base64 -w0)
assert_exit "allow git status" 0 "$(run_hook .claude/hooks/pre-tool-bash-allowlist.sh "$P")"

# rm -rf / — blocked by danger pattern (encoded so this script doesn't trip)
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | base64 -w0)
assert_exit "block rm -rf /" 2 "$(run_hook .claude/hooks/pre-tool-bash-allowlist.sh "$P")"

# Unknown command — blocked by allowlist
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"curl http://evil.example"}}' | base64 -w0)
assert_exit "block unlisted command" 2 "$(run_hook .claude/hooks/pre-tool-bash-allowlist.sh "$P")"

# Allowlisted: ./verify.sh
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"./verify.sh"}}' | base64 -w0)
assert_exit "allow ./verify.sh" 0 "$(run_hook .claude/hooks/pre-tool-bash-allowlist.sh "$P")"

echo
echo "=== policy-guard ==="
# Write to .env — blocked
P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".env","content":"X"}}' | base64 -w0)
assert_exit "block write to .env" 2 "$(run_hook .claude/hooks/policy-guard.sh "$P")"

# Write to .git/config — blocked
P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".git/config","content":"X"}}' | base64 -w0)
assert_exit "block write to .git/config" 2 "$(run_hook .claude/hooks/policy-guard.sh "$P")"

# Write to docs/x.md — allowed
P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/x.md","content":"hi"}}' | base64 -w0)
assert_exit "allow write to docs/" 0 "$(run_hook .claude/hooks/policy-guard.sh "$P")"

# Edit to .claude/runs/next-goal.md (the human-authored input file) — blocked
P=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":".claude/runs/next-goal.md","old_string":"a","new_string":"b"}}' | base64 -w0)
assert_exit "block edit to .claude/runs/next-goal.md" 2 "$(run_hook .claude/hooks/policy-guard.sh "$P")"

# Write to .claude/runs/<ts>/orchestrator.log (per-run working dir) — allowed
P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".claude/runs/20260101T000000Z/orchestrator.log","content":"wave 1 done"}}' | base64 -w0)
assert_exit "allow write to .claude/runs/<ts>/" 0 "$(run_hook .claude/hooks/policy-guard.sh "$P")"

echo
echo "=== pre-commit-verify ==="
# verify.sh exits 0 (default WARN) — commit allowed
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | base64 -w0)
assert_exit "allow git commit when verify passes" 0 "$(run_hook .claude/hooks/pre-commit-verify.sh "$P")"

# Substitute a failing verify.sh
cp verify.sh /tmp/verify.bak
cat > verify.sh <<'EOF'
#!/usr/bin/env bash
echo "intentional failure" >&2
exit 1
EOF
chmod +x verify.sh
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | base64 -w0)
assert_exit "block git commit when verify fails" 2 "$(run_hook .claude/hooks/pre-commit-verify.sh "$P")"
mv /tmp/verify.bak verify.sh
chmod +x verify.sh

# Non-commit Bash command — pass-through (exit 0)
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | base64 -w0)
assert_exit "skip pre-commit-verify on non-commit command" 0 "$(run_hook .claude/hooks/pre-commit-verify.sh "$P")"

echo
echo "=== session-start-context ==="
P=$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' | base64 -w0)
out=$(echo "$P" | base64 -d | .claude/hooks/session-start-context.sh)
rc=$?
if echo "$out" | grep -q '\[session-start-context\]' && [ "$rc" = "0" ]; then
  echo "  PASS  session-start-context produces tagged output"
  PASS=$((PASS+1))
else
  echo "  FAIL  session-start-context (rc=$rc, output=$out)"
  FAIL=$((FAIL+1))
fi

echo
echo "=== on-stop-summary (smoke) ==="
export CLAUDE_RUN_TS="20260509T000000Z-test"
P=$(printf '%s' '{"session_id":"sid-test","hook_event_name":"Stop","stop_hook_active":false}' | base64 -w0)
echo "$P" | base64 -d | .claude/hooks/on-stop-summary.sh
if [ -f ".claude/runs/$CLAUDE_RUN_TS/summary.md" ]; then
  echo "  PASS  on-stop-summary writes summary.md"
  PASS=$((PASS+1))
  rm -rf ".claude/runs/$CLAUDE_RUN_TS"
else
  echo "  FAIL  on-stop-summary did not write summary.md"
  FAIL=$((FAIL+1))
fi
unset CLAUDE_RUN_TS

echo
echo "=== Result ==="
echo "passed=$PASS  failed=$FAIL"
[ "$FAIL" = "0" ] || exit 1
exit 0

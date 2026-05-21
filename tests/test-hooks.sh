#!/usr/bin/env bash
# Smoke-test for the smurf plugin's hooks. Sets $CLAUDE_PLUGIN_ROOT to the
# plugin/ subdir of the repo and $CLAUDE_PROJECT_DIR to a throwaway
# tempdir, then drives each hook with synthetic stdin payloads.
#
# Uses base64 payloads so this script's own commands don't trip the
# bash-allowlist hook if it happens to be active in the surrounding session.

set +e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO/plugin"

# Isolated project workspace for the tests.
TESTPROJ=$(mktemp -d)
trap 'rm -rf "$TESTPROJ"' EXIT
export CLAUDE_PROJECT_DIR="$TESTPROJ"

mkdir -p "$TESTPROJ/.claude/runs"
mkdir -p "$TESTPROJ/docs"
echo "prototype" > "$TESTPROJ/docs/rigor-level.md"

# Default verify.sh = passes (no-op). Tests can swap it out below.
cat > "$TESTPROJ/verify.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TESTPROJ/verify.sh"

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
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | base64 -w0)
assert_exit "allow git status" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | base64 -w0)
assert_exit "block rm -rf /" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"curl http://evil.example"}}' | base64 -w0)
assert_exit "block unlisted command" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"./verify.sh"}}' | base64 -w0)
assert_exit "allow ./verify.sh" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"./verify.sh 2>&1"}}' | base64 -w0)
assert_exit "allow ./verify.sh with redirect" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

# Compound command handling: each top-level segment must match the allowlist.
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status && git diff"}}' | base64 -w0)
assert_exit "allow compound of allowlisted segments" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep foo bar.txt | head -n 5"}}' | base64 -w0)
assert_exit "allow pipe of allowlisted segments" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status && curl http://evil.example"}}' | base64 -w0)
assert_exit "block compound when one segment is unlisted" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo $(date)"}}' | base64 -w0)
assert_exit "block command substitution" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

# Quote-aware splitter: operators inside quoted strings are not separators.
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo \"a && b\""}}' | base64 -w0)
assert_exit "allow && inside double quotes" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

# Bare commands (no arguments) must still match a "<cmd> *" allowlist entry.
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo"}}' | base64 -w0)
assert_exit "allow bare echo (no args)" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls && echo done"}}' | base64 -w0)
assert_exit "allow bare command in compound" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

# Subshell grouping is unwrapped, not treated as part of the command name.
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"(git status || git diff)"}}' | base64 -w0)
assert_exit "allow subshell grouping" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"helm version --short && (kubeconform -v || echo missing)"}}' | base64 -w0)
assert_exit "allow helm/kubeconform with subshell" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

# Leading FOO=bar env-assignment prefixes are stripped before matching.
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"NODE_ENV=test npm test"}}' | base64 -w0)
assert_exit "allow env-assignment prefix" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"FOO=bar"}}' | base64 -w0)
assert_exit "allow bare env-assignment (no command)" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

# Stripping the assignment prefix must not weaken the allowlist for the command.
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"FOO=bar curl http://evil.example"}}' | base64 -w0)
assert_exit "block unlisted command behind env-assignment" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-tool-bash-allowlist.sh" "$P")"

echo
echo "=== policy-guard ==="
P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".env","content":"X"}}' | base64 -w0)
assert_exit "block write to .env" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/policy-guard.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".git/config","content":"X"}}' | base64 -w0)
assert_exit "block write to .git/config" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/policy-guard.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"docs/x.md","content":"hi"}}' | base64 -w0)
assert_exit "allow write to docs/" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/policy-guard.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":".claude/runs/next-goal.md","old_string":"a","new_string":"b"}}' | base64 -w0)
assert_exit "block edit to .claude/runs/next-goal.md" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/policy-guard.sh" "$P")"

P=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".claude/runs/20260101T000000Z/orchestrator.log","content":"wave 1 done"}}' | base64 -w0)
assert_exit "allow write to .claude/runs/<ts>/" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/policy-guard.sh" "$P")"

echo
echo "=== pre-commit-verify ==="
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | base64 -w0)
assert_exit "allow git commit when verify passes" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-commit-verify.sh" "$P")"

# Substitute a failing verify.sh in the test project.
cat > "$TESTPROJ/verify.sh" <<'EOF'
#!/usr/bin/env bash
echo "intentional failure" >&2
exit 1
EOF
chmod +x "$TESTPROJ/verify.sh"
P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | base64 -w0)
assert_exit "block git commit when verify fails" 2 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-commit-verify.sh" "$P")"

# Restore passing verify.sh
cat > "$TESTPROJ/verify.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TESTPROJ/verify.sh"

P=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | base64 -w0)
assert_exit "skip pre-commit-verify on non-commit command" 0 "$(run_hook "$CLAUDE_PLUGIN_ROOT/hooks/pre-commit-verify.sh" "$P")"

echo
echo "=== session-start-context ==="
P=$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' | base64 -w0)
out=$(echo "$P" | base64 -d | "$CLAUDE_PLUGIN_ROOT/hooks/session-start-context.sh")
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
echo "$P" | base64 -d | "$CLAUDE_PLUGIN_ROOT/hooks/on-stop-summary.sh"
if [ -f "$TESTPROJ/.claude/runs/$CLAUDE_RUN_TS/summary.md" ]; then
  echo "  PASS  on-stop-summary writes summary.md"
  PASS=$((PASS+1))
else
  echo "  FAIL  on-stop-summary did not write summary.md"
  FAIL=$((FAIL+1))
fi
unset CLAUDE_RUN_TS

echo
echo "=== on-subagent-complete (smoke) ==="
export CLAUDE_RUN_TS="20260509T000000Z-test-sub"
P=$(printf '%s' '{"session_id":"sid-test","hook_event_name":"SubagentStop","stop_hook_active":false}' | base64 -w0)
echo "$P" | base64 -d | "$CLAUDE_PLUGIN_ROOT/hooks/on-subagent-complete.sh"
if [ -f "$TESTPROJ/.claude/runs/$CLAUDE_RUN_TS/agents.log" ]; then
  echo "  PASS  on-subagent-complete writes agents.log"
  PASS=$((PASS+1))
else
  echo "  FAIL  on-subagent-complete did not write agents.log"
  FAIL=$((FAIL+1))
fi
unset CLAUDE_RUN_TS

echo
echo "=== Result ==="
echo "passed=$PASS  failed=$FAIL"
[ "$FAIL" = "0" ] || exit 1
exit 0

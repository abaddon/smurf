#!/usr/bin/env bash
# Health check for the smurf orchestrator. Verifies the local setup is
# consistent. Run before the first autonomous run, or whenever the
# system misbehaves.
#
# Exit 0 — all checks pass.
# Exit 1 — one or more checks failed.

set +e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1" cmd="$2"
  local out rc
  out=$(eval "$cmd" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  PASS  $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $name"
    [ -n "$out" ] && echo "        $out"
    FAIL=$((FAIL+1))
  fi
}

warn() {
  local name="$1" cmd="$2"
  local out rc
  out=$(eval "$cmd" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  PASS  $name"
    PASS=$((PASS+1))
  else
    echo "  WARN  $name"
    [ -n "$out" ] && echo "        $out"
    WARN=$((WARN+1))
  fi
}

echo "=== Files and structure ==="
check ".claude/smurf.md exists"                'test -f .claude/smurf.md'
check ".claude/policy.yaml exists"             'test -f .claude/policy.yaml'
check ".claude/settings.json exists"           'test -f .claude/settings.json'
check ".claude/settings.json is valid JSON"    'jq . .claude/settings.json > /dev/null'
check ".claude/policy.yaml is valid YAML"      'python3 -c "import yaml; yaml.safe_load(open(\".claude/policy.yaml\"))"'
check "verify.sh exists and is executable"    'test -x verify.sh'
check "docs/rigor-level.md exists"             'test -f docs/rigor-level.md'

echo
echo "=== Agents ==="
for a in orchestrator product-owner architect developer qa-engineer devops marketing sales-feedback; do
  check ".claude/agents/$a.md exists" "test -f .claude/agents/$a.md"
done

echo
echo "=== Skills ==="
for s in code-quality adr-template gherkin-stories conventional-commits openrouter-curl; do
  check ".claude/skills/$s/SKILL.md exists" "test -f .claude/skills/$s/SKILL.md"
done

echo
echo "=== Hooks (executable) ==="
for h in session-start-context pre-tool-bash-allowlist policy-guard pre-commit-verify on-stop-summary on-subagent-complete; do
  check ".claude/hooks/$h.sh executable" "test -x .claude/hooks/$h.sh"
done

echo
echo "=== Slash commands ==="
for c in kickoff kickoff-team nightly-run close-loop; do
  check ".claude/commands/$c.md exists" "test -f .claude/commands/$c.md"
done

echo
echo "=== Settings ==="
check "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json" \
  'jq -e ".env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == \"1\"" .claude/settings.json > /dev/null'
check "Hooks registered for SessionStart"  'jq -e ".hooks.SessionStart | length > 0" .claude/settings.json > /dev/null'
check "Hooks registered for PreToolUse"    'jq -e ".hooks.PreToolUse | length > 0" .claude/settings.json > /dev/null'
check "Hooks registered for Stop"          'jq -e ".hooks.Stop | length > 0" .claude/settings.json > /dev/null'
check "Hooks registered for SubagentStop"  'jq -e ".hooks.SubagentStop | length > 0" .claude/settings.json > /dev/null'

echo
echo "=== Hook smoke test ==="
if [ -x scripts/test-hooks.sh ]; then
  if bash scripts/test-hooks.sh > /tmp/test-hooks.out 2>&1; then
    PASSED_LINE=$(grep -E '^passed=' /tmp/test-hooks.out | tail -1)
    echo "  PASS  scripts/test-hooks.sh ($PASSED_LINE)"
    PASS=$((PASS+1))
  else
    echo "  FAIL  scripts/test-hooks.sh"
    cat /tmp/test-hooks.out | sed 's/^/        /'
    FAIL=$((FAIL+1))
  fi
else
  echo "  WARN  scripts/test-hooks.sh missing"
  WARN=$((WARN+1))
fi

echo
echo "=== Tools available ==="
for t in jq yq python3 git timeout; do
  check "$t on PATH" "command -v $t > /dev/null"
done
warn "claude on PATH (required for autonomous runs)" "command -v claude > /dev/null"
warn "gh on PATH (required for devops PR creation)" "command -v gh > /dev/null"
warn "curl on PATH (required for OpenRouter shell-out)" "command -v curl > /dev/null"

echo
echo "=== MCP ==="
warn ".mcp.json exists" 'test -f .mcp.json'

echo
echo "=== Result ==="
echo "  passed=$PASS  warnings=$WARN  failed=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

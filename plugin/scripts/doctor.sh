#!/usr/bin/env bash
# Health check for the smurf plugin install. Splits checks into:
#   [plugin] — files inside the installed plugin (or development repo)
#   [project] — files the user must scaffold in their project
#
# Exit 0 — all plugin checks pass (project checks are warnings only).
# Exit 1 — one or more plugin checks failed.

set +e

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

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

echo "=== [plugin] Manifest ==="
check ".claude-plugin/plugin.json exists"     "test -f $PLUGIN_ROOT/.claude-plugin/plugin.json"
check ".claude-plugin/plugin.json valid JSON" "jq . $PLUGIN_ROOT/.claude-plugin/plugin.json > /dev/null"
check "hooks/hooks.json exists"               "test -f $PLUGIN_ROOT/hooks/hooks.json"
check "hooks/hooks.json valid JSON"           "jq . $PLUGIN_ROOT/hooks/hooks.json > /dev/null"
check "policy.yaml exists"                    "test -f $PLUGIN_ROOT/policy.yaml"
# PyYAML is optional: the wiki scripts fall back to a minimal parser when
# it is absent, so its absence must not fail the plugin health check.
if python3 -c "import yaml" 2>/dev/null; then
  check "policy.yaml is valid YAML"           "python3 -c \"import yaml; yaml.safe_load(open('$PLUGIN_ROOT/policy.yaml'))\""
else
  warn "policy.yaml YAML check skipped (PyYAML not installed; scripts use a fallback parser)" "false"
fi
check "smurf.md exists"                       "test -f $PLUGIN_ROOT/smurf.md"

echo
echo "=== [plugin] Agents ==="
for a in orchestrator product-owner architect developer qa-engineer devops marketing sales-feedback; do
  check "agents/$a.md exists" "test -f $PLUGIN_ROOT/agents/$a.md"
done

echo
echo "=== [plugin] Skills ==="
for s in code-quality adr-template gherkin-stories conventional-commits openrouter-curl; do
  check "skills/$s/SKILL.md exists" "test -f $PLUGIN_ROOT/skills/$s/SKILL.md"
done

echo
echo "=== [plugin] Hooks (executable) ==="
for h in session-start-context pre-tool-bash-guard policy-guard pre-commit-verify on-stop-summary on-subagent-complete; do
  check "hooks/$h.sh executable" "test -x $PLUGIN_ROOT/hooks/$h.sh"
done

echo
echo "=== [plugin] Slash commands ==="
for c in init kickoff-team kickoff-workflow nightly-run close-loop bootstrap; do
  check "commands/$c.md exists" "test -f $PLUGIN_ROOT/commands/$c.md"
done

echo
echo "=== [plugin] Scripts ==="
for s in autonomous-run.sh close-loop.py doctor.sh install-cron.sh init-project.sh \
         build-wiki-index.py append-wiki-log.py wiki_lint.py; do
  check "scripts/$s exists" "test -f $PLUGIN_ROOT/scripts/$s"
done
for s in build-wiki-index.py append-wiki-log.py wiki_lint.py; do
  check "scripts/$s parses as Python" "python3 -c \"import ast; ast.parse(open('$PLUGIN_ROOT/scripts/$s').read())\""
done

echo
echo "=== [plugin] Tools available on PATH ==="
for t in jq yq python3 git; do
  check "$t on PATH" "command -v $t > /dev/null"
done
warn "timeout or gtimeout on PATH (optional — pure-shell watchdog used otherwise)" \
  "command -v timeout > /dev/null || command -v gtimeout > /dev/null"
warn "claude on PATH (required for autonomous runs)" "command -v claude > /dev/null"
warn "gh on PATH (required for devops PR creation)" "command -v gh > /dev/null"
warn "curl on PATH (required for OpenRouter shell-out)" "command -v curl > /dev/null"

echo
echo "=== [project] Scaffolded files ($PROJECT_ROOT) ==="
warn "verify.sh exists and is executable"     "test -x $PROJECT_ROOT/verify.sh"
warn "docs/rigor-level.md exists"             "test -f $PROJECT_ROOT/docs/rigor-level.md"
warn ".claude/runs/next-goal.md exists"       "test -f $PROJECT_ROOT/.claude/runs/next-goal.md"
warn ".mcp.json exists (optional)"            "test -f $PROJECT_ROOT/.mcp.json"

echo
echo "=== [project] Wiki layer (active when wiki.enabled: true) ==="
warn "docs/wiki/index.md exists (created by first wave 7)"           "test -f $PROJECT_ROOT/docs/wiki/index.md"
warn "docs/wiki/log.md exists (created on first run append)"         "test -f $PROJECT_ROOT/docs/wiki/log.md"
warn "docs/wiki/health.md exists (created by first close-loop)"      "test -f $PROJECT_ROOT/docs/wiki/health.md"
warn "docs/wiki/health.md mtime within 14d (stale → close-loop dead)" \
  "test -f $PROJECT_ROOT/docs/wiki/health.md && test -z \"\$(find $PROJECT_ROOT/docs/wiki/health.md -mtime +14 -print 2>/dev/null)\""
warn ".claude/worktrees/ empty or absent (leftover worktrees may hide wave-7 input)" \
  "test ! -d $PROJECT_ROOT/.claude/worktrees || test -z \"\$(ls -A $PROJECT_ROOT/.claude/worktrees 2>/dev/null)\""

echo
echo "=== [project] Settings ==="
warn "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in user settings (enables peer-to-peer wave 3; /smurf:kickoff-team degrades to subagent mode without it)" \
  "jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == \"1\"' $PROJECT_ROOT/.claude/settings.local.json $PROJECT_ROOT/.claude/settings.json 2>/dev/null | grep -q true"
warn "CLAUDE_CODE_DISABLE_WORKFLOWS not set to 1 (workflows enabled for /smurf:kickoff-workflow)" \
  "test \"\$(printenv CLAUDE_CODE_DISABLE_WORKFLOWS)\" != 1"

echo
echo "=== Result ==="
echo "  passed=$PASS  warnings=$WARN  failed=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

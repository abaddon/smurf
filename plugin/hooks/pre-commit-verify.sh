#!/usr/bin/env bash
# PreToolUse(Bash) hook — runs the policy's verify_command and blocks the
# git commit invocation if it exits non-zero.
#
# Registration: hooks/hooks.json, under matcher "Bash". Hook matchers
# select on the TOOL NAME only, so this script receives every Bash call
# and self-filters: anything that is not a git-commit invocation returns
# immediately (exit 0) without running verify.
#
# The filter matches `git commit` at the start of the command OR after a
# separator (;, &, |, parenthesis), so compound forms like
# `cd x && git commit` cannot bypass it. The match is deliberately
# conservative: a quoted string containing `; git commit` also triggers
# it — the cost of a false positive is one redundant verify run.
#
# verify_command comes from .claude/policy.yaml (project override) or the
# plugin default policy.yaml; it falls back to ./verify.sh.
#
# Stdin JSON shape:
#   { "tool_name": "Bash", "tool_input": { "command": "git commit -m \"...\"" } }
#
# Exit 0 → allow the commit; exit 2 → block with stderr explanation.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

PAYLOAD=$(cat)
CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty')

# Only act on git-commit invocations (start of command or after ; & | ( ).
GIT_COMMIT_RE='(^|[;&|(])[[:space:]]*git[[:space:]]+commit'
if ! [[ "$CMD" =~ $GIT_COMMIT_RE ]]; then
  exit 0
fi

# Resolve verify_command: project policy override wins, plugin default
# fallback, hardcoded ./verify.sh last.
POLICY="$PROJECT_ROOT/.claude/policy.yaml"
[ -f "$POLICY" ] || POLICY="$PLUGIN_ROOT/policy.yaml"

VERIFY_CMD=""
if [ -f "$POLICY" ]; then
  if command -v yq >/dev/null 2>&1; then
    VERIFY_CMD=$(yq -r '.verify_command // empty' "$POLICY" 2>/dev/null || true)
  else
    VERIFY_CMD=$(awk '$1=="verify_command:" {
      sub(/^[[:space:]]*verify_command:[[:space:]]*/, "");
      gsub(/^"|"[[:space:]]*(#.*)?$/, "");
      gsub(/^'\''|'\''[[:space:]]*(#.*)?$/, "");
      print; exit
    }' "$POLICY")
  fi
fi
[ -z "$VERIFY_CMD" ] && VERIFY_CMD="./verify.sh"

# The shipped default is the ./verify.sh shim — give a precise error when
# it is missing rather than a generic command-not-found.
if [ "$VERIFY_CMD" = "./verify.sh" ] && [ ! -x "$PROJECT_ROOT/verify.sh" ]; then
  echo "BLOCKED by pre-commit-verify: verify.sh missing or not executable at $PROJECT_ROOT/verify.sh" >&2
  exit 2
fi

# Capture verify output for the agent's context.
VERIFY_OUT=$( ( cd "$PROJECT_ROOT" && bash -c "$VERIFY_CMD" ) 2>&1 ) || RC=$?
RC="${RC:-0}"

if [ "$RC" -ne 0 ]; then
  echo "BLOCKED by pre-commit-verify: '$VERIFY_CMD' exited $RC" >&2
  echo "---verify output---" >&2
  printf '%s\n' "$VERIFY_OUT" >&2
  exit 2
fi

exit 0

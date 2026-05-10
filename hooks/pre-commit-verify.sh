#!/usr/bin/env bash
# PreToolUse(Bash) hook with matcher "^git commit" — runs ./verify.sh and
# blocks the git commit invocation if verify exits non-zero.
#
# Stdin JSON shape:
#   { "tool_name": "Bash", "tool_input": { "command": "git commit -m \"...\"" } }
#
# Exit 0 → allow the commit; exit 2 → block with stderr explanation.
#
# Note: this hook is registered in settings.json with a matcher that fires
# only on `git commit` invocations. Other Bash calls don't pay this cost.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

PAYLOAD=$(cat)
CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty')

# Defensive: only run on actual git commit commands.
if ! [[ "$CMD" =~ ^git[[:space:]]+commit ]]; then
  exit 0
fi

if [ ! -x "$PROJECT_ROOT/verify.sh" ]; then
  echo "BLOCKED by pre-commit-verify: verify.sh missing or not executable at $PROJECT_ROOT/verify.sh" >&2
  exit 2
fi

# Capture verify output for the agent's context.
VERIFY_OUT=$( ( cd "$PROJECT_ROOT" && ./verify.sh ) 2>&1 ) || RC=$?
RC="${RC:-0}"

if [ "$RC" -ne 0 ]; then
  echo "BLOCKED by pre-commit-verify: ./verify.sh exited $RC" >&2
  echo "---verify output---" >&2
  printf '%s\n' "$VERIFY_OUT" >&2
  exit 2
fi

exit 0

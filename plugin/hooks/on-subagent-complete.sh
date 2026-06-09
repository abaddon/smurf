#!/usr/bin/env bash
# SubagentStop hook — append a one-line record to .claude/runs/<ts>/agents.log
# each time a subagent finishes.
#
# Stdin JSON shape:
#   { "session_id": "...", "transcript_path": "...",
#     "hook_event_name": "SubagentStop",
#     "stop_hook_active": false }
#
# Exit 0 always — never block.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PAYLOAD=$(cat)

TS="${CLAUDE_RUN_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="$PROJECT_ROOT/.claude/runs/$TS"
mkdir -p "$RUN_DIR"

SESSION_ID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"')
TRANSCRIPT=$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty')

# Best-effort: try to extract the subagent's name from the transcript tail.
SUBAGENT_NAME="?"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # Last matching entry; `tail -1` instead of GNU-only `tac … | head -1`.
  SUBAGENT_NAME=$(jq -r 'select(.subagent_type or .agent_name) | (.subagent_type // .agent_name)' \
    "$TRANSCRIPT" 2>/dev/null | tail -1 || echo "?")
  [ -z "$SUBAGENT_NAME" ] && SUBAGENT_NAME="?"
fi

NOW=$(date -u +%FT%TZ)
echo "$NOW  session=$SESSION_ID  subagent=$SUBAGENT_NAME" >> "$RUN_DIR/agents.log"

exit 0

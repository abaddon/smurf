#!/usr/bin/env bash
# Stop hook — write a per-run summary into .claude/runs/<ts>/summary.md.
#
# Stdin JSON shape:
#   { "session_id": "...", "transcript_path": "<path to JSONL transcript>",
#     "cwd": "...", "hook_event_name": "Stop",
#     "stop_hook_active": false }
#
# Exit 0 always — never block stop. Failure to write summary is logged to
# stderr but does not abort the session.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PAYLOAD=$(cat)

# Use the run dir created by autonomous-run.sh if present (env CLAUDE_RUN_TS),
# else create one stamped now (interactive sessions).
TS="${CLAUDE_RUN_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="$PROJECT_ROOT/.claude/runs/$TS"
mkdir -p "$RUN_DIR"

SESSION_ID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"')
TRANSCRIPT=$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty')

# Extract simple metrics from transcript if available.
TURN_COUNT="?"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TURN_COUNT=$(wc -l < "$TRANSCRIPT" 2>/dev/null || echo "?")
fi

# Files changed since the run began (best-effort).
FILES_CHANGED="?"
if (cd "$PROJECT_ROOT" && git rev-parse --git-dir > /dev/null 2>&1); then
  FILES_CHANGED=$( (cd "$PROJECT_ROOT" && git status --porcelain | wc -l) || echo "?")
fi

# QA iteration count from orchestrator.log if it exists.
QA_ITERATIONS="0"
if [ -f "$RUN_DIR/orchestrator.log" ]; then
  QA_ITERATIONS=$(grep -c -i 'qa.iteration' "$RUN_DIR/orchestrator.log" 2>/dev/null || echo 0)
fi

# The orchestrator's OUTPUT CONTRACT writes its own (richer) summary.md
# during the run. Never overwrite it — divert this hook's digest to
# stop-summary.md in that case.
OUT_FILE="$RUN_DIR/summary.md"
if [ -f "$OUT_FILE" ]; then
  OUT_FILE="$RUN_DIR/stop-summary.md"
fi

cat > "$OUT_FILE" <<EOF
# Run summary — $TS

- session_id: $SESSION_ID
- transcript: ${TRANSCRIPT:-(none)}
- transcript_lines: $TURN_COUNT
- files_changed_in_workspace: $FILES_CHANGED
- qa_iterations_observed: $QA_ITERATIONS

## Orchestrator log
$([ -f "$RUN_DIR/orchestrator.log" ] && cat "$RUN_DIR/orchestrator.log" || echo "(no orchestrator.log produced)")

## Subagent log
$([ -f "$RUN_DIR/agents.log" ] && cat "$RUN_DIR/agents.log" || echo "(no agents.log produced)")

## Status
$([ -f "$RUN_DIR/escalation.md" ] && echo "ESCALATED — see escalation.md" || echo "completed (status not explicitly recorded — check transcript)")
EOF

exit 0

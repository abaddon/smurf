#!/usr/bin/env bash
# SessionStart hook — inject rigor-level + last 3 feedback files into context.
#
# Stdin JSON shape (Claude Code SessionStart event):
#   { "session_id": "...", "transcript_path": "...", "cwd": "...",
#     "hook_event_name": "SessionStart", "source": "startup|resume|clear|..." }
#
# Stdout content is added to the assistant's context.
# Exit code 0 always (this is informational, never blocking).

set -euo pipefail

# Plugin scripts run with $CLAUDE_PLUGIN_ROOT pointing at the installed plugin
# and $CLAUDE_PROJECT_DIR pointing at the user's project. Fall back to the
# repo layout when invoked directly from tests/.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# Drain stdin (we don't need its fields, but Claude Code expects us to read it)
cat > /dev/null

# Plugin hooks fire in every project once the plugin is installed. Stay
# silent when this project has no smurf scaffolding (no /smurf:init yet)
# instead of injecting "missing" noise into unrelated sessions.
if [ ! -f "$PROJECT_ROOT/docs/rigor-level.md" ] \
   && [ ! -f "$PROJECT_ROOT/.claude/runs/next-goal.md" ]; then
  exit 0
fi

cat <<EOF
[session-start-context]

## Rigor level
$(cat "$PROJECT_ROOT/docs/rigor-level.md" 2>/dev/null || echo "unknown — docs/rigor-level.md missing")

## Recent feedback (last 3 files)
EOF

if [ -d "$PROJECT_ROOT/docs/feedback" ]; then
  # List the 3 most recent feedback files; print their headlines (## sections).
  # `ls -t` (mtime sort) is portable — GNU find's -printf is not (macOS).
  ls -t "$PROJECT_ROOT/docs/feedback"/*.md 2>/dev/null | head -3 \
    | while read -r f; do
        echo ""
        echo "### $(basename "$f")"
        # Print the file's H2 headlines and any P1/P2/P3 lines
        grep -E '^(## |- P[0-9]:)' "$f" 2>/dev/null || echo "(empty file)"
      done
else
  echo "(no docs/feedback/ yet)"
fi

exit 0

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

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Drain stdin (we don't need its fields, but Claude Code expects us to read it)
cat > /dev/null

cat <<EOF
[session-start-context]

## Rigor level
$(cat "$REPO_ROOT/docs/rigor-level.md" 2>/dev/null || echo "unknown — docs/rigor-level.md missing")

## Recent feedback (last 3 files)
EOF

if [ -d "$REPO_ROOT/docs/feedback" ]; then
  # List the 3 most recent feedback files; print their headlines (## sections)
  find "$REPO_ROOT/docs/feedback" -maxdepth 1 -type f -name '*.md' \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -3 | awk '{print $2}' \
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

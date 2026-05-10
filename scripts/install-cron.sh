#!/usr/bin/env bash
# Idempotent crontab installer for smurf nightly autonomous runs.
# Re-running is a no-op.
#
# Usage:
#   bash install-cron.sh /path/to/project              # install at 01:00
#   bash install-cron.sh /path/to/project "0 2 * * *"  # custom schedule
#   bash install-cron.sh /path/to/project --remove     # remove the line
#   bash install-cron.sh /path/to/project --status     # show current state

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="$PLUGIN_ROOT/scripts/autonomous-run.sh"

if [ $# -lt 1 ]; then
  cat <<EOF >&2
usage: $0 PROJECT_DIR [SCHEDULE | --remove | --status]
Install a nightly cron entry that runs smurf autonomous-run.sh inside
PROJECT_DIR. SCHEDULE is a 5-field cron spec; default "0 1 * * *".
EOF
  exit 2
fi

PROJECT_DIR="$(cd "$1" && pwd)"
shift
LOG_FILE="$PROJECT_DIR/.claude/runs/cron.log"

# Marker comment lets us find/remove our line without disturbing other entries.
MARKER="# smurf-orchestrator (autonomous-run.sh @ $PROJECT_DIR)"

case "${1:-}" in
  --help|-h) cat <<EOF; exit 0
usage: $0 PROJECT_DIR [SCHEDULE | --remove | --status]
EOF
  ;;
  --remove)  ACTION="remove" ;;
  --status)  ACTION="status" ;;
  "")        ACTION="install"; SCHEDULE="0 1 * * *" ;;
  *)         ACTION="install"; SCHEDULE="$1" ;;
esac

current=$(crontab -l 2>/dev/null || true)

case "$ACTION" in
  status)
    echo "$current" | grep -F "$MARKER" || echo "(not installed for $PROJECT_DIR)"
    exit 0
    ;;
  remove)
    new=$(echo "$current" | grep -vF "$MARKER" || true)
    printf '%s\n' "$new" | crontab -
    echo "[install-cron] removed entry for $PROJECT_DIR"
    exit 0
    ;;
  install)
    if echo "$current" | grep -qF "$MARKER"; then
      echo "[install-cron] already installed for $PROJECT_DIR; no change"
      exit 0
    fi
    line="$SCHEDULE /usr/bin/env bash -lc 'cd $PROJECT_DIR && CLAUDE_PROJECT_DIR=$PROJECT_DIR CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT bash $SCRIPT >> $LOG_FILE 2>&1'  $MARKER"
    printf '%s\n%s\n' "$current" "$line" | sed '/^$/d' | crontab -
    echo "[install-cron] installed: $SCHEDULE for $PROJECT_DIR"
    exit 0
    ;;
esac

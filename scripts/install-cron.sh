#!/usr/bin/env bash
# Idempotent crontab installer. Adds a single line for nightly runs at
# 01:00 local time. Re-running this script is a no-op.
#
# Usage:
#   bash scripts/install-cron.sh           # install (default 01:00)
#   bash scripts/install-cron.sh "0 2 * * *"  # custom schedule
#   bash scripts/install-cron.sh --remove  # remove the line
#   bash scripts/install-cron.sh --status  # show current state, no changes

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/autonomous-run.sh"
LOG_FILE="$REPO_ROOT/.claude/runs/cron.log"

# Marker comment lets us find/remove our line without disturbing other entries.
MARKER="# smurf-orchestrator (autonomous-run.sh)"

usage() {
  cat <<EOF
Usage: $0 [SCHEDULE | --remove | --status]
Install a nightly cron entry for scripts/autonomous-run.sh.
SCHEDULE is a 5-field cron spec; default "0 1 * * *".
EOF
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --remove)  ACTION="remove" ;;
  --status)  ACTION="status" ;;
  "")        ACTION="install"; SCHEDULE="0 1 * * *" ;;
  *)         ACTION="install"; SCHEDULE="$1" ;;
esac

current=$(crontab -l 2>/dev/null || true)

case "$ACTION" in
  status)
    echo "$current" | grep -F "$MARKER" || echo "(not installed)"
    exit 0
    ;;
  remove)
    new=$(echo "$current" | grep -vF "$MARKER" || true)
    new=$(echo "$new" | grep -vF "$SCRIPT" || true)
    printf '%s\n' "$new" | crontab -
    echo "[install-cron] removed"
    exit 0
    ;;
  install)
    if echo "$current" | grep -qF "$MARKER"; then
      echo "[install-cron] already installed; no change"
      exit 0
    fi
    line="$SCHEDULE /usr/bin/env bash -lc 'cd $REPO_ROOT && bash $SCRIPT >> $LOG_FILE 2>&1'  $MARKER"
    printf '%s\n%s\n' "$current" "$line" | sed '/^$/d' | crontab -
    echo "[install-cron] installed: $SCHEDULE"
    exit 0
    ;;
esac

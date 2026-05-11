#!/usr/bin/env bash
# Headless autonomous run. Reads .claude/runs/next-goal.md as the goal,
# invokes claude -p with the orchestrator, applies the watchdog, and
# writes everything under .claude/runs/<ts>/.
#
# Env vars (all optional):
#   MODE=subagent|team       — default "subagent". Selects budget tier.
#   BUDGET_OVERRIDE=<usd>    — overrides policy.yaml budget (e.g. for tests)
#   WATCHDOG_OVERRIDE=<dur>  — overrides 4h watchdog (e.g. "10s" for tests)
#   ANTHROPIC_BASE_URL=...   — outage failover (e.g. OpenRouter Anthropic Skin)
#   SLACK_WEBHOOK=...        — if set, post run summary to Slack
#
# Exit codes:
#   0   — run completed (success or graceful budget/turn cap)
#   1   — preflight failure (missing files, etc.)
#   124 — watchdog fired (SIGTERM partial summary written)

set -euo pipefail

# Plugin scripts run with $CLAUDE_PLUGIN_ROOT (installed plugin) and
# $CLAUDE_PROJECT_DIR (user's project). Headless `claude -p` must run
# in the project so the plugin auto-loads in that session.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_ROOT"

# ---- preflight ----
if [ ! -f ".claude/runs/next-goal.md" ]; then
  echo "ERROR: .claude/runs/next-goal.md not found in $PROJECT_ROOT. Run /smurf:init then write the goal." >&2
  exit 1
fi

# Policy: project override wins, plugin default fallback.
POLICY=".claude/policy.yaml"
[ -f "$POLICY" ] || POLICY="$PLUGIN_ROOT/policy.yaml"
if [ ! -f "$POLICY" ]; then
  echo "ERROR: policy.yaml not found in $PROJECT_ROOT/.claude/ or $PLUGIN_ROOT/." >&2
  exit 1
fi

if [ ! -x "verify.sh" ]; then
  echo "ERROR: verify.sh missing or not executable in $PROJECT_ROOT. Run /smurf:init." >&2
  exit 1
fi

GOAL=$(cat .claude/runs/next-goal.md)
if [ -z "${GOAL// /}" ]; then
  echo "ERROR: .claude/runs/next-goal.md is empty." >&2
  exit 1
fi

MODE="${MODE:-subagent}"
case "$MODE" in
  subagent|team) ;;
  *) echo "ERROR: MODE must be 'subagent' or 'team', got '$MODE'." >&2; exit 1 ;;
esac

# ---- budget resolution ----
if [ -n "${BUDGET_OVERRIDE:-}" ]; then
  BUDGET="$BUDGET_OVERRIDE"
elif command -v yq >/dev/null 2>&1; then
  BUDGET=$(yq -r ".budget_usd_${MODE}" "$POLICY")
else
  # Fallback: grep the line
  BUDGET=$(awk -v key="budget_usd_${MODE}:" '$1==key {print $2}' "$POLICY")
fi
[ -z "$BUDGET" ] && BUDGET="12"

# ---- watchdog ----
WATCHDOG="${WATCHDOG_OVERRIDE:-4h}"

# ---- run dir ----
TS=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR=".claude/runs/$TS"
mkdir -p "$RUN_DIR"
export CLAUDE_RUN_TS="$TS"   # picked up by on-stop-summary.sh and on-subagent-complete.sh

echo "$GOAL" > "$RUN_DIR/goal.md"
{
  echo "ts=$TS"
  echo "mode=$MODE"
  echo "budget_usd=$BUDGET"
  echo "watchdog=$WATCHDOG"
  echo "anthropic_base_url=${ANTHROPIC_BASE_URL:-default}"
  echo "git_head=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
} > "$RUN_DIR/meta.txt"

# ---- SIGTERM trap → partial summary ----
on_term() {
  cat > "$RUN_DIR/partial-summary.json" <<EOF
{"status":"terminated","reason":"timeout_or_signal","ts":"$(date -u +%FT%TZ)","run_dir":"$RUN_DIR"}
EOF
  echo "[watchdog] killed; partial summary at $RUN_DIR/partial-summary.json" >&2
  exit 124
}
trap on_term TERM INT

# ---- slash command selection ----
if [ "$MODE" = "team" ]; then
  PROMPT="/smurf:kickoff-team $GOAL"
else
  PROMPT="/smurf:kickoff $GOAL"
fi

# ---- run ----
# Note: --bare deliberately NOT used — it would suppress .mcp.json auto-load
# and break mcp__github (research §1.5 + plan §8).
# --max-turns is the real ceiling under subscription billing; --max-budget-usd
# is best-effort.
ALLOWED_TOOLS="Read,Write,Edit,Bash(./verify.sh),Bash(git *),Bash(gh *),Bash(curl https://openrouter.ai/api/v1/*),Bash(python3 *),Bash(jq *),Bash(yq *),TodoWrite,mcp__github"

set +e
timeout --signal=TERM "$WATCHDOG" \
  claude -p "$PROMPT" \
    --allowedTools "$ALLOWED_TOOLS" \
    --max-turns 200 \
    --output-format stream-json --verbose \
    > "$RUN_DIR/run.ndjson" 2> "$RUN_DIR/run.err"
RC=$?
set -e

# `timeout` exits 124 when the watchdog fires; it does not propagate SIGTERM
# to this script, so the trap above won't run. Explicitly handle the case.
if [ "$RC" -eq 124 ]; then
  cat > "$RUN_DIR/partial-summary.json" <<EOF
{"status":"terminated","reason":"watchdog_timeout","watchdog":"$WATCHDOG","ts":"$(date -u +%FT%TZ)","run_dir":"$RUN_DIR"}
EOF
  echo "[watchdog] timeout fired; partial summary at $RUN_DIR/partial-summary.json" >&2
fi

# ---- post-run notification ----
if [ -n "${SLACK_WEBHOOK:-}" ]; then
  LAST=$(jq -r '.messages[-1].content // empty' < "$RUN_DIR/run.ndjson" 2>/dev/null | tail -c 2000)
  if [ -n "$LAST" ]; then
    curl -sS -X POST -H "Content-Type: application/json" \
      --data "{\"text\": $(printf '%s' "$LAST" | jq -Rs .)}" \
      "$SLACK_WEBHOOK" > /dev/null || true
  fi
fi

# ---- close-loop hook (Phase 7+) ----
if [ -x "$PLUGIN_ROOT/scripts/close-loop.py" ]; then
  python3 "$PLUGIN_ROOT/scripts/close-loop.py" --window 7d \
    > "$RUN_DIR/close-loop.out" 2> "$RUN_DIR/close-loop.err" || true
fi

echo "[autonomous-run] complete: $RUN_DIR/ (rc=$RC)"
exit "$RC"

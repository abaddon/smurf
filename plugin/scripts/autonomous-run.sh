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

# Policy: project override wins, plugin default fallback (lib/policy.sh
# is the single bash-side parser).
. "$PLUGIN_ROOT/lib/policy.sh"
if ! POLICY=$(policy_file "$PROJECT_ROOT" "$PLUGIN_ROOT"); then
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

# ---- budget + turn-cap resolution ----
if [ -n "${BUDGET_OVERRIDE:-}" ]; then
  BUDGET="$BUDGET_OVERRIDE"
else
  BUDGET=$(policy_scalar "budget_usd_${MODE}" "$POLICY")
fi
[ -z "$BUDGET" ] && BUDGET="12"

# max_turns_orchestrator caps the headless main session (which runs the
# orchestrator role). Policy is the single source of truth for caps.
MAX_TURNS=$(policy_scalar max_turns_orchestrator "$POLICY")
case "$MAX_TURNS" in (*[!0-9]*|"") MAX_TURNS="200" ;; esac

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

# ---- portable watchdog ----
# GNU `timeout` is absent on stock macOS. Prefer it (or Homebrew coreutils'
# `gtimeout`) when present; otherwise fall back to a pure-shell watchdog so
# the plugin needs zero extra installs. All paths SIGTERM the command on
# expiry and yield exit code 124 — matching GNU `timeout`'s contract.
WD_CMD_PID=""   # PID of the wrapped command (pure-shell path only)
WD_PID=""       # PID of the watchdog subshell (pure-shell path only)

duration_to_secs() {
  # Accepts NNN[s|m|h|d] — the suffixes GNU `timeout` understands.
  local d="$1"
  if [[ "$d" =~ ^([0-9]+)([smhd]?)$ ]]; then
    local n="${BASH_REMATCH[1]}" u="${BASH_REMATCH[2]}"
    case "$u" in
      ""|s) echo "$n" ;;
      m)    echo "$(( n * 60 ))" ;;
      h)    echo "$(( n * 3600 ))" ;;
      d)    echo "$(( n * 86400 ))" ;;
    esac
    return 0
  fi
  return 1
}

run_with_watchdog() {
  local duration="$1"; shift

  local timeout_bin=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_bin="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin="gtimeout"
  fi
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" --signal=TERM "$duration" "$@"
    return $?
  fi

  # Pure-shell fallback: background the command, arm a killer subshell.
  local secs
  if ! secs=$(duration_to_secs "$duration"); then
    echo "[watchdog] unparseable duration '$duration'; running without a watchdog" >&2
    "$@"
    return $?
  fi

  local fired="$RUN_DIR/.watchdog-fired"
  rm -f "$fired"

  "$@" &
  WD_CMD_PID=$!

  (
    sleep "$secs"
    : > "$fired"
    kill -TERM "$WD_CMD_PID" 2>/dev/null
    sleep 10
    kill -KILL "$WD_CMD_PID" 2>/dev/null
  ) &
  WD_PID=$!

  wait "$WD_CMD_PID" 2>/dev/null
  local rc=$?

  # Command returned first — retire the watchdog subshell.
  kill -TERM "$WD_PID" 2>/dev/null
  wait "$WD_PID" 2>/dev/null || true
  WD_CMD_PID=""
  WD_PID=""

  if [ -e "$fired" ]; then
    rm -f "$fired"
    return 124
  fi
  return "$rc"
}

# ---- SIGTERM trap → partial summary ----
on_term() {
  # Tear down pure-shell watchdog children, if any are in flight.
  [ -n "$WD_PID" ]     && kill -TERM "$WD_PID" 2>/dev/null || true
  [ -n "$WD_CMD_PID" ] && kill -TERM "$WD_CMD_PID" 2>/dev/null || true
  cat > "$RUN_DIR/partial-summary.json" <<EOF
{"status":"terminated","reason":"timeout_or_signal","ts":"$(date -u +%FT%TZ)","run_dir":"$RUN_DIR"}
EOF
  echo "[watchdog] killed; partial summary at $RUN_DIR/partial-summary.json" >&2
  exit 124
}
trap on_term TERM INT

# ---- slash command ----
# /smurf:kickoff-team is the single kickoff: it attempts Agent Teams for
# wave 3 and degrades to subagent mode on its own. MODE only selects the
# budget tier above.
PROMPT="/smurf:kickoff-team $GOAL"

# ---- run ----
# Note: --bare deliberately NOT used — it would suppress .mcp.json auto-load
# and break mcp__github.
# --max-turns is the real ceiling under subscription billing; --max-budget-usd
# is best-effort.
# Note: agents read smurf.md / policy.yaml via the Read tool (not `cat`),
# so no Bash(cat *) entry is needed. Bash(claude --version) is for the
# orchestrator's ultrareview/workflow CLI-version gates.
ALLOWED_TOOLS="Read,Write,Edit,Bash(./verify.sh),Bash(git *),Bash(gh *),Bash(curl https://openrouter.ai/api/v1/*),Bash(python3 *),Bash(jq *),Bash(yq *),Bash(claude --version),TodoWrite,mcp__github"

set +e
run_with_watchdog "$WATCHDOG" \
  claude -p "$PROMPT" \
    --allowedTools "$ALLOWED_TOOLS" \
    --max-turns "$MAX_TURNS" \
    --max-budget-usd "$BUDGET" \
    --output-format stream-json --verbose \
    > "$RUN_DIR/run.ndjson" 2> "$RUN_DIR/run.err"
RC=$?
set -e

# The watchdog yields exit 124 when it fires; it does not propagate SIGTERM
# to this script, so the trap above won't run. Explicitly handle the case.
if [ "$RC" -eq 124 ]; then
  cat > "$RUN_DIR/partial-summary.json" <<EOF
{"status":"terminated","reason":"watchdog_timeout","watchdog":"$WATCHDOG","ts":"$(date -u +%FT%TZ)","run_dir":"$RUN_DIR"}
EOF
  echo "[watchdog] timeout fired; partial summary at $RUN_DIR/partial-summary.json" >&2
fi

# ---- post-run notification ----
if [ -n "${SLACK_WEBHOOK:-}" ]; then
  # stream-json is NDJSON; the final event is {"type":"result","result":"…"}.
  LAST=$(jq -r 'select(.type == "result") | .result // empty' < "$RUN_DIR/run.ndjson" 2>/dev/null | tail -c 2000)
  if [ -n "$LAST" ]; then
    curl -sS -X POST -H "Content-Type: application/json" \
      --data "{\"text\": $(printf '%s' "$LAST" | jq -Rs .)}" \
      "$SLACK_WEBHOOK" > /dev/null || true
  fi
fi

# ---- wiki log fallback ----
# The orchestrator is responsible for appending its own log row. If it
# crashed (RC != 0) or was killed by the watchdog, it may not have done
# so. append-wiki-log.py is idempotent on --ts, so calling it here is
# safe: if the orchestrator already logged this run, it's a no-op.
if [ -x "$PLUGIN_ROOT/scripts/append-wiki-log.py" ]; then
  FALLBACK_STATUS="interrupted"
  if [ "$RC" -eq 0 ]; then FALLBACK_STATUS="green"; fi
  if [ "$RC" -eq 124 ]; then FALLBACK_STATUS="terminated"; fi
  python3 "$PLUGIN_ROOT/scripts/append-wiki-log.py" \
    --ts "$TS" \
    --goal "$(printf '%s' "$GOAL" | head -1)" \
    --waves "-" \
    --qa-iterations 0 \
    --status "$FALLBACK_STATUS" \
    --pr-url "-" \
    --head-sha "$(git rev-parse --short HEAD 2>/dev/null || echo -)" \
    >> "$RUN_DIR/wiki-log.out" 2>&1 || true
  # Commit the fallback row so the next run doesn't start with a dirty
  # tree. If the orchestrator already logged+committed this run, the
  # idempotent append above was a no-op and porcelain is empty → skip.
  # The log path honours a project's wiki.log_path override, same as
  # append-wiki-log.py.
  WIKI_LOG_REL=$(policy_scalar wiki.log_path "$POLICY")
  [ -z "$WIKI_LOG_REL" ] && WIKI_LOG_REL="docs/wiki/log.md"
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain -- "$WIKI_LOG_REL" 2>/dev/null)" ]; then
      git add "$WIKI_LOG_REL" >> "$RUN_DIR/wiki-log.out" 2>&1 || true
      git commit -q -m "docs(wiki): log run $TS (autonomous fallback)" -- "$WIKI_LOG_REL" \
        >> "$RUN_DIR/wiki-log.out" 2>&1 || true
    fi
  fi
fi

# ---- close-loop hook (Phase 7+) ----
if [ -x "$PLUGIN_ROOT/scripts/close-loop.py" ]; then
  python3 "$PLUGIN_ROOT/scripts/close-loop.py" --window 7d \
    > "$RUN_DIR/close-loop.out" 2> "$RUN_DIR/close-loop.err" || true
fi

echo "[autonomous-run] complete: $RUN_DIR/ (rc=$RC)"
exit "$RC"

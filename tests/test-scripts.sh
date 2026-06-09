#!/usr/bin/env bash
# Tests for the plugin's script entry points: doctor.sh, init-project.sh,
# and autonomous-run.sh (driven with a stubbed `claude` on PATH).

set +e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO/plugin"

. "$(dirname "$0")/common.sh"

# Pull the value following a flag out of the recorded one-arg-per-line argv.
argval() { awk -v flag="$1" 'prev==flag {print; exit} {prev=$0}' "$2"; }

CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]}"' EXIT

echo "=== doctor.sh (self-check on this repo) ==="
DOCTORPROJ=$(mktemp -d); CLEANUP_DIRS+=("$DOCTORPROJ")
CLAUDE_PROJECT_DIR="$DOCTORPROJ" bash "$CLAUDE_PLUGIN_ROOT/scripts/doctor.sh" > /tmp/doctor-test.out 2>&1
assert_ok "doctor.sh exits 0 on the development repo" $?

echo
echo "=== init-project.sh ==="
T=$(mktemp -d); CLEANUP_DIRS+=("$T")
bash "$CLAUDE_PLUGIN_ROOT/scripts/init-project.sh" "$T" > /tmp/init-test.out 2>&1
assert_ok "first run exits 0" $?
[ -x "$T/verify.sh" ];                       assert_ok "creates executable verify.sh" $?
[ -f "$T/docs/rigor-level.md" ];             assert_ok "creates docs/rigor-level.md" $?
[ -f "$T/.claude/runs/next-goal.md" ];       assert_ok "creates .claude/runs/next-goal.md" $?
grep -qxF ".claude/runs/" "$T/.gitignore";   assert_ok "gitignore gains .claude/runs/" $?
jq -e '.permissions.allow | length == 2' "$T/.claude/settings.local.json" > /dev/null 2>&1
assert_ok "both allow-rule variants written to settings.local.json" $?

echo "do not overwrite me" > "$T/verify.sh"
bash "$CLAUDE_PLUGIN_ROOT/scripts/init-project.sh" "$T" > /tmp/init-test2.out 2>&1
assert_ok "re-run exits 0 (idempotent)" $?
grep -qx "do not overwrite me" "$T/verify.sh"
assert_ok "re-run does not overwrite existing files" $?
jq -e '.permissions.allow | length == 2' "$T/.claude/settings.local.json" > /dev/null 2>&1
assert_ok "re-run does not duplicate allow rules" $?
[ "$(grep -cxF '.claude/runs/' "$T/.gitignore")" = "1" ]
assert_ok "re-run does not duplicate gitignore lines" $?

T2=$(mktemp -d); CLEANUP_DIRS+=("$T2")
mkdir -p "$T2/.claude"
echo '[]' > "$T2/.claude/settings.local.json"
bash "$CLAUDE_PLUGIN_ROOT/scripts/init-project.sh" "$T2" > /tmp/init-test3.out 2>&1
assert_ok "run with malformed settings.local.json still exits 0" $?
grep -qx '\[\]' "$T2/.claude/settings.local.json"
assert_ok "malformed settings.local.json left untouched" $?

echo
echo "=== autonomous-run.sh (stubbed claude) ==="
STUB=$(mktemp -d); CLEANUP_DIRS+=("$STUB")
cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
# Test stub: records argv (one per line), optionally hangs once, then
# emits a minimal stream-json transcript.
[ -n "${CLAUDE_ARGS_FILE:-}" ] && printf '%s\n' "$@" >> "$CLAUDE_ARGS_FILE"
if [ -n "${CLAUDE_STUB_HANG_MARKER:-}" ] && [ ! -e "$CLAUDE_STUB_HANG_MARKER" ]; then
  : > "$CLAUDE_STUB_HANG_MARKER"
  sleep 60
fi
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
echo '{"type":"result","subtype":"success","result":"run finished: GREEN"}'
EOF
chmod +x "$STUB/claude"

make_project() {
  local p
  p=$(mktemp -d)
  git -C "$p" init -q
  git -C "$p" config user.email "test@smurf.local"
  git -C "$p" config user.name "smurf-test"
  # Isolate from host-level signing config (CI sandboxes may force it).
  git -C "$p" config commit.gpgsign false
  mkdir -p "$p/.claude/runs"
  echo "stub goal" > "$p/.claude/runs/next-goal.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$p/verify.sh"
  chmod +x "$p/verify.sh"
  printf 'budget_usd_subagent: 7\nmax_turns_orchestrator: 33\n' > "$p/.claude/policy.yaml"
  echo "$p"
}

# --- preflight failure: missing goal file ---
EMPTY=$(mktemp -d); CLEANUP_DIRS+=("$EMPTY")
( cd "$EMPTY" && PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$EMPTY" \
    bash "$CLAUDE_PLUGIN_ROOT/scripts/autonomous-run.sh" ) > /tmp/auto-pre.out 2>&1
[ "$?" = "1" ]; assert_ok "preflight: missing next-goal.md exits 1" $?

# --- green run: caps from project policy, result parse, fallback log commit ---
PROJ=$(make_project); CLEANUP_DIRS+=("$PROJ")
ARGS="$PROJ/claude-args.txt"
PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_ARGS_FILE="$ARGS" \
  WATCHDOG_OVERRIDE=60s bash "$CLAUDE_PLUGIN_ROOT/scripts/autonomous-run.sh" > /tmp/auto-green.out 2>&1
assert_ok "green run exits 0" $?
[ "$(argval --max-budget-usd "$ARGS")" = "7" ]
assert_ok "budget read from project policy override (7)" $?
[ "$(argval --max-turns "$ARGS")" = "33" ]
assert_ok "max-turns read from project policy override (33)" $?
RUN_DIR=$(ls -d "$PROJ"/.claude/runs/2* 2>/dev/null | tail -1)
[ "$(jq -r 'select(.type == "result") | .result // empty' < "$RUN_DIR/run.ndjson" 2>/dev/null)" = "run finished: GREEN" ]
assert_ok "run.ndjson result event parseable" $?
grep -q "| green |" "$PROJ/docs/wiki/log.md" 2>/dev/null
assert_ok "fallback wiki log row appended with status green" $?
git -C "$PROJ" log --oneline | grep -q "docs(wiki): log run"
assert_ok "fallback wiki log row committed" $?
[ -z "$(git -C "$PROJ" status --porcelain -- docs/wiki/log.md 2>/dev/null)" ]
assert_ok "docs/wiki/log.md left clean in the work tree" $?

# --- watchdog: hung claude is killed, partial summary written ---
PROJ2=$(make_project); CLEANUP_DIRS+=("$PROJ2")
PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$PROJ2" \
  CLAUDE_STUB_HANG_MARKER="$PROJ2/.hang-once" \
  WATCHDOG_OVERRIDE=2s bash "$CLAUDE_PLUGIN_ROOT/scripts/autonomous-run.sh" > /tmp/auto-wd.out 2>&1
[ "$?" = "124" ]; assert_ok "watchdog fires: exit 124" $?
RUN_DIR2=$(ls -d "$PROJ2"/.claude/runs/2* 2>/dev/null | tail -1)
[ -f "$RUN_DIR2/partial-summary.json" ]
assert_ok "partial-summary.json written on watchdog timeout" $?
grep -q "| terminated |" "$PROJ2/docs/wiki/log.md" 2>/dev/null
assert_ok "fallback wiki log row appended with status terminated" $?

echo
echo "=== close-loop.py (--dry-run) ==="
P3=$(mktemp -d); CLEANUP_DIRS+=("$P3")
CLAUDE_PROJECT_DIR="$P3" python3 "$CLAUDE_PLUGIN_ROOT/scripts/close-loop.py" --dry-run > /tmp/closeloop-dry.out 2>&1
assert_ok "dry-run exits 0" $?
[ -z "$(ls -A "$P3" 2>/dev/null)" ]
assert_ok "dry-run writes nothing to the project tree" $?

test_summary

#!/usr/bin/env bash
# Install Smurf into a target project.
#
# Usage:
#   bash scripts/install.sh /path/to/target-project
#   bash scripts/install.sh .                          # install into current dir
#
# Idempotent: never overwrites existing files at the target. Each skipped
# file prints `[skip] ...`. Each newly created file prints `[ok] ...`.
#
# Smurf's manual lives at `.claude/smurf.md` and never collides with the
# target project's own `CLAUDE.md`. The target project may opt-in to
# inheriting Smurf's house rules globally by adding `@.claude/smurf.md`
# to its `CLAUDE.md`.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <target-project-dir>" >&2
  exit 2
fi

SMURF_SRC="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$(cd "$1" 2>/dev/null && pwd || true)"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "ERROR: target dir does not exist: $1" >&2
  exit 1
fi

if [ "$TARGET" = "$SMURF_SRC" ]; then
  echo "ERROR: target is the smurf source repo itself; pick a different dir" >&2
  exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "WARN: $TARGET is not a git repo. Smurf agents commit atomically — initialize git before your first run."
fi

echo "Installing Smurf"
echo "  source: $SMURF_SRC"
echo "  target: $TARGET"
echo

# Copy a file or directory from SMURF_SRC to TARGET, preserving relative path.
# Skips silently if the target path already exists.
copy_path() {
  local rel="$1"
  local src="$SMURF_SRC/$rel"
  local dst="$TARGET/$rel"
  if [ ! -e "$src" ]; then
    echo "  [warn] source missing: $rel"
    return
  fi
  if [ -e "$dst" ]; then
    echo "  [skip] $rel (already exists)"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp -r "$src" "$dst"
  echo "  [ok]   $rel"
}

# Write a literal file only if it doesn't already exist.
write_if_missing() {
  local rel="$1"
  local content="$2"
  local mode="${3:-}"
  local dst="$TARGET/$rel"
  if [ -e "$dst" ]; then
    echo "  [skip] $rel (already exists)"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  printf '%s' "$content" > "$dst"
  [ -n "$mode" ] && chmod "$mode" "$dst"
  echo "  [ok]   $rel"
}

echo "== Portable .claude/ =="
copy_path ".claude/agents"
copy_path ".claude/commands"
copy_path ".claude/hooks"
copy_path ".claude/skills"
copy_path ".claude/policy.yaml"
copy_path ".claude/settings.json"
copy_path ".claude/smurf.md"

echo
echo "== Portable docs/specs/ =="
copy_path "docs/specs"

echo
echo "== Portable scripts/ =="
copy_path "scripts/autonomous-run.sh"
copy_path "scripts/close-loop.py"
copy_path "scripts/doctor.sh"
copy_path "scripts/test-hooks.sh"
copy_path "scripts/install-cron.sh"

echo
echo "== Project-specific stubs (created only if missing) =="

write_if_missing "docs/rigor-level.md" "prototype
"

write_if_missing "verify.sh" '#!/usr/bin/env bash
# Project verify shim. Smurf agents call ONLY this script.
# Replace the body with your stack: npm test, pytest, cargo test, mvn verify, etc.
set -euo pipefail
echo "verify.sh: no checks configured yet — replace this body" >&2
exit 0
' "+x"

write_if_missing ".claude/runs/next-goal.md" ""

# .mcp.json — copy from source if missing
copy_path ".mcp.json"

echo
echo "== .gitignore (append missing lines) =="
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"
for line in ".claude/runs/" ".claude/worktrees/" ".claude/settings.local.json"; do
  if grep -qxF "$line" "$GITIGNORE"; then
    echo "  [skip] .gitignore already contains: $line"
  else
    printf '%s\n' "$line" >> "$GITIGNORE"
    echo "  [ok]   appended to .gitignore: $line"
  fi
done

cat <<EOF

Smurf installed at $TARGET.

Next steps:
  1. Edit .claude/policy.yaml — extend bash_allowlist + forbidden_patterns
     for your stack and project rules.
  2. Replace verify.sh body with your real test/build command.
  3. (Optional) Append \`@.claude/smurf.md\` to your CLAUDE.md to inherit
     Smurf's house rules in every Claude Code session, not just Smurf
     agent runs.
  4. Verify the install:
       cd "$TARGET" && bash scripts/doctor.sh
  5. Write your first goal:
       echo "<your goal>" > "$TARGET/.claude/runs/next-goal.md"
EOF

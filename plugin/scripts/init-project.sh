#!/usr/bin/env bash
# Scaffold the minimum project-side files smurf needs. Idempotent —
# never overwrites existing files. Each created file prints `[ok]`,
# each pre-existing file prints `[skip]`.
#
# Invoked by /smurf:init. Usage:
#   bash init-project.sh /path/to/target-project
#   bash init-project.sh                            # uses current dir
set -euo pipefail

TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)"
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "ERROR: target dir does not exist: ${1:-$PWD}" >&2
  exit 1
fi

echo "Scaffolding smurf project files in $TARGET"

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

# .gitignore: append missing lines.
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

if [ ! -d "$TARGET/.git" ]; then
  echo "  [warn] $TARGET is not a git repo. Smurf agents commit atomically — initialize git before your first run."
fi

echo
echo "Done. Next: edit verify.sh, write a goal to .claude/runs/next-goal.md, run /smurf:kickoff."
echo "Wiki layer (docs/wiki/) is enabled by default; it populates on your first"
echo "/smurf:kickoff or /smurf:bootstrap. To opt out, set wiki.enabled: false in"
echo ".claude/policy.yaml (see docs/specs/15-wiki.md)."

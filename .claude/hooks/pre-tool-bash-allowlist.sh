#!/usr/bin/env bash
# PreToolUse(Bash) hook — block commands not matching .claude/policy.yaml bash_allowlist.
# Also blocks well-known dangerous patterns regardless of allowlist.
#
# Stdin JSON shape:
#   { "session_id": "...", "tool_name": "Bash",
#     "tool_input": { "command": "<cmd>", "description": "...", "timeout": 120000 } }
#
# Exit 0 → allow.
# Exit 2 → deny; stderr is shown to the user/agent.
# Other non-zero → error (treated as block in current Claude Code).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$REPO_ROOT/.claude/policy.yaml"

PAYLOAD=$(cat)
CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  # Nothing to check; allow.
  exit 0
fi

# Hard denylist (independent of allowlist) — dangerous patterns.
DANGER_PATTERNS=(
  'rm[[:space:]]+-rf[[:space:]]+/'
  'rm[[:space:]]+-rf[[:space:]]+\$HOME'
  'rm[[:space:]]+-rf[[:space:]]+~'
  ':\(\)\s*\{\s*:\|:&\s*\};:'   # fork bomb
  'mkfs\.'
  'dd[[:space:]]+if=/dev/(zero|random|urandom)[[:space:]]+of=/dev/'
  '>[[:space:]]*/dev/sda'
  'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
  'curl[[:space:]]+[^|]*\|[[:space:]]*sh'    # blind curl|sh
  'wget[[:space:]]+[^|]*\|[[:space:]]*sh'
)
for p in "${DANGER_PATTERNS[@]}"; do
  if [[ "$CMD" =~ $p ]]; then
    echo "BLOCKED by pre-tool-bash-allowlist: matches dangerous pattern /$p/" >&2
    echo "command: $CMD" >&2
    exit 2
  fi
done

# Allowlist from policy.yaml. Patterns are glob-style; we convert to regex.
if [ ! -f "$POLICY" ]; then
  echo "BLOCKED: .claude/policy.yaml missing — cannot evaluate allowlist" >&2
  exit 2
fi

# Read allowlist via yq if available, else minimal awk fallback.
if command -v yq >/dev/null 2>&1; then
  mapfile -t PATTERNS < <(yq -r '.bash_allowlist[]' "$POLICY" 2>/dev/null)
else
  # Fallback: parse "  - \"...\"" lines under bash_allowlist:
  mapfile -t PATTERNS < <(awk '
    /^bash_allowlist:/ {in_list=1; next}
    in_list && /^[a-zA-Z]/ {in_list=0}
    in_list && /^[[:space:]]+-[[:space:]]/ {
      sub(/^[[:space:]]+-[[:space:]]+/, "");
      gsub(/^["'\'']/, "");
      gsub(/["'\'']$/, "");
      print
    }
  ' "$POLICY")
fi

if [ "${#PATTERNS[@]}" -eq 0 ]; then
  echo "BLOCKED: bash_allowlist is empty in policy.yaml" >&2
  exit 2
fi

# Match command (full string) against any pattern.
# Convert glob -> regex anchored: '*' -> '.*', escape regex metas.
glob_to_regex() {
  local glob="$1"
  local re=""
  local i ch
  for (( i=0; i<${#glob}; i++ )); do
    ch="${glob:$i:1}"
    case "$ch" in
      '*') re+=".*" ;;
      '?') re+="." ;;
      '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'\\'|'|') re+="\\$ch" ;;
      *)   re+="$ch" ;;
    esac
  done
  printf '^%s$' "$re"
}

for glob in "${PATTERNS[@]}"; do
  re=$(glob_to_regex "$glob")
  if [[ "$CMD" =~ $re ]]; then
    exit 0
  fi
done

echo "BLOCKED by pre-tool-bash-allowlist: '$CMD' does not match any pattern in policy.yaml bash_allowlist" >&2
echo "Allowlist: ${PATTERNS[*]}" >&2
exit 2

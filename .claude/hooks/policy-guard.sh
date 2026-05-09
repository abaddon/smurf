#!/usr/bin/env bash
# PreToolUse(Write|Edit) hook — block writes to forbidden paths and writes
# whose content matches forbidden_patterns from .claude/policy.yaml.
#
# Stdin JSON shape:
#   Write: { "tool_name": "Write",
#            "tool_input": { "file_path": "...", "content": "..." } }
#   Edit:  { "tool_name": "Edit",
#            "tool_input": { "file_path": "...", "old_string": "...", "new_string": "..." } }
#
# Exit 0 → allow; exit 2 → deny with stderr explanation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$REPO_ROOT/.claude/policy.yaml"

PAYLOAD=$(cat)
TOOL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty')
FILE=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE" ]; then
  exit 0
fi

case "$TOOL" in
  Write)  CONTENT=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.content // empty') ;;
  Edit)   CONTENT=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.new_string // empty') ;;
  *)      exit 0 ;;
esac

if [ ! -f "$POLICY" ]; then
  echo "BLOCKED: .claude/policy.yaml missing — cannot evaluate policy" >&2
  exit 2
fi

# Forbidden paths — glob style.
if command -v yq >/dev/null 2>&1; then
  mapfile -t FORBID_PATHS < <(yq -r '.forbidden_paths[]' "$POLICY" 2>/dev/null)
  mapfile -t FORBID_PATTERNS < <(yq -r '.forbidden_patterns[]' "$POLICY" 2>/dev/null)
else
  mapfile -t FORBID_PATHS < <(awk '
    /^forbidden_paths:/ {in_list=1; next}
    in_list && /^[a-zA-Z]/ {in_list=0}
    in_list && /^[[:space:]]+-[[:space:]]/ {
      sub(/^[[:space:]]+-[[:space:]]+/, "");
      gsub(/^["'\'']/, ""); gsub(/["'\'']$/, "");
      print
    }
  ' "$POLICY")
  mapfile -t FORBID_PATTERNS < <(awk '
    /^forbidden_patterns:/ {in_list=1; next}
    in_list && /^[a-zA-Z]/ {in_list=0}
    in_list && /^[[:space:]]+-[[:space:]]/ {
      sub(/^[[:space:]]+-[[:space:]]+/, "");
      gsub(/^["'\'']/, ""); gsub(/["'\'']$/, "");
      print
    }
  ' "$POLICY")
fi

# Normalize FILE to repo-relative path for matching.
REL_FILE="${FILE#$REPO_ROOT/}"

glob_to_regex() {
  local glob="$1"
  local re=""
  local i ch
  for (( i=0; i<${#glob}; i++ )); do
    ch="${glob:$i:1}"
    case "$ch" in
      '*')
        # Handle ** as match-anything-including-slash
        if [ "${glob:$((i+1)):1}" = "*" ]; then
          re+=".*"; i=$((i+1))
        else
          re+="[^/]*"
        fi
        ;;
      '?') re+="." ;;
      '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'\\'|'|') re+="\\$ch" ;;
      *)   re+="$ch" ;;
    esac
  done
  printf '^%s$' "$re"
}

for glob in "${FORBID_PATHS[@]}"; do
  re=$(glob_to_regex "$glob")
  if [[ "$REL_FILE" =~ $re ]] || [[ "$FILE" =~ $re ]]; then
    echo "BLOCKED by policy-guard: write to '$FILE' matches forbidden_paths pattern '$glob'" >&2
    exit 2
  fi
done

# Forbidden content patterns (regex; matched against new content).
for pat in "${FORBID_PATTERNS[@]}"; do
  [ -z "$pat" ] && continue
  if printf '%s' "$CONTENT" | grep -qE "$pat"; then
    echo "BLOCKED by policy-guard: content of '$FILE' matches forbidden_patterns regex '$pat'" >&2
    exit 2
  fi
done

exit 0

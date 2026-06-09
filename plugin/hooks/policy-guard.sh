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

# Plugin scripts run with $CLAUDE_PLUGIN_ROOT (installed plugin) and
# $CLAUDE_PROJECT_DIR (user's project). Project-side override takes
# precedence over the plugin-shipped default policy.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PLUGIN_ROOT}"
. "$PLUGIN_ROOT/lib/policy.sh"

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

if ! POLICY=$(policy_file "$PROJECT_ROOT" "$PLUGIN_ROOT"); then
  echo "BLOCKED: policy.yaml missing — checked $PROJECT_ROOT/.claude/policy.yaml and $PLUGIN_ROOT/policy.yaml" >&2
  exit 2
fi

# Forbidden paths — glob style. Parsed via lib/policy.sh (yq with awk
# fallback). while-read instead of `mapfile` for bash 3.2 (macOS default).
FORBID_PATHS=()
FORBID_PATTERNS=()
while IFS= read -r line; do
  [ -n "$line" ] && FORBID_PATHS+=("$line")
done < <(policy_list forbidden_paths "$POLICY")
while IFS= read -r line; do
  [ -n "$line" ] && FORBID_PATTERNS+=("$line")
done < <(policy_list forbidden_patterns "$POLICY")

# Normalize FILE to project-relative path for matching.
REL_FILE="${FILE#$PROJECT_ROOT/}"

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

# Size guards: bash 3.2 (macOS default) errors on iterating an empty array under `set -u`.
if [ "${#FORBID_PATHS[@]}" -gt 0 ]; then
  for glob in "${FORBID_PATHS[@]}"; do
    re=$(glob_to_regex "$glob")
    if [[ "$REL_FILE" =~ $re ]] || [[ "$FILE" =~ $re ]]; then
      echo "BLOCKED by policy-guard: write to '$FILE' matches forbidden_paths pattern '$glob'" >&2
      exit 2
    fi
  done
fi

# Forbidden content patterns (regex; matched against new content).
if [ "${#FORBID_PATTERNS[@]}" -gt 0 ]; then
  for pat in "${FORBID_PATTERNS[@]}"; do
    [ -z "$pat" ] && continue
    if printf '%s' "$CONTENT" | grep -qE "$pat"; then
      echo "BLOCKED by policy-guard: content of '$FILE' matches forbidden_patterns regex '$pat'" >&2
      exit 2
    fi
  done
fi

exit 0

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

# Plugin scripts run with $CLAUDE_PLUGIN_ROOT (installed plugin) and
# $CLAUDE_PROJECT_DIR (user's project). Project-side override takes
# precedence over the plugin-shipped default policy.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PLUGIN_ROOT}"
POLICY="$PROJECT_ROOT/.claude/policy.yaml"
[ -f "$POLICY" ] || POLICY="$PLUGIN_ROOT/policy.yaml"

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

# Compound commands are split into segments; each segment is matched against
# the allowlist independently. Top-level operators recognized (outside quotes):
# && || ; | — each starts a new segment.
# Subshell grouping parentheses ( ) are unwrapped: they are not part of any
# command, so `(a && b)` yields segments `a` and `b`.
# Command substitution ($(...) or backticks) is still blocked since a nested
# command can't be cleanly audited against a flat allowlist.
# The splitter is quote-aware (single/double quotes, double-quote backslash
# escapes), so `echo "a && b"` is treated as a single segment.
split_command() {
  local cmd="$1"
  local len=${#cmd}
  local i=0
  local ch next
  local in_single=0 in_double=0
  local seg=""
  local segments=()
  while [ $i -lt $len ]; do
    ch="${cmd:$i:1}"
    next="${cmd:$((i+1)):1}"
    if [ $in_single -eq 1 ]; then
      seg+="$ch"
      if [ "$ch" = "'" ]; then in_single=0; fi
      i=$((i+1)); continue
    fi
    if [ $in_double -eq 1 ]; then
      if [ "$ch" = "\\" ] && [ -n "$next" ]; then
        seg+="$ch$next"; i=$((i+2)); continue
      fi
      seg+="$ch"
      if [ "$ch" = '"' ]; then in_double=0; fi
      i=$((i+1)); continue
    fi
    case "$ch" in
      "'") in_single=1; seg+="$ch"; i=$((i+1)) ;;
      '"') in_double=1; seg+="$ch"; i=$((i+1)) ;;
      '\\')
        if [ -n "$next" ]; then seg+="$ch$next"; i=$((i+2))
        else seg+="$ch"; i=$((i+1))
        fi
        ;;
      '`') return 2 ;;
      '$')
        if [ "$next" = "(" ]; then return 2; fi
        seg+="$ch"; i=$((i+1))
        ;;
      '('|')')
        # Subshell grouping — the parenthesis is not part of any command, so
        # drop it and let the operators inside split normally.
        i=$((i+1))
        ;;
      '&')
        if [ "$next" = "&" ]; then
          segments+=("$seg"); seg=""; i=$((i+2))
        else
          seg+="$ch"; i=$((i+1))
        fi
        ;;
      '|')
        if [ "$next" = "|" ]; then
          segments+=("$seg"); seg=""; i=$((i+2))
        else
          segments+=("$seg"); seg=""; i=$((i+1))
        fi
        ;;
      ';')
        segments+=("$seg"); seg=""; i=$((i+1))
        ;;
      *)
        seg+="$ch"; i=$((i+1))
        ;;
    esac
  done
  if [ $in_single -eq 1 ] || [ $in_double -eq 1 ]; then
    return 3
  fi
  segments+=("$seg")
  local s
  for s in "${segments[@]}"; do
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    if [ -n "$s" ]; then printf '%s\n' "$s"; fi
  done
  return 0
}

SPLIT_RC=0
SEGMENTS_OUTPUT=$(split_command "$CMD") || SPLIT_RC=$?
if [ "$SPLIT_RC" -eq 2 ]; then
  echo "BLOCKED by pre-tool-bash-allowlist: command substitution (\$(...) or backticks) is not allowed." >&2
  echo "Write intermediate results to a file or pass them as explicit arguments instead." >&2
  echo "command: $CMD" >&2
  exit 2
fi
if [ "$SPLIT_RC" -eq 3 ]; then
  echo "BLOCKED by pre-tool-bash-allowlist: unbalanced quotes in command." >&2
  echo "command: $CMD" >&2
  exit 2
fi
if [ "$SPLIT_RC" -ne 0 ]; then
  echo "BLOCKED by pre-tool-bash-allowlist: split_command returned unexpected status $SPLIT_RC" >&2
  echo "command: $CMD" >&2
  exit 2
fi

SEGMENTS=()
while IFS= read -r line; do
  if [ -n "$line" ]; then SEGMENTS+=("$line"); fi
done <<< "$SEGMENTS_OUTPUT"

if [ "${#SEGMENTS[@]}" -eq 0 ]; then
  echo "BLOCKED by pre-tool-bash-allowlist: no valid command segments found." >&2
  echo "command: $CMD" >&2
  exit 2
fi

# Allowlist from policy.yaml. Patterns are glob-style; we convert to regex.
if [ ! -f "$POLICY" ]; then
  echo "BLOCKED: policy.yaml missing — checked $PROJECT_ROOT/.claude/policy.yaml and $PLUGIN_ROOT/policy.yaml" >&2
  exit 2
fi

# Read allowlist via yq if available, else minimal awk fallback.
# Use a while-read loop instead of `mapfile` for bash 3.2 (macOS default) compatibility.
PATTERNS=()
if command -v yq >/dev/null 2>&1; then
  while IFS= read -r line; do
    PATTERNS+=("$line")
  done < <(yq -r '.bash_allowlist[]' "$POLICY" 2>/dev/null)
else
  # Fallback: parse "  - \"...\"" lines under bash_allowlist:
  while IFS= read -r line; do
    PATTERNS+=("$line")
  done < <(awk '
    /^bash_allowlist:/ {in_list=1; next}
    in_list && /^[a-zA-Z]/ {in_list=0}
    in_list && /^[[:space:]]+-[[:space:]]/ {
      sub(/^[[:space:]]+-[[:space:]]+/, "");
      # Double-quoted value: take content between first pair of double quotes.
      if (match($0, /^"[^"]*"/)) { val = substr($0, 2, RLENGTH-2); print val; next }
      # Single-quoted value: same with single quotes.
      if (match($0, /^'\''[^'\'']*'\''/)) { val = substr($0, 2, RLENGTH-2); print val; next }
      # Unquoted: strip trailing YAML inline comment and surrounding whitespace.
      val = $0;
      sub(/[[:space:]]+#.*$/, "", val);
      sub(/[[:space:]]+$/, "", val);
      print val;
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
  # A pattern ending in " *" means "this command, optionally followed by
  # arguments". Make the separating space optional so a bare command with no
  # arguments (e.g. `echo`, `ls`, `git`) matches too — not just `echo foo`.
  local trailing_args=0
  case "$glob" in
    *" *")
      trailing_args=1
      glob="${glob:0:${#glob}-2}"
      ;;
  esac
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
  if [ "$trailing_args" -eq 1 ]; then
    re+="( .*)?"
  fi
  printf '^%s$' "$re"
}

# Strip leading "NAME=value" environment-assignment tokens so that
# `FOO=bar cmd args` is matched against the allowlist as `cmd args`. The
# assignment names no command, so ignoring the prefix is safe — the real
# command is still matched, and the hard denylist still sees the raw command.
# Quote- and backslash-aware so quoted spaces in a value do not end a token
# early. A segment that is only assignments yields the empty string.
strip_assignments() {
  local s="$1"
  while :; do
    case "$s" in *=*) ;; *) break ;; esac
    local name="${s%%=*}"
    case "$name" in
      ''|[0-9]*|*[!A-Za-z0-9_]*) break ;;
    esac
    local rest="${s#*=}"
    local len=${#rest}
    local j=0 ch in_s=0 in_d=0
    while [ $j -lt $len ]; do
      ch="${rest:$j:1}"
      if [ $in_s -eq 1 ]; then
        [ "$ch" = "'" ] && in_s=0
        j=$((j+1)); continue
      fi
      if [ $in_d -eq 1 ]; then
        if [ "$ch" = "\\" ]; then j=$((j+2)); continue; fi
        [ "$ch" = '"' ] && in_d=0
        j=$((j+1)); continue
      fi
      case "$ch" in
        "'") in_s=1 ;;
        '"') in_d=1 ;;
        '\\') j=$((j+2)); continue ;;
        [[:space:]]) break ;;
      esac
      j=$((j+1))
    done
    local after="${rest:$j}"
    after="${after#"${after%%[![:space:]]*}"}"
    s="$after"
    [ -z "$s" ] && break
  done
  printf '%s' "$s"
}

# Every segment must match the allowlist. For a non-compound command there
# is exactly one segment — same behavior as before for that case.
for seg in "${SEGMENTS[@]}"; do
  # Match against the command minus any leading FOO=bar env-assignment prefix.
  match_target=$(strip_assignments "$seg")
  # A segment that is purely env-var assignments runs no command — allow it.
  if [ -z "$match_target" ]; then
    continue
  fi
  matched=0
  for glob in "${PATTERNS[@]}"; do
    re=$(glob_to_regex "$glob")
    if [[ "$match_target" =~ $re ]]; then
      matched=1
      break
    fi
  done
  if [ $matched -eq 0 ]; then
    echo "BLOCKED by pre-tool-bash-allowlist: segment '$seg' does not match any pattern in policy.yaml bash_allowlist" >&2
    if [ "${#SEGMENTS[@]}" -gt 1 ]; then
      echo "(from compound command: $CMD)" >&2
    fi
    echo "Allowlist: ${PATTERNS[*]}" >&2
    exit 2
  fi
done

exit 0

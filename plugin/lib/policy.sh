# Shared policy.yaml accessors for the smurf hooks and scripts.
# Source this file; do not execute it. Bash 3.2 compatible (macOS default).
#
#   policy_file PROJECT_ROOT PLUGIN_ROOT
#       Echo the resolved policy path (project override wins, plugin
#       default fallback). Returns 1 and echoes nothing if neither exists.
#
#   policy_scalar KEY FILE
#       Echo a scalar value with quotes and trailing comments stripped;
#       echo nothing if the key is absent. KEY is a top-level key
#       ("verify_command") or one nesting level ("wiki.log_path").
#
#   policy_list KEY FILE
#       Echo the items of a top-level list key, one per line.
#
# Each accessor prefers `yq` (jq-style) and falls back to a minimal awk
# parser, so PyYAML/yq are optional everywhere. Keep parsing changes
# HERE — this is the single bash-side policy parser (the Python-side
# equivalent is scripts/_policy.py).

policy_file() {
  local p="$1/.claude/policy.yaml"
  [ -f "$p" ] || p="$2/policy.yaml"
  [ -f "$p" ] || return 1
  printf '%s\n' "$p"
}

policy_scalar() {
  local key="$1" file="$2" val=""
  if command -v yq >/dev/null 2>&1; then
    val=$(yq -r ".${key} // empty" "$file" 2>/dev/null) || val=""
  fi
  if [ -z "$val" ]; then
    val=$(awk -v key="$key" '
      function clean(line) {
        sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
        if (line ~ /^"/)        { sub(/^"/, "", line); sub(/".*$/, "", line) }
        else if (line ~ /^'\''/) { sub(/^'\''/, "", line); sub(/'\''.*$/, "", line) }
        else { sub(/[[:space:]]*#.*$/, "", line); sub(/[[:space:]]+$/, "", line) }
        return line
      }
      BEGIN { n = split(key, part, ".") }
      n == 1 && $1 == part[1] ":" { print clean($0); exit }
      n == 2 {
        if (index($0, part[1] ":") == 1) { in_block = 1; next }
        if (in_block && $0 ~ /^[^[:space:]]/) { in_block = 0 }
        if (in_block && $1 == part[2] ":") { print clean($0); exit }
      }
    ' "$file")
  fi
  printf '%s' "$val"
}

policy_list() {
  local key="$1" file="$2" out=""
  if command -v yq >/dev/null 2>&1; then
    out=$(yq -r ".${key}[]" "$file" 2>/dev/null) || out=""
  fi
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  awk -v key="$key" '
    index($0, key ":") == 1 { in_list = 1; next }
    in_list && /^[^[:space:]]/ { in_list = 0 }
    in_list && /^[[:space:]]+-[[:space:]]/ {
      sub(/^[[:space:]]+-[[:space:]]+/, "")
      if (match($0, /^"[^"]*"/))           { print substr($0, 2, RLENGTH - 2); next }
      if (match($0, /^'\''[^'\'']*'\''/))  { print substr($0, 2, RLENGTH - 2); next }
      sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, "")
      print
    }
  ' "$file"
}

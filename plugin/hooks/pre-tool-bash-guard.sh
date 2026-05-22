#!/usr/bin/env bash
# PreToolUse(Bash) hook — block well-known dangerous commands.
#
# Denylist model: a Bash command is allowed unless it matches a dangerous
# pattern below. The whole command string is scanned as-is, so compound
# commands (pipes, &&, ||, ;, subshells, brace groups) and command
# substitution all pass through — there is no command splitter to misfire.
#
# This is deliberately less strict than an allowlist. The threat model is
# "an autonomous run destroys its environment by mistake", not "a motivated
# adversary evading regexes" — a denylist cannot stop the latter.
#
# Stdin JSON shape:
#   { "session_id": "...", "tool_name": "Bash",
#     "tool_input": { "command": "<cmd>", "description": "...", "timeout": 120000 } }
#
# Exit 0 → allow.  Exit 2 → deny; stderr is shown to the user/agent.

set -euo pipefail

CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Nothing to check (no command, or unparseable payload) → allow.
if [ -z "$CMD" ]; then
  exit 0
fi

# Dangerous patterns — POSIX extended regex, matched against the full
# command string. Keep these narrow: a false positive blocks real work.
DANGER_PATTERNS=(
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+(/|~|\$HOME)([[:space:]*]|$)'          # recursive rm of / ~ $HOME
  ':\(\)[[:space:]]*\{[[:space:]]*:\|:&[[:space:]]*\}[[:space:]]*;[[:space:]]*:'        # fork bomb
  'mkfs\.'                                                                              # format a filesystem
  'dd[[:space:]]+if=/dev/(zero|random|urandom)[[:space:]]+of=/dev/'                     # overwrite a device
  '>[[:space:]]*/dev/(sd|nvme|disk|hd)'                                                 # clobber a raw disk
  'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'                                     # world-writable root
  '(curl|wget)[[:space:]][^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)'  # blind pipe to shell
  '/dev/tcp/'                                                                           # bash reverse shell
)

for p in "${DANGER_PATTERNS[@]}"; do
  if [[ "$CMD" =~ $p ]]; then
    echo "BLOCKED by pre-tool-bash-guard: command matches dangerous pattern /$p/" >&2
    echo "command: $CMD" >&2
    exit 2
  fi
done

exit 0

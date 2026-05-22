# 09 — Hooks and policy

The deterministic guardrail layer. Hooks run **outside** the model's
context, so they cannot be bargained with or hallucinated past. They are
the only enforcement mechanism in this repo that is guaranteed to fire.

## Files

- `.claude/hooks/session-start-context.sh` — SessionStart
- `.claude/hooks/pre-tool-bash-guard.sh` — PreToolUse(Bash)
- `.claude/hooks/policy-guard.sh` — PreToolUse(Write|Edit)
- `.claude/hooks/pre-commit-verify.sh` — PreToolUse(Bash matching `git commit`)
- `.claude/hooks/on-stop-summary.sh` — Stop
- `.claude/hooks/on-subagent-complete.sh` — SubagentStop
- `.claude/policy.yaml` — config consumed by the above
- `.claude/settings.json` — registers each script under its event/matcher
- `scripts/test-hooks.sh` — smoke test (base64-encoded payloads so the
  test script's own bash invocation doesn't trip the guard)

## Stdin JSON shape per event

Claude Code passes a JSON document on stdin to each hook. Scripts must
parse with `jq` — never assume positional args.

| Event | Required fields | Optional |
|---|---|---|
| `SessionStart` | `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `source` (`startup`/`resume`/`clear`) | — |
| `PreToolUse(Bash)` | `tool_name="Bash"`, `tool_input.command` | `tool_input.description`, `tool_input.timeout` |
| `PreToolUse(Write)` | `tool_name="Write"`, `tool_input.file_path`, `tool_input.content` | — |
| `PreToolUse(Edit)` | `tool_name="Edit"`, `tool_input.file_path`, `tool_input.old_string`, `tool_input.new_string` | `tool_input.replace_all` |
| `Stop` | `session_id`, `transcript_path`, `hook_event_name="Stop"`, `stop_hook_active` | — |
| `SubagentStop` | `session_id`, `transcript_path`, `hook_event_name="SubagentStop"`, `stop_hook_active` | — |

## Exit code semantics

- `0` → allow (and any stdout for `SessionStart` is appended to context).
- `2` → block; stderr is shown to the user/agent. The agent receives the
  block as a tool error and may try a different approach.
- Other non-zero → treated as error; current Claude Code blocks the call.

Hooks may also emit JSON on stdout matching:
```json
{"hookSpecificOutput": {"permissionDecision": "allow|deny|ask",
                         "permissionDecisionReason": "..."}}
```
We don't use this richer form yet — exit-code semantics suffice.

## `.claude/policy.yaml` schema

```yaml
forbidden_paths: [<glob-pattern>, ...]  # path match; ** matches across slashes
forbidden_patterns: [<regex>, ...]      # extended regex; matched against new content
verify_command: "./verify.sh"           # informational; hook always invokes ./verify.sh
max_qa_iterations: <int>                # consumed by orchestrator
max_parallel_subagents: <int>           # consumed by orchestrator
max_turns_orchestrator: <int>
max_turns_subagent: <int>
budget_usd_subagent: <number>           # consumed by autonomous-run.sh
budget_usd_team: <number>               # consumed by autonomous-run.sh
```

Bash command safety is **not** configured here — it lives in
`pre-tool-bash-guard.sh` as a hardcoded denylist (see below).

Glob → regex conversion (used by `policy-guard.sh` for `forbidden_paths`):

| Glob | Regex |
|---|---|
| `*` | `[^/]*` (single-segment match) |
| `**` | `.*` (any depth, including `/`) |
| `?` | `.` |
| literal regex metas (`.+()[]{}^$\|\\`) | escaped |

Patterns are anchored (`^...$`).

## Bash command guard

`pre-tool-bash-guard.sh` enforces a **denylist**: a Bash command is
allowed unless it matches a dangerous pattern. The whole command string
is scanned as-is, so compound commands (pipes, `&&`, `||`, `;`,
subshells, brace groups) and command substitution all pass through —
there is no command splitter that could misfire on valid shell.

Blocked patterns (`DANGER_PATTERNS` in the script):
- recursive `rm` of `/`, `~`, or `$HOME`
- fork bombs (`:(){:|:&};:`)
- `mkfs.*`
- `dd if=/dev/(zero|random|urandom) of=/dev/...`
- output redirect onto a raw disk device (`/dev/sda` and similar)
- world-writable recursive chmod on root (`chmod -R 777 /`)
- blind pipe-to-shell (`curl ... | sh`, `wget ... | sh`)
- bash reverse shells (`/dev/tcp/...`)

This is deliberately permissive. The threat model is an autonomous run
destroying its environment by mistake — not a motivated adversary, whom
a regex denylist cannot stop. There is no bash *allowlist*.

## Settings registration

```jsonc
"hooks": {
  "SessionStart":  [{ "hooks": [{ "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start-context.sh" }] }],
  "PreToolUse": [
    { "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-bash-guard.sh" }] },
    { "matcher": "Write|Edit",
      "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/policy-guard.sh" }] },
    { "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-commit-verify.sh" }] }
  ],
  "Stop":         [{ "hooks": [{ "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/on-stop-summary.sh" }] }],
  "SubagentStop": [{ "hooks": [{ "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/on-subagent-complete.sh" }] }]
}
```

`$CLAUDE_PROJECT_DIR` is expanded by Claude Code at hook-load time. The
two PreToolUse(Bash) entries chain: bash-guard runs first; if it
allows, pre-commit-verify runs and (only on `git commit` invocations)
runs `./verify.sh`. Either can block.

## Test plan

`scripts/test-hooks.sh` exercises every hook with base64-encoded
payloads (so the test script's own `bash` call doesn't trip the live
guard when hooks are registered). Run it whenever `policy.yaml` or any
hook script is modified.

```
$ bash scripts/test-hooks.sh
…
passed=24  failed=0
```

## Known limitations / future work

- Glob `**` is partly implemented — leaning toward `.*` for any-depth.
  Edge cases (e.g. `a/**/b`) not exhaustively tested.
- `policy-guard.sh` for `Edit` checks only `new_string` content, not the
  resulting file. A multi-step Edit that gradually constructs forbidden
  content could slip through. Mitigation: keep `forbidden_patterns` tight
  and add a periodic sweep in CI.
- `on-subagent-complete.sh` extracts the subagent name from the
  transcript tail with a best-effort `jq` query; format may shift across
  Claude Code versions.
- The hook system **applies to humans too** when settings.json is
  registered. If the bash guard blocks a command a human dev needs,
  loosen the matching `DANGER_PATTERNS` entry in
  `pre-tool-bash-guard.sh`, or add a personal override in
  `.claude/settings.local.json` (gitignored).

# Plugin review — inconsistencies and improvements

Review date: 2026-06-09. Scope: everything under `plugin/`, plus the
root-level install/marketplace files. Items ordered by severity.

Status update (same day): all section-A items fixed and verified —
hook suite 25/25, wiki suite 19/19, `doctor.sh` exits 0 (incl. a
simulated no-PyYAML environment), and a stubbed-`claude` end-to-end run
of `autonomous-run.sh` confirms the budget flag and result parsing.
Sections B and C re-reviewed after the fixes; per-item notes added
where the A work changed their scope.

## A. Bugs (broken behaviour today) — ALL FIXED

- [x] **A1. `doctor.sh` fails on a fresh clone.** `plugin/scripts/doctor.sh:77`
  still checks `commands/kickoff.md`, removed in `a0b92ff`
  ("remove /kickoff, make /kickoff-team the default"). Result:
  `failed=1`, exit 1 → README's "exits non-zero if the plugin install is
  broken" tells every new user their install is broken. The same loop is
  also missing `bootstrap.md`, which does exist. Fix the command list to
  `init kickoff-team kickoff-workflow nightly-run close-loop bootstrap`.

- [x] **A2. Stale references to the removed `/kickoff` command.**
  - `plugin/commands/init.md:26` — tells the user to run `/smurf:kickoff "<goal>"`.
  - `plugin/commands/kickoff-workflow.md:2` — "additive 3rd mode alongside
    /kickoff and /kickoff-team" (there are only two commands now).

- [x] **A3. Stop hook clobbers the orchestrator's summary.**
  `on-stop-summary.sh` writes `$RUN_DIR/summary.md` unconditionally
  (`cat > …`). In autonomous runs `CLAUDE_RUN_TS` pins both writers to the
  same directory, so the hook's generic template overwrites the richer
  summary the orchestrator is contractually required to write
  (orchestrator.md OUTPUT CONTRACT), which `/smurf:nightly-run` then reads.
  Write to a different file (e.g. `stop-summary.md`) or skip when
  `summary.md` already exists.

- [x] **A4. `autonomous-run.sh` budget is resolved but never enforced.**
  `BUDGET` is computed from policy (lines 59–67) and written to `meta.txt`,
  but the `claude -p` invocation passes no `--max-budget-usd` — the header
  comment ("--max-budget-usd is best-effort") implies it is passed.
  Either pass the flag or delete the resolution and fix the comments.
  Related: the `MODE=team` / `else` branches at lines 180–184 build the
  identical prompt — dead conditional left over from the `/kickoff` removal.

- [x] **A5. Headless allowlist doesn't cover what the agents are told to run.**
  `autonomous-run.sh` sets `--allowedTools "…,Bash(./verify.sh),Bash(git *),
  Bash(gh *),Bash(curl …),Bash(python3 *),Bash(jq *),Bash(yq *),…"`, but:
  - all seven specialist agents instruct pre-flight via
    `Bash(cat "…smurf.md")` and a compound `cat … 2>/dev/null || cat …`
    (developer.md:19-21, qa-engineer.md:14-16, product-owner.md:19-21,
    architect.md:19-21, devops.md:14-16, marketing.md:13-15,
    sales-feedback.md:13-15) — `cat` is not allowlisted → silently denied
    in headless runs;
  - the kickoff-workflow gate uses `printenv …` and `claude --version` —
    also not allowlisted.
  Fix by switching agent pre-flights to the `Read` tool (orchestrator.md
  already recommends exactly this) and/or extending the allowlist.

- [x] **A6. Contradictory story on compound Bash commands (3-way).**
  - `orchestrator.md:13-16` and `kickoff-workflow.md:15-16` claim "this
    plugin's PreToolUse hook rejects compound commands (no `&&`, `||`, …)".
  - `pre-tool-bash-guard.sh:5-8` and `policy.yaml:4-9` explicitly state the
    opposite: denylist only, compound commands pass through.
  - `bootstrap.md` bans compounds ("three separate Bash calls — no compound
    commands", lines 155, 313, 347) yet line 57 instructs
    `git add <paths> && git commit -m '…'`.
  Pick one model and make all five files agree.

- [x] **A7. Wave numbering drift.** `marketing.md:3` says "Invoke as wave 5",
  but in `orchestrator.md` wave 5 is Deploy (devops) and Promote
  (marketing + sales-feedback) is wave 6.

- [x] **A8. Story `## Status` section missing from the PO contract.**
  `gherkin-stories/SKILL.md`, `build-wiki-index.py` (parse_story) and
  `wiki_lint.py` (orphan check) all depend on a trailing `## Status` block,
  but `product-owner.md` CONTRACT's trailing-block template omits it
  entirely — every PO-authored story indexes as status `unknown` and the
  orphan-story lint can never fire. Also `product-owner.md:116` says to mark
  superseded stories "at the top", while the skill puts Status at the bottom.

- [x] **A9. ADR ports section name drift defeats the port-conflict lint.**
  `architect.md` template uses `## Ports / Adapters (or modules)`;
  `wiki_lint.py:96` only matches `Ports / Adapters`, `Ports`, or
  `Ports / Adapters / Modules` (the adr-template skill's spelling). ADRs
  written from the architect.md template are invisible to the
  port-conflict check. Align architect.md with the skill.

- [x] **A10. GNU-only commands break the hooks on macOS.** The repo works
  hard at macOS compat elsewhere (bash-3.2 workarounds in policy-guard.sh,
  `gtimeout` fallback in autonomous-run.sh), but:
  - `session-start-context.sh:33` uses `find -printf` (GNU-only);
  - `on-subagent-complete.sh:27` uses `tac` (GNU-only).
  Use portable equivalents (`ls -t` / `stat -f`, `tail -r` fallback or awk).

- [x] **A11. `doctor.sh` hard-requires PyYAML; the scripts deliberately don't.**
  The "policy.yaml is valid YAML" check (doctor.sh:54) imports `yaml`,
  while build-wiki-index.py / append-wiki-log.py / wiki_lint.py all carry an
  ImportError fallback so PyYAML is optional. On a machine without PyYAML,
  doctor reports the plugin "broken" even though everything works.

- [x] **A12. Slack notification can never fire with real content.**
  `autonomous-run.sh:214` parses `.messages[-1].content` out of
  `run.ndjson`, but `--output-format stream-json` emits NDJSON events
  (`{"type":"assistant",…}`, terminal `{"type":"result","result":…}`) —
  there is no `.messages` array, so `LAST` is always empty and the webhook
  is silently skipped. Read the `result` event instead.

- [x] **A13. `plugin.json` version `1.0.0.19` is not semver** (4 segments).
  Marketplace tooling expects `MAJOR.MINOR.PATCH`.

- [x] **A14. OpenRouter cost field is wrong.** `openrouter-curl/SKILL.md:56`
  and `marketing.md:49-50` read `usage.total_cost`; OpenRouter's chat
  completions return `usage.cost`, and only when the request includes
  `"usage": {"include": true}` — as written the cost is always `0`.

## B. Doc / spec inconsistencies (misleading but not breaking) — ALL FIXED

Fixed 2026-06-09 (second pass). B1+B7 landed together in
`pre-commit-verify.sh` (header corrected, compound `git commit`
detection hardened, `verify_command` wired from policy — 4 new hook
tests, suite 29/29). B6 wired `--max-turns` from
`max_turns_orchestrator` (policy value raised 60→200 to preserve the
previously enforced behaviour) and documented close-loop's
fixed-scope constants. B8 removed `permissionMode: ask` — per the
docs the field is ignored for plugin subagents and `ask` was never a
valid value. Phase 8 in the README turned out to be the wiki layer
(per docs/specs/00-overview.md), so B4 added it rather than
renumbering.

- [x] **B1. `pre-commit-verify.sh` header lies about its registration.**
  Lines 10-11 claim a `^git commit` matcher "registered in settings.json";
  it's actually registered in `hooks/hooks.json` with matcher `Bash` and
  self-filters. Also note: a compound `cd x && git commit` bypasses the
  `^git commit` regex, so verify can be skipped — document or harden.

- [x] **B2. `smurf.md:10-12` points to `docs/research.md`** — the file does
  not exist anywhere in the repo (policy.yaml and kickoff-team.md also cite
  "research §1.7"). Either add the doc or drop the references.

- [x] **B3. README "Force Agent-Teams" section is stale.** Since #12,
  `/smurf:kickoff-team` *attempts* Agent Teams and degrades — nothing
  forces it. Same stale wording in doctor.sh:121
  ("required for /smurf:kickoff-team" — it's optional now).

- [x] **B4. README Status section drift.** "13/13 hook smoke tests pass" —
  the suite now reports 25 passing (was 24 at review time; the A3 fix
  added a no-clobber test); phases jump 7 → 9 with no Phase 8.

- [x] **B5. `developer.md:13-15` names `/kickoff-team` for *both* modes**
  ("In Agent Teams mode (`/kickoff-team`) … in subagent mode
  (`/kickoff-team`)") — leftover from when subagent mode was `/kickoff`.

- [x] **B6. Hard-coded caps contradict the house rule.** smurf.md says
  "Edit policy.yaml, never hard-code numbers in agent prompts or scripts",
  yet `autonomous-run.sh` hard-codes `--max-turns 200` (policy says
  `max_turns_orchestrator: 60`) and `close-loop.py:138-139` hard-codes
  `--max-turns 20` / `--max-budget-usd 1.50`. Note: the
  autonomous-run budget is no longer hard-coded — A4 wired
  `--max-budget-usd` to policy; the turn caps and close-loop values
  remain.

- [x] **B7. `verify_command` policy key is read by no hook or script.**
  `pre-commit-verify.sh` hard-codes `./verify.sh`. Either wire the key up
  or document it as agent-prompt-only.

- [x] **B8. `devops.md` frontmatter `permissionMode: ask`** — not a
  documented value (documented: `default`, `acceptEdits`, `plan`,
  `bypassPermissions`). Verify it does anything; the agent body also
  asserts "every Bash invocation prompts", which depends on it.

- [x] **B9. `/smurf:close-loop` uses `!`-inline execution** for a
  `claude -p` call that can run for minutes, while `nightly-run.md`
  explicitly warns that long-running scripts must use background Bash,
  not `!` expansion. Inconsistent guidance for the same problem.

## C. Improvements

- [ ] **C1. Make the session-start hook quiet outside smurf projects.**
  The plugin's SessionStart hook fires in *every* project once installed,
  injecting "unknown — docs/rigor-level.md missing" noise. Exit silently
  (no output) when no smurf scaffolding is detected.

- [x] **C2. Restrict `close-loop.py` MCP surface to read-only.**
  `--allowedTools …,mcp__github,…` grants the whole GitHub MCP server,
  including write tools, while the prompt merely asks the model not to use
  them. Allowlist the specific read tools instead.
  (Done as part of the B6 close-loop.py edit: github restricted to
  `list_issues`/`get_issue`/`search_issues`; sentry/linear stay
  server-level because their tool names depend on user-supplied
  configs and both are read-oriented.)

- [ ] **C3. Deduplicate the wave-3 gate prose.** The Dynamic-Workflows gate
  and the Agent-Teams capability probe are spelled out nearly verbatim in
  both `orchestrator.md` and the two kickoff commands — they have already
  drifted (A6). Keep the canonical text in one place and reference it.

- [ ] **C4. Merge the two `matcher: "Bash"` PreToolUse entries in
  `hooks/hooks.json`** into one entry with two hooks — same behaviour,
  less duplication.

- [ ] **C5. CONFIRMED BUG (was: verify): the orchestrator cannot spawn
  subagents when invoked via `@orchestrator`.** Docs verified
  (code.claude.com/docs/en/sub-agents): "Subagents cannot spawn other
  subagents" — the Agent/Task tool is unavailable inside a subagent.
  Fix: kickoff commands must instruct the MAIN session to adopt the
  orchestrator role (bootstrap.md already uses this pattern).** The
  kickoff commands invoke `@orchestrator: $ARGUMENTS`, i.e. the
  orchestrator runs *as a subagent*, and subagents normally cannot use
  `Task` to spawn further subagents. If that restriction applies on the
  targeted CLI versions, the entire wave model silently degrades to
  inline execution; the commands may need to instruct the *main* session
  to assume the orchestrator role instead.

- [ ] **C6. Fragile permission rule in `init-project.sh:68`.**
  `RULE="Bash(bash \"$(dirname "$CLAUDE_PLUGIN_ROOT")/:*)"` only matches
  when the agent quotes the path exactly the same way (`bash "<path>/…"`).
  Add the unquoted variant too, or document the dependency.

- [ ] **C7. Add metadata: `license` in `plugin.json`; description/owner
  metadata in `marketplace.json`.** (The non-semver version part of the
  original finding was fixed in A13.)

- [ ] **C8. Decide where QA reports live.** Agents write `qa/<id>.md` at the
  project root and bootstrap commits them; the directory is never
  scaffolded, gitignored, or documented in README's file inventory.
  `docs/qa/` (committed) or `.claude/runs/<ts>/qa/` (ephemeral) would be
  more deliberate.

- [ ] **C9. Test coverage for the shell entry points.** `tests/` covers
  hooks and the wiki scripts well, but `init-project.sh` (JSON merge
  paths), `autonomous-run.sh` (budget/watchdog/fallback log row), and
  `doctor.sh` itself (A1 would have been caught by a self-test) are
  untested. Also discovered while fixing section A:
  - `tests/verify.sh` only runs `test-hooks.sh` — `tests/test-wiki.sh`
    (19 tests) is never invoked by the verify entrypoint; wire it in.
  - The A4/A12 verification used an ad-hoc stubbed-`claude` run of
    `autonomous-run.sh`; promoting that stub pattern into `tests/`
    would cover the budget flag, result parsing, and fallback log row.
  (The A3 fix already added a stop-summary no-clobber test to
  `test-hooks.sh`.)

- [ ] **C10. Wiki log row is left uncommitted on the fallback path.**
  When `autonomous-run.sh` appends the fallback row to `docs/wiki/log.md`
  (orchestrator crashed/timed out), nothing commits it — the next run
  starts with a dirty tree. Commit it in the script or document why not.

# 03 — Architect agent

Wave 2 (subagent) and Wave 3 (advisor in Agent Teams mode). Decides
shape; never implements.

## File

`.claude/agents/architect.md`

## Frontmatter

| Field | Value | Why |
|---|---|---|
| `model` | `opus` | architecture work benefits from stronger reasoning |
| `tools` | `Read, Write, Edit, Glob, Grep` | read everything; write only `docs/` |
| `skills` | `adr-template, code-quality` | ADR format + design heuristics |

The agent enforces **read-only on `src/`** in its system prompt — there
is no programmatic guard. Trust + skill. The `policy-guard.sh` hook
catches obvious slips by virtue of `forbidden_paths`.

## Pre-flight

1. Read `CLAUDE.md` and `.claude/policy.yaml`.
2. Read assigned story files (paths supplied in prompt).
3. Read existing ADRs in `docs/adr/` (numbering, prior decisions).
4. Inspect source structure with `Glob`/`Grep` — never `Edit`.

## Two modes

### Subagent mode (Wave 2)

Output: `docs/adr/NNNN-<slug>.md`. Numbering is sequential 4-digit
zero-padded. Each ADR follows the template in
`.claude/skills/adr-template/SKILL.md` (Status / Context / Decision /
Consequences / Ports-Adapters / Sequence diagram).

Final chat message: list ADR ids and the ports/adapters each defines.

### Advisor mode (Wave 3, Agent Teams)

Triggered when invoked as a teammate with `advisor: true` in the
prompt. The agent's system prompt branches:
- stay idle until a teammate sends a message
- replies ≤200 words; cite ADR id where relevant
- never edit any file
- max 8 turns total; on overflow, `shutdown_response` and signal the
  orchestrator to re-spawn the architect as a full subagent

## Escalation

Stop and write `.claude/runs/<ts>/escalation.md` if a story requires:
- a new external dependency,
- a security-critical decision (auth, crypto, secret handling),
- a public API contract change touching consumers.

## Test plan

1. With `rigor-level=production` and a story that introduces a new
   port, run `/kickoff "<goal>"`.
2. Confirm `docs/adr/NNNN-*.md` is created with the next sequential
   number.
3. Confirm the ADR has all template sections; ports list maps to the
   developer's subsequent file changes.
4. With `rigor-level=prototype`, confirm Wave 2 is skipped unless the
   goal explicitly requests an ADR.
5. In Agent Teams mode (`/kickoff-team`), confirm the architect
   teammate's transcript contains `SendMessage` *responses* but no
   file writes.

---
name: adr-template
description: ADR (Architecture Decision Record) template, numbering rules, and usage notes. Use when proposing or recording an architecture decision. Loaded by architect.
---

# ADR template

Architecture Decision Records live under `docs/adr/` with the filename
pattern `NNNN-<slug>.md` where `NNNN` is a zero-padded 4-digit sequence
number. Numbers are assigned sequentially, never reused, never gapped.

## Numbering rules

- Find the highest existing number under `docs/adr/`.
- Use `<highest>+1`. Pad to 4 digits.
- Two architects writing in parallel must coordinate via the orchestrator
  (the orchestrator assigns numbers when running in Agent-Teams wave 3).

## Template

```markdown
# ADR-<NNNN>: <decision title in imperative voice>

**Status**: proposed | accepted | superseded by ADR-<id> | deprecated
**Date**: YYYY-MM-DD
**Stories**: <comma-separated list of story ids this addresses>

## Context

What is the situation that requires a decision? Include relevant
constraints (technical, organizational, time), prior decisions that
remain in force, and the forces in tension. 1–3 paragraphs.

## Decision

What we will do, in 1–3 paragraphs. Be specific. "We will use Redis as
the rate-limit store, accessed through the `RateLimiter` port, with the
`RedisRateLimiter` adapter, configured via `RATE_LIMIT_REDIS_URL`."

## Consequences

- **positive**: <bullets — what becomes easier, what we gain>
- **negative**: <bullets — what becomes harder, what we lose>
- **neutral**: <bullets — observable effects without a clear sign>

## Ports / Adapters / Modules

- `<port-or-module-name>`:
  - interface: <one-line description>
  - consumers: <list>
  - implementations to follow: <list>

## Sequence (optional)

```mermaid
sequenceDiagram
  Client->>API: POST /resource
  API->>RateLimiter: check(tenant)
  RateLimiter-->>API: ok
  API->>...
```

## Alternatives considered (optional)

- **<alternative>**: <why we did not pick this>
- ...

## Open questions

- <items the team did not resolve; tag with owner and target date>
```

## Statuses

- `proposed` — drafted but not yet executed against. Default for a new ADR.
- `accepted` — implemented and in force. Promote when wave 3 begins.
- `superseded by ADR-<id>` — replaced. Keep the old file; the new ADR
  links back. Never delete history.
- `deprecated` — withdrawn without a replacement. Rare.

## When NOT to write an ADR

- A decision affects only a single function's internals.
- A decision is a direct restatement of an existing ADR.
- The change is mechanical (renaming, moving files) with no design
  implication.

## Related

- `code-quality` skill — sets the baseline architects assume in
  Decision text.
- `gherkin-stories` skill — story IDs cited in the `Stories:` header.

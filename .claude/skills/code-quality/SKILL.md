---
name: code-quality
description: Language-agnostic code quality heuristics — single responsibility, dependency direction, simple complexity ceilings, naming. Apply when writing or reviewing source code. Loaded by architect, developer, qa-engineer, orchestrator.
---

# Code quality — language-agnostic baseline

These rules apply regardless of stack. Project-specific overrides go in
`.claude/policy.yaml` `forbidden_patterns` or in `.claude/smurf.md`
`PROJECT_INVARIANTS`.

## Principles

- **Single responsibility (SRP)** — one reason to change per file. If a
  file has two distinct reasons to change, split it.
- **Dependency direction (DIP)** — depend on interfaces (ports) defined
  by the consumer, not on concrete implementations from another module.
  Adapters live at the edges; domain logic stays pure.
- **Open/closed (OCP)** — extend behavior by adding new files, not by
  editing stable ones. Strategy / decorator / handler-list beats a long
  `if/elif` chain.
- **Liskov (LSP)** — subtype substitutability. If a subclass weakens a
  precondition or breaks an invariant, you have the wrong abstraction.
- **Interface segregation (ISP)** — many small interfaces beat one fat
  one. A consumer should not depend on methods it doesn't call.

## Complexity ceilings (warn, not block)

- function ≤ 30 lines (excluding comments and blank lines)
- file ≤ 300 lines
- function arguments ≤ 5
- nesting depth ≤ 3
- cyclomatic complexity ≤ 10

If you must exceed these, leave a one-line comment explaining why.

## Naming

- Names describe **what** not **how**. `userRepository` not `userMongoDao`.
- Booleans read as predicates: `isReady`, `hasAccess`, `canCommit`.
- Avoid Hungarian, type suffixes (`*Impl`, `*Manager`), and abbreviations
  unless the project already uses them.
- Match existing project conventions over personal preference. If the
  project mixes styles, surface the conflict; don't pick a side silently.

## Anti-patterns to refuse

- `instanceof`-chain or `switch (type)` in domain code → use polymorphism.
- Field/setter injection in language-runtimes that have constructor
  injection → use the constructor.
- Mutable globals or singletons holding business state.
- Dead code (defined but never called).
- TODO/FIXME without an associated ticket reference.

## When asked to "simplify"

1. Inline single-use helpers.
2. Remove dead branches (anything unreachable via inputs the API can
   actually receive).
3. Replace conditional chains with polymorphism only if there are ≥3
   variants AND the variants are stable.
4. Stop. Don't refactor more than asked.

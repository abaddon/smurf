# 00 — Overview

This directory holds the per-component specs for the smurf orchestrator.
Each spec is a contract: what the component must do, what it produces,
what it must never do.

The plan that drove this build is `~/.claude/plans/i-want-to-create-fluffy-curry.md`
(at the time of writing; not committed). The research that informed the
plan is `docs/research.md` — Architettura A from §3.

## Spec index

| # | Spec | Status |
|---|---|---|
| 00 | This overview | written |
| 01 | `agents/orchestrator.md` contract | written (Phase 2) |
| 02 | `agents/product-owner.md` contract | Phase 7 |
| 03 | `agents/architect.md` contract | Phase 7 |
| 04 | `agents/developer.md` contract | Phase 7 |
| 05 | `agents/qa-engineer.md` contract | Phase 7 |
| 06 | `agents/devops.md` contract | Phase 7 |
| 07 | `agents/marketing.md` contract | Phase 7 |
| 08 | `agents/sales-feedback.md` contract | Phase 7 |
| 09 | Hooks and `policy.yaml` | Phase 3 |
| 10 | Skills | Phase 4 |
| 11 | MCP and secrets | Phase 7 |
| 12 | Headless run + cron + watchdog | Phase 5 |
| 13 | Feedback loop (`close-loop.py`) | Phase 7 |
| 14 | Iteration mechanism + budgets | Phase 6a |

## Reading order

1. This file.
2. `01-agent-orchestrator.md` — the heart of the system.
3. `09-hooks-and-policy.md` — the deterministic guardrails (the only
   layer that can't hallucinate).
4. `14-iteration-and-budgets.md` — the three-layer iteration loop +
   budget tiers.
5. The remaining per-agent specs in numerical order.

## Architecture in one diagram

```
                  ┌──────────────────────┐
                  │ .claude/smurf.md (human) │
                  └────────────┬─────────┘
                               │ read at session-start hook
                               ▼
   /kickoff <goal>  ─►  orchestrator (opus)
                               │ plan-mode → wave DAG
                               ▼
   Wave 1  product-owner    → docs/stories/<sprint>/*.feature
   Wave 2  architect        → docs/adr/NNNN-*.md       (production rigor)
   Wave 3  developer × N    → src/* + commits          (subagents OR Agent Team)
           qa-engineer      → qa/<id>.md               (red → re-dispatch dev, max 2)
           architect-advisor (Agent Team only, idle, SendMessage-driven)
   Wave 4  devops           → CI/CD/PR draft
   Wave 5  marketing        → docs/marketing/<date>/*  (curl OpenRouter)
           sales-feedback   → docs/feedback/<date>.md  (input to next run)
                               │
                               ▼
                  on-Stop hook → .claude/runs/<ts>/summary.md
```

## Iteration mechanism (the requirement that matters)

| Layer | Trigger | Mechanism | Cap |
|---|---|---|---|
| Intra-wave | dev unsure → ask architect | `SendMessage architect-advisor` (Agent Teams only) | unbounded within wave |
| Intra-wave | qa finds failing AC | `SendMessage developer` (Agent Teams only) | unbounded within wave |
| Inter-wave | qa report RED | orchestrator re-dispatches developer with `qa/<id>.md` | `max_qa_iterations` from policy.yaml |
| Cross-run | overnight | `close-loop.py` writes `docs/feedback/<date>.md` → product-owner reads next run | 1 file/day |

## Caps live in `.claude/policy.yaml`

Single source of truth. `.claude/smurf.md` cites this file; agents read it at
pre-flight; hooks (Phase 3+) enforce it. Edit the file, not the prompts.

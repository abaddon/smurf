# Sistemi multi-agent autonomi end-to-end con Claude Code: guida tecnica per Stefano (maggio 2026)

Ciao Stefano. Di seguito trovi un’analisi tecnica completa, calibrata sui tuoi vincoli reali (subscription Claude Code, no LLM locali, OpenRouter come complemento, MacBook M4 Max + Proxmox per orchestrazione, mentalità DDD/SOLID). Spoiler della raccomandazione: **parti dall’Architettura A (Pure Claude Code) integrandola con due-tre subagent OpenRouter via Claude Code Router per i ruoli non critici**, e considera l’Architettura B solo se dopo 2-3 settimane senti davvero la mancanza di uno scheduler stateful più robusto. L’Architettura C (MetaGPT/ChatDev come “cervello”) la lascerei come esperimento di weekend, non come fondamenta di produzione — vedrai sotto perché.

-----

## 1. Claude Code come motore di orchestrazione (priorità #1)

### 1.1 Subagents: definizione, scoping, modelli

In Claude Code (v2.1.32+ a maggio 2026) i subagent sono **file Markdown con frontmatter YAML** che vivono in quattro location, risolte con priorità decrescente in caso di name collision:

1. **Session-defined** (via `--agents` JSON o SDK `agents` parameter) — vincono sempre
1. **Managed** (`.claude/agents/` nella managed settings directory di un’organizzazione)
1. **Project** (`.claude/agents/` nella radice del repo) — committalo in git
1. **User** (`~/.claude/agents/`) — personale, attivo in ogni sessione
1. **Plugin** (`.claude/agents/` dentro un plugin installato) — last resort, e con restrizioni: i plugin subagent **non** supportano `hooks`, `mcpServers` né `permissionMode` per ragioni di sicurezza 

Lo scheletro canonico:

```markdown
---
name: developer-spring-boot
description: Implements Spring Boot features using DDD/SOLID. Invoke after the architect has produced a design doc.
tools: Read, Write, Edit, Bash, Glob, Grep
model: sonnet         # sonnet | opus | haiku | inherit
permissionMode: default
isolation: worktree    # crea un git worktree dedicato (v2.1.50+)
color: blue
---
You are a senior Java/Spring Boot engineer. Apply hexagonal architecture,
keep domain layer pure (no Spring annotations), use constructor injection,
respect SRP/OCP/LSP/ISP/DIP. Output: code + ADR snippet + JUnit5 tests.
```

Campi disponibili oggi nel frontmatter (sia file che SDK): `description`, `prompt`, `tools`, `disallowedTools`, `model`, `permissionMode`, `mcpServers`, `hooks`, `maxTurns`, `skills`, `initialPrompt`, `memory`, `effort`, `background`, `isolation`, `color`.  Il comando interattivo `/agents` (tab Library) genera questi file con uno scaffolder; `claude agents` da CLI lista tutto raggruppato per source.  Un trigger esplicito in chat è `@agent-name` o `@"name (agent)"`;  altrimenti Claude delega in automatico in base al campo `description`.

**Tre subagent built-in** (gratuiti, sempre presenti): `Explore` (read-only, gira di default su Haiku 4.5 → veloce ed economico), `Plan` (research nello slash-command `/plan`), `general-purpose` (read+write, fallback). Non li definisci tu; Claude li chiama da solo.

**Importante sul costo**: ogni subagent apre la propria context window (200K, fino a 1M su Sonnet 4.6/Opus 4.6/4.7) → la documentazione Anthropic stessa indica **~4-7× più token** dei flussi single-agent, e gli **Agent Teams in plan mode arrivano a ~7× e fino a ~15×** quando i teammates sono persistenti. Per la Pro plan questo significa esaurire il window di 5 ore in 20 minuti se non metti dei guardrail.

### 1.2 Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)

Introdotti come *research preview* in **v2.1.32 (5 febbraio 2026)** insieme a Opus 4.6, gli Agent Teams sono una primitiva diversa dai subagent:

|Aspetto          |Subagent                              |Agent Team                                                      |
|-----------------|--------------------------------------|----------------------------------------------------------------|
|Comunicazione    |Solo verso il parent                  |Peer-to-peer via `SendMessage`                                  |
|Coordinamento    |Implicito (parent)                    |Lead esplicito + shared task list su disco                      |
|Sessioni         |Una sola, in-process                  |N sessioni Claude Code indipendenti                             |
|Persistenza stato|Nessuna                               |`~/.claude/teams/{name}/config.json` + `~/.claude/tasks/{name}/`|
|Resume           |`/resume` ok                          |**NO**: `/resume` e `/rewind` non riportano in vita i teammates |
|Nesting          |I subagent non possono spawnarne altri|I teammates **non** possono spawnare altri team                 |
|Limite           |—                                     |**One team at a time per lead**                                 |

Tooling esposto al lead: `Teammate` (con sub-azioni `spawnTeam`, `cleanup`), `SendMessage` (con `message`, `broadcast`, `shutdown_request/response`, `plan_approval_response`), `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`. Le task fluiscono in tre stati con file-locking per evitare double-claim. 

Limiti noti documentati ufficialmente da Anthropic e confermati nei post di campo (Heeki Park, Addy Osmani, alexop.dev):

- task status che lagga (i teammates a volte non chiudono la task → blocca i dipendenti)
- shutdown lento (i teammates finiscono il tool call corrente prima di morire)
- skills + mcpServers nel frontmatter dei subagent **non** vengono applicati quando lo stesso file gira come teammate (carica solo da project/user settings)
- richiede **Opus 4.6 minimo** come modello

Per il tuo caso d’uso (PM/Architect/Dev/QA/DevOps/Marketing in parallelo) gli Agent Teams sono concettualmente perfetti, ma in maggio 2026 sono ancora *experimental*. La regola pragmatica: **subagent quando i worker non devono comunicare tra loro, Agent Teams quando devono**. Dato che il tuo flusso è in larga parte sequenziale (Product → Architect → Dev → QA → DevOps → Marketing → Product) con qualche fan-out (es. Dev split su feature parallele), nel 90% dei casi i subagent + git worktrees ti bastano.

### 1.3 Skills vs Subagents vs Hooks — quando usare cosa

Dalla doc ufficiale e dalle guide consolidate (Ofox, Anthropic best-practices, Sathish Raju Apr 2026):

- **Skills** = pacchetti di conoscenza riusabili con *progressive disclosure* (frontmatter sempre caricato, body on-activation, `resources/` on-demand). Usali per *cross-cutting concerns* tipo “convenzioni API”, “pattern DDD del progetto”, “playbook PR description”. Una skill può anche girare in sub-context aggiungendo `agent: true` + `model:` al frontmatter — utile per task tipo “estrai TL;DR da PDF” senza inquinare il parent. **I subagent NON ereditano le skill del parent**: vanno preloaded esplicitamente con `skills: [...]`.
- **Subagents** = unità di esecuzione isolata con system-prompt proprio, tool-set proprio, context window proprio. Usali quando il *ruolo* è diverso dal parent (qa-engineer ≠ developer).
- **Hooks** = codice deterministico eseguito intorno a tool call, session start/stop, subagent completion. Lì metti i guardrail veri (block edits to generated files, run `mvn test` prima di committare, blocca `rm -rf`, inietta CLAUDE.md context al session start, log di audit). Sono l’unica leva che **non può allucinare**  — fondamentale per un sistema che gira unattended.

Heuristic della doc Anthropic (“Best practices for Claude Code”): *“Start with skills — they are the easiest. Add hooks when you need deterministic enforcement. Use subagents when parallel work or context isolation matters.”*

### 1.4 MCP integration

Tutti i pezzi del flusso end-to-end (GitHub, GitLab, AWS, Docker, Sentry, Linear/Jira, Vercel/Netlify, Stripe, Slack, email/SMS) si attaccano via **MCP server**. Ne esistono già di production-ready per quasi tutti questi servizi (`@modelcontextprotocol/server-github`, `@stripe/mcp`, server Slack ufficiali, `linear-mcp`, ecc.). Si dichiarano in `.mcp.json` a livello project oppure in `~/.claude/settings.json` a livello user, e li scopri da dentro con `/mcp`. I subagent possono scopare l’accesso con `mcpServers: [github, linear]` nel frontmatter — molto importante: **il marketing-agent NON deve avere accesso a Stripe in scrittura, il dev NON deve avere accesso al gateway email**.

Esempio `.mcp.json` minimo per la tua pipeline:

```json
{
  "mcpServers": {
    "github":   { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": { "GITHUB_TOKEN": "$GH_PAT" } },
    "linear":   { "command": "npx", "args": ["-y", "linear-mcp"],          "env": { "LINEAR_API_KEY": "$LINEAR" } },
    "sentry":   { "command": "npx", "args": ["-y", "@sentry/mcp-server"],  "env": { "SENTRY_AUTH": "$SENTRY" } },
    "stripe":   { "command": "npx", "args": ["-y", "@stripe/mcp"],         "env": { "STRIPE_KEY": "$STRIPE_RO" } },
    "slack":    { "command": "npx", "args": ["-y", "slack-mcp"],           "env": { "SLACK_BOT": "$SLACK" } },
    "postmark": { "command": "npx", "args": ["-y", "postmark-mcp"],        "env": { "POSTMARK_KEY": "$POSTMARK" } }
  }
}
```

### 1.5 Headless mode (`-p`) e automazione

L’invocazione non-interattiva è la chiave per i tuoi cron run. Flag essenziali (mappati alla “playbook” di backgroundclaude/codewithseb del 2026):

```bash
claude -p "$PROMPT" \
  --bare \                              # disabilita auto-discovery di hook/skill/MCP esterni → CI riproducibile
  --allowedTools "Read,Edit,Bash(git:*),Bash(mvn *)" \
  --max-turns 40 \                      # ceiling tool-call (5 per pre-commit, 120 per overnight refactor)
  --max-budget-usd 2 \                  # hard ceiling in dollari
  --output-format stream-json \         # NDJSON parsabile con jq, observability decente
  --verbose \
  > result.json 2> claude.err
```

Note importanti:

- `--bare` salta auto-load di `~/.claude` e `.mcp.json`. CI riproducibili → consigliato. Devi però **passare esplicitamente** ciò che ti serve.
- `--dangerously-skip-permissions` è “l’opzione nucleare”. Solo dentro container sandboxed con credentials read-only.
- **Auto Mode** (`--permission-mode auto`) è il via di mezzo introdotto nel 2026: skip-prompts su azioni “safe”, blocca quelle rischiose senza chiedere — più sicuro di `--dangerously-skip-permissions`.
- `--continue` e `--resume <session_id>` permettono di mantenere conversazioni multi-step in script bash. `claude --bare -p "..." --output-format json | jq -r '.session_id'` ti dà l’ID per il re-attach.
- A Q1 2026 Anthropic ha rilasciato anche **Scheduled Tasks** (`claude schedule create --cron "0 9 * * MON" --prompt "..."`) che girano sull’infra Anthropic, non sulla tua. Pratico per task time-based; ma per il tuo flusso (vuoi vedere log e debuggare in locale) preferisci `cron` sul tuo Mac o sul Proxmox.

### 1.6 Worktrees & parallel execution

Da v2.1.50 c’è il flag nativo `--worktree <name>`:

```bash
claude --worktree feature-auth      # crea .claude/worktrees/feature-auth/ con branch worktree-feature-auth
```

E nel frontmatter dei subagent puoi forzarlo:

```yaml
---
name: developer
isolation: worktree   # ogni invocazione → worktree fresco; auto-cleanup se 0 modifiche
---
```

Strategie di merging che funzionano in 2026:

1. **Orchestrator-managed sequential**: il main agent (o il team lead) merge-a in ordine, con rebase per linearità. Heeki Park lo descrive come il pattern più stabile.
1. **Human review gate**: tool come **Conductor** (Mac, ottimo per il tuo M4) e **Vibe Kanban** mostrano una kanban board con un worktree per card e diff-first review. Conductor usa il Claude Code SDK sotto sotto.
1. **Competing solutions**: due-tre agent risolvono lo *stesso* problema in worktree diversi → tu (o un reviewer-agent) scegli il vincitore. Sfrutta il non-determinismo come feature. 
1. **Built-in `/batch`**: se installi un kit come ClaudeFast Code Kit, ottieni questo pattern out-of-the-box.

### 1.7 Limiti del piano e gestione del costo

Stato a maggio 2026 (post-update Anthropic del 6 maggio che ha **raddoppiato i limiti Code per la maggior parte degli utenti**):

|Piano       |Prezzo                              |Sessione 5h (relativa a Pro)|Weekly cap                                |Note Code                                                                                                         |
|------------|------------------------------------|----------------------------|------------------------------------------|------------------------------------------------------------------------------------------------------------------|
|Free        |–                                   |baseline                    |–                                         |Code praticamente non utilizzabile per sessioni lunghe                                                            |
|**Pro**     |**$20/mo**                          |1×                          |sì (cap settimanale + cap Sonnet separato)|~44k token/window (stima community pre-raddoppio)                                                                 |
|**Max 5×**  |**$100/mo**                         |5×                          |sì                                        |~88k token/window                                                                                                 |
|**Max 20×** |**$200/mo**                         |20×                         |sì                                        |~220k/window; può **opt-in a usage extra a tariffe API standard** dopo il cap (Pro/Max5 NO, blocchi fino al reset)|
|Team Premium|$100-125/seat/mo                    |6.25× di Pro                |sì                                        |unica seat che include Code                                                                                       |
|Enterprise  |per-seat annuo + token a tariffa API|–                           |–                                         |nessun usage incluso                                                                                              |

**Per il tuo profilo (single dev che vuole runs autonomi multi-ora) Max 5× è il floor minimo serio, Max 20× è il sweet spot.** La differenza chiave: solo Max 20× ti permette di pagare overflow API rate dopo il cap, gli altri si bloccano fino al reset. Con un sistema che gira di notte, sbattere contro il cap a metà run e svegliarsi con il task incompleto è frustrante.

**Subagent counting**: ogni subagent gira con la propria context window e consuma token in parallelo. Caso reale documentato (Finout, 2026): un `/typescript-checks` con 49 subagent paralleli ha bruciato $8k-$15k in 2.5h; un team di financial services ha consumato $47k in 3 giorni con 23 subagent unattended. **In CLAUDE.md vincola sempre il fan-out massimo.**

Cause più comuni di token-burn anomalo (tutte documentate su Anthropic GitHub issues):

1. **Subagent fan-out**: cap il numero massimo
1. **Autocompact cascade**: scatta a ~187K token, può sparare 100-200K token per compaction, fino a 3× per turn. Su Opus con 1M window è stato osservato a 76K (92% spreco)
1. **MCP server bloat**: 18K+ token/turn/server se carichi tutto. Disabilita gli MCP non usati e usa il *deferred tool definitions* (default: solo i nomi entrano nel context, le definizioni piene solo all’invocazione)
1. **Context resubmission loops**: durante i retry il loop main risubmit l’intera storia → singola prompt da 50-300K token. Tieni `--max-turns` e `--max-budget-usd` sempre.
1. **Opus 4.7 (rilasciato 16 aprile 2026) ha un nuovo tokenizer che produce fino a 35% più token a parità di input** rispetto a Opus 4.6. Stesse $/MTok ma cost-per-request più alto. Per ora, per task lunghi unattended, **Sonnet 4.6 è il default più sicuro**, Opus 4.7 solo per ragionamento complesso.

### 1.8 Operator/Orchestrator pattern

Il pattern canonico nel repo `wshobson/agents` (la marketplace più matura: **78 plugin, 185 agent specializzati, 153 skill, 16 orchestratori multi-agent**, 4-tier model strategy Opus 4.6/Sonnet 4.6/Haiku 4.5/Inherit) è:

```
Main agent (orchestrator) 
   ├─ enters plan mode (cheap, no edits)
   ├─ decomposes goal into wave-based DAG
   ├─ spawns waves of subagents in parallel (or teammates if Agent Teams enabled)
   │     ├─ wave 1: research / requirements
   │     ├─ wave 2: design (architect)
   │     ├─ wave 3: implementation (developer × N feature, parallel worktree)
   │     ├─ wave 4: review (reviewer + qa)
   │     └─ wave 5: deployment (devops)
   ├─ synthesizes results
   └─ exits plan mode → integration verification phase
```

Plugin notevoli da `wshobson/agents` per il tuo caso:

- **`full-stack-orchestration`** — backend → frontend → testing → security → deployment
- **`agent-orchestration`** e **`agent-teams`** — primitives di coordinamento
- **`backend-development`** (3 architecture skill), **`kubernetes-operations`**, **`cloud-infrastructure`** (AWS/Azure/GCP, Terraform), **`incident-response`**
- **`comprehensive-review`** — analisi multi-perspective (security, performance, architecture)
- **`conductor`** — adattamento Mac di Context-Driven Development: enforce un workflow strutturato Context → Spec & Plan → Implement, con artifact `context/` versionato. Comandi: `/conductor:setup`, `/conductor:new-track`, `/conductor:implement`. **Per te è particolarmente utile** perché previene la “drift” del LLM dai tuoi standard DDD/SOLID — il context è scritto da te, non rigenerato.
- Pattern **“Product Trinity”** (PM → UX → Implementation) — orchestratore con 3 wave specializzate

Altri repo da committare a memoria:

- **`VoltAgent/awesome-claude-code-subagents`** — 100+ subagent organizzati per dominio, ottimo “library” per pescare prompt-template
- **`lst97/claude-code-sub-agents`** — collezione full-stack con orchestratori inclusi (esempi documentati con cifre: feature semplice ~300K token / ~17 min con team da 4 agent) 
- **`ryanmac/code-conductor`** — orchestrazione GitHub-native via labels su issue (`conductor:task`) + worktree 
- **`barkain/claude-code-workflow-orchestration`** — plugin nativo per multi-step workflow con plan mode integrato e detection automatica subagent vs team mode
- **`obra/superpowers`** — set di skill avanzate (subagent-driven-development, dispatching-parallel-agents)

### 1.9 Combinare OpenRouter dentro Claude Code

Per i ruoli non critici (marketing, sales-copy, draft testuali) hai tre opzioni, in ordine di “peso”:

**Opzione 1 — Override globale via env var (semplice, riguarda TUTTO Claude Code)**

```bash
export OPENROUTER_API_KEY="sk-or-..."
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"   # NON /api/v1
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
export ANTHROPIC_API_KEY=""                              # esplicitamente vuoto
export ANTHROPIC_DEFAULT_SONNET_MODEL="anthropic/claude-sonnet-4.5"
export ANTHROPIC_DEFAULT_OPUS_MODEL="anthropic/claude-opus-4.6"
```

OpenRouter espone un **“Anthropic Skin”** wire-compatible con l’API Anthropic Messages — non serve proxy. Ottieni: failover multi-provider (Vertex/Bedrock se Anthropic ha outage), per-key spending caps, dashboard usage centralizzato. **Nota della doc OpenRouter**: la compatibilità è garantita solo con l’Anthropic first-party provider; modelli non-Anthropic possono rompere su tool-use complessi. Per Stefano questo significa: **tieni Anthropic 1P come provider top-priority, usa OpenRouter solo per il management layer**.

**Opzione 2 — Claude Code Router (`musistudio/claude-code-router`, l’eseguibile `ccr`)** è la scelta professionale per il routing per-ruolo:

```jsonc
{
  "Providers": [
    { "name": "openrouter", "api_base_url": "https://openrouter.ai/api/v1/chat/completions",
      "api_key": "sk-or-...", "models": ["deepseek/deepseek-v4-pro", "google/gemini-2.5-flash", "anthropic/claude-haiku-4.5"],
      "transformer": { "use": ["openrouter"] } },
    { "name": "anthropic", "api_base_url": "https://api.anthropic.com/v1/messages",
      "api_key": "$ANTHROPIC_KEY", "models": ["claude-opus-4.6", "claude-sonnet-4.6"] }
  ],
  "Router": {
    "default":     "anthropic,claude-sonnet-4.6",
    "background":  "openrouter,google/gemini-2.5-flash",
    "longContext": "anthropic,claude-sonnet-4.6",
    "think":       "anthropic,claude-opus-4.6"
  }
}
```

Avvii con `ccr start` (gira su `http://127.0.0.1:3456`),  poi Claude Code lo usa via `ANTHROPIC_BASE_URL`. Dentro Claude switchi al volo con `/model openrouter,deepseek/deepseek-v4-pro`. Custom router script JS per logica più fine (es. “se il subagent name contiene ‘marketing’ → DeepSeek, altrimenti Sonnet”).

**Opzione 3 — Subagent shell-out a OpenRouter via CLI esterno**: i subagent Claude Code stessi non possono usare un model backend diverso da quello in cui gira il parent (a meno di usare l’Opzione 2). Però **puoi dare al subagent `marketing-copywriter` solo i tool `Bash(curl *)` e fargli chiamare l’API OpenRouter direttamente con un prompt/role minimale, salvando l’output su file**. Pattern utile quando vuoi tagliare drasticamente i token Claude su task come “scrivi 20 varianti di copy per ad campaign”:

```bash
curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_KEY" \
  -d '{"model":"deepseek/deepseek-v4-pro","messages":[...]}' \
  | jq -r '.choices[0].message.content' > marketing/copy-batch.md
```

Questo **non scala bene per chain agentiche complesse** ma è perfetto per ruoli “monouso” come la generazione contenuti.

**Raccomandazione per te**: parti con Opzione 1 (override completo a OpenRouter quando vuoi un run economico) o Opzione 3 (puntuale, dentro un subagent). Salta a Opzione 2 quando senti l’esigenza di routing per-ruolo automatico.

-----

## 2. Framework open source che complementano o rimpiazzano Claude Code

### 2.1 MetaGPT + MGX (`FoundationAgents/MetaGPT`)

Concettualmente è il più vicino a quello che vuoi: ruoli espliciti **Product Manager / Architect / Project Manager / Engineer / QA**, filosofia “Code = SOP(Team)”, input one-line → output user stories + competitive analysis + requirements + data structures + APIs + docs. **MGX (MetaGPT X)** è l’offshoot commerciale lanciato 19 febbraio 2025  e attivo nel 2026.

Backend LLM: configurato in `~/.metagpt/config2.yaml` con campi `api_type` (`openai`, `azure`, `anthropic`, `ollama`, `groq`, ecc.), `model`, `base_url`, `api_key`. **Per Claude funziona**: o `api_type: "anthropic"` con la tua chiave, o `api_type: "openai"` puntato a `https://openrouter.ai/api/v1` (Anthropic Skin con prefisso `/v1`) per usare l’Opus 4.6 via OpenRouter. **Critico**: MetaGPT NON sa nulla del subscription Claude Code — paghi a token, non sfrutti il Pro/Max.

Punti di forza: SOP rigide (ogni ruolo ha output formalizzato), feedback loop via `Environment` shared, riproducibile, paper-backed (AFlow ICLR 2025 oral). Limiti: il codice generato è spesso “demo-quality”, il fine-tuning richiede fork del prompt-set, **manca un’integrazione nativa con Claude Code per la fase di coding** (devi farla tu).

Status maggio 2026: progetto vivo, repo in evoluzione, ma il momentum si è spostato verso framework più graph-based.

### 2.2 ChatDev 2.0 / DevAll (`OpenBMB/ChatDev`)

**Rilasciato 7 gennaio 2026**, è una piattaforma **zero-code multi-agent orchestration** con interfaccia Vue 3 web + FastAPI backend. Workflow definiti in YAML (`yaml_instance/`), drag-and-drop canvas, batch execution, **integrazione nativa con OpenClaw** (`clawdhub install chatdev` da OpenClaw → invoca workflow ChatDev).

ChatDev 1.0 è ancora disponibile come legacy branch (`chatdev1.0`) — è la “virtual software company” classica con CEO/CTO/Programmer in seminari sequenziali. La 2.0 è più generale: definisci tu ruoli e workflow.

Backend LLM: variabili `API_KEY` e `BASE_URL` in `.env`, con placeholder `${VAR}` nei YAML. **Funziona con OpenRouter** puntando `BASE_URL=https://openrouter.ai/api/v1`. Esiste un Python SDK pubblicato su PyPI (`pip install chatdev`) che esegue YAML workflow programmaticamente — utile se vuoi triggerare da n8n.

Punti di forza: visual builder, batch mode, Docker Compose deploy, Human-Agent-Interaction mode (`--config "Human"`). Limiti: scalabilità enterprise non testata, l’astrazione è opinionated, **il codice generato non eguaglia Claude Code in qualità su progetti reali**.

### 2.3 CrewAI

Maturo, ~44.6K stars (mar 2026), v1.10.1 con MCP e A2A native.  **5.76× più veloce di LangGraph** in alcuni benchmark grazie all’architettura standalone (no LangChain dependency).  Modello mentale: `Crew` di `Agent` con `role`, `goal`, `backstory`; `Task` con `expected_output`; `Process` (sequential / hierarchical). Dal 2025 ha aggiunto **`Flows`**: pipeline event-driven più produzione-ready (la maggior parte dei tutorial vecchi le ignora ancora).

Supporto Claude: nativo (`Agent(llm=ChatAnthropic(model="claude-opus-4.6"))`), e via OpenRouter punti `base_url`. **È il framework più veloce per arrivare al primo prototipo working** (2-4 ore  per un crew completo a 4 ruoli).

Limiti onesti: no built-in checkpointing (problema per workflow lunghi che crashano), comunicazione agent-to-agent mediata via task output (non messaggistica diretta), error handling coarse-grained, e quando scali a 8+ agent senti la differenza con LangGraph.

### 2.4 LangGraph

**Tier-1 production-grade** secondo tutti i comparativi 2026 (Pharos, Alice Labs, Toolradar, gurusup). Reached **1.0 GA in ottobre 2025**, ora a v1.0.10. Modello: directed graph con edge condizionali, state machine esplicita, native checkpointing → **time-travel debugging** via LangSmith. Adottato in produzione da Klarna (85M user, -80% resolution time), Replit, Elastic, Uber, LinkedIn, AppFolio.

Per il tuo caso è **the right tool quando il flusso ha cycles, branching, retry su errore, HITL, parallel branches**. La curva di apprendimento è reale (devi pensare a `State`, `Reducer`, `Checkpointer`) ma la storia di debugging è impareggiabile.

Multi-LLM: ottimo, via abstraction LangChain (Anthropic, OpenAI, OpenRouter, Bedrock, Vertex, Ollama). License MIT, monthly downloads ~47M.

Limite per te: non ha primitive specifiche per “ruoli” (PM/Dev/QA) — devi modellarli tu come node. Più verboso di CrewAI.

### 2.5 AutoGen / AG2 e Microsoft Agent Framework

**Stato definitivo 2026**: AutoGen è **in maintenance mode** (bug fix + security patch only).  Il successore è **Microsoft Agent Framework 1.0**, **GA ufficiale 3 aprile 2026** (.NET + Python).  Unisce le orchestration patterns di AutoGen (sequential, concurrent, handoff, group chat, **Magentic-One**) con la stabilità enterprise di Semantic Kernel.  **Supporta Anthropic Claude nativamente**, oltre a Foundry, Azure OpenAI, OpenAI, GitHub Copilot, AWS Bedrock, Ollama. Supporta **MCP** e **A2A** standards. 

Per te: **non ha senso adottare AutoGen oggi** per nuovi progetti. Se finisci nel mondo .NET (cosa improbabile vista la tua stack Java/Spring Boot) Agent Framework è l’opzione naturale. La community che vuole continuare la lineage AutoGen v0.2 è migrata sotto **AG2 (`ag2.ai`)**.

Per Java, ricorda che esiste anche **Spring AI** + **Spring AI Alibaba Agent** in beta, ma non sono ancora paragonabili a CrewAI/LangGraph per multi-agent serio.

### 2.6 OpenClaw

Progetto breakout 2026, descritto come “Your own personal AI assistant. Any OS. Any Platform. The lobster way 🦞”.  Self-hosted, privacy-first, connette 50+ app, modello a plugin/skill/channel con SecretRef per credentials. La release notes recente (maggio 2026, v2026.5.x) mostra integrazioni mature con OpenAI Codex OAuth, Anthropic Claude CLI bypass-permissions, Telegram, WhatsApp, Discord, plus CLI commands (`openclaw models`, `openclaw status`, `openclaw channels`, `openclaw cron`).

L’integrazione con ChatDev 2.0 è bidirezionale: ChatDev backend invoca team OpenClaw, OpenClaw può creare workflow ChatDev. È il candidato ideale **come “agent home base” sul tuo Proxmox** se vuoi un dashboard centralizzato che parla con Telegram/email per notifiche e tiene cron job. Per te potrebbe essere il tassello che orchestra trigger e notifiche, lasciando a Claude Code la parte di coding vera.

### 2.7 Dify

Self-hostable LLM app platform con visual workflow builder, RAG nativo, API gateway. Più orientato a “build LLM-powered app” che a “build software end-to-end”. Per te utile come componente per il marketing-agent (chatbot, RAG su feedback utenti) ma non come orchestratore principale.

### 2.8 Langflow

Drag-and-drop visual builder che compila a Python. Buono per prototipi visivi, debole per produzione long-running. Lo metterei nella stessa categoria di Dify: complementare, non centrale.

### 2.9 Anthropic Claude Agent SDK

L’SDK ufficiale Python/TypeScript che **è il runtime di Claude Code stesso**. Quando usarlo direttamente vs Claude Code CLI:

- **Claude Code CLI** = quando vuoi l’esperienza terminal completa, hooks/skills/MCP discovery automatica, slash commands, plugin marketplace, plan mode UI.
- **Claude Agent SDK** = quando vuoi controllo programmatico fine-grained dentro un’app Python/TS, tool approval callback custom, structured output Pydantic-style, hosting in serverless, integrazione in altri flussi (es. orchestratore CrewAI che chiama l’SDK per la fase coding). **Eredita gli stessi env var** quindi ANTHROPIC_BASE_URL → OpenRouter funziona identico.

Per te il sweet spot: **Claude Code CLI per il day-to-day e i cron run, Claude Agent SDK solo se decidi di costruire l’orchestratore Architettura B in Python**.

### 2.10 Tabella riassuntiva

|Framework                |Maturità         |License          |Claude native          |OpenRouter  |Infra               |Closed-loop fit               |Limite onesto                      |
|-------------------------|-----------------|-----------------|-----------------------|------------|--------------------|------------------------------|-----------------------------------|
|Claude Code (CLI)        |GA               |proprietario     |sì                     |sì (env var)|zero (Mac M4)       |ottimo (subagents+teams+MCP)  |lock-in Anthropic, costi se non Max|
|Claude Agent SDK         |GA               |MIT              |sì                     |sì          |Python/TS app       |ottimo (programmatico)        |richiede codice                    |
|MetaGPT/MGX              |attivo           |MIT              |sì (anthropic api_type)|sì          |Python              |medio (SOP rigide)            |qualità code mediocre              |
|ChatDev 2.0              |rilasciato 1/2026|Apache-2.0       |sì (BASE_URL)          |sì          |Docker Compose + Vue|medio (più generale che dev)  |scalabilità non testata            |
|CrewAI                   |maturo           |MIT              |sì                     |sì          |Python              |buono (ruoli espliciti)       |no checkpointing nativo            |
|LangGraph                |GA 1.0           |MIT              |sì                     |sì          |Python              |ottimo (graph+HITL+checkpoint)|curva apprendimento                |
|Microsoft Agent Framework|GA 1.0 (4/2026)  |MIT              |sì                     |parziale    |.NET/Python         |buono                         |ecosistema MS-centric              |
|AutoGen/AG2              |maintenance      |MIT/Apache       |sì                     |sì          |Python              |ok                            |non investire più                  |
|OpenClaw                 |attivo           |proprietario open|sì                     |sì          |self-host           |utile come hub                |non è un dev-orchestrator          |
|Dify / Langflow          |maturi           |open             |sì                     |sì          |self-host           |scarso (LLM app, non SDLC)    |non per il tuo use case            |

-----

## 3. Architetture concrete

### Architettura A — “Pure Claude Code” (lowest setup time) 🏆

**Filosofia**: un singolo progetto Claude Code con 7-8 subagent custom, skill per cross-cutting concerns, MCP server per integrazioni, headless mode + cron per autonomia, git worktrees per parallelismo. Niente Python, niente orchestratore esterno.

**Struttura repo**:

```
communication-hub-autonomous/
├── .claude/
│   ├── agents/
│   │   ├── orchestrator.md         # opus, full-tools
│   │   ├── product-owner.md        # sonnet, MCP linear
│   │   ├── architect.md            # opus, read-only + write docs/
│   │   ├── developer.md            # sonnet, isolation: worktree
│   │   ├── qa-engineer.md          # sonnet, Bash(mvn test)
│   │   ├── devops.md               # sonnet, MCP github,aws,docker
│   │   ├── marketing.md            # haiku via OpenRouter, MCP slack,postmark
│   │   └── sales-feedback.md       # haiku, MCP stripe(ro),analytics
│   ├── skills/
│   │   ├── ddd-conventions/        # agent: false; sempre disponibile
│   │   ├── solid-checklist/
│   │   ├── spring-boot-patterns/
│   │   └── adr-template/
│   ├── hooks/
│   │   ├── pre-commit-mvn-test.sh
│   │   ├── block-domain-spring-leak.sh   # blocca @Component nel package domain
│   │   ├── pre-tool-bash-allowlist.sh
│   │   └── on-stop-summary.sh
│   ├── commands/
│   │   ├── kickoff-feature.md      # /kickoff-feature "<spec>"
│   │   ├── nightly-run.md
│   │   └── close-loop.md
│   └── settings.json               # MCP servers, env, allowed tools
├── .mcp.json
├── CLAUDE.md                       # rigorosamente human-written (Addy Osmani: AI-written = -3% success)
├── docs/
│   ├── adr/
│   ├── domain-glossary.md
│   └── rigor-level.md              # parametro prototype|production
├── scripts/
│   ├── autonomous-run.sh
│   └── close-loop.py               # pulls Sentry/Posthog → feeds product-owner
└── src/main/java/...
```

**`CLAUDE.md` essenziale** (scrivi tu, niente AI):

```markdown
# Communication Hub — Agent Operating Manual

## RIGOR_LEVEL
Read from docs/rigor-level.md. Values: prototype | production.
- prototype: skip ADR, allow technical debt with TODO, minimum tests = happy path
- production: enforce DDD layering, write ADR for any new bounded context, 
  >85% coverage on domain layer, integration tests for every API endpoint

## DOMAIN
- Bounded contexts: Messaging, Routing, AuditTrail, Subscription
- Ubiquitous language in docs/domain-glossary.md
- Domain layer (com.example.hub.domain.*) MUST NOT depend on Spring annotations

## STACK
- Java 21, Spring Boot 3.4, PostgreSQL 16, Kafka 3.7, Testcontainers
- Build: Maven, profile production-grade requires `mvn verify`
- Hexagonal: domain → application → infrastructure (one-way only)

## SOLID NON-NEGOTIABLES
- SRP: max 1 reason to change per class
- OCP: extension via Strategy/Decorator, no modification of stable code
- DIP: depend on ports (interfaces in domain), adapters in infrastructure
- Constructor injection only. Field injection rejected by hook.

## AGENT CONTRACT
- max parallel subagents: 4
- max-turns per subagent: 30 (50 for orchestrator)
- max-budget-usd per autonomous run: 8
- always plan before edit (use plan mode)
- always run hooks/pre-commit-mvn-test.sh before declaring task complete
- ALL agents must read docs/rigor-level.md before starting

## ESCALATION
Stop and request human review if:
- adding a new bounded context
- changing public API contract
- introducing a new external dependency
- security-related change (auth, crypto, secrets)
```

**Esempio orchestrator agent**:

```markdown
---
name: orchestrator
description: |
  Top-level coordinator. Decomposes a product goal into wave-based DAG and delegates
  to specialist subagents. Invoke with "@orchestrator: <goal>".
tools: Read, Write, Edit, Bash, Glob, Grep, TodoWrite
model: opus
maxTurns: 60
---
You are the engineering orchestrator for the Communication Hub.

WORKFLOW (sequential, with parallel waves):
1. Read docs/rigor-level.md and CLAUDE.md
2. Read docs/adr/ and docs/domain-glossary.md
3. ENTER PLAN MODE. Decompose the goal into:
   - Wave 1: Product (product-owner subagent) → user stories + acceptance criteria
   - Wave 2: Design (architect subagent) → ADR + sequence diagrams + ports/adapters
   - Wave 3: Implement (1-3 developer subagents in parallel, each in own worktree)
   - Wave 4: Verify (qa-engineer subagent) → unit + integration + contract tests
   - Wave 5: Deploy (devops subagent) → CI/CD + observability
   - Wave 6: Promote (marketing subagent + sales-feedback subagent)
4. Present plan with cost estimate (token budget per wave) and EXIT plan mode for approval
5. Execute waves. Use isolation:worktree for parallel developers.
6. After each wave, summarize and decide go/no-go for next wave
7. On Wave 4 failure, dispatch developer subagent with QA report; max 2 fix iterations
8. Final integration phase: rebase all worktrees, run full mvn verify, write release notes

NEVER edit src/main/java/**/domain/** with Spring annotations.
NEVER skip the architect wave when rigor-level=production.
ALWAYS write summary to .claude/runs/<timestamp>.md
```

**Esempio developer agent** (calibrato sui tuoi standard):

```markdown
---
name: developer
description: Implements Spring Boot features with hexagonal/DDD/SOLID rigor.
tools: Read, Write, Edit, Bash(mvn *), Bash(git *), Glob, Grep
model: sonnet
isolation: worktree
maxTurns: 30
skills:
  - ddd-conventions
  - solid-checklist
  - spring-boot-patterns
---
You are a senior Spring Boot engineer. The architect has produced design artifacts in docs/adr/.

CONTRACT:
1. Read the assigned ADR and the relevant domain-glossary entries
2. Create ports (interfaces) in com.example.hub.<context>.domain
3. Implement domain logic with NO framework dependencies
4. Implement adapters in infrastructure/, use constructor injection
5. Write JUnit5 tests: domain (unit, mockito-free preferred), application (mocked ports),
   infrastructure (Testcontainers if DB/Kafka)
6. Run `mvn test -pl <module>` after EVERY logical change
7. Commit with conventional commits: feat(<context>): <what>
8. Open PR draft via gh CLI when wave is complete

CHECKLIST BEFORE DECLARING DONE:
- [ ] No @Service/@Component/@Repository in domain/
- [ ] No setters on aggregates (use commands)
- [ ] All collaborators injected by constructor
- [ ] No `instanceof` chains (use polymorphism)
- [ ] Public methods <20 lines, classes <200 lines (warning, not blocker)
- [ ] mvn verify green
```

**Hook deterministico** (`hooks/block-domain-spring-leak.sh`):

```bash
#!/usr/bin/env bash
# pre-tool hook: blocca scrittura di file domain/ con annotation Spring
file="$1"
if [[ "$file" == *"/domain/"* ]]; then
  if grep -qE "@(Component|Service|Repository|Autowired|RestController)" /tmp/claude-pending-content; then
    echo "BLOCKED: Spring annotation in domain layer violates hexagonal architecture (CLAUDE.md §SOLID)" >&2
    exit 1
  fi
fi
exit 0
```

**Cron run autonomo notturno** (`scripts/autonomous-run.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /Users/stefano/code/communication-hub-autonomous
source .env

GOAL=$(cat .claude/runs/next-goal.md)  # tu lo scrivi prima di andare a dormire
TS=$(date +%Y%m%d-%H%M)

claude -p "@orchestrator: $GOAL" \
  --bare \
  --allowedTools "Read,Write,Edit,Bash(mvn *),Bash(git *),Bash(gh *),TodoWrite,mcp__github,mcp__linear" \
  --max-turns 200 \
  --max-budget-usd 12 \
  --output-format stream-json \
  --verbose \
  > ".claude/runs/${TS}.ndjson" 2> ".claude/runs/${TS}.err"

# Notifica a Slack via MCP separato (HTTP)
jq -r '.messages[-1].content' < ".claude/runs/${TS}.ndjson" | \
  curl -s -X POST -H "Content-Type: application/json" \
       --data "{\"text\": $(jq -Rs .)}" "$SLACK_WEBHOOK"
```

**Crontab** (`crontab -e`):

```
0 1 * * * /usr/bin/env bash -c 'source /Users/stefano/.zshrc && /Users/stefano/code/communication-hub-autonomous/scripts/autonomous-run.sh' >> /Users/stefano/.cron.log 2>&1
```

**Esempio flusso end-to-end**:

1. La sera prima Stefano scrive `.claude/runs/next-goal.md`: *“Aggiungi rate-limiting per-tenant al Messaging context, prototype-grade ok”*
1. Imposta `docs/rigor-level.md` = `prototype`
1. Cron alle 01:00 lancia lo script → orchestrator entra in plan mode → decompone in 6 wave
1. Product-owner genera 3 user stories in `docs/stories/`
1. Architect genera ADR-0042 + sequence diagram
1. Developer implementa in worktree `.claude/worktrees/feat-rate-limit/`, scrive port `RateLimiter` in domain, adapter Redis in infra, test
1. QA-engineer esegue `mvn verify`, integration test su Testcontainers Redis → passa
1. DevOps aggiorna `docker-compose.yml` con redis service e action workflow CI
1. Orchestrator merge il worktree in `main` con rebase, apre draft PR
1. Marketing (haiku via OpenRouter, ~$0.01) scrive 3 varianti di release-note + tweet
1. Stefano alle 8:00 trova: PR draft + release notes + Slack summary “feature implemented in 47min, $4.20 spent, 0 hooks blocked”

**Stime**:

- **Time-to-first-prototype**: 1-2 giorni di setup, primo run autonomo riuscito entro fine giorno 2
- **Costo mensile** (Max 5× a $100 + ~$5 OpenRouter per marketing/sales): **~$105/mese**, fino a **~$205** se passi a Max 20× per overflow API
- **Autonomia**: cron-driven, file system come stato persistente (no DB), git come single source of truth
- **Prototype vs production-grade**: file `docs/rigor-level.md` letto da CLAUDE.md → ogni agent decide branching del workflow. Prototype salta wave architect e qa-integration; production li forza.
- **Feedback loop**: nightly script `close-loop.py` (Python minimo) tira analytics da Posthog/Sentry MCP → scrive `docs/feedback/<date>.md` → product-owner agent al run successivo legge questo file e formula nuove user story
- **Debolezze oneste**: token burn alto se `--max-budget-usd` non è ben tarato; debug difficile (NDJSON è verbose), nessuna persistenza di stato strutturato (tutto file), Agent Teams ancora sperimentali quindi se vuoi parallelismo vero usi worktree+subagent (non lead+teammates), se Anthropic ha outage il run muore (mitigation: OpenRouter Anthropic Skin per failover Vertex/Bedrock)

### Architettura B — “Claude Code + lightweight orchestrator” (mid setup time)

**Filosofia**: thin layer Python in CrewAI (più veloce a partire) o LangGraph (più robusto) che chiama Claude Code in headless mode per la fase coding e OpenRouter (DeepSeek V4 Pro, GLM, Llama, Gemini Flash) per la fase non-coding. Stato persistente in **SQLite** (overkill su Postgres per single-user). Trigger via **n8n** (che già ti gira sul Proxmox).

**Stack**:

```
proxmox-vm-orchestrator/
├── crew/
│   ├── pyproject.toml           # crewai, anthropic, openai, claude-code-sdk
│   ├── crew.py                  # Crew + Agents + Tasks
│   ├── tools/
│   │   ├── claude_code_runner.py   # Tool: subprocess claude -p
│   │   ├── github_tool.py
│   │   └── analytics_tool.py
│   ├── state.db                 # SQLite (tasks, runs, costs, feedback)
│   └── triggers/
│       └── n8n-webhook.py       # FastAPI endpoint /trigger
└── docker-compose.yml           # n8n + the crew + sqlite-web
```

**Esempio crew.py minimal**:

```python
from crewai import Agent, Task, Crew, Process
from crewai.llm import LLM
from tools.claude_code_runner import ClaudeCodeTool

opus    = LLM(model="anthropic/claude-opus-4.6", api_key=ANTHROPIC_KEY)
sonnet  = LLM(model="anthropic/claude-sonnet-4.6", api_key=ANTHROPIC_KEY)
cheap   = LLM(model="openrouter/deepseek/deepseek-v4-pro", api_key=OR_KEY,
              base_url="https://openrouter.ai/api/v1")

product = Agent(role="Product Owner", goal="...", backstory="...", llm=sonnet)
architect = Agent(role="DDD Architect", goal="...", llm=opus)
developer = Agent(role="Spring Boot Engineer", goal="...", llm=sonnet,
                  tools=[ClaudeCodeTool()])  # delega il coding vero a `claude -p`
qa       = Agent(role="QA", goal="...", llm=sonnet, tools=[ClaudeCodeTool()])
devops   = Agent(role="DevOps", goal="...", llm=sonnet, tools=[ClaudeCodeTool()])
marketing = Agent(role="Marketing", goal="...", llm=cheap)   # OpenRouter, $0.001/1k
sales    = Agent(role="Sales-Feedback", goal="...", llm=cheap)

t1 = Task(description="Break down: {goal}", agent=product, output_file="out/stories.md")
t2 = Task(description="Design from stories.md", agent=architect, context=[t1])
t3 = Task(description="Implement design via Claude Code subagents",
          agent=developer, context=[t2])
# ...

crew = Crew(agents=[product, architect, developer, qa, devops, marketing, sales],
            tasks=[t1, t2, t3, ...], process=Process.sequential, memory=True)

result = crew.kickoff(inputs={"goal": sys.argv[1], "rigor": sys.argv[2]})
```

**Il `ClaudeCodeTool`** è un wrapper che fa `subprocess.run(["claude", "-p", prompt, "--bare", "--output-format", "stream-json", ...])` dentro il working dir del repo target → il developer agent CrewAI parla in linguaggio naturale, ma quando deve “scrivere codice” delega tutto al Claude Code subscription, sfruttando subagent + worktree + hooks definiti nel repo. Risultato: paghi a token solo CrewAI (ruoli “thinking”) e i subagent Claude Code con il subscription (ruolo “doing”).

**Trigger n8n**: webhook on schedule (daily 2am) o on event (Linear issue labeled `autonomous`, Sentry incident severity ≥ high) → POST a `/trigger` con body `{"goal": "...", "rigor": "production"}`.

**Stime**:

- **Time-to-first-prototype**: 4-7 giorni (CrewAI base in 1 giorno, integrazione Claude Code 1-2 giorni, n8n trigger + persistenza 1-2 giorni, taratura prompt 2 giorni)
- **Costo mensile**: $100 (Max 5×) + $20-40 OpenRouter (DeepSeek/Gemini Flash per Product/Architect “thinking” + marketing/sales) = **$120-140/mo**
- **Autonomia**: persistent task queue in SQLite, n8n cron + event triggers, retry logic in CrewAI Flows
- **Rigor-parameter**: passato come input a Crew.kickoff, ogni Agent ha system-prompt branching su rigor; in production si abilita uno step extra `architect-review` e si forza coverage threshold
- **Feedback loop**: n8n flow ogni mattina pulla analytics → scrive in SQLite tabella `feedback` → la Crew successiva la consuma come `inputs={'last_week_feedback': ...}`
- **Debolezze**: complessità in più (Python, SQLite, n8n), dependency hell potenziale (CrewAI ha pinning aggressivo), debug più difficile (3 layer: n8n, Crew, Claude Code), latency aggiunto

### Architettura C — “MetaGPT/ChatDev come brain, Claude Code come hands” (highest setup time)

**Filosofia**: usi MetaGPT (più software-centric) o ChatDev 2.0 (più visual/general) come orchestratore high-level con i ruoli built-in, e li configuri perché il “engineer” sia in realtà un wrapper che chiama Claude Code in headless. Cervello SOP-driven, mani Claude.

**Pro**: ottieni gratis i ruoli e gli artefatti (PRD, design, tasks) di MetaGPT, sfrutti gli SOP testati su milioni di esempi. **Contro**: il prompt-set MetaGPT è frozen sui suoi standard, **non sui tuoi DDD/SOLID**, quindi devi forkare e riscrivere prompt → setup pesante. ChatDev 2.0 è più malleabile (workflow YAML drag-and-drop) ma più giovane.

**Setup minimo MetaGPT + Claude Code**:

```yaml
# ~/.metagpt/config2.yaml
llm:
  api_type: "anthropic"
  model: "claude-opus-4.6"
  base_url: "https://api.anthropic.com"
  api_key: "$ANTHROPIC_KEY"
```

E poi un custom `Engineer` role che invece di scrivere codice in-memory delega a `claude -p`:

```python
from metagpt.roles import Engineer
class ClaudeCodeEngineer(Engineer):
    async def _act(self):
        spec = self.rc.memory.get(...)
        subprocess.run(["claude", "-p", f"@developer: {spec}",
                        "--bare", "--max-budget-usd", "5"])
        # leggi git diff, restituisci come ActionOutput
```

**Stime**:

- **Time-to-first-prototype**: 7-14 giorni (fork MetaGPT, riscrittura prompt-set per DDD, integrazione Claude Code engineer, debugging SOP)
- **Costo mensile**: $100 Max 5× + $30-80 token Anthropic/OpenRouter (MetaGPT chiama l’LLM autonomamente, non sfrutta il subscription) = **$130-180/mo**, ma può salire molto se MetaGPT entra in loop
- **Autonomia**: CLI MetaGPT (`metagpt "build X"`), può girare in container long-running
- **Rigor-parameter**: complicato — bisogna iniettare nei prompt MetaGPT (i suoi sono opinionated)
- **Feedback loop**: assente nativamente, devi costruirlo (es. Environment shared di MetaGPT con un FeedbackRole)
- **Debolezze**: MetaGPT genera codice “demo-quality” (vedi forum 2024-2025), il fork ti costa mantenance, **doppio token bill** (MetaGPT paga per pensare + Claude Code paga per fare), debugging da incubo (3 layer LLM)

**Verdetto**: utile come esperimento per capire il pattern SOP, ma **per il tuo obiettivo l’Architettura A o B sono nettamente migliori**.

-----

## 4. Raccomandazioni concrete per Stefano

### Quale partire? **Architettura A**.

Razionale: setup-time minimo, sfrutta al massimo il tuo subscription Claude Code (zero overhead di altri provider), git come state-store ti dà debug e rollback gratis, hook deterministici sono il tuo migliore alleato per non far driftare gli agent dai tuoi standard DDD/SOLID. Aggiungi OpenRouter solo per marketing/sales con Opzione 1 (env-var override quando triggeri quei subagent specifici) o Opzione 3 (curl dentro tool ristretto).

**Passa ad Architettura B solo se** dopo 3-4 settimane senti che:

- vuoi orchestrare *più progetti diversi* in parallelo da un dashboard (n8n pulls da multipli repo)
- ti serve persistent state strutturato per analytics multi-mese (SQLite query)
- vuoi mixare modelli per ruolo in modo programmatico ben oltre il subscription

### Piano di partenza giorno-per-giorno (1 settimana)

**Day 0 (sera prima)**: leggi `code.claude.com/docs/en/sub-agents`, `agent-teams`, `headless`, `costs` (1 ora). Decidi tier: ti consiglio **Max 5× a $100/mo** per partire, upgrade a 20× se vedi che bruci il cap.

**Day 1 — Setup base + un agente funzionante**

1. Crea repo `communication-hub-autonomous` con scheletro Java/Spring Boot esistente (anche un fork di tuo lavoro)
1. `mkdir -p .claude/{agents,skills,hooks,commands,runs}`
1. Scrivi `CLAUDE.md` (modello sopra) — **a mano**, niente AI
1. Crea `docs/rigor-level.md` con valore `prototype`
1. Crea `docs/domain-glossary.md` con i 4-5 termini chiave (Message, Tenant, Channel, RoutingRule, AuditEvent)
1. `claude` interattivo, comando `/agents` → crea `developer` con scaffolder, poi rifinisci il file
1. Test: `claude -p "@developer: implementa endpoint GET /health"` → vedi che committa cleanly

**Day 2 — Subagent suite**

1. Definisci i 7 agent (orchestrator, product-owner, architect, developer, qa, devops, marketing) — usa i template del paragrafo 3.A come base
1. Configura `.mcp.json` con github, linear/jira (scegli il tuo), sentry (anche placeholder), slack via webhook
1. Test interattivo: `@product-owner: spec una feature di rate-limiting` → leggi output, raffinare prompt
1. Test orchestrator end-to-end su feature triviale: `@orchestrator: aggiungi un endpoint /version che ritorna versione e build-hash`. Tempo atteso: 5-10 min, costo <$1.

**Day 3 — Hooks & guardrail**

1. Scrivi `block-domain-spring-leak.sh`, `pre-commit-mvn-test.sh`, `pre-tool-bash-allowlist.sh`
1. Registra hook in `.claude/settings.json` (sezione `hooks: { PreToolUse: [...], Stop: [...] }`)
1. Test attivo: chiedi a developer di mettere `@Service` in un domain class → l’hook deve bloccare. Se non blocca, aggiusta.
1. Aggiungi `--max-turns` e `--max-budget-usd` come default in CLAUDE.md

**Day 4 — Skills DDD/SOLID e parametro rigor**

1. Crea skill `ddd-conventions/SKILL.md` con: aggregate roots, value objects, domain events, repository naming, package structure
1. Crea skill `solid-checklist/SKILL.md` con i 5 principi formalizzati e check concreti (es: “no `instanceof`”, “constructor injection only”)
1. Crea skill `spring-boot-patterns/SKILL.md` con i pattern del tuo Communication Hub (canali, retry, idempotency keys)
1. Test: cambia `docs/rigor-level.md` a `production`, rilancia orchestrator → verifica che ora attivi wave architect e qa-integration

**Day 5 — Headless + cron**

1. Scrivi `scripts/autonomous-run.sh` (template sopra)
1. Crea un Slack incoming webhook (o usa l’MCP) per le notifiche
1. Test manuale: `./scripts/autonomous-run.sh` con goal di prova, leggi NDJSON, verifica notifica Slack
1. Aggiungi a crontab. Programma il primo run reale per la notte
1. Imposta `--bare`, allowed tools strict, budget ceiling

**Day 6 — OpenRouter per marketing/sales**

1. Crea key OpenRouter, $10 di credito per partire
1. Decidi pattern: A (env-var override quando lanci marketing-agent in subprocess separato dal main run) o B (curl dentro un tool Bash whitelisted del subagent)
1. Implementa in `marketing.md` e `sales-feedback.md`. Test isolato: marketing agent scrive 5 varianti di release-note per la feature di ieri, costo <$0.05
1. (Opzionale) Installa `claude-code-router` via `npm i -g @musistudio/claude-code-router` e configura un router che usa Haiku 4.5 per qualsiasi subagent con `model: haiku` nel frontmatter, e DeepSeek V4 Pro per quelli marcati `marketing-tier`

**Day 7 — Feedback loop & polishing**

1. Scrivi `scripts/close-loop.py`: query Posthog/Sentry MCP, dump in `docs/feedback/<date>.md`
1. Aggiungi step finale a `autonomous-run.sh` che chiama `close-loop.py` dopo il run
1. Modifica `product-owner.md` perché legga `docs/feedback/` come primo step
1. Installa Conductor (`brew install --cask conductor`) per la review visuale dei worktree quando i run notturni producono PR multiple
1. Documenta tutto in `docs/operations.md` per future-Stefano

### Definizioni high-level dei 6 ruoli ottimizzate per te

**Product Owner** (`product-owner.md`, sonnet):

> Lavora SOLO sull’output, mai sul codice. Input: goal di business + `docs/feedback/`. Output: 3-7 user story in `docs/stories/<sprint>/` con formato Gherkin (`Feature/Scenario/Given/When/Then`), ognuna con: bounded-context targettato, acceptance criteria SMART, NFR (latency, throughput, errore), priorità MoSCoW. Mai inventare nuovi bounded context senza escalation.

**Architect** (`architect.md`, opus, read-only su src/, write-only su docs/):

> Input: stories. Output: ADR numerato in `docs/adr/`, sequence diagram (Mermaid), lista ports/adapters da creare, eventuali nuove ubiquitous-language entry. Applica SEMPRE: hexagonal layering, no leak Spring nel domain, evento-driven cross-context (Kafka), idempotenza, observability (OpenTelemetry tracing). Se la storia richiede un nuovo BC → STOP, escalate.

**Developer** (`developer.md`, sonnet, isolation: worktree):

> Una storia per invocazione (no bundling). Pattern: porta domain prima, test domain (no mock), adapter dopo, integration test con Testcontainers. Constructor injection. Aggregates immutabili (record di Java 21). Commits atomici, conventional. PR draft alla fine. Non cambiare ADR, non cambiare ports decisi dall’architect.

**QA Engineer** (`qa-engineer.md`, sonnet):

> Input: PR draft + ADR + stories. Esegue: `mvn verify`, `pitest` (mutation testing) per moduli critici, OpenAPI contract test contro adapter REST, security scan basico (`mvn dependency-check`). Output: report `qa/<pr>.md` con fail/pass per ogni acceptance criterion, suggested fix. Se fail: ritorna a developer con report (max 2 cicli, poi escalate).

**DevOps** (`devops.md`, sonnet, MCP github/aws/docker):

> Input: PR pronto + release notes. Aggiorna: `Dockerfile`, `docker-compose.yml`, k8s manifest se applicabile, GitHub Actions (`.github/workflows/ci.yml`) con stages build/test/security/deploy-staging, alerting Sentry/Prometheus rule. NON deploya in production senza human approval (escalation policy).

**Marketing** (`marketing.md`, haiku via OpenRouter, MCP slack/postmark, Bash limited):

> Input: release notes + features summary. Output: 3 varianti di tweet, 1 LinkedIn post, 1 changelog entry user-facing, 1 short demo-video script. NON inventa metriche di adozione; chiede sempre dati a `sales-feedback`. Tono: tecnico ma accessibile, lessico inglese (no marketese).

**Sales-Feedback** (`sales-feedback.md`, haiku via OpenRouter, MCP stripe-readonly/posthog):

> Input: window temporale (default 7d). Output: `docs/feedback/<date>.md` con: top 5 feature-request da support tickets, top 3 churn-signal, MAU/conversion delta, suggested next-sprint priorities (input al product-owner). NON tocca production data oltre la lettura, mai write.

### Pitfall da evitare

1. **Token burn**: hard-cap `--max-budget-usd` SEMPRE, fan-out massimo 4 parallel subagent in CLAUDE.md, autocompact sotto controllo (`/compact` manuale prima di task lunghi, custom compact instructions). Per Opus 4.7 stai attento al nuovo tokenizer (+35%): per ora preferisci Sonnet 4.6 come default.
1. **Agent che si pestano i piedi sui file**: SEMPRE `isolation: worktree` per developer paralleli; mai più di un agent che scrive nello stesso path al di fuori dei worktree.
1. **Drift dai tuoi standard DDD/SOLID**: CLAUDE.md scritta da te (Addy Osmani: AI-written CLAUDE = -3% success rate, +20% cost), hooks deterministici, skill `solid-checklist` preloaded esplicitamente nei subagent dev/architect, code-reviewer subagent obbligatorio prima del merge.
1. **Loop runaway**: `--max-turns` per ogni subagent, `--max-budget-usd` totale, hook on-stop che notifica e killa, monitoring con `/usage` periodico. Mai `--dangerously-skip-permissions` fuori da container sandbox.
1. **Sicurezza infra**: gli MCP server con write-permission (AWS, Stripe, deploy) sono accessibili SOLO dal `devops` agent, e quel subagent ha `permissionMode: ask` (non `auto`). Token AWS/Stripe in 1Password CLI o Mac Keychain, mai in `.env` versionato. Read-only token per i ruoli che osservano (sales-feedback su Stripe RO).
1. **Hallucinated requirements**: il product-owner DEVE leggere `docs/feedback/` (un file ground-truth) all’inizio di ogni run; in CLAUDE.md scrivi esplicitamente “non inventare metriche, citare sempre fonti”.
1. **Outage di Anthropic** (è successo aprile-maggio 2026, uptime giù a ~98%): tieni il fallback OpenRouter Anthropic Skin pronto in un alias di shell (`alias claude-or='ANTHROPIC_BASE_URL=https://openrouter.ai/api claude'`), e per i cron run in produzione valuta di avere un secondo workflow su Vertex AI tramite OpenRouter.
1. **Subagent che cercano di spawnare subagent**: documentato come limite — se vedi messaggi “task stuck” pensa a questo. Spostare la logica al livello orchestrator.
1. **Agent Teams resume**: se usi `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, sappi che `/resume` non rianima i teammates. Per cron job preferisci subagent classici, sono stabili.
1. **Costi nascosti del 1M context**: 1M Sonnet costa ~$3 in input per richiesta, $5 su Opus. Filling-it-up senza retrieval mirato è uno spreco; preferisci skill+grep+read targeted a “load tutto”.

-----

## 5. Stato dell’arte fine 2025 / 2026 — cosa funziona davvero

**Il quadro onesto**, sintetizzato dal **2026 Agentic Coding Trends Report di Anthropic** (basato su deployment reali) e da fonti di campo (Heeki Park, Addy Osmani, ksred.com, productcompass.pm, finout.io):

**Cosa funziona davvero in produzione oggi**:

- **Coding agent semi-autonomi guidati da un human-in-the-loop attivo** (Cursor, Claude Code, Windsurf, Cline). Klarna, Replit, Elastic, Uber, LinkedIn, AppFolio (su LangGraph) hanno casi documentati di -80% resolution time su task ben scoped.
- **Pipeline CI/CD con Claude Code in headless mode** per code review, dependency audit, test generation, security scan. Pattern stabile, costi prevedibili (≤$30/dev/active-day mediano in deployment enterprise documentati).
- **Devin (Cognition Labs)** è il caso più estremo di “fully autonomous”: SWE-bench Verified ~90% in early 2026, valuation $25B target, costo $8-9/h. Funziona su ticket ben scoped (CSV export, bug-fix di 2+ ore eng). Non funziona su spec ambigue, codebase legacy senza convention, cross-team coordination. Cisco, Dell, Goldman Sachs, Nvidia clienti enterprise.
- **Agent Teams in Claude Code** funzionano per refactoring, QA swarm, parallel exploration, ma sono *experimental*: Heeki Park documenta task stuck, teammates lost, 4-6 requirement è il sweet spot, ≥10 va in difficoltà.
- **MetaGPT/ChatDev** sono interessanti accademicamente ma la maggior parte dei case study pubblici sono demo da $5-50, non sistemi produzione.

**Cosa NON funziona ancora (modi di fallimento ricorrenti)**:

- **Drift graduale dai requirement** su run multi-ora: il modello mantiene coerenza locale ma perde l’intento globale. Anthropic stessa lo cita nel report — manifestazione subdola, scoperta solo a verification.
- **Verification gap**: i test passano, il codice “sembra” giusto, ma viola convention non scritte o ha bug che richiedono context umano per scoprire. La verification rimane il bottleneck umano.
- **Long-horizon coherence**: oltre le 4-6 ore di run continuo, planning degrada anche con context management sofisticato.
- **Multi-agent orchestration falsa**: la maggior parte dei sistemi multi-agent in produzione sono in realtà sequential pipeline mascherate. Il vero peer-to-peer agentico è ancora raro e fragile.
- **Token economics surprise**: $47K in 3 giorni è documentato (financial services, 23 subagent unattended). Senza budget ceiling è russian roulette.
- **AI-written CLAUDE.md/AGENTS.md**: paper Gloaguen et al. ETH Zurich → -3% success rate medio, +20% inference cost. Il context strategico DEVE essere scritto dall’umano.

**Quanto siamo vicini al “kick off and come back to a finished product”?**

Onestamente: **per progetti greenfield piccoli (≤5K LOC, dominio ben noto, NFR semplici) sì, già oggi funziona**. Devin lo fa, Architettura A che ti ho descritto lo fa, MetaGPT ci prova. Per il **Communication Hub di Stefano (Spring Boot, dominio reale, integration multipla, DDD)**: l’autonomia “kick & forget” è realistica per **feature increment singole** (aggiungi rate-limiting, aggiungi un nuovo channel adapter, aggiungi audit trail su evento X) — non per “build me from scratch”. Il pattern vincente nel 2026 è: **umano spec → agent build feature → umano review PR → agent address comments → merge**. Riduzione effort 60-80% sul lavoro routine, non sostituzione 100%.

**Trend che si stanno consolidando** (segnali forti, non hype):

- **MCP è lo standard** di fatto per tool integration (Anthropic, OpenAI, Google, Microsoft, AWS, Block, Cloudflare, Bloomberg lo backano via Agentic AI Foundation)
- **A2A protocol** sta diventando lo standard per agent-to-agent cross-framework
- **Spec-driven development** (scrivi spec, agent compila) — Mindstudio Remy, Cognition con SWE-grep, Conductor pattern di wshobson — è il direction-of-travel
- **Subscription model con cap** (Claude Pro/Max, Cursor) sta vincendo su pay-per-token per il day-to-day; pay-per-token rimane per overflow e enterprise
- **Code review umana è il bottleneck definitivo**: per un futuro prossimo l’umano resta il last mile

**Mio giudizio su dove sei posizionato**: il tuo profilo (senior, DDD, applica SOLID, ha già homelab e n8n, conosce Claude Code) ti mette nel **top 5% di chi può sfruttare al massimo questa tecnologia OGGI**. Il rischio non è tecnico, è **scope creep**: vuoi costruire l’orchestratore quando dovresti usarlo per spedire feature. Tieni il setup minimale (Architettura A), spedisci 2-3 feature reali del Communication Hub via il sistema autonomo, misura il delta, e solo allora ottimizza. Il pattern Pareto qui è brutale: il 20% di setup ti dà l’80% del valore.

-----

### Riferimenti operativi rapidi

- Doc ufficiale Claude Code: `code.claude.com/docs/en/{sub-agents,agent-teams,headless,costs,hooks,skills,mcp,worktrees}`
- Anthropic best practices: `anthropic.com/engineering/claude-code-best-practices`
- Anthropic 2026 Agentic Coding Trends Report: `resources.anthropic.com/hubfs/2026 Agentic Coding Trends Report.pdf`
- Repo da clonare/studiare: `wshobson/agents` (marketplace), `VoltAgent/awesome-claude-code-subagents` (library), `lst97/claude-code-sub-agents` (full-stack), `ryanmac/code-conductor` (GitHub-native), `barkain/claude-code-workflow-orchestration` (plan-mode plugin), `obra/superpowers` (skill avanzate), `musistudio/claude-code-router` (multi-provider router), `aattaran/deepclaude` (mid-session backend swap)
- Frameworks: `FoundationAgents/MetaGPT`, `OpenBMB/ChatDev` (2.0 / DevAll), `microsoft/agent-framework`, CrewAI docs, LangGraph 1.0 docs, `openclaw/openclaw`
- Comunità/post utili: Addy Osmani “Code Agent Orchestra”, Heeki Park “Collaborating with agent teams” (Medium, mar 2026), alexop.dev “From Tasks to Swarms”, productcompass.pm “Claude Code Limits: 4 Fixes”, finout.io “Claude Code Pricing 2026”, backgroundclaude.com “Headless”

In bocca al lupo Stefano — rimani sul minimal-setup, lascia che siano gli hook a fare da poliziotti, e ricordati: l’orchestratore migliore è quello che spedisce, non quello che è bello.
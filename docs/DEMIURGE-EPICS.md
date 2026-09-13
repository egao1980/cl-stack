# Draft cl-stack epics (paste-ready)

Plan of record: workspace `docs/DEMIURGE-PLAN.md` (2026-09-13). Rows: [AI-GAP.md](AI-GAP.md).

Existing issues — do **not** duplicate:

- [#196](https://github.com/egao1980/cl-stack/issues/196) wire↔board — **shipped** as [`blackboard-wire`](https://github.com/egao1980/blackboard-wire) **0.1.0**. Close or retitle when the paste lands.
- [#197](https://github.com/egao1980/cl-stack/issues/197) demiurge rewrite — **still open**. Paste §5 as a comment / body refresh, not a new issue.

`gh` is read-only here. File by pasting. Wave-1 protocols already exist; bodies record shipped vs leftover so the issues track the remaining work, not a greenfield start.

---

## 1. `[epic] eval-protocol — datasets, scorers, gates`

```markdown
## Priority
P1. Shipped **0.1.0**. Tracking leftover is none on the critical path — B2 consumes this.

## Domain
eval (AI)

## Disposition
[`eval-protocol`](https://github.com/egao1980/eval-protocol) (`stack-eval`). Core dep-free. `/judge` holds the `llm-protocol` dep. Not LangGraph.

## Demand
Golden-set evals + promotion gates for demiurge A/B KS trials. Feedback ingest (`add-case` `:source :human-feedback`) is the B3 close-the-loop point.

## Protocol surface (shipped)
- `eval-case` / `eval-dataset` / `eval-score` / `eval-run`
- `score-case`, `run-eval`, `eval-report`
- scorers: exact-match, contains, numeric-tolerance, rubric; `llm-judge-scorer` in `/judge`
- versioned datasets (content-hash); `add-case` → new version
- `gate-passes-p`: `mean-improvement-gate`, `no-critical-regression-gate`
- conditions + `skip-case` / `retry-case` / `score-as-failure`

## Depends on
None remaining. Plan: workspace `docs/DEMIURGE-PLAN.md` A1. Companion [AI-GAP.md](https://github.com/egao1980/cl-stack/blob/main/docs/AI-GAP.md).

## Done when
- [x] Core GFs + built-in scorers + gate policies + Rove
- [x] `/judge` against mock `llm-protocol`
- [ ] Consumed by demiurge `/improve` (B2) — product work, not this repo

## Non-goals
LangGraph. Product controller. Hosted eval SaaS.
```

---

## 2. `[epic] llm-protocol/router — fallback, budget, tokens`

```markdown
## Priority
P1. Shipped in `llm-protocol` **0.3.0**. Leftover: A7b GenAI spans (not this subsystem).

## Domain
llm (generation)

## Disposition
Subsystem `llm-protocol/router` (precedent: `/capability`, `/schema`). Composition, not a product backend. Not LiteLLM.

## Demand
Fallback / budget / token-window so conversation 0.2 and demiurge spend accounting have one source of truth.

## Protocol surface (shipped)
- `llm-router-backend` implements the full GF surface by delegating through a `routing-policy`
- policies: `fallback-chain-policy`, `budget-policy`, `least-latency-policy` (wrap)
- `llm-budget`; `llm-budget-exceeded` + `use-cheaper-model` / `continue-anyway` / `abort-generation`
- core GFs: `count-tokens`, `context-window`, `fit-turns`

## Leftover (A7b, separate)
`llm-protocol/telemetry` — `gen_ai.*` spans on `generate` / `respond` / `embed`. Does not block B1.

## Depends on
Shipped. Consumers: conversation **0.2.0**, plan A2. [#197](https://github.com/egao1980/cl-stack/issues/197) B5 reads the budget counters.

## Done when
- [x] `/router` + token GFs + Rove (`router-test`, `tokens-test`)
- [ ] `llm-protocol/telemetry` GenAI semconv (A7b)

## Non-goals
Prompt cache (`cache_control` / `prompt_cache_key`) — P2. Audio / realtime parts — P2.
```

---

## 3. `[epic] task-protocol — durable journal, timers, trees`

```markdown
## Priority
P1. Protocol **0.1.0** + `task-backend-sql` **0.1.0** shipped. **A6b is the remaining B1 gate.**

## Domain
task (execution)

## Disposition
[`task-protocol`](https://github.com/egao1980/task-protocol) (`stack-task`) + [`task-backend-sql`](https://github.com/egao1980/task-backend-sql). Temporal-shaped CLOS, not a DSL. In-memory colocated for tests.

## Demand
Kill-and-resume HITL, deep-research fan-out, scheduled improvement cycles. Single persistence spine for agent steps and blackboard section writes — **that integration is A6b, not done**.

## Protocol surface (shipped)
- `durable-task`, event-sourced journal (`append-event` / `replay-journal`)
- `with-durable-step` + idempotency keys
- `schedule-wake` / `schedule-recurring` (cron via `datetime-protocol`)
- `spawn-child-task` / `join-children` (`:all` / `:any` / `:quorum`)
- `compact-journal`, `retention-policy`, `redact-event` (secrets as `secrets-protocol` refs)
- SQL journal + worker leases

## Leftover (A6b — gates B1)
- `ai-agent-protocol` **0.3** `:durability` — journal each model call + tool invocation; HITL approve/deny resumes
- blackboard persistence = journal events for section writes + KSAR agenda + workspace fork/merge
- no parallel snapshot layer

## Depends on
A6 protocol: done. A6b → B1 → B2/B4. Plan A6. Sibling wire: [#196](https://github.com/egao1980/cl-stack/issues/196) shipped.

## Done when
- [x] journal / replay / timers / trees / compact / redaction + SQL backend
- [ ] agent `:durability` (A6b)
- [ ] blackboard journal persistence (A6b)

## Non-goals
Multi-node board. Distributed Temporal cluster. In-process CL sandbox (that's `compute-protocol`).
```

---

## 4. `[epic] enterprise tier-1 — identity, MQ, object store, IMAP, extract, cache`

```markdown
## Priority
P2. Protocols **0.1.0** shipped (mail **0.2.0** for IMAP). Leftovers: C2b canaries, C3b pdfium. C4/C5 are product/profile, not this epic.

## Domain
enterprise (identity / messaging / storage)

## Disposition
First-class `*-protocol` + `*-backend-*`. Vendor SaaS stays on the MCP client bridge. Do not clone boto3 / official SDKs.

## Shipped
- [`ldap-protocol`](https://github.com/egao1980/ldap-protocol) + OIDC on `cl-stack-oauth2` / `cl-stack-jwt`
- [`mq-protocol`](https://github.com/egao1980/mq-protocol) + `mq-backend-amqp` (pure CL) + `mq-backend-kafka` (librdkafka overlay)
- [`object-store-protocol`](https://github.com/egao1980/object-store-protocol) + S3 (SigV4)
- IMAP in `mail-protocol` **0.2.0**
- [`doc-extract-protocol`](https://github.com/egao1980/doc-extract-protocol) — HTML + OOXML; **PDF stub**
- [`cache-protocol`](https://github.com/egao1980/cache-protocol) + redis/RESP3

## Leftover
- **C2b** parity canaries vs dockerized OpenLDAP, RabbitMQ, Redpanda, MinIO, Valkey (same shape as `mcp-parity`)
- **C3b** `doc-extract-backend-pdf` pdfium CFFI overlay
- **C4** (in demiurge, [#197](https://github.com/egao1980/cl-stack/issues/197)): OIDC/LDAP → catalogues, Postgres everywhere, tenant scope key
- **C5** tier 2: GraphQL, SCIM, ssh/sftp, WebDAV/CalDAV, OpenSearch

## Depends on
C1–C3 protocols: done. C4 needs B1+B3+B5 + this. Plan Track C.

## Done when
- [x] ldap + OIDC
- [x] mq + amqp/kafka
- [x] S3 + IMAP + cache + doc-extract (HTML/OOXML)
- [ ] C2b canaries
- [ ] C3b pdfium
- [ ] C4/C5 tracked on [#197](https://github.com/egao1980/cl-stack/issues/197), not here

## Non-goals
SOAP. Hosted vector stores. Official AWS SDK clone. SCIM in wave 1.
```

---

## 5. Refresh [#197](https://github.com/egao1980/cl-stack/issues/197) — do not open a second issue

Paste as a **comment** (or replace the body). Original #197 predates the stack protocols and still says “bootstrap on pre-stack SDKs”.

```markdown
## Status (2026-09-13)

Plan of record: workspace `docs/DEMIURGE-PLAN.md`. Companion: [AI-GAP.md](https://github.com/egao1980/cl-stack/blob/main/docs/AI-GAP.md). Wire adapters [#196](https://github.com/egao1980/cl-stack/issues/196) shipped as `blackboard-wire` 0.1.0.

**Do not revive `egao1980/demiurge`.** Fresh checkout `demiurge/` — composition product only. No `cl-mcp-sdk` / `cl-a2a` / `cl-openai` / dexador / hunchentoot.

Wave-1 protocols are in. Critical path: **A6b** (`ai-agent-protocol` 0.3 `:durability` + blackboard journal) → **B1** core → B2–B6 in parallel → **C4**. A7b / C2b / C3b are parallel loose ends.

## Subsystems (still unstarted)

- **B1** `demiurge` core — `defexpert`, `expert-domain`, `agent-ks`, controller, personal profile (SQLite + llama.cpp / LM Studio)
- **B2** `/improve` — `versioned-ks`, sandboxed candidates, COW A/B, eval gates, provenance
- **B3** `/serve` + `/ingest` — MCP / A2A / AG-UI / TUI over `blackboard-wire`; durable ingest; feedback → `eval-protocol`
- **B4** `/workflows` — durable projects + deep-research fan-out
- **B5** `/observe` — span/metric taxonomy, health/ready, Grafana compose (wants A7b for GenAI span content)
- **B6** `/bundle` — expert OCI artifacts; pack / install / rollback
- **C4** corporate profile — OIDC/LDAP authz, Postgres, tenant scope key
- **C5** tier 2 — after MVP

## Done when (supersedes original checklist)

- [ ] README + architecture (core vs adapters; no pre-stack SDKs)
- [ ] B1 reference expert runs on KSAR / `requeue-ksar`
- [ ] B2 improve cycle promotes only when A1 gates pass
- [ ] B3 serve + ingest + feedback capture
- [ ] B4 kill-and-resume deep-research e2e
- [ ] B5 taxonomy + `/healthz` `/readyz`
- [ ] B6 pack/install/rollback as durable tasks
- [ ] C4 config switch personal→corporate

## Non-goals
Autolith / live-image. Replacing `cl-mcp` Lisp-tools. Multi-node board. LangGraph clone.
```

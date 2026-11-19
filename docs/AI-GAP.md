# AI protocol / backend gaps vs Python / Node / Java

Scored **2026-09-14** against GitHub `main` + GHCR pins after Tracks A / B / C1–C4; versions and the long-run agent rows refreshed **2026-11-18** against GHCR tags (plan of record: workspace `docs/DEMIURGE-PLAN.md`). Companion to [STDLIB-GAP.md](STDLIB-GAP.md) — that file is ANSI batteries; this one is the LLM / agent layer. Draft issue bodies: [DEMIURGE-EPICS.md](DEMIURGE-EPICS.md).

**Comparators**

| Ecosystem | Generation | Agents | Wire | RAG / memory |
|-----------|------------|--------|------|--------------|
| Python | OpenAI / Anthropic / Google SDKs, LiteLLM | PydanticAI, LangGraph, CrewAI / AG2, OpenAI Agents SDK | FastMCP 3, official MCP, A2A Python | LlamaIndex, LangChain, Instructor |
| Node | Vercel AI SDK 6, LangChain.js | AI SDK `Agent` / `DurableAgent`, Mastra | official MCP TS, CopilotKit / AG-UI | Mastra, LlamaIndex.TS |
| Java | Spring AI 2.0, LangChain4j | Spring advisors, `langchain4j-agentic` | Spring MCP starters, LangChain4j MCP + A2A | Spring advisors, LangChain4j stores |

Do **not** clone LangChain. Locked split: protocol GFs + thin backends + product (`demiurge`) above. Gaps are missing *protocols or backends*, not a kitchen-sink facade.

---

## Verdict

**Wire is competitive.** Dual-era MCP, three A2A bindings, AG-UI 36-event + `/client` + TUI, and a CLOS agent loop with HITL / handoffs / parallel tools / permissions / background subagents are on-par with 2026 Java/TS agent kits.

**Generation shipped past wave-1.** `llm-protocol` **0.3.0** added `/router` (fallback / budget / latency policies) plus `count-tokens` / `context-window` / `fit-turns` and `/telemetry` (`gen_ai.*` spans, A7b); **0.4.0** adds `retry-policy` by failure class (`llm-retry-class`), `llm-context-overflow`, cache-aware `llm-usage` and `anchored-token-count`. Catalog + `embed` / stream stay. OpenAI-compat **0.3.2** streams chat + Responses and hits `/embeddings`; image-input wire shipped. Anthropic Messages **0.2.0** (official / vLLM / llama-server, same class; native tools official-only, `:compat` flattens; image-input wire; prompt-cache breakpoints, API-side compaction, `Retry-After`). Native `llama-cpp` **0.2.0** (ABI 4; natives through `asdf-native`) + `llm-backend-llama-cpp` **0.1.5** generate / stream / embed / GBNF tools / Lisp chat templates (`:chatml` / `:llama3`). No GGUF Jinja (ABI 5).

**RAG P0 shipped.** `rag-protocol` **0.1.3** (`ingest` / `retrieve` with time / kind filters / `analyze` / `fuse` / `encode-sparse`) + memory / SQL cosine + pgvector ANN + hybrid BM25 + tsvector / SPLADE / cross-encoder + `rag-backend-text` **0.2.0** (`block-tree-chunker`). Embeddings stay on `llm-protocol`.

**Conversation memory shipped.** `conversation-protocol` **0.3.0** (buffer / window / `summary-memory` / `token-window-memory`; `compact-turns`: templated summary + verbatim token tail) + [`conversation-backend-sql`](https://github.com/egao1980/conversation-backend-sql) **0.1.0**. Agent `:memory` unchanged; agent `:compaction` uses `compact-turns`.

**Steering shipped.** `steer-protocol` **0.3.0** — `SKILL.md` + tool-bearing skills + git-backed versioned store; path-scoped `AGENTS.md` discovery (`instruction-discovery`) + `build-system-prompt`. Agent `:steering` and `:instructions-discovery`. Not A2A `agent-skill`. [#198](https://github.com/egao1980/cl-stack/issues/198) closed into 0.1.0.

**Evals shipped.** [`eval-protocol`](https://github.com/egao1980/eval-protocol) **0.3.0** — datasets (roles, paired trials, promotion stages), scorers, `/judge`, gate policies, calibration metrics (Brier / ECE) + drift reports. Not LangGraph.

**Long runs shipped.** `ai-agent-protocol` **0.6.0** (0.7.0: `:durability` journals subagents, inbox and injected instructions): retries by failure class, agent-side compaction (and once on context overflow), max-steps wrap-up, typed tool failures (`tool-input-error` / `tool-unavailable` / `tool-timeout`), permission rules (`:allow` / `:deny` / `:ask`, last match wins, policy layer), background subagents, lazily discovered `AGENTS.md`. Walkthrough: [agent harness tutorial](tutorials/agent-harness.md).

**Still missing as protocols:** audio/realtime (A11 / P2); prompt cache on the OpenAI wire (`prompt_cache_key`, cached-token usage). Router/budget/tokens, durability, GenAI spans, Anthropic prompt cache, and the corporate profile are no longer gaps.

Blackboard KSAR is a *different* orchestration model (not a missing LangGraph).
[#196](https://github.com/egao1980/cl-stack/issues/196) wire adapters shipped as [`blackboard-wire`](https://github.com/egao1980/blackboard-wire) **0.1.0**.
[#197](https://github.com/egao1980/cl-stack/issues/197) product rewrite: B1–B6 + C4 shipped (`demiurge` **0.4.2**, decision KS + memory chronicle adapter, published). Remaining wrap-up = B7c S9-corporate + B8 v2 demos — not the product hole.

**Shipped leftovers:** A6b durability, A6d CI, A7b GenAI spans, C2b parity canaries, C3b pdfium source + native overlays (`doc-extract-backend-pdf` **0.1.4**, optional `asdf-native` component; linux amd64/arm64, darwin arm64, windows amd64). **C5 HOLD** (GraphQL, SCIM, ssh/sftp, WebDAV/CalDAV, OpenSearch, webhooks — do not spec further).

---

## Inventory (what exists)

| Layer | Repo | Ver | Role | Hole |
|-------|------|-----|------|------|
| Generate | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.4.0** | Turns + parts + items; `generate` / stream / `embed`; catalog; `retry-policy` + `llm-retry-class`; `llm-context-overflow`; cache-aware usage; `/router`; `count-tokens` / `context-window` / `fit-turns`; `/telemetry` (`gen_ai.*`); mock; schema `:output`; `/capability` | No audio/file/video parts (A11) |
| OpenAI wire | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | **0.3.2** | `/chat/completions` + `/responses` + `/embeddings` + stream; image-input parts | No audio / realtime / batches / files / vector stores; no `prompt_cache_key` / cached-token usage |
| Anthropic wire | [`llm-protocol-anthropic`](https://github.com/egao1980/llm-protocol-anthropic) | **0.3.0** | `POST /v1/messages` + SSE; official / vLLM / llama-server; native tools (`:dialect :compat` flattens); image-input parts; `:prompt-cache` breakpoints (`cache_control`), `:server-compaction`, `Retry-After`, overflow → `llm-context-overflow` | No embeddings; vLLM tools need `--enable-auto-tool-choice` |
| Native GGUF | [`llama-cpp`](https://github.com/egao1980/llama-cpp) **0.2.0** + [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) **0.1.5** | `libllamastack` ABI 4 via `asdf-native` (optional CUDA libs); generate / stream / embed; GBNF tools; `:chat-template` | No GGUF Jinja (ABI 5). Grammar/stream/` :parsed` need matching overlay |
| Agent loop | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.9.0** | `run-ai-agent(-async)`, function tools, nested agent-as-tool, `:handoffs`, HITL, `:memory`, `:steering`, `:durability` (A6b/A6d), `/telemetry`; retries, compaction, max-steps wrap-up, typed tool failures, permissions, background subagents, `:instructions-discovery` | Evals are `eval-protocol`, not a graph. Durability does not journal subagents / inbox / injected instructions |
| Conversation | [`conversation-protocol`](https://github.com/egao1980/conversation-protocol) **0.3.0** + [`conversation-backend-sql`](https://github.com/egao1980/conversation-backend-sql) **0.1.0** | session + buffer / window / summary / token-window; `compact-turns`; SQL store | — |
| Steering | [`steer-protocol`](https://github.com/egao1980/steer-protocol) | **0.3.0** | `SKILL.md` + tool-bearing skills + git versioned store; `instruction-discovery` (`AGENTS.md`); `build-system-prompt` | Not A2A `agent-skill` |
| MCP sampling + tools | `ai-agent-protocol/mcp` | **0.1.0** | `create-message` → `generate`; `make-mcp-tool-source` | **Not** `llm-protocol/mcp` (does not exist) |
| AG-UI encode | `ai-agent-protocol/ag-ui` | **0.2.0** | `on-event` → AG-UI events | — |
| A2A expose | `ai-agent-protocol/a2a` | **0.1.0** | Sync `run-ai-agent` → completed task + text artifact | No stream / input-required / artifacts beyond text |
| MCP | [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) **0.3.1** + stdio **0.2.0** + Streamable HTTP **0.3.0** | dual-era; tools/resources/prompts + sampling GFs; tool annotations, server notifications, templated resources + `resources/subscribe`, tool-argument repair | Auth / OAuth / Tasks = non-goal |
| A2A | [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) **0.2.0** + jsonrpc **0.2.2** + httpjson **0.2.1** + grpc **0.2.0** | Card + tasks + stream | Push notifications refuse |
| AG-UI | [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) **0.4.1** + SSE **0.2.1** + protobuf **0.4.0** (WKT + official `Event` oneof, `ag-ui-protocol/proto`) + TUI **0.1.0** + `/client` (`json-patch`) | all 36 events; chunks; interrupts | WKT Lisp-only in canary |
| Blackboard | [`blackboard-protocol`](https://github.com/egao1980/blackboard-protocol) **0.2.3** + [`blackboard-journal`](https://github.com/egao1980/blackboard-journal) **0.1.0** + `capability-protocol` **0.2.3** | KSAR + COW; `:llm` / `:world` vocab; journal persist (A6b); policy + decision interceptors | Zero LLM/wire deps (locked) |
| Wire adapters | [`blackboard-wire`](https://github.com/egao1980/blackboard-wire) | **0.1.0** | MCP / A2A / AG-UI ↔ board + capability projection ([#196](https://github.com/egao1980/cl-stack/issues/196)) | Core asd still wire-free |
| Evals | [`eval-protocol`](https://github.com/egao1980/eval-protocol) | **0.3.0** | datasets (versioned, feedback ingest, roles), paired trials, promotion stages, scorers, `/judge`, gate policies, calibration (Brier / ECE) + drift | Not LangGraph |
| Durable tasks | [`task-protocol`](https://github.com/egao1980/task-protocol) **0.2.2** + [`task-backend-sql`](https://github.com/egao1980/task-backend-sql) **0.1.1** | journal, replay, timers/cron, trees, compact/redact; versioned event schema, activation identity, effect receipts; `/telemetry` **0.1.0** | Agent `:durability` + blackboard journal shipped (A6b) |
| Telemetry | [`telemetry-protocol`](https://github.com/egao1980/telemetry-protocol) **0.2.0** + `llm-protocol/telemetry` **0.3.0** | traces + metrics; OTLP + redaction; GenAI semconv spans (A7b) | — |
| Web search | [`websearch-protocol`](https://github.com/egao1980/websearch-protocol) | **0.1.1** | `search-web` / `fetch-page`; SearXNG (HTTP timeouts, binary pages skipped); `:world` op | — |
| Compute | [`compute-protocol`](https://github.com/egao1980/compute-protocol) **0.2.0** + [`compute-backend-podman`](https://github.com/egao1980/compute-backend-podman) **0.2.0** | sandboxed run + limits/net; `egress-rule` / `sandbox-network-policy`; `:compute` ops | — |
| Browser | [`browser-protocol`](https://github.com/egao1980/browser-protocol) | **0.1.0** | CDP + computer-use loop (image input) | OS desktop use = wave 2 |
| LDAP | [`ldap-protocol`](https://github.com/egao1980/ldap-protocol) | **0.1.0** | bind / search / modify; OIDC on `cl-stack-oauth2`; OpenLDAP canary (C2b) | SCIM = C5 HOLD |
| MQ | [`mq-protocol`](https://github.com/egao1980/mq-protocol) **0.1.0** + amqp / kafka | publish / subscribe / ack; AMQP 0-9-1 + librdkafka; RabbitMQ / Redpanda canaries (C2b) | — |
| Object store | [`object-store-protocol`](https://github.com/egao1980/object-store-protocol) **0.1.0** + s3 | put/get/list/presign; SigV4; MinIO canary (C2b) | — |
| IMAP | `mail-protocol` **0.2.0** | SELECT / FETCH / SEARCH / IDLE + MIME | SMTP already shipped |
| Doc extract | [`doc-extract-protocol`](https://github.com/egao1980/doc-extract-protocol) **0.2.0** + pdf **0.1.4** + docling/unstructured/libreoffice/render/render-pdf **0.1.0** | block tree + ids + markup; HTML / OOXML; pdfium CFFI + native overlays (C3b) | — |
| Cache | [`cache-protocol`](https://github.com/egao1980/cache-protocol) **0.1.0** + redis | get/put/ttl/cas; in-memory + RESP3; Valkey canary (C2b) | — |
| RAG | [`rag-protocol`](https://github.com/egao1980/rag-protocol) **0.1.3** + memory / sql / pgvector **0.1.0** / hybrid **0.1.1** / tsvector / splade / cross-encoder / text **0.2.0** | chunk / store / rerank / `ingest` / `retrieve`; ANN + BM25 + FTS + sparse; `block-tree-chunker` (C3d2) | Cross-encoder default is token overlap, not a CE model |
| Product TUI | [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui) **0.1.0**, [`ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) **0.1.0** | desk chat + transcript sink | Not a protocol. `cl-stack-llm-demo` is local (no GHCR) |
| Product | [`demiurge`](https://github.com/egao1980/demiurge) **0.4.2** + [`demiurge-parity`](https://github.com/egao1980/demiurge-parity) **0.1.9** | core / improve / observe / serve / ingest / workflows / bundle + C4 corporate; S1–S8 run; decision KS + memory chronicle adapter, published | B7c S9-corporate still skipped; B8 v2 demos |
| Leftover | [#196](https://github.com/egao1980/cl-stack/issues/196) shipped (`blackboard-wire`); [#197](https://github.com/egao1980/cl-stack/issues/197) wrap-up | B7c / B8 (`demiurge` **0.4.2** published) | C5 HOLD. A11 P2 (audio/realtime; OpenAI prompt-cache usage) | [#198](https://github.com/egao1980/cl-stack/issues/198) → `steer-protocol` **0.3.0** |

Parity canaries: [`mcp-parity`](https://github.com/egao1980/mcp-parity), [`a2a-parity`](https://github.com/egao1980/a2a-parity), [`ag-ui-parity`](https://github.com/egao1980/ag-ui-parity) (SSE JSON full; WKT Lisp-only).

---

## Scorecard

Status: **ahead** / **on-par** / **thin** / **gap** / **leave** (intentional non-goal).

| Capability | cl-stack | Status |
|------------|----------|--------|
| Typed turns + parts | `llm-turn` / `llm-part` | **on-par** |
| Chat + Responses dual grain | `generate` + `respond` | **on-par** |
| HTTP streaming | OpenAI `stream-generate` / `stream-respond`; Anthropic Messages SSE; llama.cpp `stream-generate` | **on-par** (shipped) |
| Embeddings | `embed` / `embed-query`; OpenAI `/embeddings`; llama.cpp GGUF | **on-par** (shipped) |
| Structured output | `:output` + `schema-protocol`; llama.cpp → GBNF | **thin** — parse + `use-value`; no `ModelRetry` (locked) |
| Native GGUF | `llama-cpp` ABI 4 + backend | **thin** — tools via GBNF-constrained `{name,arguments}` (no native tool API in the ABI); no GGUF Jinja templates (needs ABI 5) |
| Provider catalog | `register-provider` / `resolve-backend` on `llm-protocol` **0.4.0** + Anthropic Messages **0.2.0** | **thin** — in-memory only; not LiteLLM |
| Fallback / router / budget | `llm-protocol/router` **0.3.0** — fallback-chain / budget / least-latency | **on-par** (shipped) |
| RAG / vector / chunk / rerank | `rag-protocol` **0.1.3** + memory / sql / pgvector / hybrid / tsvector / splade / CE / text **0.2.0** | **on-par** — ANN + BM25/RRF + FTS + sparse; `block-tree-chunker`; CE hook is `:score-fn` |
| Conversation memory / window | `conversation-protocol` **0.3.0** + SQL store + agent `:memory` / `:compaction` | **on-par** — SQL / summary / token-window / `compact-turns` shipped |
| Token count / context mgmt | `count-tokens` / `context-window` / `fit-turns` / `anchored-token-count`; compaction on overflow; provider compaction on demand (`server-compact`, `:llm-compaction`) | **on-par** (shipped) |
| Retries / backoff | `retry-policy` by failure class; `Retry-After`; agent `:retry-policy` | **on-par** (shipped 0.4.0) |
| Prompt cache | Anthropic `cache_control` breakpoints (`:prompt-cache :auto`) + cache-read/write usage; no OpenAI `prompt_cache_key` | **thin** — Anthropic shipped (0.2.0); OpenAI wire still P2 |
| Image / audio / speech / realtime | image-input wire (OpenAI + Anthropic); `llm-image-part` | **thin** — audio / speech / realtime still P2 |
| Batch / files / vector stores | no | **leave** — hosted OpenAI vector stores still out; in-process store is `rag-backend-memory` |
| Agent loop (HITL / handoff / nested) | `ai-agent-protocol` **0.7.0** | **on-par** — `:durability` shipped (A6b/A6d); retries, compaction, wrap-up, permissions, background subagents shipped |
| Durable execution | `task-protocol` **0.2.2** + SQL journal + agent/board persist | **on-par** (A6b) |
| MCP / A2A / AG-UI wire | dual-era + 3 A2A + 36-event AG-UI + `blackboard-wire` **0.1.0** | **on-par** / **ahead** on AG-UI typing |
| Skills / `SKILL.md` / `AGENTS.md` | `steer-protocol` **0.3.0** + agent `:steering` / `:instructions-discovery` | **on-par** — tool-bearing + versioned store + path-scoped discovery; not A2A `agent-skill` |
| Evals / graph | `eval-protocol` **0.3.0** | **on-par** on evals — not LangGraph (leave) |
| GenAI spans | `llm-protocol/telemetry` **0.3.0** + agent/task `/telemetry` | **on-par** (A7b) |
| Identity / MQ / S3 / IMAP / cache / extract | ldap / mq / object-store / mail 0.2 / cache / doc-extract **0.2.0** + pdfium **0.1.4** | **on-par** — C2b canaries + C3b source and pdfium overlays shipped |
| Demiurge product | [`demiurge`](https://github.com/egao1980/demiurge) **0.4.2** ([#197](https://github.com/egao1980/cl-stack/issues/197)) | **on-par** — B1–B6 + C4 shipped; decision KS + memory chronicle adapter, published; wrap-up = B7c S9 + B8 v2 |
| Corporate profile / tier 2 | C4 shipped in 0.3.5; C5 HOLD | **thin** — S9 live-corporate still skipped; C5 not started |

Tutorial: [agent harness](tutorials/agent-harness.md). Hub cookbooks: [llm](cookbooks/llm.md) · [conversation](cookbooks/conversation.md) · [steer](cookbooks/steer.md) · [rag](cookbooks/rag.md) · [ai-agent](cookbooks/ai-agent.md) · [mcp](cookbooks/mcp.md) · [a2a](cookbooks/a2a.md) · [ag-ui](cookbooks/ag-ui.md).

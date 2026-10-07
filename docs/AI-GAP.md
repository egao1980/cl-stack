# AI protocol / backend gaps vs Python / Node / Java

Scored **2026-09-14** against GitHub `main` + GHCR pins after Tracks A / B / C1–C4 (plan of record: workspace `docs/DEMIURGE-PLAN.md`). Companion to [STDLIB-GAP.md](STDLIB-GAP.md) — that file is ANSI batteries; this one is the LLM / agent layer. Draft issue bodies: [DEMIURGE-EPICS.md](DEMIURGE-EPICS.md).

**Comparators**

| Ecosystem | Generation | Agents | Wire | RAG / memory |
|-----------|------------|--------|------|--------------|
| Python | OpenAI / Anthropic / Google SDKs, LiteLLM | PydanticAI, LangGraph, CrewAI / AG2, OpenAI Agents SDK | FastMCP 3, official MCP, A2A Python | LlamaIndex, LangChain, Instructor |
| Node | Vercel AI SDK 6, LangChain.js | AI SDK `Agent` / `DurableAgent`, Mastra | official MCP TS, CopilotKit / AG-UI | Mastra, LlamaIndex.TS |
| Java | Spring AI 2.0, LangChain4j | Spring advisors, `langchain4j-agentic` | Spring MCP starters, LangChain4j MCP + A2A | Spring advisors, LangChain4j stores |

Do **not** clone LangChain. Locked split: protocol GFs + thin backends + product (`demiurge`) above. Gaps are missing *protocols or backends*, not a kitchen-sink facade.

---

## Verdict

**Wire is competitive.** Dual-era MCP, three A2A bindings, AG-UI 36-event + `/client` + TUI, and a CLOS agent loop with HITL / handoffs / parallel tools are on-par with 2026 Java/TS agent kits.

**Generation shipped past wave-1.** `llm-protocol` **0.3.0** adds `/router` (fallback / budget / latency policies) plus `count-tokens` / `context-window` / `fit-turns` and `/telemetry` (`gen_ai.*` spans, A7b). Catalog + `embed` / stream stay. OpenAI-compat **0.3.0** streams chat + Responses and hits `/embeddings`; image-input wire shipped. Anthropic Messages **0.1.0** (official / vLLM / llama-server, same class; native tools official-only, `:compat` flattens; image-input wire). Native `llama-cpp` **0.1.5** (ABI 4) + `llm-backend-llama-cpp` **0.1.4** generate / stream / embed / GBNF tools / Lisp chat templates (`:chatml` / `:llama3`). No GGUF Jinja (ABI 5).

**RAG P0 shipped.** `rag-protocol` **0.1.2** (`ingest` / `retrieve` / `analyze` / `fuse` / `encode-sparse`) + memory / SQL cosine + pgvector ANN + hybrid BM25 + tsvector / SPLADE / cross-encoder + `rag-backend-text` **0.2.0** (`block-tree-chunker`). Embeddings stay on `llm-protocol`.

**Conversation memory shipped.** `conversation-protocol` **0.2.0** (buffer / window / `summary-memory` / `token-window-memory`) + [`conversation-backend-sql`](https://github.com/egao1980/conversation-backend-sql) **0.1.0**. Agent `:memory` unchanged.

**Steering shipped.** `steer-protocol` **0.2.0** — `SKILL.md` + tool-bearing skills + git-backed versioned store. Agent `:steering`. Not A2A `agent-skill`. [#198](https://github.com/egao1980/cl-stack/issues/198) closed into 0.1.0.

**Evals shipped.** [`eval-protocol`](https://github.com/egao1980/eval-protocol) **0.1.0** — datasets, scorers, `/judge`, gate policies. Not LangGraph.

**Still missing as protocols:** prompt cache, audio/realtime (A11 / P2). Router/budget/tokens, durability, GenAI spans, and the corporate profile are no longer gaps.

Blackboard KSAR is a *different* orchestration model (not a missing LangGraph).
[#196](https://github.com/egao1980/cl-stack/issues/196) wire adapters shipped as [`blackboard-wire`](https://github.com/egao1980/blackboard-wire) **0.1.0**.
[#197](https://github.com/egao1980/cl-stack/issues/197) product rewrite: B1–B6 + C4 shipped (`demiurge` **0.4.2**, decision KS + memory chronicle adapter, published). Remaining wrap-up = B7c S9-corporate + B8 v2 demos — not the product hole.

**Shipped leftovers:** A6b durability, A6d CI, A7b GenAI spans, C2b parity canaries, C3b pdfium source (`doc-extract-backend-pdf` **0.1.1**). **C3b residue:** pdfium native OCI overlay (`publish-oci` in flight). **C5 HOLD** (GraphQL, SCIM, ssh/sftp, WebDAV/CalDAV, OpenSearch, webhooks — do not spec further).

---

## Inventory (what exists)

| Layer | Repo | Ver | Role | Hole |
|-------|------|-----|------|------|
| Generate | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.3.0** | Turns + parts + items; `generate` / stream / `embed`; catalog; `/router`; `count-tokens` / `context-window` / `fit-turns`; `/telemetry` (`gen_ai.*`); mock; schema `:output`; `/capability` | No audio/file/video parts (A11) |
| OpenAI wire | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | **0.3.0** | `/chat/completions` + `/responses` + `/embeddings` + stream; image-input parts | No audio / realtime / batches / files / vector stores |
| Anthropic wire | [`llm-protocol-anthropic`](https://github.com/egao1980/llm-protocol-anthropic) | **0.1.0** | `POST /v1/messages` + SSE; official / vLLM / llama-server; native tools (`:dialect :compat` flattens); image-input parts | No embeddings; no `cache_control`; vLLM tools need `--enable-auto-tool-choice` |
| Native GGUF | [`llama-cpp`](https://github.com/egao1980/llama-cpp) **0.1.5** + [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) **0.1.4** | `libllamastack` ABI 4; generate / stream / embed; GBNF tools; `:chat-template` | No GGUF Jinja (ABI 5). Grammar/stream/` :parsed` need matching overlay |
| Agent loop | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.3.1** | `run-ai-agent(-async)`, function tools, nested agent-as-tool, `:handoffs`, HITL, `:memory`, `:steering`, `:durability` (A6b/A6d), `/telemetry` | Evals are `eval-protocol`, not a graph |
| Conversation | [`conversation-protocol`](https://github.com/egao1980/conversation-protocol) **0.2.0** + [`conversation-backend-sql`](https://github.com/egao1980/conversation-backend-sql) **0.1.0** | session + buffer / window / summary / token-window; SQL store | — |
| Steering | [`steer-protocol`](https://github.com/egao1980/steer-protocol) | **0.2.0** | `SKILL.md` + tool-bearing skills + git versioned store | Not A2A `agent-skill` |
| MCP sampling + tools | `ai-agent-protocol/mcp` | **0.1.0** | `create-message` → `generate`; `make-mcp-tool-source` | **Not** `llm-protocol/mcp` (does not exist) |
| AG-UI encode | `ai-agent-protocol/ag-ui` | **0.2.0** | `on-event` → AG-UI events | — |
| A2A expose | `ai-agent-protocol/a2a` | **0.1.0** | Sync `run-ai-agent` → completed task + text artifact | No stream / input-required / artifacts beyond text |
| MCP | [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) **0.2.0** + stdio **0.1.1** + Streamable HTTP **0.2.0** | dual-era; tools/resources/prompts + sampling GFs | Auth / OAuth / Tasks = non-goal |
| A2A | [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) **0.2.0** + jsonrpc **0.2.1** + httpjson **0.2.0** + grpc **0.2.0** | Card + tasks + stream | Push notifications refuse |
| AG-UI | [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) **0.3.0** + SSE **0.2.1** + protobuf **0.3.0** (WKT) + TUI **0.1.0** + `/client` (`json-patch`) | all 36 events; chunks; interrupts | Official `Event` oneof not compiled. WKT Lisp-only in canary |
| Blackboard | [`blackboard-protocol`](https://github.com/egao1980/blackboard-protocol) **0.2.2** + [`blackboard-journal`](https://github.com/egao1980/blackboard-journal) **0.1.0** + `capability-protocol` **0.2.1** | KSAR + COW; `:llm` / `:world` vocab; journal persist (A6b) | Zero LLM/wire deps (locked) |
| Wire adapters | [`blackboard-wire`](https://github.com/egao1980/blackboard-wire) | **0.1.0** | MCP / A2A / AG-UI ↔ board + capability projection ([#196](https://github.com/egao1980/cl-stack/issues/196)) | Core asd still wire-free |
| Evals | [`eval-protocol`](https://github.com/egao1980/eval-protocol) | **0.1.0** | datasets (versioned, feedback ingest), scorers, `/judge`, gate policies | Not LangGraph |
| Durable tasks | [`task-protocol`](https://github.com/egao1980/task-protocol) **0.1.0** + [`task-backend-sql`](https://github.com/egao1980/task-backend-sql) **0.1.0** | journal, replay, timers/cron, trees, compact/redact; `/telemetry` **0.1.0** | Agent `:durability` + blackboard journal shipped (A6b) |
| Telemetry | [`telemetry-protocol`](https://github.com/egao1980/telemetry-protocol) **0.2.0** + `llm-protocol/telemetry` **0.3.0** | traces + metrics; OTLP + redaction; GenAI semconv spans (A7b) | — |
| Web search | [`websearch-protocol`](https://github.com/egao1980/websearch-protocol) | **0.1.0** | `search-web` / `fetch-page`; SearXNG; `:world` op | — |
| Compute | [`compute-protocol`](https://github.com/egao1980/compute-protocol) **0.1.0** + [`compute-backend-podman`](https://github.com/egao1980/compute-backend-podman) **0.1.0** | sandboxed run + limits/net; `:compute` ops | — |
| Browser | [`browser-protocol`](https://github.com/egao1980/browser-protocol) | **0.1.0** | CDP + computer-use loop (image input) | OS desktop use = wave 2 |
| LDAP | [`ldap-protocol`](https://github.com/egao1980/ldap-protocol) | **0.1.0** | bind / search / modify; OIDC on `cl-stack-oauth2`; OpenLDAP canary (C2b) | SCIM = C5 HOLD |
| MQ | [`mq-protocol`](https://github.com/egao1980/mq-protocol) **0.1.0** + amqp / kafka | publish / subscribe / ack; AMQP 0-9-1 + librdkafka; RabbitMQ / Redpanda canaries (C2b) | — |
| Object store | [`object-store-protocol`](https://github.com/egao1980/object-store-protocol) **0.1.0** + s3 | put/get/list/presign; SigV4; MinIO canary (C2b) | — |
| IMAP | `mail-protocol` **0.2.0** | SELECT / FETCH / SEARCH / IDLE + MIME | SMTP already shipped |
| Doc extract | [`doc-extract-protocol`](https://github.com/egao1980/doc-extract-protocol) **0.2.0** + pdf **0.1.1** + docling/unstructured/libreoffice/render/render-pdf **0.1.0** | block tree + ids + markup; HTML / OOXML; pdfium CFFI source (C3b) | pdfium native OCI overlay (`publish-oci` in flight) |
| Cache | [`cache-protocol`](https://github.com/egao1980/cache-protocol) **0.1.0** + redis | get/put/ttl/cas; in-memory + RESP3; Valkey canary (C2b) | — |
| RAG | [`rag-protocol`](https://github.com/egao1980/rag-protocol) **0.1.2** + memory / sql / pgvector / hybrid **0.1.0** / tsvector / splade / cross-encoder / text **0.2.0** | chunk / store / rerank / `ingest` / `retrieve`; ANN + BM25 + FTS + sparse; `block-tree-chunker` (C3d2) | Cross-encoder default is token overlap, not a CE model |
| Product TUI | [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui) **0.1.0**, [`ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) **0.1.0** | desk chat + transcript sink | Not a protocol. `cl-stack-llm-demo` is local (no GHCR) |
| Product | [`demiurge`](https://github.com/egao1980/demiurge) **0.4.2** + [`demiurge-parity`](https://github.com/egao1980/demiurge-parity) **0.1.3** | core / improve / observe / serve / ingest / workflows / bundle + C4 corporate; S1–S8 run; decision KS + memory chronicle adapter, published | B7c S9-corporate still skipped; B8 v2 demos |
| Leftover | [#196](https://github.com/egao1980/cl-stack/issues/196) shipped (`blackboard-wire`); [#197](https://github.com/egao1980/cl-stack/issues/197) wrap-up | B7c / B8 (`demiurge` **0.4.2** published) | C5 HOLD. A11 P2 (prompt cache + audio/realtime). pdfium native OCI | [#198](https://github.com/egao1980/cl-stack/issues/198) → `steer-protocol` **0.2.0** |

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
| Native GGUF | `llama-cpp` ABI 4 + backend | **thin** — no tools |
| Provider catalog | `register-provider` / `resolve-backend` on `llm-protocol` **0.3.0** + Anthropic Messages **0.1.0** | **thin** — in-memory only; not LiteLLM |
| Fallback / router / budget | `llm-protocol/router` **0.3.0** — fallback-chain / budget / least-latency | **on-par** (shipped) |
| RAG / vector / chunk / rerank | `rag-protocol` **0.1.2** + memory / sql / pgvector / hybrid / tsvector / splade / CE / text **0.2.0** | **on-par** — ANN + BM25/RRF + FTS + sparse; `block-tree-chunker`; CE hook is `:score-fn` |
| Conversation memory / window | `conversation-protocol` **0.2.0** + SQL store + agent `:memory` | **on-par** — SQL / summary / token-window shipped |
| Token count / context mgmt | `count-tokens` / `context-window` / `fit-turns` | **on-par** (shipped) |
| Prompt cache | no `cache_control` / `prompt_cache_key` | **gap** (P2) |
| Image / audio / speech / realtime | image-input wire (OpenAI + Anthropic); `llm-image-part` | **thin** — audio / speech / realtime still P2 |
| Batch / files / vector stores | no | **leave** — hosted OpenAI vector stores still out; in-process store is `rag-backend-memory` |
| Agent loop (HITL / handoff / nested) | `ai-agent-protocol` **0.3.1** | **on-par** — `:durability` shipped (A6b/A6d) |
| Durable execution | `task-protocol` **0.1.0** + SQL journal + agent/board persist | **on-par** (A6b) |
| MCP / A2A / AG-UI wire | dual-era + 3 A2A + 36-event AG-UI + `blackboard-wire` **0.1.0** | **on-par** / **ahead** on AG-UI typing |
| Skills / `SKILL.md` | `steer-protocol` **0.2.0** + agent `:steering` | **on-par** — tool-bearing + versioned store; not A2A `agent-skill` |
| Evals / graph | `eval-protocol` **0.1.0** | **on-par** on evals — not LangGraph (leave) |
| GenAI spans | `llm-protocol/telemetry` **0.3.0** + agent/task `/telemetry` | **on-par** (A7b) |
| Identity / MQ / S3 / IMAP / cache / extract | ldap / mq / object-store / mail 0.2 / cache / doc-extract **0.2.0** + pdfium **0.1.1** | **on-par** — C2b canaries + C3b source shipped; pdfium native OCI still open |
| Demiurge product | [`demiurge`](https://github.com/egao1980/demiurge) **0.4.2** ([#197](https://github.com/egao1980/cl-stack/issues/197)) | **on-par** — B1–B6 + C4 shipped; decision KS + memory chronicle adapter, published; wrap-up = B7c S9 + B8 v2 |
| Corporate profile / tier 2 | C4 shipped in 0.3.5; C5 HOLD | **thin** — S9 live-corporate still skipped; C5 not started |

Hub cookbooks: [llm](cookbooks/llm.md) · [conversation](cookbooks/conversation.md) · [steer](cookbooks/steer.md) · [rag](cookbooks/rag.md) · [ai-agent](cookbooks/ai-agent.md) · [mcp](cookbooks/mcp.md) · [a2a](cookbooks/a2a.md) · [ag-ui](cookbooks/ag-ui.md).

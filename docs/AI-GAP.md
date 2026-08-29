# AI protocol / backend gaps vs Python / Node / Java

Scored **2026-08-29** against workspace sources (not README claims) and current
Py / Node / Java surfaces. Companion to [STDLIB-GAP.md](STDLIB-GAP.md) — that
file is ANSI batteries; this one is the LLM / agent layer.

**Comparators**

| Ecosystem | Generation | Agents | Wire | RAG / memory |
|-----------|------------|--------|------|--------------|
| Python | OpenAI / Anthropic / Google SDKs, LiteLLM | PydanticAI, LangGraph, CrewAI / AG2, OpenAI Agents SDK | FastMCP 3, official MCP, A2A Python | LlamaIndex, LangChain, Instructor |
| Node | Vercel AI SDK 6, LangChain.js | AI SDK `Agent` / `DurableAgent`, Mastra | official MCP TS, CopilotKit / AG-UI | Mastra, LlamaIndex.TS |
| Java | Spring AI 2.0, LangChain4j 1.17 | Spring advisors, `langchain4j-agentic` | Spring MCP starters, LangChain4j MCP + A2A | Spring advisors, LangChain4j stores (~30) |

Do **not** clone LangChain. Keep the locked split: protocol GFs + thin backends +
product (`demiurge`) above. Gaps below are missing *protocols or backends*, not
a kitchen-sink facade.

---

## Verdict

**Wire is competitive.** Dual-era MCP, three A2A bindings, typed AG-UI events,
and a CLOS agent loop with HITL / handoffs / parallel tool invoke are ahead of
most CL and on-par with 2026 Java/TS agent kits.

**Generation is a wave-1 stub.** One OpenAI-compat HTTP backend, no streaming
on the wire, no embeddings GF, no RAG, no memory, no router. That is the
delta that makes `generate` feel like 2023 `openai.ChatCompletion` while
PydanticAI / Vercel / Spring AI ship a product surface.

Blackboard KSAR is a *different* orchestration model (not a missing LangGraph).
[#196](https://github.com/egao1980/cl-stack/issues/196) / [#197](https://github.com/egao1980/cl-stack/issues/197)
are the composition holes, not a missing graph DSL.

---

## Inventory (what exists)

| Layer | Repo | Ver | Role | Hole |
|-------|------|-----|------|------|
| Generate | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | 0.1.0 | Turns + parts + items; `generate` / `respond`; mock; schema `:output` | No `embed`; no audio/file/video parts; stream GF default = `llm-unsupported` |
| OpenAI wire | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | 0.1.0 | `POST /chat/completions` + `/responses`; `GET /models`; vision/tools/json_schema | `stream-*` → `llm-unsupported`. No embeddings / images / audio / realtime / batches / files / vector stores |
| Agent loop | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | 0.2.0 | `run-ai-agent(-async)`, function tools, nested agent-as-tool, `:handoffs`, HITL `approve`/`deny`, parallel `invoke-tool-async` | No memory, no graph, no evals, no skill loader. Streaming depends on LLM backend |
| MCP sampling + tools | `ai-agent-protocol/mcp` | 0.1.0 | `create-message` → `generate`; `make-mcp-tool-source` | Cookbook pointed at nonexistent `llm-protocol/mcp` (fixed here) |
| AG-UI encode | `ai-agent-protocol/ag-ui` | 0.2.0 | `on-event` → AG-UI events | Drops thinking / image parts |
| A2A expose | `ai-agent-protocol/a2a` | 0.1.0 | Sync `run-ai-agent` → completed task + text artifact | No stream / input-required / artifacts beyond text |
| MCP | [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) **0.2.0** + stdio **0.1.1** + Streamable HTTP **0.2.0** | dual-era `2026-07-28` / `2025-11-25`; tools/resources/prompts + sampling/elicit/roots/completions/subs/MRTR GFs | Auth / OAuth / Tasks = non-goal. No legacy `2025-06-18` |
| A2A | [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) **0.2.0** + jsonrpc **0.2.1** + httpjson **0.2.0** + grpc **0.2.0** | Card + tasks + stream + list/cancel/resubscribe | Push notifications refuse. gRPC payloads = JSON objects (no official proto) |
| AG-UI | [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) **0.2.1** + SSE / protobuf-in-SSE **0.2.0** + TUI sink | `RUN_*` / `TEXT_MESSAGE_*` / `TOOL_CALL_*` / `STATE_*` / `MESSAGES_SNAPSHOT` | No reasoning/activity families. Protobuf = JSON octets. TUI `STATE_DELTA` no-op |
| Blackboard | [`blackboard-protocol`](https://github.com/egao1980/blackboard-protocol) **0.1.1** + `capability-protocol` **0.2.0** | KSAR + COW; `:llm` / `:world` vocab | Zero LLM/wire deps (locked). `:llm-audio` etc. are vocab only |
| Caps | `:llm-generation` … `:llm-responses` | 0.2.0 | Catalogue + `complete` → `generate` | No `:llm-embeddings`. Speech/transcribe GFs have no backend |
| Telemetry | [`telemetry-protocol`](https://github.com/egao1980/telemetry-protocol) | 0.1.0 | `+gen-ai-usage-{input,output}-tokens+` constants | No auto-span around `generate`. No gen_ai semantic conventions wiring in llm-protocol |
| Native GGUF | [`llm-backend-vllm-cpp`](https://github.com/egao1980/llm-backend-vllm-cpp) | — | Used by demo/TUI `/vllm` | Not an OpenAI-compat peer |
| Product TUI | [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui), [`ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) | — | Desk chat + MCP file tools; AG-UI transcript sink | Not a protocol |
| Leftover epics | [#196](https://github.com/egao1980/cl-stack/issues/196) wire↔board, [#197](https://github.com/egao1980/cl-stack/issues/197) demiurge, [#198](https://github.com/egao1980/cl-stack/issues/198) agent-skills | open | Composition / SKILL.md | Not started |

Parity canaries: [`mcp-parity`](https://github.com/egao1980/mcp-parity), [`a2a-parity`](https://github.com/egao1980/a2a-parity). **No `ag-ui-parity`.**

---

## Scorecard

Status: **ahead** / **on-par** / **thin** / **gap** / **leave** (intentional non-goal).

| Capability | cl-stack | Python | Node | Java | Status |
|------------|----------|--------|------|------|--------|
| Typed turns + parts (role on turn) | `llm-turn` / `llm-part` | Anthropic Messages, PydanticAI | AI SDK `ModelMessage` | LangChain4j content types | **on-par** |
| Chat + Responses dual grain | `generate` + `respond` | OpenAI SDK | AI SDK | Spring `ChatClient` | **on-par** |
| Structured output | `:output` + `schema-protocol` (no retry) | PydanticAI / Instructor (retry) | AI SDK `Output` | Spring / LangChain4j | **thin** — parse + `use-value` / `ignore-output`; no `ModelRetry` (locked) |
| HTTP streaming | GF yes; OpenAI backend **signals** | all SDKs | AI SDK default | Spring reactive / LC4j module | **gap** (P0) |
| Provider catalog | 1 (`openai-compat`, LM Studio default) | LiteLLM 100+; native Anthropic/Gemini/Bedrock | AI SDK 20+ | LC4j 20+; Spring ~8 | **gap** (P1) — OpenAI-compat covers Groq/OpenRouter/vLLM *if* they speak the same JSON |
| Fallback / router / budget | `with-auto-retry` on 429/5xx only | LiteLLM | AI Gateway | Spring retry advisors | **gap** |
| Embeddings | explicit wave-1 non-goal | every SDK | every SDK | `EmbeddingModel` required for RAG | **gap** (P0) |
| RAG / vector / chunk / rerank | absent | LlamaIndex, LangChain | Mastra, LlamaIndex.TS | Spring advisors; LC4j 30+ stores | **gap** (P1) — new protocol, do not stuff into `llm-protocol` |
| Conversation memory / window | `prepare-agent-turns` hook only | LangChain memory, PydanticAI | AI SDK / Mastra memory | Spring `MessageChatMemoryAdvisor` | **gap** |
| Token count / context mgmt | `llm-usage` after the fact | tiktoken, Anthropic | AI SDK usage | Spring `TokenCountEstimator` | **gap** |
| Prompt cache | no `cache_control` / `prompt_cache_key` | Anthropic, OpenAI | AI SDK | Spring | **gap** (P2) |
| Image / audio / speech / realtime | `llm-image-part` only; caps vocab for the rest | full SDKs | AI SDK | Spring image/audio/TTS | **gap** (P2) — parts + GFs first |
| Batch / files / vector stores | no | OpenAI | limited | Spring | **leave** until embed exists |
| Moderation / guardrails | finish `:content-filter` only | Guardrails, NeMo, LC4j guardrails | — | LC4j experimental | **leave** (product) |
| Tool loop + HITL | `function-tool`, `approve`/`deny`, `complete-invocation` | PydanticAI, OpenAI Agents | AI SDK `Agent` | LC4j HITL / Spring advisors | **on-par** |
| Parallel tools | `%invoke-ready` fans out `invoke-tool-async` | yes | yes | yes | **on-par** |
| Handoff / nested agent | `:handoffs` takes the run; nested agent = one peer tool | OpenAI Agents, CrewAI | Mastra | LC4j agentic | **on-par** |
| Graph / checkpoint / time-travel | blackboard KSAR (different) | LangGraph | AI SDK `DurableAgent`, Mastra | Koog, Embabel | **leave** as graph — use board + `#196` |
| Evals / datasets / traces UI | gen_ai token constants only | Phoenix, PydanticAI evals, LangSmith | AI SDK DevTools | Micrometer + OTel | **gap** (P2) — wire `generate` into `telemetry-protocol` first |
| MCP client+server dual-era | **0.2.0** modern + legacy; parity vs FastMCP 3 / Node v2 | FastMCP 3 | official SDK v2 | Spring 2.0 starters | **ahead** on era split |
| MCP OAuth / Tasks | non-goal | FastMCP / spec | SDK | Spring | **leave** wave-1; P2 if hosts require it |
| A2A 1.0 three bindings | jsonrpc + REST + grpc (JSON payloads) | A2A Python, PydanticAI | TS SDK | LC4j A2A; Spring: no | **ahead** of Spring; **thin** vs official proto |
| AG-UI typed events | schema-protocol events + SSE | rare | CopilotKit / AI SDK UI | rare | **on-par** with CopilotKit server; no React kit (locked) |
| Agent Skills (`SKILL.md`) | [#198](https://github.com/egao1980/cl-stack/issues/198) unlocked | — | Cursor / Claude | — | **gap** (P3) |
| Computer use / browser / code interp | `:world` GFs only (`run-command`, `read-file`) | Anthropic CU, OpenAI | — | — | **leave** — implement as capability backends, not llm-protocol |

---

## Layer notes

### `llm-protocol` — right shape, incomplete grain

Shipped and should stay:

- Role on `llm-turn`; type on `llm-part` (`text` / `image` / `tool-call` / `tool-result` / `thinking`).
- Responses grain: `llm-item` (`message` / `function-call` / `function-call-output` / `reasoning`) + `turns->items` / `items->turns`.
- Settings object, not kwargs soup. Tools = descriptors.
- Conditions: `llm-http-error` + `retry` / `use-value`; `llm-output-error` + `ignore-output`. `auto-retry` is 408/409/429/5xx only.

Missing vs every mainstream `ChatModel`:

1. **`embed` / `embed-query` / `embed-documents` GFs + `llm-embedding` value type.** Brief already deferred this. Without it there is no RAG, no semantic cache, no clustering. Add `llm-protocol/embed` (optional system) — do not force it on `generate`.
2. **Parts for audio / video / file.** Caps already name `:llm-audio` `:llm-video` `:llm-files`. Protocol has no `llm-audio-part` / `llm-file-part`. OpenAI backend cannot round-trip them.
3. **Settings holes:** no `seed`, `frequency-penalty`, `presence-penalty`, `n`, `logprobs`, `verbosity`, `reasoning-effort`. Park in `llm-settings-extra` today; promote when a second backend needs them.
4. **Usage holes:** no `cached-tokens` / `reasoning-tokens` (OpenAI + Anthropic already emit these).
5. **No `previous-response-id` / server conversation.** Locked non-goal — keep it out of the protocol; a store belongs in product or a later `llm-store` backend.

Capability probe vs catalogue: `backend-supports-p` is a wire flag. `make-llm-catalogue` only registers what the backend claims. OpenAI backend claims `:tools :structured-output :vision :responses` — **not** `:stream`, `:thinking`, `:audio`. Honest. `:vision` is claimed but there is no live vision corpus.

### `llm-protocol-openai` — 2 of ~12 OpenAI surfaces

Implemented: chat completions, responses, list models, tools, json_schema / Responses `text.format`, image_url parts, Bearer + org header, injectable `request-fn`.

Explicitly broken / missing vs `openai` Python / Spring `OpenAiChatModel`:

| Endpoint / feature | Status |
|--------------------|--------|
| `stream=true` SSE (chat + responses) | **`llm-unsupported`** — agent `:part` events never fire on live HTTP |
| `/embeddings` | absent |
| `/images/generations` | absent |
| `/audio/speech`, `/audio/transcriptions` | absent |
| Realtime WS | absent (would be `ws-protocol`) |
| `/batches`, `/files`, `/vector_stores` | absent |
| `/moderations` | absent |
| Azure `api-version` / `api-key` header | absent (OpenRouter/LM Studio path only) |
| Thinking on chat wire | `%wire-part` drops `llm-thinking-part`; only `reasoning_content` on the turn |

Streaming is the only P0 on this backend. Everything else can wait for dedicated `llm-protocol-*` repos (Anthropic Messages is the next native; Gemini / Bedrock after). Do **not** grow this file into LiteLLM.

OpenAI-compat is enough for: LM Studio, vLLM, llama.cpp server, Groq, OpenRouter, Azure OpenAI *if* they keep the JSON. It is **not** enough for Anthropic prompt cache, computer use, or Gemini `Part` file_data.

### `ai-agent-protocol` — loop is real; product features are not

This is the PydanticAI / AI SDK `Agent` analogue — and it is closer than the LLM backend.

Has: max-steps, timeout, off-loop generate + tool handlers, cancel token + `continue` restart, unknown-tool `skip` / `use-value`, deferred tools (`complete-invocation`), first-tool-choice, `defagent`.

Already has MCP peer-as-tools: `make-mcp-tool-source` → `list-agent-tools` / `invoke-tool-async` via `call-tool` (tested).

Does **not** have (and should not steal from LangGraph):

- Message window / summarization memory (add `agent-memory` protocol or a `prepare-agent-turns` mixin — not a board dep).
- Output-tool / result validator retry loop (llm-protocol locked this out).
- Durable checkpoint of `agent-run` (Mastra / `DurableAgent`). `agent-run` is in-memory. Blackboard is the durable story.

### MCP — spec surface yes; host product no

Protocol GFs cover the 2026-07-28 surface. Catalog (tools/resources/prompts) + MRTR + completions + dual-era negotiate are real. Backends are thin transports — locked.

Server vs client is the real hole vs FastMCP 3:

- **Sampling / elicitation / roots as server RPC** — GFs + client handlers exist; server dispatch **rejects `-32601`**. A Lisp MCP *server* cannot ask the host to sample. Host-side `make-mcp-sampling-handler` still works.
- **Outbound push** — `notify-*-list-changed` / progress build objects and return `t`; no wire send. Client inbound handlers exist.
- **OAuth / Tasks** — non-goals. First SaaS MCP that requires OAuth loses.
- **`cl-mcp` does not consume `mcp-protocol`.** Product split is correct; two stacks until it switches.
- `mcp-parity` skips `input_required` interop. No HTTP+SSE `2025-06-18` (locked).

### A2A — bindings exist; proto and push do not

GFs: `fetch/serve-agent-card`, `send-message`, `stream-message`, `get/list/cancel-task`, `resubscribe-task`. Push-notification methods are recognized and **refused** (`-32003`). Auth is a wire enum (`TASK_STATE_AUTH_REQUIRED`) — no OAuth/JWT flow.

Binding holes: HTTP+JSON has no resubscribe (`:unsupported`). gRPC is JSON-in-gRPC, not compiled `a2a.proto`. `a2a-parity` covers JSON-RPC SendMessage only; stream / REST / gRPC deferred.

vs official A2A Python/Java/TS: missing authenticated extended card UX and webhook push. LangChain4j has A2A; Spring AI 2.0 still does not — we are ahead of Spring on bindings, behind on proto/auth.

### AG-UI — server events yes; client ecosystem no

Wave-1 event set matches CopilotKit's core transcript (`RUN_*` / `TEXT_MESSAGE_*` / `TOOL_CALL_*` / `STATE_*` / `MESSAGES_SNAPSHOT`). `STEP_*` schemas exist; default echo never emits them. `REASONING_*` is missing — decode **errors**. TUI `STATE_DELTA` is a no-op. Encoder skips thinking/image.

HITL lives on `ai-agent-protocol` (`approve`/`deny`), not as AG-UI event types. No interop canary. Add `ag-ui-parity` (Lisp ↔ CopilotKit / `@ag-ui/client`) before claiming done vs Node.

### Blackboard + capabilities — vocab ahead of adapters

`:llm-*` and `:world` names exist. `register-llm-backend` can copy a live catalogue onto a board. Nothing in-tree implements `:compute` / `:code-editing` / `:web-search` as real backends, and `#196` adapters (MCP tools ↔ sections, A2A `SendMessage` → `:pending-task`, AG-UI observe) are unchecked.

That is the Demiurge hole, not a missing `LangGraph.StateGraph`.

### Telemetry

Constants exist (`gen_ai.usage.input_tokens`). `generate` does not open a span, does not record TTFT, does not attach `gen_ai.request.model`. Spring AI + OTel and Phoenix do this by default. One `:around` on `generate` / `run-ai-agent` would close most of the observability gap without a new repo.

### PydanticAI v2 (2026-06-23 → **v2.36.0** 2026-08-28)

v2 is harness-first. The primitive is **`Capability`**: one object that bundles tools + lifecycle hooks + instructions + model settings, passed as `capabilities=[...]`. Core stays small (`pydantic-ai`: providers, loop, MCP, native tools, Thinking, Tool Search, compaction, durability, OTel). Everything else is [`pydantic-ai-harness`](https://github.com/pydantic/pydantic-ai-harness) (0.x, moves fast): `Coder` / `Researcher` are just combined capabilities.

**Their `Capability` ≠ our `capability-protocol`.** Ours is a catalogue/vocab (`:llm-generation`, `:world`) with GFs. Theirs is an agent-loop mixin. Do not rename ours. Closest steal: an `ai-agent` *bundle* (tools + instructions + hook GFs) you can `defer-load`. Name it `agent-bundle` / `agent-skill` — never `capability`.

v2 defaults that matter:

| Change | Implication for us |
|--------|-------------------|
| `openai:` → Responses API (`openai-chat:` to stay) | We already split `generate` / `respond`. Default the OpenAI backend's *app* path to `respond` once streaming works. |
| `WebSearch`/`WebFetch` native-only unless `local=` | Pattern for `:world` backends: native tool when the model has it, local fallback otherwise. |
| `MCP(url=)` **local by default** (credentials); `native=True` opt-in | Matches our "MCP is a peer, not a provider tool" stance. |
| A2A extra **removed** → upstream `fasta2a` | We keep first-party `a2a-protocol`. Don't wrap fasta2a. |
| Instrumentation v5 + `gen_ai.aggregated_usage.*` | When we wire telemetry, skip v1–4 names. |
| `end_strategy` `early` → `graceful` (side-effect tools run next to output tools) | Our loop already runs all tool-calls in the step. Fine. |
| Slim extras (bedrock/groq/mistral opt-in) | Same as our one-backend-per-repo rule. |

Feature delta vs this stack (v2.36.0):

| PydanticAI v2 | cl-stack | Steal? |
|---------------|----------|--------|
| 20+ providers, string swap, `FallbackModel` | 1 openai-compat + optional `llm-backend-vllm-cpp` | Anthropic next; no LiteLLM |
| Embeddings + image gen + realtime voice (OpenAI/Gemini/Azure/xAI) | image part only; no embed/audio GFs | embed P0; voice P2 |
| Typed `output_type` + `ModelRetry` | `:output` + `use-value` / `ignore-output`, no retry | **leave** in `llm-protocol` |
| Streaming + `run_stream_events` / AG-UI / Vercel AI adapters | stream GF; OpenAI signals; AG-UI encoder | stream P0 |
| AG-UI interrupts → `DeferredTools` | `complete-invocation` / `:deferred` | already isomorphic |
| MCP as `MCPToolset` + `list_prompts`/`get_prompt` | full dual-era protocol + `make-mcp-tool-source` | **ahead** on eras; **behind** on OAuth |
| Tool Search + `defer_loading` capabilities | always-on tool list | P2: collapse unused tools to a catalog line |
| Compaction (provider-native + window/summarize/tiered) | `prepare-agent-turns` hook only | **P1 after embed** — long runs die without this |
| Code Mode (Monty sandbox, one `run_code` RT) | absent | leave until we have a sandbox; interesting |
| Skills (`SKILL.md` on demand) | [#198](https://github.com/egao1980/cl-stack/issues/198) unlocked | P2, name ≠ A2A `agent-skill` |
| Memory + conversation search (BM25 over compacted history) | absent | P2 mixin, not board |
| Subagents / Planning / Advisor / Dynamic Workflow | `:handoffs` + nested agent-as-tool | on-par for handoff; no planner/advisor |
| `Coder` harness (FS + shell + repo + plan + compaction) | `:world` GFs, no backends | `#196` + real `:compute`/`:code-editing` |
| Durable: Temporal / DBOS / Prefect + `@durable_operation` + `StepPersistence` (`continue_run` / `fork_run`) | in-memory `agent-run`; blackboard is the durable story | leave Temporal; optional persist of `agent-run` is P2 |
| Pending queue (`ctx.enqueue`) — steer mid-run | cancel + resume only | P2 if TUI needs it |
| ACP (experimental, Zed) | no | leave (not A2A) |
| YAML/JSON `AgentSpec` | `defagent` | leave |
| Guardrails + spend limits | finish `:content-filter` | leave (product) |
| CLI `clai` + `--mcp-config` + tool-call streaming | `cl-stack-llm-tui` | TUI is enough |
| `count_tokens` on Anthropic/Bedrock | usage after the fact | P2 with anthropic backend |

Do **not** grow `llm-protocol` into their Agent. v2 confirms the split we already locked: thin generate protocol, agent loop above, product/harness (`demiurge`) above that. Their Harness is the Demiurge analogue — `#197`.

---

## Recommended next (keep the protocol split)

### P0 — make the only backend usable

1. **`stream-generate` / `stream-respond` on `llm-protocol-openai`** — SSE over `http-protocol` stream body; `on-part` for text + tool-call argument deltas (agent loop already coalesces same-id suffixes). This unblocks AG-UI live tokens and the TUI.
2. **`embed` GF + OpenAI `/embeddings` method** — optional `llm-protocol/embed` + methods on the existing openai backend. Value type: id + float vector + usage.

### P1 — stop being a single-provider chat wrapper

3. **`llm-protocol-anthropic`** — native Messages + thinking signature + prompt cache headers. Parts already exist.
4. **Retriever protocol** (`retrieve-protocol` or `rag-protocol`) — `embed` + store + `retrieve` → list of `llm-text-part` / citations. First store: pgvector via `sql-protocol` (already shipped) or an in-memory backend. **Not** a LangChain `VectorStore` clone; keep it as thin as `http-protocol`.
5. **`#196` in-process adapters** — MCP cap→tool, A2A ingress, AG-UI observe. Unblocks `#197`. (`make-mcp-tool-source` already hosts a peer as tools; this item is board projection, not the host loop.)

### P2 — product parity, not protocol sprawl

6. Telemetry `:around` on generate/run — emit OTel v5 / `gen_ai.aggregated_usage.*` (PydanticAI default).
7. Compaction mixin on `prepare-agent-turns` (window + summarize). Their Harness Compaction is the model; do not put this in `llm-protocol`.
8. `ag-ui-parity` + official A2A/AG-UI protos.
9. Speech / transcribe backends (caps already named).
10. Agent Skills ([#198](https://github.com/egao1980/cl-stack/issues/198)) — name must not collide with A2A `agent-skill` or `capability-protocol`.
11. MCP OAuth on `mcp-backend-streamable-http` when a host requires it.

### Leave

- PydanticAI `Agent` / output-tools / `ModelRetry` inside `llm-protocol`.
- Renaming `capability-protocol` after their `Capability` mixin.
- LangGraph / `pydantic-graph` next to blackboard.
- Temporal/DBOS as a protocol (board + optional `agent-run` persist is enough).
- Code Mode / Monty / ACP / YAML `AgentSpec`.
- Colocating OpenAI / Anthropic / OTLP in protocol repos.
- CopilotKit React.
- Forking Autolith / `cl-llm-provider-api`.
- Embedding GF on blackboard core.

---

## Doc bugs found while scoring

Cookbook + brief pointed at nonexistent `llm-protocol/mcp`. Sampling is `ai-agent-protocol/mcp:make-mcp-sampling-handler`. Fixed in this PR.

---

## Sources

- Workspace: `llm-protocol` 0.1.0, `llm-protocol-openai` 0.1.0, `ai-agent-protocol` 0.2.0, `mcp-protocol` 0.2.0, `a2a-protocol` 0.2.0, `ag-ui-protocol` 0.2.1, `blackboard-protocol` 0.1.1 / `capability-protocol` 0.2.0, `telemetry-protocol` 0.1.0.
- Briefs: [llm.md](capabilities/llm.md) · [agent-wire.md](capabilities/agent-wire.md) · [mcp.md](capabilities/mcp.md) · [a2a.md](capabilities/a2a.md) · [ag-ui.md](capabilities/ag-ui.md) · [blackboard.md](capabilities/blackboard.md).
- Issues: [#195](https://github.com/egao1980/cl-stack/issues/195)–[#198](https://github.com/egao1980/cl-stack/issues/198).
- External (2026-08-29): Spring AI 2.0 vs LangChain4j 1.17; Vercel AI SDK 6; **PydanticAI v2.36.0** (v2.0.0 2026-06-23; [capabilities](https://ai.pydantic.dev/capabilities/), [upgrade](https://ai.pydantic.dev/changelog/), [v2 post](https://pydantic.dev/articles/pydantic-ai-v2)); FastMCP 3 / MCP spec `2026-07-28`.

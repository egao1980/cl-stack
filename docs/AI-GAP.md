# AI protocol / backend gaps vs Python / Node / Java

Scored **2026-08-31** against GitHub `main` + GHCR pins. Companion to [STDLIB-GAP.md](STDLIB-GAP.md) — that file is ANSI batteries; this one is the LLM / agent layer.

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

**Generation shipped past wave-1.** `llm-protocol` **0.2.0** has `embed` / `stream-generate` / `stream-respond`. OpenAI-compat **0.3.0** streams chat + Responses and hits `/embeddings`. Native `llama-cpp` **0.1.5** (ABI 4) + `llm-backend-llama-cpp` **0.1.2** generate / stream / embed / GBNF — still **no tools**.

**Still missing as protocols:** RAG / vector / chunk / rerank, conversation memory, provider catalog beyond OpenAI-compat + llama.cpp, router/budget, Anthropic native, prompt cache, audio/realtime. Those are the delta vs PydanticAI / Vercel / Spring AI.

Blackboard KSAR is a *different* orchestration model (not a missing LangGraph).
[#196](https://github.com/egao1980/cl-stack/issues/196) / [#197](https://github.com/egao1980/cl-stack/issues/197)
are the composition holes, not a missing graph DSL.

---

## Inventory (what exists)

| Layer | Repo | Ver | Role | Hole |
|-------|------|-----|------|------|
| Generate | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.2.0** | Turns + parts + items; `generate` / `stream-generate` / `respond` / `stream-respond` / `embed`; mock; schema `:output`; `/capability` | No audio/file/video parts |
| OpenAI wire | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | **0.3.0** | `/chat/completions` + `/responses` + `/embeddings` + stream | No images / audio / realtime / batches / files / vector stores |
| Native GGUF | [`llama-cpp`](https://github.com/egao1980/llama-cpp) **0.1.5** + [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) **0.1.2** | `libllamastack` ABI 4; generate / stream / embed; `:output` → GBNF | **No tools.** Grammar/stream/` :parsed` need matching overlay |
| Agent loop | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.2.0** | `run-ai-agent(-async)`, function tools, nested agent-as-tool, `:handoffs`, HITL | No memory, no graph, no evals, no skill loader |
| MCP sampling + tools | `ai-agent-protocol/mcp` | **0.1.0** | `create-message` → `generate`; `make-mcp-tool-source` | **Not** `llm-protocol/mcp` (does not exist) |
| AG-UI encode | `ai-agent-protocol/ag-ui` | **0.2.0** | `on-event` → AG-UI events | — |
| A2A expose | `ai-agent-protocol/a2a` | **0.1.0** | Sync `run-ai-agent` → completed task + text artifact | No stream / input-required / artifacts beyond text |
| MCP | [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) **0.2.0** + stdio **0.1.1** + Streamable HTTP **0.2.0** | dual-era; tools/resources/prompts + sampling GFs | Auth / OAuth / Tasks = non-goal |
| A2A | [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) **0.2.0** + jsonrpc **0.2.1** + httpjson **0.2.0** + grpc **0.2.0** | Card + tasks + stream | Push notifications refuse |
| AG-UI | [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) **0.3.0** + SSE **0.2.1** + protobuf **0.3.0** (WKT) + TUI **0.1.0** + `/client` (`json-patch`) | all 36 events; chunks; interrupts | Official `Event` oneof not compiled. WKT Lisp-only in canary |
| Blackboard | [`blackboard-protocol`](https://github.com/egao1980/blackboard-protocol) **0.1.1** + `capability-protocol` **0.2.1** | KSAR + COW; `:llm` / `:world` vocab | Zero LLM/wire deps (locked) |
| Product TUI | [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui) **0.1.0**, [`ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) **0.1.0** | desk chat + transcript sink | Not a protocol. `cl-stack-llm-demo` is local (no GHCR) |
| Leftover epics | [#196](https://github.com/egao1980/cl-stack/issues/196) wire↔board, [#197](https://github.com/egao1980/cl-stack/issues/197) demiurge, [#198](https://github.com/egao1980/cl-stack/issues/198) agent-skills | open | Composition / SKILL.md | Not started |

Parity canaries: [`mcp-parity`](https://github.com/egao1980/mcp-parity), [`a2a-parity`](https://github.com/egao1980/a2a-parity), [`ag-ui-parity`](https://github.com/egao1980/ag-ui-parity) (SSE JSON full; WKT Lisp-only).

---

## Scorecard

Status: **ahead** / **on-par** / **thin** / **gap** / **leave** (intentional non-goal).

| Capability | cl-stack | Status |
|------------|----------|--------|
| Typed turns + parts | `llm-turn` / `llm-part` | **on-par** |
| Chat + Responses dual grain | `generate` + `respond` | **on-par** |
| HTTP streaming | OpenAI `stream-generate` / `stream-respond`; llama.cpp `stream-generate` | **on-par** (shipped) |
| Embeddings | `embed` / `embed-query`; OpenAI `/embeddings`; llama.cpp GGUF | **on-par** (shipped). RAG still **gap** |
| Structured output | `:output` + `schema-protocol`; llama.cpp → GBNF | **thin** — parse + `use-value`; no `ModelRetry` (locked) |
| Native GGUF | `llama-cpp` ABI 4 + backend | **thin** — no tools |
| Provider catalog | OpenAI-compat + llama.cpp | **gap** (P1) — no Anthropic native; compat covers Groq/OpenRouter/vLLM *if* they speak the same JSON |
| Fallback / router / budget | `with-auto-retry` on 429/5xx only | **gap** |
| RAG / vector / chunk / rerank | absent | **gap** (P1) — new protocol, do not stuff into `llm-protocol` |
| Conversation memory / window | `prepare-agent-turns` hook only | **gap** |
| Token count / context mgmt | `llm-usage` after the fact | **gap** |
| Prompt cache | no `cache_control` / `prompt_cache_key` | **gap** (P2) |
| Image / audio / speech / realtime | `llm-image-part` only | **gap** (P2) |
| Batch / files / vector stores | no | **leave** until a RAG protocol exists |
| Agent loop (HITL / handoff / nested) | `ai-agent-protocol` | **on-par** |
| MCP / A2A / AG-UI wire | dual-era + 3 A2A + 36-event AG-UI | **on-par** / **ahead** on AG-UI typing |
| Evals / skills / graph | absent | **gap** — [#198](https://github.com/egao1980/cl-stack/issues/198); not LangGraph |

Hub cookbooks: [llm](cookbooks/llm.md) · [ai-agent](cookbooks/ai-agent.md) · [mcp](cookbooks/mcp.md) · [a2a](cookbooks/a2a.md) · [ag-ui](cookbooks/ag-ui.md).

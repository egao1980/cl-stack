# llm-protocol (P2)

**Issues:** [#195](https://github.com/egao1980/cl-stack/issues/195) · parent [#192](https://github.com/egao1980/cl-stack/issues/192)
**Status:** `llm-protocol` **0.2.0** + [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) **0.3.0** + [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) **0.1.2** · cookbook [llm.md](../cookbooks/llm.md)

CLOS generation + embeddings protocol. **Not** a `blackboard-protocol` dependency. **Demiurge is a consumer**, not the driver.

MCP sampling is [`ai-agent-protocol/mcp`](ai-agent.md) — **not** here. There is no `llm-protocol/mcp`.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Anthropic Messages, Gemini `Part`, OpenAI Responses Items, Vercel `LanguageModelV2` | Typed **parts**; **role on the turn** | Chat Completions “one message, glued concerns” as the *protocol* |
| Vercel `generateText`/`streamText`, Anthropic `messages.create`/`stream` | `generate` + `stream-generate` GFs | Agent `maxSteps`, `tool.execute`, UIMessage |
| OpenAI Responses | `respond` / `stream-respond` + `llm-item` | Server-side `previous_response_id` store |
| All provider SDKs | `llm-settings`, `llm-usage`, finish-reason keywords | Kwargs soup on the GF |
| `quasi/cl-llm-provider` | `backend-supports-p` | Telos |
| OpenAI-compat / LM Studio | First **HTTP** backend | Protocol ≠ `/v1/chat/completions` |
| llama.cpp | Native CFFI backend (`libllamastack`) | Tools on that backend |
| PydanticAI | — | `ModelRequest` part-encodes-role, `ModelRetry` |

Product/agent loop, tool *execution*, UI transcripts stay out. Those are [ai-agent](ai-agent.md) / blackboard / capability / ag-ui.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `llm-backend` + `generate` / `stream-generate` + `respond` / `stream-respond` + `embed` / `embed-query`. Turns + parts + items. Tools optional. |
| **Roles** | Keywords `:system` `:user` `:assistant` `:tool` on `llm-turn`. |
| **Parts** | `llm-text-part` `llm-image-part` `llm-tool-call-part` `llm-tool-result-part` `llm-thinking-part`. |
| **Settings** | `llm-settings` (or a plist). Not flattened onto the GF. |
| **Tools** | `llm-tool` = name / description / JSON-schema parameters. **Not** an executor. |
| **Finish** | `:stop` `:length` `:tool-use` `:content-filter`. |
| **Wire (HTTP)** | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) **0.3.0**: `POST {base}/chat/completions` + `/responses` + `/embeddings` + streaming. HTTP = `http-backend-async` × libuv. Default `http://127.0.0.1:1234/v1`. |
| **Wire (native)** | [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) **0.1.2** over [`llama-cpp`](https://github.com/egao1980/llama-cpp) **0.1.5**. CFFI to `libllamastack` (`llama-stack.h`), **not** `llama.h`. |
| **Capability** | Optional `llm-protocol/capability` — `:llm` catalogue (`make-llm-catalogue`) + `complete` → `generate` + `embed`. Lookup is `capability-supported-p`. |
| **Schema** | Optional `llm-protocol/schema` — `:output` → `schema-protocol` parse. |
| **MCP** | **Not here.** `ai-agent-protocol/mcp:make-mcp-sampling-handler`. |
| **Stream** | GF exists. Mock + OpenAI + llama.cpp all stream. `:on-part` gets `llm-part`s. |
| **Embed** | `embed` (string or sequence) → `llm-embed-result`. `embed-query` → first float vector. |
| **Autolith** | Do not fork `cl-llm-provider-api`. |

---

## Protocol surface

```lisp
(defclass llm-backend () ())
(defgeneric generate (backend turns &key model settings tools tool-choice output))
(defgeneric stream-generate (backend turns &key model settings tools tool-choice output on-part))
(defgeneric respond (backend items &key model settings tools tool-choice output))
(defgeneric stream-respond (backend items &key model settings tools tool-choice output on-part))
(defgeneric embed (backend inputs &key model dimensions encoding-format))
(defgeneric list-models (backend &key))
(defgeneric backend-supports-p (backend feature))
```

`turns`: string, `llm-turn`, or a sequence. Result is `llm-response` (`llm-response-text`, `llm-response-tool-calls`, `llm-response-thinking`, `llm-response-output`, `llm-usage`). Items: `llm-item` (`llm-message-item`, `llm-function-call-item`, …). `embed-query` is sugar over `embed`.

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol + mock | [`egao1980/llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.2.0** |
| OpenAI-compat | [`egao1980/llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | **0.3.0** |
| llama.cpp native | [`egao1980/llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) | **0.1.2** |
| CFFI + overlays | [`egao1980/llama-cpp`](https://github.com/egao1980/llama-cpp) | **0.1.5** |
| Capability / schema | `llm-protocol/capability`, `llm-protocol/schema` | (same as protocol) |

Env: `OPENAI_API_KEY` / `LM_API_TOKEN` · `OPENAI_BASE_URL` · `OPENAI_MODEL` · `OPENAI_EMBEDDING_MODEL` · `LLAMA_MODEL_PATH`. Tests inject `request-fn` plus an async×libuv fixture; live HTTP behind `LLM_OPENAI_LIVE=1`. Embed smoke: `cl-stack-llm-demo` `scripts/smoke-embed.lisp` (local product, **not** on GHCR).

---

## Native llama.cpp

Lisp binds **`include/llama-stack.h`** (`libllamastack`). Overlay also stages `libllama` + `libggml*`. Never ship `libcuda` / Vulkan ICD — host provides those.

| Overlay | Backends |
|---------|----------|
| `linux/amd64` | CUDA + Vulkan |
| `windows/amd64` | CUDA + Vulkan |
| `darwin/arm64` | Metal |
| `linux/arm64` | CPU |

ABI on **0.1.5** (pin the Lisp tag; grammar / stream / `:parsed` need a matching overlay):

| ABI | Entry | Lisp |
|-----|-------|------|
| 1 | `llama_stack_complete` | `complete` (stays) |
| 2 | `llama_stack_complete_ex` | `:grammar` / `:grammar-root` |
| 3 | `llama_stack_complete_stream` | `:on-token` (non-NIL stops) |
| 4 | `llama_stack_grammar_parse` | `parse-grammar` + `:parsed` (clone; engine outlives handle) |

Backend: `generate` / `stream-generate` (no tools). `respond` → `generate`. `:output` (JSON Schema / `schema-protocol`) → GBNF via `json-schema-to-gbnf`. Raw GBNF is backend-local (`llama-cpp-settings` / `llm-settings-extra`) — **not** an `llm-protocol` field. Extra grammar **wins** over `:output`. `backend-supports-p`: `:structured-output` `:grammar` `:stream`. `embed` → `llama_stack_embed` (GGUF families llama.cpp loads: `bert`, `qwen3`, …).

An ABI 1 overlay against Lisp 0.1.5: `:grammar` / `:on-token` / `:parsed` are no-ops or fall back to non-streaming complete. Rebuild the overlay (`publish-oci.yml` / local `scripts/build-llama.sh`).

---

## Non-goals

- Blackboard / KSAR in this package
- MCP sampling (→ [ai-agent.md](ai-agent.md))
- Anthropic native backend (parts already round-trip thinking + signature)
- Autolith fork
- Provider-side conversation store
- Tools / tool-calling on the llama.cpp backend

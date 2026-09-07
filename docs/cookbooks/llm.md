# Cookbook: LLM generate / stream / embed

**Audience:** call a model from Lisp **without** putting the provider in blackboard core.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol + mock + catalog (`stack-llm`) | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.2.1** |
| OpenAI-compat (`stack-llm-openai`) | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | **0.3.0** |
| Anthropic Messages (`stack-llm-anthropic`) | [`llm-protocol-anthropic`](https://github.com/egao1980/llm-protocol-anthropic) | **0.1.0** |
| llama.cpp native | [`llm-backend-llama-cpp`](https://github.com/egao1980/llm-backend-llama-cpp) | **0.1.2** |
| CFFI + overlays | [`llama-cpp`](https://github.com/egao1980/llama-cpp) | **0.1.5** |

Brief: [llm.md](../capabilities/llm.md) (#195). Adapter — **not** a `blackboard-protocol` dep. Demiurge **consumes** this. Sampling → [ai-agent.md](ai-agent.md). Conversation memory → [conversation.md](conversation.md). Rules / skills → [steer.md](steer.md). RAG / chunk / retrieve → [rag.md](rag.md).

```lisp
(cl-repo:load-system "llm-protocol" :version "0.2.1")
(cl-repo:load-system "llm-protocol-openai" :version "0.3.0")
(cl-repo:load-system "llm-protocol-anthropic" :version "0.1.0")
```

---

## 1. Mock

```lisp
(asdf:load-system "llm-protocol")

(let ((b (stack-llm:make-mock-llm-backend)))
  (stack-llm:llm-response-text (stack-llm:generate b "hi")))
;; ⇒ "echo: hi"
(stack-llm:llm-response-text (stack-llm:respond b "hi"))
;; ⇒ "echo: hi"  ; items→turns then generate
(stack-llm:embed-query b "hi" :dimensions 8)
```

Turns + parts:

```lisp
(stack-llm:generate b (list (stack-llm:system-turn "be brief")
                            (stack-llm:user-turn "ping")))
```

`stream-generate` / `stream-respond` take `:on-part` (function of an `llm-part`). Settings: `(make-llm-settings :temperature 0)` or `'(:temperature 0)`.

---

## 2. OpenAI-compatible (LM Studio / OpenRouter)

Bind **`http-backend-async` × libuv** (dexador is maintenance). Default base is LM Studio `http://127.0.0.1:1234/v1`.

```lisp
(asdf:load-system "llm-protocol-openai")
(asdf:load-system "event-backend-libuv")
(asdf:load-system "http-backend-async")

(setf http-backend-async:*event-backend-maker*
      #'event-backend-libuv:make-libuv-backend)
(setf http-protocol:*http-backend*
      (http-backend-async:make-async-backend))

(let ((b (stack-llm-openai:make-openai-compat-backend)))
  (stack-llm:llm-response-text
   (stack-llm:generate b "ping"
                       :settings '(:temperature 0 :max-tokens 32)))
  (stack-llm:llm-response-text
   (stack-llm:respond b "ping"
                     :settings '(:temperature 0 :max-tokens 32)))
  (stack-llm:stream-generate b "ping" :on-part #'print)
  (stack-llm:stream-respond b "ping" :on-part #'print)
  (stack-llm:embed-query b "ping"))
```

`OPENAI_API_KEY` / `LM_API_TOKEN` / `OPENAI_BASE_URL` / `OPENAI_MODEL` / `OPENAI_EMBEDDING_MODEL` fill omitted initargs. Default chat model `gpt-4o-mini`; embeddings `text-embedding-3-small`. `list-models` → `GET {base}/models`. `respond` → `POST {base}/responses`. `embed` → `POST {base}/embeddings` (float only).

`stream-generate` → `/chat/completions` `stream: true` (chat.completion.chunk SSE, `[DONE]`). `stream-respond` → `/responses` `stream: true` (`response.output_text.delta`, reasoning deltas, `response.function_call_arguments.*`, `response.completed` / `failed`). Compat servers that stream `/responses` as chat chunks are accepted. `:on-part` gets text/thinking deltas; assembled `llm-response` at EOF.

```lisp
(stack-llm:generate b "add 1 and 2"
  :tools (list (stack-llm:make-llm-tool :name "sum")))
;; finish-reason :tool-use → llm-response-tool-calls
```

`llm-settings-extra` merges onto the JSON body after first-class fields. Live HTTP: `LLM_OPENAI_LIVE=1`.

---

## 3. Anthropic Messages (official / vLLM / llama-server)

Same class. Official default `https://api.anthropic.com/v1`. Bind async × libuv. `max_tokens` required (default 4096). Headers: `x-api-key` **and** `Authorization: Bearer`.

```lisp
(asdf:load-system "llm-protocol-anthropic")

(let ((b (stack-llm-anthropic:make-anthropic-backend)))
  (stack-llm:llm-response-text
   (stack-llm:generate b "ping" :settings '(:temperature 0 :max-tokens 32)))
  (stack-llm:stream-generate b "ping" :on-part #'print))

(stack-llm-anthropic:make-vllm-anthropic-backend)          ; http://127.0.0.1:8000/v1
(stack-llm-anthropic:make-llama-server-anthropic-backend)  ; http://127.0.0.1:8080/v1
```

vLLM / llama-server use **`:dialect :compat`**: native Anthropic `type`s flatten to `{name, input_schema}`; outbound `server_tool_use` → `tool_use`. `:native-tools` is **official only**. vLLM tools need `--enable-auto-tool-choice`. Env: `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` / `ANTHROPIC_VERSION` / `ANTHROPIC_BETA`. `list-models` 404 → default model. Thinking + `signature` round-trip. Not CFFI `llm-backend-llama-cpp`.

Official native tools (`web_search` / `web_fetch` / `code_execution` are **server**; `bash` / `text_editor` / `computer` / `memory` are **client** — you execute `tool_use`):

```lisp
(stack-llm-anthropic:make-web-search-tool :max-uses 3)
(stack-llm-anthropic:make-bash-tool)
```

Server tools land as `server_tool_use` + `*_tool_result` in the same assistant message (finish usually `:stop`). Stream finish is `:tool-use` **only** for a client call. `tool_choice`: `:auto` / `:none` / `:required` → `any` / string → `{type:tool,name}`.

Provider catalog (not LiteLLM, not a router):

```lisp
(let ((cat (stack-llm:make-in-memory-provider-catalog)))
  (stack-llm:register-provider cat "anthropic"
                               (stack-llm-anthropic:make-anthropic-backend))
  (stack-llm:register-provider cat "vllm"
                               (stack-llm-anthropic:make-vllm-anthropic-backend))
  (multiple-value-bind (b model)
      (stack-llm:resolve-backend cat "anthropic:claude-sonnet-4-20250514")
    (stack-llm:generate b "ping" :model model)))
```

Refs: `"anthropic:claude"` / `:vllm` / `("openai" "gpt-4o")`. Missing name → `llm-unknown-provider` (`use-value`).

---

## 4. Native llama.cpp

CFFI to `libllamastack` — not `llama.h`. Overlays: linux/amd64 + windows/amd64 = CUDA+Vulkan; darwin Metal; linux/arm64 CPU. Host supplies `libcuda` / Vulkan ICD. Pin Lisp **0.1.5**; grammar / stream / `:parsed` need an ABI 2+ overlay (ABI 1 = fallback).

```lisp
(asdf:load-system "llm-backend-llama-cpp")

(let ((b (stack-llm-llama-cpp:make-llama-cpp-backend
          :model-path (uiop:getenv "LLAMA_MODEL_PATH"))))
  (stack-llm:llm-response-text (stack-llm:generate b "ping"))
  (stack-llm:stream-generate b "ping" :on-part #'print)
  (stack-llm:embed-query b "ping"))
```

`respond` → `generate`. **No tools** on this backend. `LLAMA_MODEL_PATH` fills an omitted `:model-path`.

GBNF: `:output` (JSON Schema / `schema-protocol`) → `json-schema-to-gbnf`. Raw GBNF is backend-local — **not** an `llm-protocol` field — and wins over `:output`:

```lisp
(stack-llm:generate b "Oslo" :output schema)

(stack-llm:generate b "move"
  :settings (stack-llm-llama-cpp:llama-cpp-settings
             :grammar "root ::= [a-h] [1-8]"))
```

CFFI (same overlay): `llama-cpp:complete` takes `:grammar` / `:grammar-root` (ABI 2), `:on-token` (ABI 3; non-NIL stops), `:parsed` from `parse-grammar` (ABI 4; clone, engine outlives handle).

`backend-supports-p` reports `:structured-output` `:grammar` `:stream`. Embed smoke: [`cl-stack-llm-demo`](https://github.com/egao1980/cl-stack-llm-demo) `scripts/smoke-embed.lisp` (not on GHCR).

---

## 5. Structured output (`schema-protocol` + `schema-protocol-json`)

Not a PydanticAI `Agent` / retry loop. `defschema` is the model; JSON Schema emit is `schema-protocol-json`; parse is `schema-protocol:parse`.

```lisp
(asdf:load-system "llm-protocol/schema")

(stack-schema:defschema city ()
  (name string)
  (country string))

(let ((r (stack-llm:generate b "Capital of Norway as JSON."
                             :output 'city
                             :settings '(:temperature 0 :max-tokens 256))))
  (stack-llm:llm-response-text r)          ; raw JSON string
  (slot-value (stack-llm:llm-response-output r) 'name))  ; "Oslo"
```

`:output` on `generate` / `respond` (or `llm-settings-output`). OpenAI wire is `response_format.json_schema` / Responses `text.format`. Fail → `llm-output-error`. No auto-retry.

Access content: `llm-response-content` (parts), `llm-response-text`, `llm-response-thinking`.

---

## 6. Capability `complete` + catalogue lookup

```lisp
(asdf:load-system "llm-protocol/capability")
(let* ((b (stack-llm:make-mock-llm-backend))
       (cat (stack-llm:make-llm-catalogue b)))
  (stack-capability:capability-supported-p cat :llm-tools)        ; T
  (stack-capability:capability-supported-p cat :llm-embeddings)   ; T (mock)
  (stack-capability:capability-supported-p cat :llm-vision)       ; NIL
  (stack-llm:llm-response-text
   (stack-capability:complete
    (stack-capability:get-capability cat :llm-generation) "hi")))
```

Vocabulary (`catalogue-defines-p :llm :llm-video`) is not the same as an instance (`capability-supported-p cat :llm-video`). `register-llm-backend` copies the live catalogue onto a blackboard. This capability catalogue is **not** `llm-provider-catalog`.

MCP host: do **not** add a second `create-message`. Sampling is `ai-agent-protocol/mcp:make-mcp-sampling-handler` — [ai-agent cookbook](ai-agent.md).

---

## What not to do

- Don’t add `llm-protocol` to `blackboard-protocol` `:depends-on`.
- Don’t treat `/v1/chat/completions` as the protocol — that’s one backend.
- Don’t colocate the OpenAI, Anthropic, or llama.cpp wire in `llm-protocol`.
- Don’t treat the provider catalog as LiteLLM / a router — name → backend only.
- Don’t load `llm-protocol/mcp` — it does not exist.
- Don’t default the HTTP client to dexador — bind async × libuv.
- Don’t clone PydanticAI `Agent` / output-tools / `ModelRetry` — `:output` + `schema-protocol` is enough.
- Don’t put tool *execution* here (capability / [ai-agent](ai-agent.md) / product).
- Don’t put RAG / chunk / vector-store GFs here — [rag-protocol](rag.md).
- Don’t put conversation memory GFs here — [conversation-protocol](conversation.md).
- Don’t put rules / `SKILL.md` GFs here — [steer-protocol](steer.md).
- Don’t put raw GBNF on `llm-protocol` — `llama-cpp-settings` only.
- Don’t fork Autolith `cl-llm-provider-api`.
- Don’t copy Demiurge’s `generate-text` / `generate-with-tools` split.

# Cookbook: LLM generate

**Audience:** call a model from Lisp **without** putting the provider in blackboard core.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol + mock (`stack-llm`) | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.1.0** |
| OpenAI-compat (`stack-llm-openai`) | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) | **0.1.0** |

Brief: [llm.md](../capabilities/llm.md) (#195). Adapter — **not** a `blackboard-protocol` dep. Demiurge **consumes** this.

```lisp
(cl-repo:load-system "llm-protocol" :version "0.1.0")
(cl-repo:load-system "llm-protocol-openai" :version "0.1.0")
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
```

Turns + parts:

```lisp
(stack-llm:generate b (list (stack-llm:system-turn "be brief")
                            (stack-llm:user-turn "ping")))
```

`stream-generate` takes `:on-part` (function of an `llm-part`). Settings: `(make-llm-settings :temperature 0)` or `'(:temperature 0)`.

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
                     :settings '(:temperature 0 :max-tokens 32))))
```

`OPENAI_API_KEY` / `LM_API_TOKEN` / `OPENAI_BASE_URL` / `OPENAI_MODEL` fill omitted initargs. `list-models` → `GET {base}/models`. `respond` → `POST {base}/responses`.

```lisp
(stack-llm:generate b "add 1 and 2"
  :tools (list (stack-llm:make-llm-tool :name "sum")))
;; finish-reason :tool-use → llm-response-tool-calls
```

Wave-1 `stream-generate` / `stream-respond` on this backend signal `llm-unsupported`. Live HTTP: `LLM_OPENAI_LIVE=1`.

---

## 3. Structured output (`schema-protocol` + `schema-protocol-json`)

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

## 4. Capability `complete` + catalogue lookup + MCP sampling

```lisp
(asdf:load-system "llm-protocol/capability")
(let* ((b (stack-llm:make-mock-llm-backend))
       (cat (stack-llm:make-llm-catalogue b)))
  (stack-capability:capability-supported-p cat :llm-tools)   ; T
  (stack-capability:capability-supported-p cat :llm-vision)  ; NIL
  (stack-llm:llm-response-text
   (stack-capability:complete
    (stack-capability:get-capability cat :llm-generation) "hi")))
```

Vocabulary (`catalogue-defines-p :llm :llm-video`) is not the same as an instance (`capability-supported-p cat :llm-video`). `register-llm-backend` copies the live catalogue onto a blackboard.

MCP host: do **not** add a second `create-message`. Sampling is `ai-agent-protocol/mcp` — **not** `llm-protocol`.

```lisp
(asdf:load-system "ai-agent-protocol/mcp")
(setf (mcp-protocol:mcp-client-sampling-handler client)
      (ai-agent-protocol/mcp:make-mcp-sampling-handler :backend b))
```

---

## What not to do

- Don’t add `llm-protocol` to `blackboard-protocol` `:depends-on`.
- Don’t treat `/v1/chat/completions` as the protocol — that’s one backend.
- Don’t colocate the OpenAI wire in `llm-protocol`.
- Don’t default the HTTP client to dexador — bind async × libuv.
- Don’t clone PydanticAI `Agent` / output-tools / `ModelRetry` — `:output` + `schema-protocol` is enough.
- Don’t put tool *execution* here (capability / product).
- Don’t fork Autolith `cl-llm-provider-api`.
- Don’t copy Demiurge’s `generate-text` / `generate-with-tools` split.

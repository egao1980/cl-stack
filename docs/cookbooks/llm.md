# Cookbook: LLM generate

**Audience:** call a model from Lisp **without** putting the provider in blackboard core.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol + mock (`stack-llm`) | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.1.0** |
| OpenAI-compat (`stack-llm-openai`) | [`llm-backend-openai`](https://github.com/egao1980/llm-protocol) | **0.1.0** |

Brief: [llm.md](../capabilities/llm.md) (#195). Adapter — **not** a `blackboard-protocol` dep. Demiurge **consumes** this.

```lisp
(cl-repo:load-system "llm-protocol" :version "0.1.0")
(cl-repo:load-system "llm-backend-openai" :version "0.1.0")
```

---

## 1. Mock

```lisp
(asdf:load-system "llm-protocol")

(let ((b (stack-llm:make-mock-llm-backend)))
  (stack-llm:llm-response-text (stack-llm:generate b "hi")))
;; ⇒ "echo: hi"
```

Turns + parts:

```lisp
(stack-llm:generate b (list (stack-llm:system-turn "be brief")
                            (stack-llm:user-turn "ping")))
```

`stream-generate` takes `:on-part` (function of an `llm-part`). Settings: `(make-llm-settings :temperature 0)` or `'(:temperature 0)`.

---

## 2. OpenAI-compatible (LM Studio / OpenRouter)

Bind an `http-protocol` backend. Default base is LM Studio `http://127.0.0.1:1234/v1`.

```lisp
(asdf:load-system "llm-backend-openai")
(asdf:load-system "http-backend-dexador")
(setf http-protocol:*http-backend* (http-backend-dexador:make-dexador-backend))

(let ((b (stack-llm-openai:make-openai-compat-backend)))
  (stack-llm:llm-response-text
   (stack-llm:generate b "ping"
                       :settings '(:temperature 0 :max-tokens 32))))
```

`OPENAI_API_KEY` / `OPENAI_BASE_URL` / `OPENAI_MODEL` fill omitted initargs. `list-models` → `GET {base}/models`.

```lisp
(stack-llm:generate b "add 1 and 2"
  :tools (list (stack-llm:make-llm-tool :name "sum")))
;; finish-reason :tool-use → llm-response-tool-calls
```

Wave-1 `stream-generate` on this backend signals `llm-unsupported`.

---

## 3. Capability `complete` + catalogue lookup + MCP sampling

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

MCP host: do **not** add a second `create-message`.

```lisp
(asdf:load-system "llm-protocol/mcp")
(setf (mcp-protocol:mcp-client-sampling-handler client)
      (llm-protocol/mcp:make-mcp-sampling-handler :backend b))
```

---

## What not to do

- Don’t add `llm-protocol` to `blackboard-protocol` `:depends-on`.
- Don’t treat `/v1/chat/completions` as the protocol — that’s one backend.
- Don’t put tool *execution* here (capability / product).
- Don’t fork Autolith `cl-llm-provider-api`.
- Don’t copy Demiurge’s `generate-text` / `generate-with-tools` split.

# Cookbook: AG-UI (agent ↔ UI events)

**Audience:** CopilotKit `HttpAgent` / `@ag-ui/core` — stream typed events into a UI.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-ag-ui`) | [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) | **0.2.0** |
| Default backend | [`ag-ui-backend-sse`](https://github.com/egao1980/ag-ui-backend-sse) | **0.2.0** |
| Protobuf-in-SSE | [`ag-ui-backend-protobuf`](https://github.com/egao1980/ag-ui-backend-protobuf) | **0.2.0** |

Brief: [ag-ui.md](../capabilities/ag-ui.md) (#187). **Not JSON-RPC.** Official HTTP is `POST RunAgentInput` → `text/event-stream`.

```lisp
(cl-repo:load-system "ag-ui-protocol" :version "0.2.0")
(cl-repo:load-system "ag-ui-backend-sse" :version "0.2.0")
(cl-repo:load-system "http-server-backend-hunchentoot" :version "0.1.0")
```

---

## 1. Local echo (no HTTP)

```lisp
(use-package :stack-ag-ui)

(let ((agent (make-ag-ui-agent)))
  (run-agent agent
             (make-run-agent-input
              :thread-id "thread_123" :run-id "run_456"
              :messages (list (make-ag-ui-message
                               :role "user" :content "Hello, how are you?")))))
;; ⇒ (RUN_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT
;;    TEXT_MESSAGE_END RUN_FINISHED)
```

Swap the handler for a real agent:

```lisp
(make-ag-ui-agent
 :handler (lambda (input)
            (list (make-run-started-event
                   :thread-id (run-agent-input-thread-id input)
                   :run-id (run-agent-input-run-id input))
                  (make-run-finished-event
                   :thread-id (run-agent-input-thread-id input)
                   :run-id (run-agent-input-run-id input)))))
```

---

## 2. Serve SSE (stock HttpAgent)

```lisp
(asdf:load-system "ag-ui-backend-sse")
(asdf:load-system "http-server-backend-hunchentoot")

(ag-ui-protocol:serve-ag-ui
 (ag-ui-backend-sse:make-sse-ag-ui-backend
  :agent (ag-ui-protocol:make-ag-ui-agent))
 :host "127.0.0.1" :port 8000 :path "/")
```

```bash
curl -sN -X POST http://127.0.0.1:8000/ \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{
    "threadId": "thread_123",
    "runId": "run_456",
    "messages": [{"id":"msg_1","role":"user","content":"Hello, how are you?"}],
    "tools": [],
    "context": [],
    "forwardedProps": {}
  }'
```

Wire frames:

```
data: {"type":"RUN_STARTED","threadId":"thread_123","runId":"run_456"}

data: {"type":"TEXT_MESSAGE_START","messageId":"msg-echo","role":"assistant"}

data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"msg-echo","delta":"Hello, how are you?"}

data: {"type":"TEXT_MESSAGE_END","messageId":"msg-echo"}

data: {"type":"RUN_FINISHED","threadId":"thread_123","runId":"run_456"}
```

Point CopilotKit `HttpAgent` at that URL. Clack app only (no server): `make-ag-ui-app`.

---

## 3. Client consume

```lisp
(asdf:load-system "http-backend-dexador")  ; or async
(let ((backend (ag-ui-backend-sse:make-sse-ag-ui-backend
                :url "http://127.0.0.1:8000/")))
  (ag-ui-protocol:run-agent
   backend
   (ag-ui-protocol:make-run-agent-input
    :thread-id "t" :run-id "r"
    :messages (list (ag-ui-protocol:make-ag-ui-message
                     :role "user" :content "hi")))))
```

Or parse a captured stream: `decode-ag-ui-sse-stream`.

---

## Event types (wave-1)

| Family | Types |
|--------|--------|
| Run | `RUN_STARTED` `RUN_FINISHED` `RUN_ERROR` |
| Step | `STEP_STARTED` `STEP_FINISHED` |
| Text | `TEXT_MESSAGE_START` `TEXT_MESSAGE_CONTENT` `TEXT_MESSAGE_END` |
| Tools | `TOOL_CALL_START` `TOOL_CALL_ARGS` `TOOL_CALL_END` `TOOL_CALL_RESULT` |
| State | `STATE_SNAPSHOT` `STATE_DELTA` (RFC 6902) `MESSAGES_SNAPSHOT` |

Reasoning / activity / subagent families are non-goals. `:format :protobuf` is JSON UTF-8 octets in SSE `data:` until the official Event proto is compiled.

---

## 4. JSON Schema (`schema-protocol-json`)

Events / `RunAgentInput` are `defschema` models. Emit draft-07 (OpenAPI `oneOf` + `discriminator` on `type`):

```lisp
(ag-ui-json-schema 'ag-ui-event)
(ag-ui-json-schema 'run-agent-input)
(validate-ag-ui-json "{\"type\":\"RUN_STARTED\",\"threadId\":\"t\",\"runId\":\"r\"}")
```

Tool `parameters` is a JSON Schema document — validate call args with `validate-tool-arguments`.

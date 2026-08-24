# ag-ui-protocol (P1)

**Issues:** [#187](https://github.com/egao1980/cl-stack/issues/187)  
**Status:** brief **locked** — typed events, **not** JSON-RPC; SSE default + protobuf transport backend

[AG-UI](https://docs.copilotkit.ai/ag-ui/introduction). Agent ↔ UI. Client POSTs `RunAgentInput`; server streams events.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | CLOS events + `run-agent` GF; transports are backends |
| **Default backend (A)** | `ag-ui-backend-sse` — sse-protocol over http-server-protocol |
| **Second backend (B)** | `ag-ui-backend-protobuf` — protobuf-protocol payloads on SSE (or binary) |
| **Not JSON-RPC** | Do not route through `rpc-protocol-json`. Official HTTP is `POST RunAgentInput` → SSE events — that is rpc-protocol `:call-stream` with a later AG-UI codec. |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) |
| SSE (A) | [`egao1980/ag-ui-backend-sse`](https://github.com/egao1980/ag-ui-backend-sse) |
| Protobuf (B) | [`egao1980/ag-ui-backend-protobuf`](https://github.com/egao1980/ag-ui-backend-protobuf) |

## Protocol surface

```lisp
(defclass ag-ui-event ()
  ((type :initarg :type :accessor ag-ui-event-type)
   (timestamp :initarg :timestamp :initform nil)))
(defclass run-agent-input () ())
(defclass ag-ui-backend () ())
(defvar *ag-ui-backend* nil)

(defgeneric run-agent (backend input &key on-event))
(defgeneric encode-ag-ui-event (event &key format))   ; :json | :protobuf
(defgeneric decode-ag-ui-event (source &key format))
(defgeneric serve-ag-ui (backend &key path))

;; wave-1 event types
;; RUN_STARTED RUN_FINISHED RUN_ERROR
;; TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT TEXT_MESSAGE_END
;; TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END TOOL_CALL_RESULT
;; STATE_SNAPSHOT STATE_DELTA MESSAGES_SNAPSHOT
```

`STATE_DELTA` = RFC 6902 JSON Patch.

## Non-goals (wave-1)

- CopilotKit React kit
- Reasoning / activity event families
- Full protobuf binary (non-SSE) transport — backend B may start as protobuf-in-SSE `data:`

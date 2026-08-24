# sse-protocol (P1)

**Issues:** [#184](https://github.com/egao1980/cl-stack/issues/184)  
**Status:** brief **locked** — CLOS protocol + HTTP/Clack backends; **separate repos**

W3C / WHATWG Server-Sent Events (`text/event-stream`). Shared by MCP Streamable HTTP, A2A `message/stream`, AG-UI default transport.

Not a [serdes](serdes.md) format — SSE is **framing** around already-encoded `data:` payloads (JSON-RPC, AG-UI events, …).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backends | Same as http/event. Protocol owns event value + encode/decode. |
| **Default backend (A)** | `sse-backend-http` | Client GET/POST consume via [http-protocol](http-protocol.md) Gray/async body |
| **Second backend (B)** | `sse-backend-clack` | Server emit; Clack app + [http-server-protocol](http-server.md) |
| **Framing** | Protocol, not backends | `id` / `event` / `data` (multi-line) / `retry` / comments / `Last-Event-ID` |
| **Async** | Promises on event-protocol | Match http-protocol DX for long-lived GET |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol + framing + conformance | [`egao1980/sse-protocol`](https://github.com/egao1980/sse-protocol) |
| Client (A) | [`egao1980/sse-backend-http`](https://github.com/egao1980/sse-backend-http) |
| Server (B) | [`egao1980/sse-backend-clack`](https://github.com/egao1980/sse-backend-clack) |

## Protocol surface

Package nick: `stack-sse`.

```lisp
(defclass sse-event ()
  ((id :initarg :id :initform nil :accessor sse-event-id)
   (event :initarg :event :initform nil :accessor sse-event-type)
   (data :initarg :data :initform "" :accessor sse-event-data)
   (retry :initarg :retry :initform nil :accessor sse-event-retry)))

(defclass sse-backend () ())
(defvar *sse-backend* nil)

(defgeneric encode-sse-event (event &key))
(defgeneric decode-sse-block (string &key))
(defgeneric backend-read-sse-event (backend stream &key))
(defgeneric backend-write-sse-event (backend stream event &key flush))
(defgeneric backend-open-sse (backend url &key last-event-id headers timeout))
(defgeneric backend-serve-sse (backend handler &key))

(defun read-sse-event (stream &key (backend *sse-backend*)) …)
(defun write-sse-event (stream event &key (backend *sse-backend*) flush) …)
(defun open-sse (url &key last-event-id headers timeout (backend *sse-backend*)) …)
```

Conditions: `sse-error` → `sse-decode-error` / `sse-protocol-error`.

## Non-goals

- WebSocket EventSource polyfill
- AG-UI protobuf *payload* encoding (that is protobuf-protocol + ag-ui-backend-protobuf)
- Owning JSON-RPC message types (rpc-protocol)

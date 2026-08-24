# rpc-protocol (P1)

**Issues:** [#170](https://github.com/egao1980/cl-stack/issues/170) · related [#106](https://github.com/egao1980/cl-stack/issues/106)  
**Status:** brief **locked** — encoding-agnostic **interaction modes**. Codecs and the gRPC binding are **separate repos**. One GitHub repo per transport.

```text
rpc-protocol          modes: call-response / notify / call-stream / client-stream / bidi-stream
    ├── rpc-protocol-json     JSON-RPC 2.0 codec
    ├── rpc-protocol-grpc     gRPC binding (rpc-transport over grpc-protocol)
    └── rpc-backend-*         JSON-RPC transports (inprocess / stdio / http / sse)
```

gRPC **wire** (channel / status / HTTP/2 / C-core) stays [`grpc-protocol`](grpc.md). Call it through `rpc-protocol-grpc`.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separation** | Modes ≠ codec ≠ process ≠ gRPC wire | Process owns OS; protocol owns call shapes; encodings are format packages |
| **Modes** | `:call-response` `:notify` `:call-stream` `:client-stream` `:bidi-stream` | AG-UI / A2A stream / gRPC map here. `rpc-invoke` dispatches |
| **JSON-RPC** | [`rpc-protocol-json`](https://github.com/egao1980/rpc-protocol-json) | `{jsonrpc:"2.0",…}` only. Do not wrap AG-UI |
| **gRPC** | [`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc) | Adapter. Backends stay `grpc-backend-http2` / `grpc-backend-native` |
| **Default transport (A)** | `rpc-backend-inprocess` — **done** | Tests + same-image unary |
| **Transport (B)** | `rpc-backend-stdio` | MCP default; newline-delimited JSON-RPC over [process-protocol](process.md) |
| **Transport (C)** | `rpc-backend-http` | POST `application/json`; client http-protocol, server Clack |
| **Transport (D)** | `rpc-backend-sse` | JSON-RPC messages as SSE `data:` — MCP Streamable HTTP + A2A stream |
| **Async** | Promises on event-protocol | Match http-protocol DX |

Default stream methods on `rpc-transport` signal unimplemented — unary transports keep working.

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol (modes + codec GFs) | [`egao1980/rpc-protocol`](https://github.com/egao1980/rpc-protocol) **0.2.0** |
| JSON-RPC 2.0 codec | [`egao1980/rpc-protocol-json`](https://github.com/egao1980/rpc-protocol-json) **0.1.0** |
| gRPC binding | [`egao1980/rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc) **0.1.0** |
| In-process (A) | [`egao1980/rpc-backend-inprocess`](https://github.com/egao1980/rpc-backend-inprocess) **0.1.0** |
| stdio (B) | [`egao1980/rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio) |
| HTTP POST (C) | [`egao1980/rpc-backend-http`](https://github.com/egao1980/rpc-backend-http) |
| SSE (D) | [`egao1980/rpc-backend-sse`](https://github.com/egao1980/rpc-backend-sse) |

## Protocol surface

```lisp
(defclass rpc-transport () ())
(defclass rpc-codec () ())
(defclass rpc-stream () ())
(defvar *rpc-transport* nil)
(defvar *rpc-codec* nil)

(defparameter +rpc-interaction-modes+
  '(:call-response :notify :call-stream :client-stream :bidi-stream))

(defun rpc-call (method params &key timeout id transport) …)
(defun rpc-notify (method params &key transport) …)
(defun rpc-call-stream (method params &key timeout id metadata transport) …)
(defun rpc-client-stream (method &key timeout id metadata transport) …)
(defun rpc-bidi-stream (method &key timeout id metadata transport) …)
(defun rpc-send (stream message &key) …)
(defun rpc-recv (stream &key timeout) …)   ; :eof when peer is done
(defun rpc-close (stream-or-transport &key) …)
(defun rpc-invoke (method params &key mode timeout id metadata transport) …)

(defun rpc-serve (handler &key transport) …)
(defun rpc-serve-stream (handler &key transport) …)

;; codec GFs — methods live in rpc-protocol-json (and later codecs)
(defun encode-request (method params &key id codec) …)
(defun encode-notification (method params &key codec) …)
(defun encode-response (result &key id codec) …)
(defun encode-error-response (code message &key id data codec) …)
(defun decode-message (source &key codec) …)
```

Stdio framing (backend B): **newline-delimited** JSON-RPC (MCP). Length-prefix optional escape hatch.

## Non-goals

- Colocating JSON-RPC or gRPC inside `rpc-protocol`
- JSON-RPC-over-gRPC
- Absorbing `grpc-backend-*` into `rpc-protocol-grpc`
- Service discovery / IDL compiler

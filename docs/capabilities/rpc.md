# rpc-protocol (P1)

**Issues:** [#170](https://github.com/egao1980/cl-stack/issues/170) · related [#106](https://github.com/egao1980/cl-stack/issues/106)  
**Status:** brief **locked** — CLOS protocol + **one GitHub repo per transport**. In-process shipped. Stdio / HTTP / SSE are the agent-wire leftovers.

JSON-RPC 2.0. **gRPC is not a transport here** — see [`grpc-protocol`](grpc.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separation** | RPC ≠ process ≠ gRPC | Process owns OS; RPC owns JSON-RPC framing; gRPC is a different protocol |
| **Message model** | JSON-RPC 2.0 (id / method / params / result / error) | MCP + A2A jsonrpc binding |
| **Codec** | serdes `:json` (today: yason in-tree; migrate) | No private encoder long-term |
| **Default transport (A)** | `rpc-backend-inprocess` — **done** | Tests + same-image |
| **Transport (B)** | `rpc-backend-stdio` | MCP default; newline-delimited JSON-RPC over [process-protocol](process.md) |
| **Transport (C)** | `rpc-backend-http` | POST `application/json`; client http-protocol, server Clack |
| **Transport (D)** | `rpc-backend-sse` | JSON-RPC messages as SSE `data:` — MCP Streamable HTTP + A2A stream |
| **Async** | Promises on event-protocol | Match http-protocol DX |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol + codec | [`egao1980/rpc-protocol`](https://github.com/egao1980/rpc-protocol) **0.1.0** |
| In-process (A) | [`egao1980/rpc-backend-inprocess`](https://github.com/egao1980/rpc-backend-inprocess) **0.1.0** |
| stdio (B) | [`egao1980/rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio) |
| HTTP POST (C) | [`egao1980/rpc-backend-http`](https://github.com/egao1980/rpc-backend-http) |
| SSE (D) | [`egao1980/rpc-backend-sse`](https://github.com/egao1980/rpc-backend-sse) |

## Protocol surface

```lisp
(defclass rpc-transport () ())
(defvar *rpc-transport* nil)

(defgeneric backend-rpc-call (transport method params &key timeout id))
(defgeneric backend-rpc-notify (transport method params))
(defgeneric backend-rpc-serve (transport handler &key))

(defun rpc-call (method params &key timeout id (transport *rpc-transport*)) …)
(defun rpc-notify (method params &key (transport *rpc-transport*)) …)
(defun rpc-serve (handler &key (transport *rpc-transport*)) …)

;; codec (protocol)
(defun encode-request (method params &key id) …)
(defun encode-notification (method params) …)
(defun encode-response (result &key id) …)
(defun encode-error-response (code message &key id data) …)
(defun decode-message (string) …)
```

Stdio framing (backend B): **newline-delimited** JSON-RPC (MCP). Length-prefix optional escape hatch.

## Non-goals

- Full gRPC compatibility (that's grpc-protocol)
- Service discovery / IDL compiler

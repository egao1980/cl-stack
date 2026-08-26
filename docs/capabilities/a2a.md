# a2a-protocol (P1)

**Issues:** [#186](https://github.com/egao1980/cl-stack/issues/186)  
**Status:** wave-1 **done** (`a2a-protocol` **0.2.0** + jsonrpc **0.2.1** + httpjson **0.2.0** + grpc **0.2.0**) — CLOS Agent Card / Task; **three binding backends**

[A2A](https://a2a-protocol.org/latest/specification/) (Linux Foundation). Agent ↔ agent. Complementary to MCP (tools/data) and AG-UI (user).

Official bindings: JSON-RPC 2.0 over HTTP+SSE, **gRPC (protobuf)**, HTTP+JSON REST.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | One `a2a-protocol` DX; bindings are backends |
| **Default backend (A)** | `a2a-backend-jsonrpc` — rpc-protocol HTTP + sse-protocol |
| **Backend (B)** | `a2a-backend-grpc` — `rpc-protocol-grpc`; path `/lf.a2a.v1.A2AService/*`. Wave-1 payloads = JSON objects (official proto not compiled). |
| **Backend (C)** | `a2a-backend-httpjson` — REST/JSON on http-protocol |
| **Card** | `/.well-known/agent-card.json` (+ alias `agent.json`). gRPC: local `:agent` / `:card`, or `GetExtendedAgentCard` |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/a2a-protocol`](https://github.com/egao1980/a2a-protocol) |
| JSON-RPC (A) | [`egao1980/a2a-backend-jsonrpc`](https://github.com/egao1980/a2a-backend-jsonrpc) |
| gRPC / protobuf (B) | [`egao1980/a2a-backend-grpc`](https://github.com/egao1980/a2a-backend-grpc) |
| HTTP+JSON (C) | [`egao1980/a2a-backend-httpjson`](https://github.com/egao1980/a2a-backend-httpjson) |

## Protocol surface

```lisp
(defclass a2a-backend () ())
(defclass agent-card () ())
(defclass a2a-task () ())
(defclass a2a-message () ())    ; parts: text / file / data
(defclass a2a-artifact () ())
(defvar *a2a-backend* nil)

(defgeneric fetch-agent-card (backend url &key))
(defgeneric serve-agent-card (backend card &key))
(defgeneric send-message (backend message &key task-id blocking))
(defgeneric stream-message (backend message &key on-event))
(defgeneric get-task (backend task-id &key))
(defgeneric cancel-task (backend task-id &key))
(defgeneric resubscribe-task (backend task-id &key on-event))
```

Task states: `submitted` → `working` → `completed` | `failed` | `canceled` | `rejected` | `input-required`.

## Non-goals (wave-1)

- Push-notification webhooks
- A second public API per binding (backends implement the same GFs)

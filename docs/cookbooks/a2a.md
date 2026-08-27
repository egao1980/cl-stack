# Cookbook: A2A (agent ↔ agent)

**Audience:** call another agent (Python `a2a-sdk` / Node `@a2a-js/sdk`) or serve one.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-a2a`) | [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) | **0.2.0** |
| JSON-RPC (default) | [`a2a-backend-jsonrpc`](https://github.com/egao1980/a2a-backend-jsonrpc) | **0.2.1** |
| HTTP+JSON REST | [`a2a-backend-httpjson`](https://github.com/egao1980/a2a-backend-httpjson) | **0.2.0** |
| gRPC | [`a2a-backend-grpc`](https://github.com/egao1980/a2a-backend-grpc) | **0.2.0** |

Brief: [a2a.md](../capabilities/a2a.md) (#186). Same GFs on every binding. Card: `GET /.well-known/agent-card.json` (alias `agent.json`).

```lisp
(cl-repo:load-system "a2a-protocol" :version "0.2.0")
(cl-repo:load-system "a2a-backend-jsonrpc" :version "0.2.1")
```

---

## 1. Local echo (no HTTP)

```lisp
(use-package :stack-a2a)

(let ((agent (make-a2a-agent :name "echo")))
  (send-message agent (make-a2a-message :text "hello")))
;; ⇒ task :completed with an "echo" artifact
```

---

## 2. Serve JSON-RPC (stock A2A client)

```lisp
(asdf:load-system "a2a-backend-jsonrpc")
(asdf:load-system "http-server-backend-hunchentoot")

(http-server-protocol:serve
 (a2a-backend-jsonrpc:make-a2a-app (a2a-protocol:make-a2a-agent :name "echo"))
 :host "127.0.0.1" :port 8080)
```

```bash
curl -s http://127.0.0.1:8080/.well-known/agent-card.json
curl -s -X POST http://127.0.0.1:8080/ \
  -H "Content-Type: application/json" \
  -H "A2A-Version: 1.0" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{"message":{"role":"user","parts":[{"text":"hi"}]}}}'
```

Client:

```lisp
(asdf:load-system "http-backend-dexador")
(let ((backend (a2a-backend-jsonrpc:make-jsonrpc-a2a-backend
                :url "http://127.0.0.1:8080/")))
  (a2a-protocol:fetch-agent-card backend "http://127.0.0.1:8080/")
  (a2a-protocol:send-message backend
                             (a2a-protocol:make-a2a-message :text "hi")))
```

---

## 3. REST (`a2a-backend-httpjson`)

Same agent, `POST /message:send`, `GET /tasks/{id}`, `POST /message:stream`.

```lisp
(asdf:load-system "a2a-backend-httpjson")
(asdf:load-system "http-server-backend-hunchentoot")
(http-server-protocol:serve
 (a2a-backend-httpjson:make-a2a-app (a2a-protocol:make-a2a-agent :name "echo"))
 :host "127.0.0.1" :port 8080)
```

---

## 4. gRPC (`a2a-backend-grpc`)

Same GFs. Service path `/lf.a2a.v1.A2AService/SendMessage` (official proto).
Wave-1 payloads are JSON objects via `rpc-protocol-grpc` until the proto is compiled.
`rpc-protocol-grpc` server serve is not implemented — local `:agent` loopback, or
`:target` once a `grpc-protocol` backend is bound.

```lisp
(asdf:load-system "a2a-backend-grpc")
(let ((backend (a2a-backend-grpc:make-grpc-a2a-backend
                :agent (a2a-protocol:make-a2a-agent :name "echo"))))
  (a2a-protocol:send-message backend
                             (a2a-protocol:make-a2a-message :text "hi")))
```

Remote:

```lisp
(a2a-backend-grpc:make-grpc-a2a-backend :target "127.0.0.1:8080")
```

---

## Methods (A2A 1.0)

| GF | JSON-RPC / gRPC | REST |
|----|-----------------|------|
| `send-message` | `SendMessage` | `POST /message:send` |
| `stream-message` | `SendStreamingMessage` | `POST /message:stream` |
| `get-task` | `GetTask` | `GET /tasks/{id}` |
| `list-tasks` | `ListTasks` | `GET /tasks` |
| `cancel-task` | `CancelTask` | `POST /tasks/{id}:cancel` |
| `resubscribe-task` | `SubscribeToTask` | JSON-RPC only |

Push-notification configs are non-goals. Interop canary: [`a2a-parity`](https://github.com/egao1980/a2a-parity).

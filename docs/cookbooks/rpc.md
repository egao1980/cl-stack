# Cookbook: RPC (`rpc-protocol`)

**Audience:** JSON-RPC 2.0 over in-process / stdio / HTTP POST / SSE — the wire MCP, A2A, and friends sit on.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-rpc`) | [`rpc-protocol`](https://github.com/egao1980/rpc-protocol) | **0.2.0** |
| JSON-RPC 2.0 codec | [`rpc-protocol-json`](https://github.com/egao1980/rpc-protocol-json) | **0.1.0** |
| In-process | [`rpc-backend-inprocess`](https://github.com/egao1980/rpc-backend-inprocess) | **0.1.0** |
| stdio | [`rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio) | **0.1.1** |
| HTTP POST | [`rpc-backend-http`](https://github.com/egao1980/rpc-backend-http) | **0.1.1** |
| SSE | [`rpc-backend-sse`](https://github.com/egao1980/rpc-backend-sse) | **0.1.1** |
| gRPC binding | [`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc) | **0.1.0** |

Brief: [rpc.md](../capabilities/rpc.md) (#170). Modes live on the protocol; JSON-RPC is a **codec**; transports are backends. **Not** AG-UI (typed events, never a JSON-RPC envelope).

```lisp
(cl-repo:load-system "rpc-protocol" :version "0.2.0")
(cl-repo:load-system "rpc-protocol-json" :version "0.1.0")
(cl-repo:load-system "rpc-backend-inprocess" :version "0.1.0")
```

---

## 1. In-process (tests / same image)

```lisp
(asdf:load-system "rpc-backend-inprocess")

(rpc-protocol:rpc-serve
 (lambda (method params)
   (cond ((equal method "echo") params)
         (t (error 'rpc-protocol:rpc-method-not-found)))))

(rpc-protocol:rpc-call "echo" "hi")
;; ⇒ "hi"
```

Load binds `*rpc-transport*`. `rpc-notify` is fire-and-forget on the same handler.

---

## 2. Stdio (newline JSON-RPC over a subprocess)

MCP’s local default. Framing is **newline-delimited** JSON-RPC, not length-prefix.

```lisp
(asdf:load-system "rpc-backend-stdio")
(asdf:load-system "process-backend-uiop")

(let ((tx (rpc-backend-stdio:make-stdio-rpc-transport
           :command '("sbcl" "--script" "scripts/echo-server.lisp"))))
  (rpc-protocol:rpc-call "echo" "hi" :transport tx))
```

Serve on `*standard-input*` / `*standard-output*` (or `:input` / `:output` streams):

```lisp
(rpc-protocol:rpc-serve
 (lambda (method params)
   (if (equal method "echo") params
       (error 'rpc-protocol:rpc-method-not-found)))
 :transport (rpc-backend-stdio:make-stdio-rpc-transport))
```

Needs `process-protocol:*process-backend*` when using `:command`.

---

## 3. HTTP POST

Client via `http-protocol`; server is a Clack app.

```lisp
(asdf:load-system "rpc-backend-http")
(asdf:load-system "http-backend-dexador")
(asdf:load-system "http-server-backend-hunchentoot")

(http-server-backend-hunchentoot:use-hunchentoot-backend)
(setf http-protocol:*http-backend*
      (http-backend-dexador:make-dexador-backend))

(http-server-protocol:with-server
    (s (rpc-backend-http:make-rpc-app
        (lambda (method params) (declare (ignore method)) params)
        :path "/rpc")
       :host "127.0.0.1" :port 8080)
  (rpc-protocol:rpc-call "echo" "hi"
    :transport (rpc-backend-http:make-http-rpc-transport
                :url "http://127.0.0.1:8080/rpc")))
```

Or `rpc-serve` on an `http-rpc-transport` (binds Hunchentoot if `*http-server-backend*` is nil).

---

## 4. JSON-RPC-over-SSE

POST a JSON-RPC request; the reply is one SSE `message` event whose `data:` is the JSON-RPC response. Used by MCP Streamable HTTP and A2A `message/stream`.

```lisp
(asdf:load-system "rpc-backend-sse")
(asdf:load-system "sse-backend-http")
(asdf:load-system "sse-backend-clack")
(asdf:load-system "http-backend-dexador")
(asdf:load-system "http-server-backend-hunchentoot")

(http-server-backend-hunchentoot:use-hunchentoot-backend)
(setf http-protocol:*http-backend*
      (http-backend-dexador:make-dexador-backend))

(http-server-protocol:with-server
    (s (rpc-backend-sse:make-rpc-sse-app
        (lambda (method params) (declare (ignore method)) params)
        :path "/")
       :host "127.0.0.1" :port 8080)
  (rpc-protocol:rpc-call "echo" "hi"
    :transport (rpc-backend-sse:make-sse-rpc-transport
                :url "http://127.0.0.1:8080/")))
```

Needs `sse-protocol:*sse-backend*` on the client (`sse-backend-http`). `rpc-serve` does not forward `:host` / `:port` — use `make-rpc-sse-app` (or `backend-rpc-serve` with those keys).

---

## Modes

| Mode | GF | Wave-1 transports |
|------|----|-------------------|
| `:call-response` | `rpc-call` | all four |
| `:notify` | `rpc-notify` | all four |
| `:call-stream` / `:client-stream` / `:bidi-stream` | `rpc-call-stream` / … | default methods signal unimplemented |

`rpc-invoke` dispatches on `:mode`. gRPC maps 1:1 except `:notify` (no wire equivalent) — go through [`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc), not `grpc-protocol` from an agent-wire backend.

---

## What not to do

- Don’t wrap AG-UI in JSON-RPC. Official HTTP is `POST RunAgentInput` → SSE of typed events.
- Don’t copy a second JSON-RPC codec into MCP/A2A backends — call `rpc-protocol` GFs.
- Don’t put framing in `process-protocol` — that’s this layer.
- Don’t call `grpc-protocol` from an agent-wire backend — `rpc-protocol-grpc` is the adapter.

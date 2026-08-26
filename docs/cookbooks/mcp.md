# Cookbook: MCP (tools / resources / prompts)

**Audience:** speak [MCP](https://modelcontextprotocol.io/specification/2026-07-28/) as a host or a server. **Not** a wrap of `cl-mcp` (that stays the Lisp-tools product).

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol | [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) | **0.2.0** |
| stdio | [`mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio) | **0.1.1** |
| Streamable HTTP | [`mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) | **0.2.0** |

Brief: [mcp.md](../capabilities/mcp.md) (#185). JSON-RPC via [`rpc-protocol`](rpc.md) — do not invent a second codec. Dual-era: modern **`2026-07-28`** (default) and legacy **`2025-11-25`**. Do **not** treat `2025-06-18` as supported.

```lisp
(cl-repo:load-system "mcp-protocol" :version "0.2.0")
(cl-repo:load-system "rpc-backend-inprocess" :version "0.1.0")
```

---

## 1. Minimal tools server (in-process)

```lisp
(asdf:load-system "mcp-protocol")
(asdf:load-system "rpc-backend-inprocess")

(let* ((server (make-instance 'mcp-protocol:mcp-server
                              :name "demo" :version "0.1.0"))
       (transport (rpc-backend-inprocess:make-inprocess-rpc-transport))
       (client (make-instance 'mcp-protocol:mcp-client :transport transport)))
  (mcp-protocol:register-tool
   server (mcp-protocol:make-mcp-tool
           "ping"
           :description "pong"
           :handler (lambda (args)
                      (declare (ignore args))
                      "pong")))
  (mcp-protocol:serve-mcp server :transport transport)
  (mcp-protocol:mcp-initialize client)   ; discover; non-retryable error → initialize
  (mcp-protocol:call-tool client "ping" (mcp-protocol:json-object)))
```

`call-tool` on the **server** object skips the wire (catalog / handler). A string handler return becomes `tool-result` + `text` content.

Resources / prompts:

```lisp
(mcp-protocol:register-resource
 server (mcp-protocol:make-mcp-resource
         "memo://hi" :name "hi"
         :handler (lambda (res) (declare (ignore res)) "hello")))
(mcp-protocol:read-resource client "memo://hi")
```

Tool `input-schema` is a JSON object; `validate-tool-arguments` goes through `schema-protocol-json` **≥0.1.1**.

---

## 2. Stdio (Inspector-compatible)

Newline JSON-RPC on stdin/stdout, or spawn via `process-protocol`.

```lisp
(asdf:load-system "mcp-backend-stdio")
(asdf:load-system "process-backend-uiop")
(mcp-backend-stdio:use-stdio-mcp-backend)

;; client — :probe t runs mcp-initialize (discover, then legacy if needed)
(let ((client (mcp-protocol:mcp-connect
               :command '("my-mcp-server") :probe t)))
  (mcp-protocol:list-tools client)
  (mcp-protocol:call-tool client "ping" (mcp-protocol:json-object)))

;; server on *standard-input* / *standard-output*
(let ((server (make-instance 'mcp-protocol:mcp-server :name "demo" :version "0.1.0")))
  (mcp-protocol:register-tool
   server (mcp-protocol:make-mcp-tool "ping" :handler (lambda (args)
                                                        (declare (ignore args))
                                                        "pong")))
  (mcp-protocol:mcp-serve server))
```

---

## 3. Streamable HTTP

Single MCP endpoint. POST JSON-RPC; `Accept: text/event-stream` wraps the JSON body as an SSE `message` event. GET is **405** (spec-ok). Client sends `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name` (tool/prompt name or resource URI). Legacy `Mcp-Session-Id` is echoed.

```lisp
(asdf:load-system "mcp-backend-streamable-http")
(asdf:load-system "http-backend-dexador")
(asdf:load-system "http-server-backend-hunchentoot")
(mcp-backend-streamable-http:use-streamable-http-mcp-backend)
(http-server-backend-hunchentoot:use-hunchentoot-backend)
(setf http-protocol:*http-backend*
      (http-backend-dexador:make-dexador-backend))

(let ((server (make-instance 'mcp-protocol:mcp-server :name "demo" :version "0.1.0")))
  (mcp-protocol:register-tool
   server (mcp-protocol:make-mcp-tool "ping" :handler (lambda (args)
                                                        (declare (ignore args))
                                                        "pong")))
  (mcp-protocol:mcp-serve server :host "127.0.0.1" :port 8080))

(let ((client (mcp-protocol:mcp-connect :url "http://127.0.0.1:8080/" :probe t)))
  (mcp-protocol:call-tool client "ping" (mcp-protocol:json-object)))
```

MUST-gaps: present `Origin` not allowed → **403** (`:allowed-origins` on `make-mcp-app`; default matches `Host`). Header/body mismatch → JSON-RPC **`-32020`**, HTTP **400**. Notification POST (no `id`) → **202** empty body.

---

## Dual-era

| Era | Revision | Handshake |
|-----|----------|-----------|
| **Modern** (default) | `2026-07-28` | stateless `_meta` + `server/discover`; `resultType` |
| **Legacy** | `2025-11-25` | `initialize` + `notifications/initialized` |

Client prefers discover. Retryable `-32022` `UnsupportedProtocolVersion` → listed version. **Any** other discover error (FastMCP 3 uses `-32602`) → `initialize`. Cache era for the process/origin lifetime.

---

## Spec GFs (protocol, even if I/O is thin)

tools / resources / prompts / templates · completions · subscriptions · sampling · elicitation · roots · logging · progress · MRTR `input_required`. OAuth stays transport-level. Canary: [`mcp-parity`](https://github.com/egao1980/mcp-parity) (Lisp ↔ FastMCP 3 / official Node SDK v2, stdio + Streamable HTTP).

---

## What not to do

- Don’t wrap `cl-mcp` — this protocol is the reusable wire; that product may consume it later.
- Don’t invent a second JSON-RPC — `rpc-protocol` + `rpc-backend-*`.
- Don’t treat `2025-06-18` as a supported era.
- Don’t put blackboard / KSAR / workspaces here — [blackboard.md](../capabilities/blackboard.md).

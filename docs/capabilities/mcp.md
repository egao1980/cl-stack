# mcp-protocol (P1)

**Issues:** [#185](https://github.com/egao1980/cl-stack/issues/185)  
**Status:** brief **locked** — CLOS client/server; transports are backends

[MCP](https://modelcontextprotocol.io/specification/2025-06-18) (also 2025-11-25). JSON-RPC 2.0. **Not** a wrap of `cl-ai-project/cl-mcp`.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `mcp-protocol` GFs + transport backends |
| **RPC** | [`rpc-protocol`](rpc.md) — do not invent a second JSON-RPC |
| **Default backend (A)** | `mcp-backend-stdio` — newline JSON-RPC via `rpc-backend-stdio` |
| **Second backend (B)** | `mcp-backend-streamable-http` — POST JSON or SSE; optional GET SSE |
| **Product** | `cl-mcp` stays Lisp-tools; may consume this later |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/mcp-protocol`](https://github.com/egao1980/mcp-protocol) |
| stdio (A) | [`egao1980/mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio) |
| Streamable HTTP (B) | [`egao1980/mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) |

## Protocol surface

```lisp
(defclass mcp-peer () ())
(defclass mcp-server (mcp-peer) ())
(defclass mcp-client (mcp-peer) ())
(defclass mcp-backend () ())
(defclass mcp-tool () ())
(defclass mcp-resource () ())
(defvar *mcp-backend* nil)

(defgeneric mcp-initialize (peer &key protocol-version capabilities client-info server-info))
(defgeneric list-tools (server &key cursor))
(defgeneric call-tool (server name arguments &key))
(defgeneric list-resources (server &key cursor))
(defgeneric read-resource (server uri &key))
(defgeneric list-prompts (server &key))
(defgeneric get-prompt (server name &key arguments))
```

Wave-1 methods: `initialize` / `initialized` / `ping` / `notifications/cancelled` / tools / resources / prompts.

## Non-goals (wave-1)

- Sampling, elicitation, roots, completions
- Replacing cl-mcp tools
- Legacy HTTP+SSE (`2024-11-05`) except a cheap compat shim

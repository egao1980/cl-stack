# mcp-protocol (P1)

**Issues:** [#185](https://github.com/egao1980/cl-stack/issues/185)  
**Status:** brief **locked** — CLOS client/server; transports are backends; **dual-era**

[MCP](https://modelcontextprotocol.io/specification/2026-07-28/) current revision **`2026-07-28`** (modern / stateless). Last handshake revision **`2025-11-25`** (legacy). JSON-RPC 2.0 via [`rpc-protocol`](rpc.md). **Not** a wrap of `cl-ai-project/cl-mcp`. Do **not** treat `2025-06-18` as a supported era.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `mcp-protocol` GFs + transport backends |
| **RPC** | [`rpc-protocol`](rpc.md) — do not invent a second JSON-RPC |
| **Eras** | **Modern** = `2026-07-28`+ per-request `_meta`. **Legacy** = `2025-11-25` initialize handshake. Implement **both**. |
| **Default / preferred** | Modern: `server/discover` first. `-32022` → retry listed version. Any other discover error / timeout on stdio → `initialize`. Cache era for process/origin lifetime. |
| **Default backend (A)** | `mcp-backend-stdio` — newline JSON-RPC via `rpc-backend-stdio` |
| **Second backend (B)** | `mcp-backend-streamable-http` — POST JSON or SSE; GET SSE optional (wave-1: 405) |
| **Product** | `cl-mcp` stays Lisp-tools; may consume this later |

## Dual-era wire

**Modern** (`2026-07-28`): no `initialize` / `initialized`, no `Mcp-Session-Id`. Every request is self-describing via `params._meta`:

```
io.modelcontextprotocol/protocolVersion     = "2026-07-28"
io.modelcontextprotocol/clientInfo          = {name, version}
io.modelcontextprotocol/clientCapabilities
result._meta.io.modelcontextprotocol/serverInfo
```

Mandatory `server/discover`. Results **MUST** include `resultType` (`"complete"` | `"input_required"`). HTTP headers: `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`. Unsupported version → JSON-RPC `-32022` `UnsupportedProtocolVersion` with `{supported, requested}`.

**Legacy** (`2025-11-25`): `initialize` + `notifications/initialized`. Session-scoped. Initialize result has **no** `resultType`.

Dual-era **server**: `_meta` protocolVersion → stateless modern (reject unknown with `-32022`); method `initialize` → legacy handshake; `server/discover` always answered.

Dual-era **client**: prefer modern. Fall back to legacy as above.

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/mcp-protocol`](https://github.com/egao1980/mcp-protocol) |
| stdio (A) | [`egao1980/mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio) |
| Streamable HTTP (B) | [`egao1980/mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) |
| Interop canary | [`egao1980/mcp-parity`](https://github.com/egao1980/mcp-parity) — Lisp ↔ FastMCP 3 / official Node SDK v2 (stdio) |

## Protocol surface

```lisp
(defclass mcp-peer () ())
(defclass mcp-server (mcp-peer) ())
(defclass mcp-client (mcp-peer) ())
(defclass mcp-backend () ())
(defclass mcp-tool () ())
(defclass mcp-resource () ())
(defvar *mcp-backend* nil)

(defgeneric mcp-discover (peer &key protocol-version capabilities client-info))
(defgeneric mcp-initialize (peer &key protocol-version capabilities client-info server-info))
(defgeneric list-tools (peer &key cursor))
(defgeneric call-tool (peer name arguments &key))
(defgeneric list-resources (peer &key cursor))
(defgeneric read-resource (peer uri &key))
(defgeneric list-prompts (peer &key))
(defgeneric get-prompt (peer name &key arguments))
```

Wave-1 methods: `server/discover` · `initialize` / `initialized` · `ping` · `notifications/cancelled` · tools / resources / prompts.

`mcp-initialize` on a dual-era client probes `server/discover` first (`era` `:unknown` / `:modern`) and only sends `initialize` when the peer is legacy (`era` `:legacy`, or discover failed).

**Spec surface (GFs + CLOS, even if backend I/O is thin):** sampling (`create-message`, `mcp-sampling-request`), elicitation, roots, completions, subscriptions, logging, progress, MRTR `input_required`. Host `mcp-client-sampling-handler` may call a future `llm-protocol` — that is **not** the [blackboard](blackboard.md) loop.

## Non-goals (wave-1)

- Auth / OAuth, Tasks extension
- Replacing cl-mcp tools
- Legacy HTTP+SSE (`2024-11-05`) except a cheap compat shim
- Blackboard / KSAR / workspaces (→ [blackboard.md](blackboard.md))

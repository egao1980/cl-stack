# mcp-protocol (P1)

**Issues:** [#185](https://github.com/egao1980/cl-stack/issues/185)  
**Status:** wave-1 **done** (`mcp-protocol` **0.2.0** + stdio **0.1.1** + Streamable HTTP **0.2.0**). Current `mcp-protocol` **0.3.1** + stdio **0.2.0** + Streamable HTTP **0.3.0**: tool annotations, server notifications, templated resources + `resources/subscribe`, tool-argument repair · cookbook [mcp.md](../cookbooks/mcp.md)

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
| Protocol | [`egao1980/mcp-protocol`](https://github.com/egao1980/mcp-protocol) **0.2.0** |
| stdio (A) | [`egao1980/mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio) **0.1.1** |
| Streamable HTTP (B) | [`egao1980/mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) **0.2.0** |
| Interop canary | [`egao1980/mcp-parity`](https://github.com/egao1980/mcp-parity) — Lisp ↔ FastMCP 3 / official Node SDK v2 (stdio + Streamable HTTP) |

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

**Spec surface (GFs + CLOS, even if backend I/O is thin):** sampling (`create-message`, `mcp-sampling-request`), elicitation, roots, completions, subscriptions, logging, progress, MRTR `input_required`. Host `mcp-client-sampling-handler` is `ai-agent-protocol/mcp:make-mcp-sampling-handler` — **not** `llm-protocol`. That is **not** the [blackboard](blackboard.md) loop. See [ai-agent.md](ai-agent.md).

## Non-goals (wave-1)

- Auth / OAuth, Tasks extension
- Replacing cl-mcp tools
- Legacy HTTP+SSE (`2024-11-05`) except a cheap compat shim
- Blackboard / KSAR / workspaces (→ [blackboard.md](blackboard.md))

## 0.4.0 — the client side for hosts (locked)

Issue [mcp-protocol#14](https://github.com/egao1980/mcp-protocol/issues/14), contract [mcp-protocol#15](https://github.com/egao1980/mcp-protocol/pull/15) (branch `agent/h3e2-mcp-protocol-contract-0943`, team-solve). Rules: the header of `src/client.lisp`. Needed by ai-agent-protocol/mcp 0.2.0 and cl-stack-code's MCP servers ([cl-stack-code.md, H3e-2](cl-stack-code.md#h3e-2--locked)). Prior art: pydantic-ai's MCP client.

| Topic | Rule |
|-------|------|
| **Tool fields** | `%parse-tool` keeps title, outputSchema, annotations, icons and `_meta`; the server emits icons and `_meta` too. `mcp-tool-annotation`, `mcp-tool-read-only-p` (readOnlyHint exactly true), `mcp-tool-visible-to-model-p` (`_meta.ui.visibility` without `"model"` → hidden). Hints are untrusted: hosts may lower a default with them, never raise trust. |
| **Pagination** | `list-tools` → `(values tools next-cursor)`; `list-all-tools` follows the cursor; a repeated cursor or more than `+max-tool-pages+` pages → `mcp-pagination-error`, restart `continue`. |
| **Server messages** | `mcp-client-handle-notification` (list_changed bumps `mcp-client-tools-generation` and calls `on-tools-changed`; message → the log handler; progress → the progress handler; then `notification-hook`; handler errors dropped). `mcp-client-handle-request` (ping, sampling, elicitation, roots; -32601 otherwise). `mcp-client-transport-handlers` → the two closures rpc-backend-stdio's transport takes; mcp-backend-stdio 0.3.0 wires them ([#7](https://github.com/egao1980/mcp-backend-stdio/issues/7)). Modern-era servers notify only during a request, so hosts can turn caching off per server. |
| **Timeouts** | `call-tool` / `list-tools` `:timeout` with client ids `"mcp-N"`; on timeout `notifications/cancelled` (reason `timeout`) and `mcp-timeout` (code -32001). The elapsed time decides, since transports name their timeouts differently. |
| **Tests** | `tests/client-test.lisp` over rpc-backend-stdio's in-memory pipe pair: a real client transport and reader thread, the server's serve loop in a thread. |

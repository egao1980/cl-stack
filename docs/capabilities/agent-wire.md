# Agent wire layer (MCP / A2A / AG-UI)

**Issues:** [#170](https://github.com/egao1980/cl-stack/issues/170) rpc · [#184](https://github.com/egao1980/cl-stack/issues/184) sse · [#185](https://github.com/egao1980/cl-stack/issues/185) mcp · [#186](https://github.com/egao1980/cl-stack/issues/186) a2a · [#187](https://github.com/egao1980/cl-stack/issues/187) ag-ui  
**Status:** layout **locked** — CLOS protocol + backend **per GitHub repo** (event/http-server precedent, not json-protocol colocated backends)

HTTP **client** ([http-protocol](http-protocol.md)) and **server** ([http-server.md](http-server.md)) are done. This wave adds the **wire codecs and RPC bindings** those stacks do not own, then the three agent-interop protocols on top.

```text
MCP / A2A / AG-UI          ← agent protocols (domain CLOS)
        │
 rpc-protocol              sse-protocol   protobuf-protocol
    ├── rpc-protocol-json                         │
    └── rpc-protocol-grpc ── grpc-protocol        │
            │                    │                │
      transports            http2/native     cl-protobufs
            │
 http-protocol / http-server-protocol / process-protocol / event-protocol
```

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `foo-protocol` generics + `foo-backend-*` `defmethod`s. One GitHub repo per layer. |
| **No colocated backends** | Unlike `json-protocol` (jzon/yason in-tree). Natives, HTTP attach, and agent bindings have different CI/deps. |
| **Selection DX** | ASDF load + `*foo-backend*` / `*rpc-transport*`. No plugin registry. |
| **Codecs** | JSON via [serdes](serdes.md) `:json`. Protobuf implements serdes `:protobuf`. SSE is **framing**, not a serdes format. |
| **RPC modes** | [`rpc-protocol`](rpc.md) owns `:call-response` / `:notify` / `:call-stream` / `:client-stream` / `:bidi-stream`. |
| **JSON-RPC** | Separate repo [`rpc-protocol-json`](https://github.com/egao1980/rpc-protocol-json). Transports stay `rpc-backend-*`. Do not wrap AG-UI. |
| **gRPC** | Binding [`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc). Wire/channel stays [`grpc-protocol`](grpc.md) + `grpc-backend-*`. A2A protobuf is a **backend** of `a2a-protocol`. |
| **cl-mcp** | Lisp-tools *product*. Does **not** become `mcp-protocol`. May consume it later. |

## Repo matrix

### Wire (do first)

| Repo | Role | Depends on (done) |
|------|------|-------------------|
| [`sse-protocol`](https://github.com/egao1980/sse-protocol) | `sse-event`, encode/decode, read/write GFs | — |
| [`sse-backend-http`](https://github.com/egao1980/sse-backend-http) | Client consume via http-protocol stream body | http-protocol, event-protocol |
| [`sse-backend-clack`](https://github.com/egao1980/sse-backend-clack) | Server emit as Clack `text/event-stream` | http-server-protocol |
| [`rpc-protocol-json`](https://github.com/egao1980/rpc-protocol-json) | JSON-RPC 2.0 codec | rpc-protocol |
| [`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc) | gRPC binding (`rpc-transport` over grpc-protocol) | rpc-protocol, grpc-protocol |
| [`rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio) | Newline JSON-RPC over process-protocol | rpc-protocol, rpc-protocol-json, process-protocol |
| [`rpc-backend-http`](https://github.com/egao1980/rpc-backend-http) | JSON-RPC POST (client + Clack app) | rpc-protocol, rpc-protocol-json, http-protocol, http-server-protocol |
| [`rpc-backend-sse`](https://github.com/egao1980/rpc-backend-sse) | JSON-RPC messages as SSE events | rpc-protocol, rpc-protocol-json, sse-protocol |
| [`protobuf-protocol`](https://github.com/egao1980/protobuf-protocol) | serdes `:protobuf` + proto message GFs | serdes-protocol |
| [`protobuf-backend-cl-protobufs`](https://github.com/egao1980/protobuf-backend-cl-protobufs) | Default — egao1980/cl-protobufs | WKT vendored (`2.0-rc2+`); unix plugin overlay |
| [`grpc-protocol`](https://github.com/egao1980/grpc-protocol) | gRPC wire: channel / status / connect | — |
| [`grpc-backend-http2`](https://github.com/egao1980/grpc-backend-http2) | Unary over http-protocol H2 (Windows-safe) | grpc-protocol, http-protocol |
| [`grpc-backend-native`](https://github.com/egao1980/grpc-backend-native) | qitab/grpc C-core (linux/darwin) | grpc-protocol |

Already shipped: [`rpc-protocol`](https://github.com/egao1980/rpc-protocol), [`rpc-backend-inprocess`](https://github.com/egao1980/rpc-backend-inprocess).

### Agent protocols (after wire)

| Repo | Role | Backends |
|------|------|----------|
| [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) | dual-era MCP: modern `2026-07-28` (`server/discover` + `_meta` + SEP-2549 `ttlMs`/`cacheScope`) and legacy `2025-11-25` (`initialize`); tools / resources / prompts. Canary: [`mcp-parity`](https://github.com/egao1980/mcp-parity) | [`mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio), [`mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) |
| [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) | Agent Card, Task, Message, Artifact | [`a2a-backend-jsonrpc`](https://github.com/egao1980/a2a-backend-jsonrpc), [`a2a-backend-grpc`](https://github.com/egao1980/a2a-backend-grpc), [`a2a-backend-httpjson`](https://github.com/egao1980/a2a-backend-httpjson) |
| [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) | `RunAgentInput` + typed events | [`ag-ui-backend-sse`](https://github.com/egao1980/ag-ui-backend-sse), [`ag-ui-backend-protobuf`](https://github.com/egao1980/ag-ui-backend-protobuf) |

One app DX per domain. Swap wire by loading a different backend system.

## Impl order

1. `sse-protocol` (framing is self-contained) + http/clack backends  
2. `rpc-backend-stdio` + `rpc-backend-http` + `rpc-backend-sse`  
3. `protobuf-protocol` + cl-protobufs backend (serdes `:protobuf`)  
4. `grpc-protocol` + native backend  
5. `mcp-protocol` + stdio + Streamable HTTP  
6. `a2a-protocol` + jsonrpc (then grpc, then REST)  
7. `ag-ui-protocol` + SSE (protobuf transport after)

## Blackboard core (sibling, not this layer)

How an agent **thinks** is [blackboard.md](blackboard.md) + [capability.md](capability.md) — KSAR loop, COW workspaces, CLOS capabilities. **Zero** agent-wire deps.

This file stays **how agents talk**. Adapters (later) may project capabilities as MCP tools, write A2A `send-message` → `:pending-task`, or stream AG-UI events from the board. They do not live in `blackboard-protocol`.

Product that composes both: `egao1980/demiurge` (same stance as `cl-mcp` vs `mcp-protocol`).

## Non-goals

- Extracting a protocol from `cl-ai-project/cl-mcp`
- Colocating backends under the protocol repo
- Colocating JSON-RPC or gRPC inside `rpc-protocol`
- JSON-RPC-over-gRPC
- Implementing MCP/A2A/AG-UI before SSE + JSON-RPC transports exist
- Putting an LLM turn loop or `agent-protocol` inside agent-wire
- Making blackboard-protocol depend on MCP / A2A / AG-UI

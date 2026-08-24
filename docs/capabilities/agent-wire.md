# Agent wire layer (MCP / A2A / AG-UI)

**Issues:** [#170](https://github.com/egao1980/cl-stack/issues/170) rpc · [#184](https://github.com/egao1980/cl-stack/issues/184) sse · [#185](https://github.com/egao1980/cl-stack/issues/185) mcp · [#186](https://github.com/egao1980/cl-stack/issues/186) a2a · [#187](https://github.com/egao1980/cl-stack/issues/187) ag-ui  
**Status:** layout **locked** — CLOS protocol + backend **per GitHub repo** (event/http-server precedent, not json-protocol colocated backends)

HTTP **client** ([http-protocol](http-protocol.md)) and **server** ([http-server.md](http-server.md)) are done. This wave adds the **wire codecs and RPC bindings** those stacks do not own, then the three agent-interop protocols on top.

```text
MCP / A2A / AG-UI          ← agent protocols (domain CLOS)
        │
 rpc-protocol   sse-protocol   protobuf-protocol   grpc-protocol
        │              │              │                  │
   transports      HTTP/Clack     cl-protobufs      qitab/grpc
        │              │
 http-protocol / http-server-protocol / process-protocol / event-protocol
```

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `foo-protocol` generics + `foo-backend-*` `defmethod`s. One GitHub repo per layer. |
| **No colocated backends** | Unlike `json-protocol` (jzon/yason in-tree). Natives, HTTP attach, and agent bindings have different CI/deps. |
| **Selection DX** | ASDF load + `*foo-backend*` / `*rpc-transport*`. No plugin registry. |
| **Codecs** | JSON via [serdes](serdes.md) `:json`. Protobuf implements serdes `:protobuf`. SSE is **framing**, not a serdes format. |
| **JSON-RPC** | Stays [`rpc-protocol`](rpc.md). New transports are **separate repos**. gRPC is **not** an rpc-protocol transport. |
| **gRPC** | Own [`grpc-protocol`](grpc.md). A2A protobuf binding is a **backend** of `a2a-protocol`, not a second A2A API. |
| **cl-mcp** | Lisp-tools *product*. Does **not** become `mcp-protocol`. May consume it later. |

## Repo matrix

### Wire (do first)

| Repo | Role | Depends on (done) |
|------|------|-------------------|
| [`sse-protocol`](https://github.com/egao1980/sse-protocol) | `sse-event`, encode/decode, read/write GFs | — |
| [`sse-backend-http`](https://github.com/egao1980/sse-backend-http) | Client consume via http-protocol stream body | http-protocol, event-protocol |
| [`sse-backend-clack`](https://github.com/egao1980/sse-backend-clack) | Server emit as Clack `text/event-stream` | http-server-protocol |
| [`rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio) | Newline JSON-RPC over process-protocol | rpc-protocol, process-protocol |
| [`rpc-backend-http`](https://github.com/egao1980/rpc-backend-http) | JSON-RPC POST (client + Clack app) | rpc-protocol, http-protocol, http-server-protocol |
| [`rpc-backend-sse`](https://github.com/egao1980/rpc-backend-sse) | JSON-RPC messages as SSE events | rpc-protocol, sse-protocol |
| [`protobuf-protocol`](https://github.com/egao1980/protobuf-protocol) | serdes `:protobuf` + proto message GFs | serdes-protocol |
| [`protobuf-backend-cl-protobufs`](https://github.com/egao1980/protobuf-backend-cl-protobufs) | Default — egao1980/cl-protobufs | WKT vendored (`2.0-rc2+`); unix plugin overlay |
| [`grpc-protocol`](https://github.com/egao1980/grpc-protocol) | channel / unary / stream GFs | — |
| [`grpc-backend-http2`](https://github.com/egao1980/grpc-backend-http2) | Unary over http-protocol H2 (Windows-safe) | grpc-protocol, http-protocol |
| [`grpc-backend-native`](https://github.com/egao1980/grpc-backend-native) | qitab/grpc C-core (linux/darwin) | grpc-protocol |

Already shipped: [`rpc-protocol`](https://github.com/egao1980/rpc-protocol), [`rpc-backend-inprocess`](https://github.com/egao1980/rpc-backend-inprocess).

### Agent protocols (after wire)

| Repo | Role | Backends |
|------|------|----------|
| [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) | initialize / tools / resources / prompts | [`mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio), [`mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) |
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

## Non-goals

- Extracting a protocol from `cl-ai-project/cl-mcp`
- Colocating backends under the protocol repo
- Treating gRPC as `rpc-protocol` transport B
- Implementing MCP/A2A/AG-UI before SSE + JSON-RPC transports exist

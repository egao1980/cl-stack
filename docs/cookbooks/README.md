# Cookbooks

Task-oriented recipes (Python/Java analogues → stack packages).

**New here?** Install path + pins → [QUICKSTART.md](../QUICKSTART.md).

| Cookbook | Package(s) |
|----------|------------|
| [HTTP client](http-client.md) | `cl-stack-http` / `http-protocol` (requests · httpx) |
| [JSON](json.md) | `json-protocol` / jzon · yason · `cl-stack-http` |
| [Serdes](serdes.md) | `serdes-protocol` / `sexp-protocol` / `json-protocol` (JSONL · events) |
| [Object streams](io.md) | `io-protocol` (ObjectInput/Output · prin1/read) |
| [Config](config.md) | `cl-stack-config` (TOML + env) |
| [WebSocket](websocket.md) | `ws-protocol` / async · winhttp · websocket-driver |
| [HTTP server](http-server.md) | `http-server-protocol` / Hunchentoot · Woo · Clack env |
| [CLI](cli.md) | `cli-protocol` / clingon · adopt · Windows dialects |
| [Logging](logging.md) | `log-protocol` / log4cl · vom · text + structured |
| [SQL](sql.md) | `sql-protocol` / `sql-query` / `sql-orm` (Engine · Core · ORM) |
| [Crypto & secrets](crypto.md) | `crypto-protocol` / `secrets-protocol` (seal · digest · tokens · Argon2) |
| [Subprocess](process.md) | `process-protocol` / `process-backend-uiop` (`run` · `launch`) |
| [RPC](rpc.md) | `rpc-protocol` / JSON-RPC · in-process · stdio · HTTP · SSE |
| [SSE](sse.md) | `sse-protocol` / http client · Clack server (`text/event-stream`) |
| [MCP](mcp.md) | `mcp-protocol` / stdio · Streamable HTTP (tools / resources / prompts) |
| [AG-UI](ag-ui.md) | `ag-ui-protocol` / SSE · protobuf-in-SSE (`RunAgentInput` → events) |
| [A2A](a2a.md) | `a2a-protocol` / JSON-RPC · REST · gRPC (Agent Card + tasks) |
| [Blackboard](blackboard.md) | `blackboard-protocol` / `capability-protocol` (KSAR + COW, no AI wire) |
| [LLM](llm.md) | `llm-protocol` / `llm-protocol-openai` (turns + parts, OpenAI-compat) — gaps: [AI-GAP.md](../AI-GAP.md) |
| [Unicode / i18n / l10n](unicode.md) | `unicode-protocol` / `i18n-protocol` / `l10n-protocol` (+ ICU · ICU4J · sb-unicode) |

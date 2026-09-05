# Cookbooks

Task-oriented recipes (Python/Java analogues → stack packages).

**New here?** Install path + pins → [QUICKSTART.md](../QUICKSTART.md).

| Cookbook | Package(s) |
|----------|------------|
| [HTTP client](http-client.md) | `cl-stack-http` / `http-protocol` (requests · httpx) |
| [JSON](json.md) | `json-protocol` / jzon · yason · `cl-stack-http` |
| [XML](xml.md) | `xml-protocol` / `xml-backend-native` (Infoset · events · `:xml`) |
| [CSV](csv.md) | `csv-protocol` (`:csv` / `:tsv` · dialects) |
| [Serdes](serdes.md) | `serdes-protocol` / formats incl. MIME · CBOR · msgpack · Avro · `encoding-protocol` (JSONL · events) |
| [Object streams](io.md) | `io-protocol` (ObjectInput/Output · prin1/read) |
| [Config](config.md) | `cl-stack-config` (TOML + env) |
| [WebSocket](websocket.md) | `ws-protocol` / async · winhttp · websocket-driver |
| [HTTP server](http-server.md) | `http-server-protocol` / Hunchentoot · Woo · Clack env |
| [CLI](cli.md) | `cli-protocol` / clingon · adopt · Windows dialects |
| [Logging](logging.md) | `log-protocol` / `log-backend-log4cl` · `log-backend-vom` · text + structured |
| [SQL](sql.md) | `sql-protocol` / `sql-query` / `sql-orm` (Engine · Core · ORM) |
| [Crypto & secrets](crypto.md) | `crypto-protocol` / `secrets-protocol` (seal · digest · tokens · Argon2) |
| [Subprocess](process.md) | `process-protocol` / `process-backend-uiop` (`run` · `launch`) |
| [RPC](rpc.md) | `rpc-protocol` / JSON-RPC · in-process · stdio · HTTP · SSE |
| [SSE](sse.md) | `sse-protocol` / http client · Clack server (`text/event-stream`) |
| [MCP](mcp.md) | `mcp-protocol` / stdio · Streamable HTTP (tools / resources / prompts) |
| [AG-UI](ag-ui.md) | `ag-ui-protocol` **0.3.0** / SSE · WKT proto · TUI sink (`RunAgentInput` → 36 events) |
| [A2A](a2a.md) | `a2a-protocol` / JSON-RPC · REST · gRPC (Agent Card + tasks) |
| [AI agent](ai-agent.md) | `ai-agent-protocol` **0.2.0** (`run-ai-agent`; `/mcp` sampling; not `run-agent`) |
| [Blackboard](blackboard.md) | `blackboard-protocol` / `capability-protocol` (KSAR + COW, no AI wire) |
| [LLM](llm.md) | `llm-protocol` **0.2.0** / OpenAI **0.3.0** / llama.cpp (generate · stream · embed) |
| [Schema](schema.md) | `schema-protocol` / `schema-protocol-json` / `schema-protocol-xsd` (`defschema` · JSON Schema · XSD) |
| [Date / time / TZ](datetime.md) | `datetime-protocol` / `cl-stack-tzdata` / `cl-stack-calendars` |
| [Conditions / restarts](conditions.md) | CLHS 9 — HTTP / FS / subprocess |
| [Unicode / i18n / l10n](unicode.md) | `unicode-protocol` / `i18n-protocol` / `l10n-protocol` (+ ICU · ICU4J · sb-unicode) |

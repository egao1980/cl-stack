# cl-stack API conventions

**Install / first load:** [QUICKSTART.md](QUICKSTART.md).

**Style:** CLOS protocols + Python-grade DX. Not Java SPI, not Boost policies.

## Layers

1. **`foo-protocol`** — tiny ASDF system: generic functions, conditions, value types. Almost no deps.
2. **`cl-stack/foo` facade** — keyword-heavy helpers with sane defaults. What cookbooks teach.
3. **`foo-backend-*`** — `defmethod`s; selected by ASDF / pins, not a plugin DSL.

## Rules

- Keywords over positionals for user-facing APIs.
- Conditions (+ restarts where useful), not status-code-only errors.
- One app-level async DX (promise xor callback xor await-macro); **multiple event-loop backends** via `event-protocol`.
- `with-` macros + `unwind-protect` for resources.
- No god base classes.
- Escape hatches for experts (`raw-*` or inject upstream objects).

## Wave-1 protocol set

- `event-protocol` — run / defer / cancel / sleep / register-io; multi-backend + default pin  
  **Brief:** [capabilities/event-protocol.md](capabilities/event-protocol.md) — DX = **promises**; default **libuv**, second **libev**
- `http-protocol` — sync + async send; request/response values  
  **Brief:** [capabilities/http-protocol.md](capabilities/http-protocol.md)
- `ws-protocol` — connect, send, on-message, ping, close  
  **Brief:** [capabilities/ws-protocol.md](capabilities/ws-protocol.md)

## Wave-2 data protocol set

- `json-protocol` — encode/decode (RFC 8259); default **jzon**, alternate **yason**  
  **Brief:** [capabilities/json-protocol.md](capabilities/json-protocol.md) · cookbook [json.md](cookbooks/json.md) — streaming = P2
- `babel` — UTF-8 octets ↔ string — [text-unicode.md](capabilities/text-unicode.md)
- `unicode-protocol` — UCD / normalize / IDNA / breaks — [unicode-protocol.md](capabilities/unicode-protocol.md)
- `i18n-protocol` — locale / MF2 templating / catalogs — [i18n.md](capabilities/i18n.md)
- `l10n-protocol` — collation / number·date format — [l10n.md](capabilities/l10n.md)
- `bordeaux-threads` (bt2) — portable threads — [concurrency.md](capabilities/concurrency.md)
- `cl-stack-config` — env + **TOML** (tomlet) — [config.md](capabilities/config.md)
- `http-server-protocol` — CLOS server lifecycle; **Clack env** app contract; Hunchentoot default / Woo Unix  
  **Brief:** [capabilities/http-server.md](capabilities/http-server.md) · cookbook [http-server.md](cookbooks/http-server.md)

## Wave-2 app tooling (briefs locked)

- `cli-protocol` — command tree / parse / run; default **clingon**, alternate **adopt**  
  **Brief:** [capabilities/cli.md](capabilities/cli.md) (#103)
- `io-protocol` — ObjectInput/Output–like **CLOS shell** (`read-object` / `write-object`); **no serdes**; OCI **0.1.0**  
  **Brief:** [capabilities/io.md](capabilities/io.md) · **Cookbook:** [cookbooks/io.md](cookbooks/io.md)
- `serdes-protocol` — format encode/decode + Gray/JSONL/events; **implemented by** `json-protocol` + sexp (OCI **0.2.0**); later XML / protobuf / Arrow / …  
  **Brief:** [capabilities/serdes.md](capabilities/serdes.md) · **Cookbook:** [cookbooks/serdes.md](cookbooks/serdes.md)
- `log-protocol` — **text** (log4j pattern) + **structured** (JSON/SEXP via serdes); default **log4cl**, alternate **vom**  
  **Brief:** [capabilities/logging.md](capabilities/logging.md) (#102)
- SQL stack (three layers) — [capabilities/sql.md](capabilities/sql.md) (#101)  
  - `sql-protocol` — connectivity + **pooling** over **cl-dbi** (sqlite3 / postgres)  
  - `sql-query` — composable **CLOS DSL** (SQLAlchemy Core checklist); **ANSI** builtin; `sql-query-sqlite3` / `sql-query-postgres` dialect backends (OCI **0.2.0**)  
  - `sql-orm` — first-party lispy CLOS ORM (`defmodel`; **not** Mito; OCI **0.1.0**) — cookbook [sql.md](cookbooks/sql.md)
- `crypto-protocol` — recipes (`seal`/`unseal` AES-256-GCM) + hazmat digest/HMAC/AEAD; default **Ironclad**  
  **Brief:** [capabilities/crypto.md](capabilities/crypto.md) (#104) · cookbook [crypto.md](cookbooks/crypto.md)
- `secrets-protocol` — CSPRNG / tokens / compare / UUID / password KDF; default OS via Ironclad  
  **Brief:** [capabilities/secrets.md](capabilities/secrets.md) (#104)
- `process-protocol` — subprocess spawn/pipes (UIOP); **not** RPC  
  **Brief:** [capabilities/process.md](capabilities/process.md) (#106)
- `rpc-protocol` — JSON-RPC 2.0–shaped calls; transports are **separate repos**  
  **Brief:** [capabilities/rpc.md](capabilities/rpc.md) (#170)

## Agent wire (P1 — MCP / A2A / AG-UI)

HTTP client + server are done. Next layer is **wire codecs + bindings**, each `*-protocol` + `*-backend-*` in **its own GitHub repo**. Overview: [capabilities/agent-wire.md](capabilities/agent-wire.md).

- `sse-protocol` — `text/event-stream` framing; backends http (client) / clack (server)  
  **Brief:** [capabilities/sse.md](capabilities/sse.md) (#184)
- `rpc-backend-stdio` / `rpc-backend-http` / `rpc-backend-sse` — JSON-RPC transports (#170)
- `protobuf-protocol` — serdes `:protobuf`; backend cl-protobufs  
  **Brief:** [capabilities/protobuf.md](capabilities/protobuf.md)
- `grpc-protocol` — channel / unary / stream; **not** an rpc-protocol transport  
  **Brief:** [capabilities/grpc.md](capabilities/grpc.md)
- `mcp-protocol` — MCP client/server; backends stdio + Streamable HTTP  
  **Brief:** [capabilities/mcp.md](capabilities/mcp.md) (#185)
- `a2a-protocol` — Agent Card / Task; backends jsonrpc + **grpc/protobuf** + httpjson  
  **Brief:** [capabilities/a2a.md](capabilities/a2a.md) (#186)
- `ag-ui-protocol` — typed UI events (not JSON-RPC); backends SSE + protobuf  
  **Brief:** [capabilities/ag-ui.md](capabilities/ag-ui.md) (#187)

Capability issues must include a **Protocol surface** section before coding backends.  
Impl order: **sse → rpc transports → protobuf/grpc → mcp → a2a → ag-ui**.

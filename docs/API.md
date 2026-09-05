# cl-stack API conventions

**Install / first load:** [QUICKSTART.md](QUICKSTART.md).

**Style:** CLOS protocols + Python-grade DX. Not Java SPI, not Boost policies.

## Layers

1. **`foo-protocol`** — tiny ASDF system: generic functions, conditions, value types. Almost no deps.
2. **`cl-stack/foo` facade** — keyword-heavy helpers with sane defaults. What cookbooks teach.
3. **`foo-backend-*`** — `defmethod`s; selected by ASDF / pins, not a plugin DSL.

## Rules

- Keywords over positionals for user-facing APIs (exceptions: binary ops, `date-add` field+n).
- Conditions (+ restarts where useful), not status-code-only errors. See [conditions.md](capabilities/conditions.md).
- One app-level async DX (promise xor callback xor await-macro); **multiple event-loop backends** via `event-protocol`.
- `with-` macros + `unwind-protect` for resources.
- No god base classes.
- Escape hatches for experts (`raw-*` or inject upstream objects).

## Wave-1 protocol set

- `event-protocol` — run / defer / cancel / sleep / register-io / wake-call / submit; multi-backend + default pin  
  **Brief:** [capabilities/event-protocol.md](capabilities/event-protocol.md) — DX = **promises**; default **libuv**, second **libev**. `submit` `:executor` is a thunk runner, not a pool type — backends may plug in [`cl-stack-executors`](https://github.com/egao1980/cl-stack-executors).
- `http-protocol` — sync + async send; request/response values  
  **Brief:** [capabilities/http-protocol.md](capabilities/http-protocol.md)
- `ws-protocol` — connect, send, on-message, ping, close  
  **Brief:** [capabilities/ws-protocol.md](capabilities/ws-protocol.md)

## Wave-2 data protocol set

- `json-protocol` — encode/decode (RFC 8259); default **jzon**, alternate **yason**  
  **Brief:** [capabilities/json-protocol.md](capabilities/json-protocol.md) · cookbook [json.md](cookbooks/json.md) — streaming = P2
- `xml-protocol` — well-formed XML 1.0 + NS Infoset / pull events / writer; default **xml-backend-native**  
  **Brief:** [capabilities/xml-protocol.md](capabilities/xml-protocol.md) · cookbook [xml.md](cookbooks/xml.md)
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
- `serdes-protocol` — format encode/decode + Gray/JSONL/events; **implemented by** `json-protocol` + `yaml-protocol` (`:yaml` **0.1.0**) + sexp (OCI **0.2.1**) + `csv-protocol` **0.1.0** + `xml-protocol` **0.1.0** + `arrow-protocol` **0.1.0** + `protobuf-protocol` **0.2.0**; later msgpack / EDN / CBOR / Avro  
  **Brief:** [capabilities/serdes.md](capabilities/serdes.md) · **Cookbook:** [cookbooks/serdes.md](cookbooks/serdes.md)
- `csv-protocol` — RFC 4180 dialects; whole-document + row streams + events; implements serdes `:csv` / `:tsv`  
  **Brief:** [capabilities/csv-protocol.md](capabilities/csv-protocol.md) · cookbook [csv.md](cookbooks/csv.md)
- `log-protocol` — **text** (log4j pattern) + **structured** (JSON/SEXP via serdes); backends **[`log-backend-log4cl`](https://github.com/egao1980/log-backend-log4cl)** / **[`log-backend-vom`](https://github.com/egao1980/log-backend-vom)** (separate repos)  
  **Brief:** [capabilities/logging.md](capabilities/logging.md) (#102)
- `schema-protocol` — CLOS interchange models (`defschema` / `defenum` / `:tag`). Schema documents: `emit-schema` / `parse-schema` (`:json` / `:xsd` / `:arrow` / `:avro`).  
  **Brief:** [capabilities/schema.md](capabilities/schema.md) · cookbook [schema.md](cookbooks/schema.md)
- `datetime-protocol` — instant / duration / period / date / zone. IANA data is `cl-stack-tzdata`. Holidays are `cl-stack-calendars`. **Not** a `local-time` pin.  
  **Brief:** [capabilities/datetime.md](capabilities/datetime.md) ([#105](https://github.com/egao1980/cl-stack/issues/105)) · cookbook [datetime.md](cookbooks/datetime.md)
- Conditions / restarts — CLHS 9; pathlib is the gold standard.  
  **Brief:** [capabilities/conditions.md](capabilities/conditions.md) ([#107](https://github.com/egao1980/cl-stack/issues/107)) · cookbook [conditions.md](cookbooks/conditions.md)
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
- `rpc-protocol` — interaction modes (`:call-response` / `:notify` / `:call-stream` / `:client-stream` / `:bidi-stream`); JSON-RPC is `rpc-protocol-json`; gRPC binding is `rpc-protocol-grpc`  
  **Brief:** [capabilities/rpc.md](capabilities/rpc.md) (#170) · cookbook [rpc.md](cookbooks/rpc.md)

## Agent wire (P1 — MCP / A2A / AG-UI)

HTTP client + server are done. Wire codecs + bindings are each `*-protocol` + `*-backend-*` in **its own GitHub repo**. Overview: [capabilities/agent-wire.md](capabilities/agent-wire.md). **Impl order complete.**

- `sse-protocol` — `text/event-stream` framing; backends http (client) / clack (server)  
  **Brief:** [capabilities/sse.md](capabilities/sse.md) (#184) · cookbook [sse.md](cookbooks/sse.md)
- `rpc-protocol-json` / `rpc-protocol-grpc` — JSON-RPC codec and gRPC binding (separate repos)
- `rpc-backend-stdio` / `rpc-backend-http` / `rpc-backend-sse` — JSON-RPC transports (#170) · cookbook [rpc.md](cookbooks/rpc.md)
- `protobuf-protocol` — serdes `:protobuf` + proto3 JSON / WKT; backend cl-protobufs **0.2.0**  
  **Brief:** [capabilities/protobuf.md](capabilities/protobuf.md)
- `grpc-protocol` — gRPC wire (channel / status); call via `rpc-protocol-grpc`  
  **Brief:** [capabilities/grpc.md](capabilities/grpc.md)
- `mcp-protocol` — MCP client/server; backends stdio + Streamable HTTP; canary [`mcp-parity`](https://github.com/egao1980/mcp-parity)  
  **Brief:** [capabilities/mcp.md](capabilities/mcp.md) (#185) · cookbook [mcp.md](cookbooks/mcp.md)
- `a2a-protocol` — Agent Card / Task; backends jsonrpc + **grpc/protobuf** + httpjson  
  **Brief:** [capabilities/a2a.md](capabilities/a2a.md) (#186) · cookbook [a2a.md](cookbooks/a2a.md)
- `ag-ui-protocol` — typed UI events (not JSON-RPC); backends SSE + protobuf + TUI sink; `/client` reducer (`json-patch` for `STATE_DELTA`)  
  **Brief:** [capabilities/ag-ui.md](capabilities/ag-ui.md) (#187) · cookbook [ag-ui.md](cookbooks/ag-ui.md)

Capability issues must include a **Protocol surface** section before coding backends.  
Impl order (wire): **sse → rpc transports → protobuf/grpc → mcp → a2a → ag-ui** — **done**.

## AI agent loop (P2 — above wire)

Not agent-wire. Not blackboard. CLOS loop over `llm-protocol`. **Do not** steal `ag-ui-protocol:run-agent` — that is the wire GF.

- `ai-agent-protocol` — `run-ai-agent` / `run-ai-agent-async`; function-tool / nested agent / handoff; optional `/mcp` `/ag-ui` `/a2a`. Core has **zero** wire deps.  
  **Brief:** [capabilities/ai-agent.md](capabilities/ai-agent.md) · cookbook [ai-agent.md](cookbooks/ai-agent.md)
- `llm-protocol` — CLOS turns + typed parts; `generate` / `stream-generate` / `respond` / `stream-respond` / `embed`. OpenAI-compat + llama.cpp are backends.  
  **Brief:** [capabilities/llm.md](capabilities/llm.md) ([#195](https://github.com/egao1980/cl-stack/issues/195)) · cookbook [llm.md](cookbooks/llm.md)

MCP sampling is `ai-agent-protocol/mcp:make-mcp-sampling-handler` — **not** `llm-protocol`.

## Blackboard core (P2 — AI-agnostic)

Sibling of agent-wire, **not** a layer on top of MCP. Demiurge **core** extract: KSAR event loop + COW workspaces + CLOS capabilities. Zero `mcp-protocol` / `a2a-protocol` / `ag-ui-protocol` / `llm-protocol` deps. Wave-1 **shipped** (OCI **0.1.1** / capability **0.2.1**).

- `blackboard-protocol` — sections, watchers, KSAR, `requeue-ksar`, serial-per-workspace, fork/merge/discard/cancel  
  **Brief:** [capabilities/blackboard.md](capabilities/blackboard.md) ([#192](https://github.com/egao1980/cl-stack/issues/192), [#193](https://github.com/egao1980/cl-stack/issues/193)) · cookbook [blackboard.md](cookbooks/blackboard.md)
- `capability-protocol` — `defcapability` / `defcatalogue` + query GFs; world I/O is **not** `mcp-tool`  
  **Brief:** [capabilities/capability.md](capabilities/capability.md) ([#194](https://github.com/egao1980/cl-stack/issues/194))

LLM / MCP / A2A / AG-UI adapters are **separate** systems that post to the board or implement capabilities. Product: `egao1980/demiurge`. Cursor “agent infra” (skills, `/stack-status`) ≠ this Lisp runtime.

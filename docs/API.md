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
- `bordeaux-threads` (bt2) — portable threads — [concurrency.md](capabilities/concurrency.md)
- `cl-stack-config` — env + **TOML** (tomlet) — [config.md](capabilities/config.md)
- `http-server-protocol` — CLOS server lifecycle; **Clack env** app contract; Hunchentoot default / Woo Unix  
  **Brief:** [capabilities/http-server.md](capabilities/http-server.md) · cookbook [http-server.md](cookbooks/http-server.md)

## Wave-2 app tooling (briefs locked)

- `cli-protocol` — command tree / parse / run; default **clingon**, alternate **adopt**  
  **Brief:** [capabilities/cli.md](capabilities/cli.md) (#103)
- `io-protocol` — ObjectInput/Output–like **CLOS shell** (`read-object` / `write-object`); **no serdes**  
  **Brief:** [capabilities/io.md](capabilities/io.md)
- `serdes-protocol` — format encode/decode + Gray/JSONL/events; **implemented by** `json-protocol` + sexp; later XML / protobuf / Arrow / …  
  **Brief:** [capabilities/serdes.md](capabilities/serdes.md)
- `log-protocol` — **text** (log4j pattern) + **structured** (JSON/SEXP via serdes); default **log4cl**, alternate **vom**  
  **Brief:** [capabilities/logging.md](capabilities/logging.md) (#102)
- `sql-protocol` — DBI lifecycle over **cl-dbi**; drivers **sqlite3** / **postgres**; ORM facade **Mito** + SxQL  
  **Brief:** [capabilities/sql.md](capabilities/sql.md) (#101)

Capability issues must include a **Protocol surface** section before coding backends.  
Impl order for this set: **CLI → logging → SQL**.

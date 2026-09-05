# Stdlib gap analysis (ANSI / CDR / CL21 vs Python / Java)

Canonical structural matrix for cl-stack prioritization. **Do not rediscover** that ANSI lacks threads/HTTP/i18n — see [Absent appendix](#absent-appendix).

**Tags diagnose the CL ecosystem** (why a protocol or pin). They are not completeness. **Action** is the living scorecard — pins = [QUICKSTART](QUICKSTART.md) §2. LLM leftovers → [AI-GAP.md](AI-GAP.md).

## Taxonomy

| Tag | Meaning |
|-----|---------|
| Kernel-strong | ANSI/CDR better or equal — teach, don't wrap away |
| De-facto converged | One obvious QL answer — pin |
| Fragmented | Many libs — protocol + curated default (ICU, jzon, …) |
| Impl-private | Per-impl only — portability layer |
| Absent | Known missing batteries |
| Wrong-shape | Exists but hostile to overlays/async/DX |

## Category matrix (summary)

| Category | Tag | Priority | cl-stack action |
|----------|-----|----------|-----------------|
| Conditions / restarts | Kernel-strong | P2 | **cookbook shipped** — [conditions.md](cookbooks/conditions.md) ([#107](https://github.com/egao1980/cl-stack/issues/107)) |
| CLOS / MOP | Kernel-strong | P0 | GF protocols. `closer-mop` is not a `stable.pins` row |
| Numbers / sequences | Kernel-strong | P2–P3 | Alexandria **1.0.1** pinned. Serapeum is not |
| Concurrency | De-facto converged | P1 | bt2 **0.9.4** — **done** ([#95](https://github.com/egao1980/cl-stack/issues/95), [concurrency.md](capabilities/concurrency.md)) |
| Async I/O / event loop | Wrong-shape | P0 | **shipped** — `event-protocol` **0.2.0** (`wake-call` / `submit`) + libuv **0.1.2** / libev **0.1.3** / nio **0.1.2** + `cl-stack-executors` **0.1.0** — [event-protocol.md](capabilities/event-protocol.md) |
| Sockets / DNS | De-facto converged | P1 | Consumed by `http-protocol`. `usocket` is not a stack pin |
| HTTP client | Fragmented | P0 | **shipped** — `http-protocol` **0.3.6** (`http-body-pipe` + H2 request DATA) + `cl-stack-http` **0.1.8**. First-party = `http-backend-async` **0.2.8** (H2 `:want-stream` + request streaming + `:protocol` HPACK) × libuv; also dexador (maintenance), winhttp, java. CE: gzip/deflate/br/zstd/**snappy** — [http-protocol.md](capabilities/http-protocol.md) · [cookbook](cookbooks/http-client.md) |
| HTTP server | Fragmented | P1 | **shipped** — `http-server-protocol` **0.1.0**; Hunchentoot / Woo + **H2** (`http-server-backend-http2` **0.2.0** — `ENABLE_CONNECT_PROTOCOL`, CONNECT on `process-end-headers`) — [#93](https://github.com/egao1980/cl-stack/issues/93) · [cookbook](cookbooks/http-server.md) |
| WebSocket | Fragmented | P0 | **shipped** — `ws-protocol` **0.4.0** + `ws-backend-websocket-driver` **0.4.0** (H1 Upgrade + **H2 Extended CONNECT server**) — [ws-protocol.md](capabilities/ws-protocol.md) · [cookbook](cookbooks/websocket.md) |
| TLS / SSL | Wrong-shape | P0 | **shipped** — `cl-stack-ssl` **3.4.1** overlays + cl+ssl — [overlays.md](overlays.md) |
| Crypto / secrets | De-facto converged | P2 | **shipped** — `crypto-protocol` **0.2.0** (sign/verify) · `secrets-protocol` **0.1.0** · Ironclad **0.2.0** — [#104](https://github.com/egao1980/cl-stack/issues/104) · [crypto.md](cookbooks/crypto.md) |
| Auth | Fragmented | P1 | **shipped** — `cl-stack-oauth2` **0.1.0** · `cl-stack-jwt` **0.3.0** (RS/ES/EdDSA via crypto-protocol) |
| Octets / UTF-8 | De-facto converged | P1 | Babel **0.5.0** — [text-unicode.md](capabilities/text-unicode.md) ([#94](https://github.com/egao1980/cl-stack/issues/94)) |
| Unicode | Fragmented | P1 | **shipped** — `unicode-protocol` **0.1.2** (UCD / normalize / IDNA / breaks / uset) + cl-unicode / sbcl / ICU4C **78.1.3** / ICU4J **78.1.3**; facade `cl-stack-idna` **0.1.0** — [unicode-protocol.md](capabilities/unicode-protocol.md) · [cookbook](cookbooks/unicode.md) |
| i18n / l10n | Fragmented | P1 | **shipped** — ICU4C + ICU4J, [#151](https://github.com/egao1980/cl-stack/issues/151) **closed**. `i18n-protocol` **0.1.0** (locale / MF2 / plural / catalogs) · `l10n-protocol` **0.1.0** (collate / number / date / currency / list / relative-time / locale case). **Not** gettext. Locked ICU *app* surface, not every ICU header (no translit / bidi / `uregex` / spoof / MeasureFormat) — [i18n.md](capabilities/i18n.md) · [l10n.md](capabilities/l10n.md) |
| Regex | De-facto converged | P2 | `cl-ppcre` is the QL answer; **not** a `stable.pins` row |
| Pathnames / FS | Wrong-shape | P1 | **shipped** — `cl-stack-pathlib` **0.2.1** (`stack-pathlib`; local/memory/`zip://`; restarts) |
| Subprocess | De-facto converged | P2 | **shipped** — `process-protocol` + `process-backend-uiop` **0.1.0** — [#106](https://github.com/egao1980/cl-stack/issues/106) · [process.md](cookbooks/process.md) |
| RPC | Fragmented | P1 | **shipped** — `rpc-protocol` **0.2.0** + JSON-RPC / gRPC bindings + inprocess/stdio/http/sse — [#170](https://github.com/egao1980/cl-stack/issues/170) · [rpc.md](cookbooks/rpc.md) |
| SSE | Fragmented | P1 | **shipped** — `sse-protocol` **0.1.0** + http / clack — [sse.md](cookbooks/sse.md) |
| Protobuf / gRPC | Fragmented | P1 | **shipped** — `protobuf-protocol` **0.2.0** + cl-protobufs **0.2.0**; `grpc-protocol` **0.1.0** + http2 **0.3.0** (unary + interleaved bidi) / native — [protobuf.md](capabilities/protobuf.md) · [grpc.md](capabilities/grpc.md) |
| JSON / YAML / CSV / XML / MIME / CBOR / MessagePack / Avro | Fragmented | P1 | JSON **shipped** — `json-protocol` **0.2.0** + jzon — [#91](https://github.com/egao1980/cl-stack/issues/91) · [json.md](cookbooks/json.md). YAML **shipped** — `yaml-protocol` **0.1.0** (same Lisp mapping; serdes `:yaml`). CSV **shipped** — [`csv-protocol`](https://github.com/egao1980/csv-protocol) OCI **0.1.0** (serdes `:csv`/`:tsv`, dialects) · [csv.md](cookbooks/csv.md). XML **shipped** — `xml-protocol` **0.1.0** + `xml-backend-native` — [xml.md](cookbooks/xml.md). MIME **shipped** — `mime-protocol` **0.1.0** (serdes `:mime`/`:multipart`) · [mime-protocol.md](capabilities/mime-protocol.md). CBOR **shipped** — `cbor-protocol` **0.1.0** · [cbor-protocol.md](capabilities/cbor-protocol.md). MessagePack **shipped** — `messagepack-protocol` **0.1.0** · [messagepack-protocol.md](capabilities/messagepack-protocol.md). Avro **shipped** — `avro-protocol` **0.1.0** + `schema-protocol-avro` **0.1.0** · [avro-protocol.md](capabilities/avro-protocol.md) |
| Schema | Fragmented | P2 | **shipped** — `schema-protocol` **0.1.3** (`avro-schema` GF) + `schema-protocol-json` **0.1.1** + `schema-protocol-xsd` **0.1.2** + `schema-protocol-arrow` **0.1.0** + `schema-protocol-avro` **0.1.0** — [schema.md](cookbooks/schema.md) |
| SQL | Fragmented | P2 | **shipped** — `sql-protocol` **0.1.0** · `sql-query{,-pg,-sqlite3}` **0.2.0** · `sql-orm` **0.1.0** (not Mito) — [#101](https://github.com/egao1980/cl-stack/issues/101) · [sql.md](cookbooks/sql.md) |
| I/O object streams | Wrong-shape | P2 | **shipped** — `io-protocol` **0.1.0** (ObjectInput/Output CLOS shell; no serdes) — [#140](https://github.com/egao1980/cl-stack/issues/140) · [io.md](capabilities/io.md) |
| Serdes | Fragmented | P2 | **shipped** — `serdes-protocol` **0.2.2** (media-type registry) + JSONL/events; json / yaml / sexp / csv / xml / arrow / protobuf / mime / cbor / messagepack / avro implement — [#132](https://github.com/egao1980/cl-stack/issues/132) · [serdes.md](capabilities/serdes.md) |
| Logging | Fragmented | P2 | **shipped** — `log-protocol` **0.1.2**; backends [`log-backend-log4cl`](https://github.com/egao1980/log-backend-log4cl) / [`log-backend-vom`](https://github.com/egao1980/log-backend-vom) **0.1.1** (separate repos) — [#102](https://github.com/egao1980/cl-stack/issues/102) · [logging.md](cookbooks/logging.md) |
| CLI | Fragmented | P2 | **shipped** — `cli-protocol` **0.1.0** + clingon / adopt — [#103](https://github.com/egao1980/cl-stack/issues/103) · [cli.md](capabilities/cli.md) |
| Config | Fragmented | P1 | **shipped** — `cl-stack-config` **0.1.0** + tomlet (env overlay) — [#98](https://github.com/egao1980/cl-stack/issues/98) / [#99](https://github.com/egao1980/cl-stack/issues/99) · [config.md](cookbooks/config.md) |
| Packaging | Fragmented | P0 | **cl-repository** + GHCR overlays + `pins/stable.pins` |
| FFI | De-facto converged | P0 | CFFI **0.24.1** + overlays |
| Time / TZ | Fragmented | P2 | **shipped** — `datetime-protocol` **0.1.1** + `cl-stack-tzdata` **2026.3.0** + `cl-stack-calendars` **0.4.0** — **not** a `local-time` pin — [#105](https://github.com/egao1980/cl-stack/issues/105) · [datetime.md](cookbooks/datetime.md) |
| Testing | Fragmented | P0 | **Rove** + license-clean corpus — [ROVE-GAPS.md](ROVE-GAPS.md) |
| LLM / agents / wire | Fragmented | P1 | **shipped** as protocols (not an ANSI hole). generate/stream/embed + MCP/A2A/AG-UI + agent loop. Leftovers (RAG / memory / providers) → [AI-GAP.md](AI-GAP.md) |
| Gray streams | De-facto converged | P1 | trivial-gray-streams (via I/O / serdes). Not a `stable.pins` row |
| Weak refs | De-facto converged | P2 | trivial-garbage **0.21** |

## Wave-1 (done)

Overlays, `event-protocol`, `http-protocol`, `ws-protocol`, cl-repository pins, Rove/corpus — **shipped**. Do not treat this list as current P0.

**Still open on this matrix:** none of the format rows. AI leftovers stay in [AI-GAP.md](AI-GAP.md).

**Depth tranche ([#220](https://github.com/egao1980/cl-stack/issues/220) closed):** H2 `:want-stream` + trailers; request-body pipe + H2 DATA (`http-protocol` **0.3.7** / async **0.2.8**); gRPC http2 **interleaved** bidi (`grpc-backend-http2` **0.3.0**, live grpcio); crypto `sign`/`verify`; JWT RS/ES/EdDSA; H2 Clack backend **0.2.0** (`ENABLE_CONNECT_PROTOCOL`); WS H1 `accept` + **H2 Extended CONNECT server** (`ws-backend-websocket-driver` **0.4.0**). MIME / CBOR / MessagePack / Avro **shipped** as serdes implementors. Follow-on: compressed gRPC; HTTP/3.

## Absent appendix

ANSI-missing: threads, async I/O, sockets/HTTP/WS, TLS, regex, UUID, JSON/CSV/XML, SQL, crypto, logging, argparse, subprocess, pathlib-grade FS, i18n, venv-equivalent. Addressed via pins/facades above except a venv-equivalent (cl-repository, not a venv).

## CDR / CL21

CDR1 MOP is real; other CDRs are language polish. CL21 stalled; ignored batteries. Batteries coherence = curation + protocols (this project).

## Full deep dives

Capability briefs + cookbooks under [docs/](.) — not this file.

# Stdlib gap analysis (ANSI / CDR / CL21 vs Python / Java)

Canonical structural matrix for cl-stack prioritization. **Do not rediscover** that ANSI lacks threads/HTTP/i18n — see [Absent appendix](#absent-appendix).

## Taxonomy

| Tag | Meaning |
|-----|---------|
| Kernel-strong | ANSI/CDR better or equal — teach, don't wrap away |
| De-facto converged | One obvious QL answer — pin |
| Fragmented | Many libs — protocol + curated default |
| Impl-private | Per-impl only — portability layer |
| Absent | Known missing batteries |
| Wrong-shape | Exists but hostile to overlays/async/DX |

## Category matrix (summary)

| Category | Tag | Priority | cl-stack action |
|----------|-----|----------|-----------------|
| Conditions / restarts | Kernel-strong | P2 | **cookbook shipped** — [conditions.md](cookbooks/conditions.md) ([#107](https://github.com/egao1980/cl-stack/issues/107)) |
| CLOS / MOP | Kernel-strong | P0 | GF protocols; pin closer-mop |
| Numbers / sequences | Kernel-strong | P2–P3 | Pin Alexandria+Serapeum |
| Concurrency | De-facto converged | P1 | Pin bt2 — **done** ([#95](https://github.com/egao1980/cl-stack/issues/95), [concurrency.md](capabilities/concurrency.md)) |
| Async I/O / event loop | Wrong-shape | P0 | `event-protocol` + **multi-backend**; overlays; one app DX |
| Sockets / DNS | De-facto converged | P1 | Pin usocket |
| HTTP client | Fragmented | P0 | `http-protocol` + facade (dexador sync + async on protocol) |
| HTTP server | Fragmented | P1 | `http-server-protocol` + Clack env; Hunchentoot / Woo — **done** ([#93](https://github.com/egao1980/cl-stack/issues/93), [http-server.md](cookbooks/http-server.md)) |
| WebSocket | Fragmented | P0 | `ws-protocol` + websocket-driver — **wave-1 done** (#4) |
| TLS / SSL | Wrong-shape | P0 | OpenSSL OCI overlays; pin cl+ssl |
| Crypto / secrets | De-facto converged | P2 | **shipped** — `crypto-protocol` 0.1.1 · `secrets-protocol` 0.1.0 · `crypto-backend-ironclad` 0.1.1 — [#104](https://github.com/egao1980/cl-stack/issues/104) · [crypto.md](capabilities/crypto.md) · [secrets.md](capabilities/secrets.md) · [cookbook](cookbooks/crypto.md) |
| Text / Unicode | Fragmented | P1 | Pin Babel; UTF-8-first — **done** ([#94](https://github.com/egao1980/cl-stack/issues/94), [text-unicode.md](capabilities/text-unicode.md)) |
| i18n / gettext | Absent | P3 | **Needs planning** — [#151](https://github.com/egao1980/cl-stack/issues/151); not gettext-only |
| Regex | De-facto converged | P2 | Pin cl-ppcre |
| Pathnames / FS | Wrong-shape | P1 | **shipped** — `cl-stack-pathlib` **0.2.1** (`stack-pathlib`; local/memory/`zip://`; restarts) |
| Subprocess | De-facto converged | P2 | **done** — `process-protocol` + `process-backend-uiop` 0.1.0 — [#106](https://github.com/egao1980/cl-stack/issues/106) · [process.md](capabilities/process.md) · [cookbook](cookbooks/process.md); RPC — `rpc-protocol` 0.2.0 + inprocess/stdio/http/sse — [#170](https://github.com/egao1980/cl-stack/issues/170) · [rpc.md](capabilities/rpc.md) · [cookbook](cookbooks/rpc.md) |
| JSON / CSV / XML | Fragmented | P1 | `json-protocol` + **jzon** — **done** ([#91](https://github.com/egao1980/cl-stack/issues/91), [json.md](cookbooks/json.md)); CSV/XML later |
| SQL | Fragmented | P2 | three layers **shipped**: `sql-protocol` 0.1.0 · `sql-query{,-pg,-sqlite3}` 0.2.0 · `sql-orm` 0.1.0 (first-party CLOS, not Mito) — [#101](https://github.com/egao1980/cl-stack/issues/101) · [sql.md](capabilities/sql.md) · [cookbook](cookbooks/sql.md) |
| I/O object streams | Absent | P2 | `io-protocol` OCI **0.1.0** — ObjectInput/Output CLOS shell (no serdes) — [#140](https://github.com/egao1980/cl-stack/issues/140) · [io.md](capabilities/io.md) |
| Serdes | Fragmented | P2 | `serdes-protocol` **0.2.1** + JSONL/events; `json-protocol` / `sexp-protocol` implement — [#132](https://github.com/egao1980/cl-stack/issues/132) · [serdes.md](capabilities/serdes.md) |
| Logging | Fragmented | P2 | `log-protocol` text (log4j) + structured (JSON/SEXP via serdes) — [#102](https://github.com/egao1980/cl-stack/issues/102) · [logging.md](capabilities/logging.md) |
| CLI | Fragmented | P2 | `cli-protocol` + clingon / adopt — brief [#103](https://github.com/egao1980/cl-stack/issues/103) · [cli.md](capabilities/cli.md) |
| Config | Fragmented | P1 | env + **TOML** (tomlet) — brief [#98](https://github.com/egao1980/cl-stack/issues/98); impl [#99](https://github.com/egao1980/cl-stack/issues/99) |
| Packaging | Fragmented | P0 | **cl-repository** product path |
| FFI | De-facto converged | P0 | CFFI + overlays |
| Time / TZ | Fragmented | P2 | **shipped** — first-party `datetime-protocol` **0.1.1** + `cl-stack-tzdata` **2026.3.0** + `cl-stack-calendars` **0.4.0** — **not** a `local-time` pin — [#105](https://github.com/egao1980/cl-stack/issues/105) · [datetime.md](capabilities/datetime.md) · [cookbook](cookbooks/datetime.md) |
| Testing | Fragmented | P0 | **Rove** + corpus; dogfood PRs |
| Gray streams | De-facto converged | P1 | trivial-gray-streams; object-stream shell → `io-protocol` |
| Weak refs | De-facto converged | P2 | trivial-garbage |

## Wave-1 (P0) ranking

1. Platform overlays (OpenSSL, event natives, CFFI-friendly)
2. `event-protocol` + default loop + second backend
3. `http-protocol` facade (sync + async)
4. `ws-protocol` + websocket-driver — **done** (#4 / #33–#35 + corpus)
5. cl-repository locks / cl-stack pins
6. Rove + license-clean corpus pipeline + Rove gap PRs

## Absent appendix

Portable threads, async I/O, sockets/HTTP/WS, TLS, regex, UUID, JSON/CSV/XML, SQL, crypto, logging, argparse, subprocess, pathlib-grade FS, i18n, venv-equivalent — ANSI-missing; addressed via pins/facades above.

## CDR / CL21

CDR1 MOP is real; other CDRs are language polish. CL21 stalled; ignored batteries. Batteries coherence = curation + protocols (this project).

## Full deep dives

See planning notes / capability issues for Fragmented/Wrong-shape writeups (async, HTTP, paths, TLS, JSON, packaging).

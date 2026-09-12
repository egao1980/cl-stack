# cl-stack vs Python stdlib + ecosystem

Companion to [STDLIB-GAP.md](STDLIB-GAP.md) (category matrix — **closed**) and [AI-GAP.md](AI-GAP.md).

**This file is the ranked remaining backlog.** Do not rediscover that ANSI lacks HTTP. Pick a wave from here.

**Postponed:** multi-impl CI (ECL/ABCL/CCL, [#42](https://github.com/egao1980/cl-stack/issues/42)). SBCL stays the only required CI impl until that epic is reopened.

---

## Verdict

Wave-1 I/O, format tranche, SQL, and agent-wire are on-par with the *categories* Python treats as batteries. Remaining work is **module-level holes**, **ecosystem products**, and **depth**.

Do not wrap kernel-strong ANSI (numbers, sequences, conditions, CLOS). Do not clone LangChain / Django / numpy.

---

## Already on-par

| Python | cl-stack |
|--------|----------|
| `asyncio` / uvloop | `event-protocol` + libuv / libev / nio + `cl-stack-executors` |
| `pathlib` | `cl-stack-pathlib` (local / memory / `zip://`) |
| `json` / `tomllib` / YAML / `csv` / `xml.etree` | `json-protocol`, config/TOML, `yaml-protocol`, `csv-protocol`, `xml-protocol` |
| `http.client` / requests / httpx | `http-protocol` + `cl-stack-http` |
| WSGI / Flask | `http-server-protocol` + Clack |
| `ssl` | `cl-stack-ssl` |
| `hashlib` / `hmac` / `secrets` / `uuid` | `crypto-protocol` + `secrets-protocol` |
| `logging` / OTel traces | `log-protocol` + `telemetry-protocol` |
| `argparse` / click | `cli-protocol` |
| `datetime` / `zoneinfo` | `datetime-protocol` + tzdata + calendars |
| `unicodedata` | `unicode-protocol` + ICU i18n/l10n (not gettext) |
| `subprocess` | `process-protocol` |
| `sqlite3` / SQLAlchemy | `sql-protocol` + `sql-query` + `sql-orm` + `sql-migrate` |
| `gzip` / zipfile / `tarfile` / `bz2` | `compression-protocol` (xz overlay) |
| pydantic-settings / pydantic models | `cl-stack-config` / `schema-protocol` |
| websockets / SSE / grpcio | `ws-` / `sse-` / `grpc-protocol` |
| FastMCP / a2a-sdk / AG-UI | MCP / A2A / AG-UI |
| OpenAI / Anthropic / RAG | `llm-protocol*` + `rag-protocol` |
| PyJWT / authlib | `cl-stack-jwt` **0.3.3** (`expired-p` #6 closed) / `cl-stack-oauth2` |

---

## P0 — platform leftovers

| Item | Status | Notes |
|------|--------|-------|
| Rove vs pytest/JUnit | **in flight** | fixtures, markers, JUnit XML, timeout, diffs, shard — [ROVE-GAPS.md](ROVE-GAPS.md) · [egao1980/rove#4](https://github.com/egao1980/rove/pull/4) · upstream #76–#79 |
| Pin `closer-mop` / `usocket` / `cl-ppcre` | **done** | GHCR `1.0.0` / `0.8.9` / `2.1.2` |
| Pin Serapeum | **done** | GHCR `0.1.0` + deps (`string-case` 0.0.2, `parse-number` 1.8, `trivial-file-size` 0.1.0, `trivial-macroexpand-all` 0.1.0, `parse-declarations-1.0` 1.0) |
| `cl-stack-jwt` #6 | **done** | Closed; pin **0.3.3** |
| Multi-impl CI #42 | **postponed** | Do not start |

---

## P1 — stdlib modules with no first-party protocol

| Rank | Python | Ship | Notes |
|------|--------|------|-------|
| 1 | `html` / BeautifulSoup | `html-protocol` + plump | **shipped** `parse` / `serialize` / `select`; CSS/JS = opaque text |
| 2 | `email` + `smtplib` | `mail-protocol` | **shipped** `make-message` / `send`; SMTP no AUTH/STARTTLS; not IMAP |
| 3 | `ipaddress` | `ip-protocol` | **shipped** `parse-ip` / `parse-network`; no IPv4-mapped IPv6 |
| 4 | `tarfile` / `bz2` / `lzma` | `compression-protocol` backends | **shipped** ustar + `:tar.gz`; `:bzip2` inflate (chipz). xz still overlay |
| 5 | `struct` | `binary-protocol` | **shipped** `pack` / `unpack` / `calcsize`; encodings stay RFC 4648/QP |
| 6 | `tempfile` / `shutil` | extend `cl-stack-pathlib` | **shipped** `with-temp-*` / `rmtree` / `copytree` / `which` |
| 7 | `signal` | process-protocol extension | **shipped** `set-signal` / `raise-signal` (Windows in-process; Unix OS) |
| 8 | `configparser` INI | `cl-stack-config` backend | **shipped** `:format :ini` / `:auto` |
| 9 | `mimetypes` | mime-protocol facade | **shipped** `guess-type` / `add-type` |
| 10 | UUID v7 | `secrets-protocol` | **shipped** RFC 9562 `make-uuid-v7` |

**Skip as new protocols:** `re` → pin `cl-ppcre`; collections/itertools → Serapeum; `decimal`/`fractions` → CL rationals; `pickle` → `io-protocol` (not CPython wire); CSS/JS engines (opaque in `html-protocol`).

---

## P2 — ecosystem

| Rank | PyPI | Ship |
|------|------|------|
| 1 | Alembic | **shipped** `sql-migrate` **0.1.0** (linear runner on sql-orm `schema-op`) |
| 2 | FastAPI OpenAPI | **shipped** `openapi-protocol` **0.1.0** — emit + Clack `document-app`; dogfood lock below |
| 3 | lxml / html5lib | html-protocol depth (selectors OK; still no CSS/JS engines) |
| 4 | redis | `cache-protocol` + memory/redis |
| 5 | dateutil `rrule` | `cl-stack-calendars` recurrence |
| 6 | watchdog | `watch-protocol` (Windows required) |
| 7 | IMAP / async SMTP | mail-protocol backends |
| 8 | pillow / openpyxl | leave unless a demo forces it |
| 9 | boto3 | SigV4 + S3 later — do not clone the AWS SDK |
| 10 | rich / tqdm | CLI helpers |
| 11 | hypothesis | after Rove fixtures |

### OpenAPI reuse lock (P2 #2)

Do **not** invent a JSON Schema dialect, YAML parser, or CLOS model layer. Precedent: `llm-protocol/schema` and `mcp-protocol` already call `schema-protocol-json`.

| Layer | Use |
|-------|-----|
| Document envelope | `json-protocol` `:json` / `yaml-protocol` `:yaml` — YAML **extends** JSON (`yaml-backend` ⊆ `json-backend`). Same repo. JSON ⊂ YAML at the document level. Do **not** invert (`json-protocol` must not depend on YAML) |
| Components / schemas | `schema-protocol` models + `schema-protocol-json` draft-07 (already emits OpenAPI `oneOf` + `discriminator`) |
| App contract | Clack env (`http-server-protocol`) |

### Depth on shipped protocols

HTTP client cache (RFC 9111), WS permessage-deflate, SSE foreign resume, A2A canary beyond JSON-RPC, Arrow/XSD 1.1 depth, MySQL dialect. **HTTP/3: do not start.** gettext: no. CFFI enum refs: P2 upstream, no fork pin.

Shipped depth (not a new wave): `http-protocol` **0.3.8** (Basic `:auth` via encoding-protocol; GHCR republished after the Sept 5 packager outage). `http-encoding-chipz` **0.1.1**.

### AI leftovers

Stay in [AI-GAP.md](AI-GAP.md). Not this file.

---

## P3 / leave

`tkinter`, `multiprocessing` (BT + executors + process cover the useful slice), `importlib`/`venv` (ASDF + cl-repository), `xmlrpc`/`ftplib`/`poplib`, `dbm`/`shelve`, Django / Celery / numpy / pandas, HTTP/3, CL21 sugar.

---

## Wave order

1. **Hygiene (P0):** closer-mop/usocket/cl-ppcre + jwt 0.3.3 + serapeum — **shipped**. Rove gaps still **in flight** (does not block P2).
2. **Stdlib hole tranche:** compression tar/bz2, pathlib tempfile/shutil, INI, mimetypes, UUID v7 — **shipped**.
3. **Remaining P1:** html + mail + ip + struct + signal — **shipped**.
4. **SQL product:** `sql-migrate` **0.1.0** — **shipped** (GHCR + pin).
5. **OpenAPI emit:** `openapi-protocol` **0.1.0** — **shipped** (emit + Clack document endpoints).
6. **Cache / watch / rrule** as demand appears.
7. **AI-GAP** on its own track.

Each new domain: capability brief → protocol repo → one hero backend → Rove + license-clean corpus → pin + QUICKSTART row.

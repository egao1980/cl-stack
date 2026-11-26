# cl-stack + cl-repository quickstart

**Living doc.** Update this file when a wave feature ships (new package, pin bump, or user-facing API). Cookbooks stay task-deep; this page stays the 5‑minute path.

| Piece | Role |
|-------|------|
| [`cl-repository`](https://github.com/egao1980/cl-repository) | Install transport — OCI packages on GHCR + platform overlays (native libs, grovel cache) |
| [`cl-stack`](https://github.com/egao1980/cl-stack) (this repo) | Curated stack hub — briefs, cookbooks, pins, issues |
| `ghcr.io/egao1980/cl-systems/*` | Published systems you load with `cl-repo:load-system` |

Layering: **protocol** (generics) → **backend** (wire/OS) → **facade** (`cl-stack-*`, Python-grade DX). See [API.md](API.md).

---

## 0. Prerequisites

| Tool | Notes |
|------|--------|
| [Roswell](https://roswell.github.io/) + SBCL | `ros install sbcl-bin` |
| `cl-repo` | the only interface, locally and in CI |

No C toolchain needed for consumer installs — natives ship in overlays.

---

## 1. Use the project

A directory with an `.asd` or a `qlfile` is a project. Defaults are `https://ghcr.io` / `egao1980/cl-systems`.

```bash
cl-repo sync
cl-repo test
cl-repo publish
```

No `CL_SOURCE_REGISTRY`. No `ql:quickload`. A missing `:depends-on` or qlfile name is published, then installed.

`cl-repo install alexandria` pulls one system outside a project. CI checks out only the repo under test and calls `test-system.yml@main`.

---

## 2. Current stack pins (bump when publishing)

| System | OCI tag | Notes |
|--------|---------|--------|
| `cl-repository-client` | **0.27.39** | bootstrap from `ghcr.io/egao1980/cl-repository/…`; installs `:defsystem-depends-on` (e.g. `asdf-native`) before reading the `.asd`; a package drops sibling `.asd` files it does not provide (cl-repository#117); a sync without a lock resolves to the newest published version (cl-repository#167); lock entries carry digest and registry (cl-repository#163); a qlfile-only project gets its entries' closure (cl-repository#170); `cl-repo ros` starts with `+Q` (cl-repository#166); parallel images share the fasl root under a flock (cl-repository#162, SBCL off Windows); `uiop` / `asdf` / SBCL contribs never become install requests, so a project on `http-backend-dexador` 0.2.0 installs without pulling `uiop:3.1.1` (cl-repository#171); pulls private packages with credentials from `CL_REPO_REGISTRY_TOKEN`, `GITHUB_TOKEN` or Docker's config (cl-repository#186); an unreachable registry costs one failed request, not retries for every package, and a sync from a current lock sends none (cl-repository#179); `cl-repo --version` prints the client's release (cl-repository#189); the client's own build prints nothing on stdout and keeps its compiler output back unless `CL_REPO_VERBOSE=1` (cl-repository#194) |
| `cl-stack/meta` | hub git | ASDF metapackage — `pins/stable.pins` + `(cl-stack:apply-pins …)` |
| `json-protocol` | **0.2.1** | encode/decode + serdes `:json`; load `json-backend-jzon` (default) or `json-backend-yason`; nick `stack-json` · [cookbook](cookbooks/json.md) |
| `yaml-protocol` | **0.2.2** | YAML 1.2 native parser; JSON⊂YAML same Lisp mapping; serdes `:yaml`; block output without trailing blanks |
| `openapi-protocol` | **0.1.0** | OpenAPI 3.1 emit + Clack `document-app` (`stack-openapi`) |
| `xml-protocol` | **0.1.0** | well-formed XML 1.0 + NS Infoset / events / writer; serdes `:xml`; nick `stack-xml` · [cookbook](cookbooks/xml.md) |
| `xml-backend-native` | **0.1.1** | default XML backend (XXE-safe Lisp parser) |
| `html-protocol` | **0.1.1** | lenient HTML parse/serialize + tiny CSS `select`; nick `stack-html` · [html-protocol](capabilities/html-protocol.md) |
| `html-backend-plump` | **0.1.1** | default HTML backend (plump) |
| `plump` | **2.0.0** | lenient HTML/XML parser (html pin) |
| `array-utils` | **1.3.0** | plump dep |
| `io-protocol` | **0.1.0** | object streams (`read-object` / `write-object`); nick `stack-io` · [cookbook](cookbooks/io.md) |
| `babel` | **0.5.0** | UTF-8 octets ↔ string ([text-unicode](capabilities/text-unicode.md)) |
| `closer-mop` | **1.0.0** | MOP portability |
| `usocket` | **0.8.9** | portable sockets |
| `ip-protocol` | **0.1.0** | IPv4/IPv6 + CIDR (`stack-ip`); no IPv4-mapped IPv6 · [ip-protocol](capabilities/ip-protocol.md) |
| `cl-ppcre` | **2.1.2** | regex |
| `serapeum` | **0.1.0** | utilities (collections / itertools slice) |
| `string-case` | **0.0.2** | serapeum dep |
| `parse-number` | **1.8** | serapeum dep |
| `trivial-file-size` | **0.1.0** | serapeum dep |
| `trivial-macroexpand-all` | **0.1.0** | serapeum dep |
| `parse-declarations-1.0` | **1.0** | serapeum dep |
| `unicode-protocol` | **0.1.2** | UCD/normalize/case/IDNA/breaks/uset (`stack-unicode`) · [cookbook](cookbooks/unicode.md) |
| `unicode-backend-cl-unicode` | **0.1.0** | portable default unicode backend |
| `unicode-backend-sbcl` | **0.1.0** | SBCL `sb-unicode` (no `:idna`) |
| `unicode-backend-icu` | **0.1.1** | ICU4C CFFI backend |
| `unicode-backend-icu4j` | **0.1.2** | ICU4J / ABCL (auto-bind `#+abcl`) |
| `cl-stack-icu` | **79.1.2** | ICU4C 79.1 overlays + CFFI (linux/darwin/windows); loads through `asdf-native`, keg-only Homebrew `icu4c` fallback |
| `cl-stack-icu4j` | **79.1.0** | ICU4J 79.1 jar + ABCL bridge |
| `i18n-protocol` | **0.1.0** | locale / MF2 / plural / catalogs (`stack-i18n`) |
| `i18n-backend-icu` | **0.1.1** | ICU4C i18n |
| `i18n-backend-icu4j` | **0.1.1** | ICU4J i18n (auto-bind `#+abcl`) |
| `l10n-protocol` | **0.1.0** | collate / numfmt / date / locale case (`stack-l10n`) |
| `l10n-backend-icu` | **0.1.1** | ICU4C l10n |
| `l10n-backend-icu4j` | **0.1.2** | ICU4J l10n (auto-bind `#+abcl`) |
| `cl-stack-idna` | **0.1.0** | `to-ascii` / `to-unicode` facade (`stack-idna`) |
| `bordeaux-threads` | **0.9.4** | portable threads / bt2 ([concurrency](capabilities/concurrency.md)) |
| `cl-stack-config` | **0.3.1** | env + `.env` (python-dotenv syntax) + TOML + INI (read as Python's `configparser` reads it: whole-line comments, lowercased option names), typed settings (`load-into`) ([config](capabilities/config.md) · [cookbook](cookbooks/config.md)) |
| `tomlet` | **0.1.0** | TOML parser (config pin) |
| `http-protocol` | **0.4.5** | wire client; `proxy-kind` :https for an `https://` proxy (TLS to the proxy, never cleartext), `proxy-tls-unsupported` for backends that cannot (http-protocol#53); Basic auth via encoding-protocol; `http-body-pipe` + H2 request DATA; `:auto` codecs; CE gzip/br/zstd/**snappy** (a missing codec backend is probed once); multipart boundaries: 128 random bits from a process-local state, and an in-memory part that contains the boundary gets a new one; `:files` / multipart content must be a stream, a string or octets, checked when the file or part is made |
| `cl-stack-http` | **0.2.1** | requests-like facade (`stack-http`); JSON via `json-protocol`/jzon; re-exports the `http-protocol` response readers and conditions; proxy precedence as in requests: a request `:proxy`, then the session's, then the environment under `:trust-env`; `:trust-env nil` never reads `*_proxy` (cl-stack-http#34, #35); `:auto` off Windows: blocking calls dexador → async, `-async` calls async (libuv) → dexador (one libuv loop per thread is not safe yet, event-backend-libuv#31); no event-loop wiring needed |
| `cl-stack-pathlib` | **0.8.0** | CLOS path + FS (`stack-pathlib`; `zip://`; snapshot-store GC (`snapshot-store-ids` / `-delete`); ranged reads, SHA-256, atomic + `:expected-hash` / `:mode` writes, `fs-chmod` / `(setf fs-mode)`, gitignore matcher, `grep`, `stat`; `with-temp-*` / `rmtree` / `copytree` / `which`) · [conditions](cookbooks/conditions.md); `symlink-p` on Windows = reparse point |
| `datetime-protocol` | **0.1.3** | instant / duration / period / date / zone / recurrence (`stack-datetime`) · [cookbook](cookbooks/datetime.md) |
| `cl-stack-tzdata` | **2026.6.0.1** | IANA tzdb (TZif) — no OS zoneinfo |
| `cl-stack-calendars` | **0.4.1** | holidays / business days / exchange sessions / event-schedule |
| `cl-stack-calendar-l10n` | **0.1.3** | localized calendar names (ICU) |
| `schema-protocol` | **0.2.2** | CLOS `defschema` (`stack-schema`); `emit-schema` / `parse-schema` · [cookbook](cookbooks/schema.md) |
| `sql-protocol` | **0.1.0** | connectivity + pool (`stack-sql`) · [cookbook](cookbooks/sql.md) |
| `sql-query` | **0.2.0** | CLOS SQL DSL |
| `sql-query-sqlite3` | **0.2.0** | sqlite3 dialect |
| `sql-query-postgres` | **0.2.0** | postgres dialect |
| `sql-orm` | **0.3.0** | CLOS ORM (`defmodel`); schema algebra: `apply-ops-to-snapshot`, `alter-column-op`, `diff-schema :complete`, `reflect-schema` (SQLite, PostgreSQL) |
| `sql-migrate` | **0.2.1** | Alembic-style revision runner (`stack-sql-migrate`; each step's DDL + stamp in one transaction) · [cookbook](cookbooks/sql.md) |
| `diff-protocol` | **0.4.0** | diffs as values (`stack-diff`): footprints, lazy content, apply / invert / compose / rebase / three-way; sexp, text (Myers / histogram, diff3) and tree engines; `:unified` render + git-diff parse; engine extension API (`register-diff-engine`, hooks, `make-conflict`) · [brief](capabilities/diff.md) |
| `revision-protocol` | **0.4.0** | revision DAG (`stack-rev`): refs + tags with CAS (`replace-annotation` restart where `tag-rewrite-p`), as-of on recorded / valid time, walks, merge-base; content, targets, resumable plans, projections, composite revisions; in-memory store + target · [brief](capabilities/revision.md) |
| `revision-backend-git` | **0.5.1** | revision-protocol over the git CLI (`stack-rev-git`); full `refs/…` names used as given; needs git ≥ 2.56 · [brief](capabilities/revision-backend-git.md) |
| `revision-backend-jj` | **0.3.1** | revision-protocol over the jj CLI (`stack-rev-jj`) · [brief](capabilities/revision-backend-jj.md) |
| `diff-backend-lisp-source` | **0.2.2** | diff engine `:lisp`: form-level diffs keyed like lisp-mcp locators (`stack-diff-lisp`) · [brief](capabilities/diff-backend-lisp-source.md) |
| `sql-query-csv` | **0.1.0** | CSV catalog dialect |
| `sql-backend-sqlite3` | **0.1.0** | sqlite3 connectivity |
| `sql-backend-postgres` | **0.1.0** | postgres connectivity |
| `cl-stack-oauth2` | **0.2.0** | OAuth2 scopes/grants/PKCE/401 refresh (`stack-oauth2`) |
| `crypto-protocol` | **0.2.0** | seal/unseal + hazmat + **sign/verify** (`stack-crypto`) |
| `crypto-backend-ironclad` | **0.2.1** | digest/HMAC/AEAD/sign + secrets (Ironclad; UUID v7) |
| `secrets-protocol` | **0.1.3** | CSPRNG/tokens/UUID v4+v7/password KDF API |
| `process-protocol` | **0.4.1** | subprocess `run`/`launch` + `set-signal`/`raise-signal`; env merge, octet I/O, `:process-group` + `kill :tree`, `process-pid` (`stack-process`) · [cookbook](cookbooks/process.md) |
| `process-backend-uiop` | **0.3.1** | UIOP backend (default); Windows tree kill via job object |
| `named-readtables` | **0.9** | fset dep (SBCL 2.6 pin, not QL 20250622) |
| `fset` | **2.4.4** | functional sets/maps (`fset2`); spec-protocol runtime |
| `misc-extensions` | **4.3.2** | fset |
| `mt19937` | **1.1** | fset |
| `spec-protocol` | **0.1.1** | `defspec` = CLOS protocol + Quint/TLA+ spec (`stack-spec`); ITF + MBT |
| `spec-backend-quint` | **0.1.1** | Quint emit + typecheck/run/test/verify/compile |
| `http2-spec` | **0.1.0** | RFC 9113 stream states + flow control `defspec`; MBT driver + frozen regression traces for `http2` ≥ 2.1.2 |
| `rpc-protocol` | **0.2.0** | RPC modes (`stack-rpc`) · [cookbook](cookbooks/rpc.md) |
| `rpc-protocol-json` | **0.1.0** | JSON-RPC 2.0 codec |
| `rpc-protocol-grpc` | **0.2.0** | gRPC binding; `:call-stream` / `:bidi-stream` → `grpc-stream` |
| `rpc-backend-inprocess` | **0.1.0** | in-process unary |
| `rpc-backend-stdio` | **0.1.2** | newline JSON-RPC over process-protocol; one write lock per transport |
| `rpc-backend-http` | **0.1.2** | JSON-RPC POST (client + Clack) |
| `rpc-backend-sse` | **0.1.2** | JSON-RPC as SSE `data:` |
| `sse-protocol` | **0.1.1** | `text/event-stream` framing (`stack-sse`) · [cookbook](cookbooks/sse.md) |
| `sse-backend-http` | **0.1.1** | SSE client via http-protocol |
| `sse-backend-clack` | **0.1.1** | SSE server (Clack) |
| `mcp-protocol` | **0.5.0** | dual-era MCP (`2026-07-28` / `2025-11-25`); argument repair; server notifications, templated resources; the client side a host needs (every tool field, pagination, server messages, timeouts); host answers: capabilities from the client's handlers, MRTR sampling / elicitation answers, `call-tool` rounds · [cookbook](cookbooks/mcp.md) |
| `mcp-backend-stdio` | **0.2.0** | newline JSON-RPC MCP; notifications from any thread |
| `mcp-backend-streamable-http` | **0.3.0** | Streamable HTTP (POST JSON/SSE; GET 405); request notifications as SSE events |
| `lisp-source-protocol` | **0.2.6** | Eclector CST, recovery, lint, structural edits, table-driven indenter in the context of the enclosing forms; skips a leading `#!` line; every `#+`/`#-` branch is a form whatever the features; edit code keeps its comments (`stack-lisp-source`) · [cookbook](cookbooks/lisp-mcp.md) |
| `repl-protocol` | **0.2.7** | live image: eval, debugger, stepping, inspector, channels (input after an aborted channel debugger is never dropped); debugger levels claimed per request (`stack-repl`) |
| `repl-backend-swank` | **0.2.2** | SLIME Swank wire |
| `repl-backend-slynk` | **0.2.2** | Sly Slynk wire (+ mrepl channels) |
| `lisp-mcp` | **0.7.3** | Common Lisp MCP server (source / edit / live image); terse output, stored long output, background jobs; `--tools` groups (`code` / `image`), `edit-structure` · [tutorial](tutorials/lisp-mcp-session.md) · [cookbook](cookbooks/lisp-mcp.md) |
| `blackboard-protocol` | **0.3.0** | KSAR board + COW workspaces (`stack-blackboard`) · [cookbook](cookbooks/blackboard.md) |
| `capability-protocol` | **0.3.0** | `defcapability` + registry (`stack-capability`); `:llm-compaction` |
| `schema-protocol-json` | **0.1.3** | `:json` schema-document backend (LLM `:output`, AG-UI, MCP tools) |
| `schema-protocol-xsd` | **0.1.4** | `:xsd` backend; `decode-validating` (`stack-schema-xsd`) |
| `schema-protocol-arrow` | **0.1.2** | `:arrow` emit + parse (IPC / Parquet) + table↔objects (`stack-schema-arrow`) |
| `schema-protocol-avro` | **0.1.2** | `:avro` emit/parse (`stack-schema-avro`) |
| `json-patch` | **0.1.0** | RFC 6902 — AG-UI `STATE_DELTA` via `ag-ui-protocol/client` |
| `llm-protocol` | **0.7.1** | turns + parts + catalog + `embed` / `respond` / stream; retry policy by failure class, cache-aware usage, `server-compact` + `portable-turns`, lossless `part-state`, `llm-incomplete-response` for cut streams, typed provider errors (`llm-rate-limited`, `llm-overloaded`, `llm-auth-error`, `llm-not-found`, `llm-transport-error`), `Retry-After`, retry jitter (`stack-llm`) · [cookbook](cookbooks/llm.md) |
| `conversation-protocol` | **0.4.0** | session store + buffer / window / summary; `compact-turns`; `provider-compaction-memory` (`stack-conversation`) · [cookbook](cookbooks/conversation.md) |
| `steer-protocol` | **0.3.0** | rules / `SKILL.md` (`stack-steer`; not A2A `agent-skill`) + path-scoped `AGENTS.md` discovery, base prompt builder · [cookbook](cookbooks/steer.md) |
| `rag-protocol` | **0.1.3** | chunk / store / rerank / `analyze` / `fuse` / `ingest` / `retrieve` (`stack-rag`) · [cookbook](cookbooks/rag.md) |
| `rag-backend-memory` | **0.1.0** | in-process cosine vector store |
| `rag-backend-sql` | **0.1.0** | persist via `sql-protocol`; Lisp cosine (not ANN) |
| `rag-backend-pgvector` | **0.1.0** | Postgres `<=>` ANN; text `'[1,0]'::vector` wire |
| `rag-backend-hybrid` | **0.1.1** | Okapi BM25 + RRF / linear fusion over a vector store |
| `rag-backend-tsvector` | **0.1.0** | Postgres `tsvector` / `ts_rank` lexical store |
| `rag-backend-splade` | **0.1.0** | sparse term-weight store + encoder |
| `rag-backend-cross-encoder` | **0.1.0** | pairwise `rerank` (`:score-fn` / `:batch-fn`) |
| `rag-backend-text` | **0.2.0** | recursive character splitter |
| `llm-protocol-openai` | **0.8.0** | OpenAI-compat `/chat/completions` + `/responses` + `/embeddings` + stream; `prompt_cache_key` + cached-token usage |
| `llm-protocol-anthropic` | **0.4.0** | Anthropic Messages (`/v1/messages`) — official / vLLM / llama-server; prompt cache breakpoints, compaction on demand (`compact-2026-09-04`) and at a threshold |
| `llama-cpp` | **0.2.1** | CFFI `libllamastack` ABI 4 (`:grammar` / `:on-token` / `:parsed`); C++ shim turns llama.cpp exceptions and grammar dead ends into `llama-error`, exit with a live engine keeps its code; natives through `asdf-native` (optional CUDA libs); overlay must match |
| `llm-backend-llama-cpp` | **0.1.5** | native generate / stream / embed; GBNF tools; `:chat-template` `:auto` / ChatML / Llama-3 |
| `ai-agent-protocol` | **0.17.0** | async-first loop + `:memory` + `:steering` + permissions (always-allow rule store, reject-all-pending), background subagents, lazily discovered instructions (`run-ai-agent`, not `run-agent`) · [cookbook](cookbooks/ai-agent.md) · [tutorial](tutorials/agent-harness.md); denied calls get a tool result; `continue-ai-agent` after a cancel is a fresh turn; `invoke-deny … :by :unattended` / `:policy`; a tool output can end the run (`make-agent-tool-output :end-run t`, finish `:tool-end`, 0.16.1); deferred tool loading (`make-deferred-tool-source`, `tool_search`, a deferred tool called by name loads, 0.17.0); `ai-agent-protocol/mcp` 0.3.0: `make-mcp-sampling-handler :model :max-tokens` (the host picks the model), image content |
| `agent-tools` | **0.2.0** | coding-agent tools: files, search, edit, shell (pty on Unix, process tree kill) · [shell brief](capabilities/agent-tools-shell.md) |
| `browser-protocol` | **0.2.0** | headless Chrome / Chromium / Edge over CDP: `launch-browser` / `with-browser` / `connect-cdp` (`browser-protocol/launch`), replies by id, `navigate :wait-until`, stack JSON + base64 (`stack-browser`) · [brief](capabilities/browser.md) |
| `cl-stack-code` | **0.16.1** | coding agent CLI: headless `-p` (H3a), interactive terminal mode (H3b), sessions + steering (H3c), plan mode plans (H5c-0: explore, `propose_plan` writes a plan document, approve / revise / reject / save), preview mode (H5a), checkpoints + rewind (H5b), retries + timeouts + compaction (H3f), MCP sampling + elicitation through the approval channel, server instructions, deferred tool loading (`tool_search`, H3e-2b) · [brief](capabilities/cl-stack-code.md) |
| `doc-extract-protocol` | **0.4.0** | document extraction: HTML, markdown, DOCX and XLSX here; PDF / docling / unstructured backends |
| `doc-extract-render` | **0.1.1** | render extracted documents |
| `cl-stack-llm-tui` | **0.1.0** | desk chat (AG-UI TUI sink + agent loop) |
| `cl-stack-jwt` | **0.3.3** | JWT HS* + RS256/PS256/ES256/EdDSA via crypto-protocol (`expired-p` #6 closed) |
| `jose` | **0.1.0** | cl-stack-systems import (JWT escape hatch) |
| `http-backend-async` | **0.2.31** | async + H2 `:want-stream` + request DATA + `:protocol` HPACK + RFC 8441 WS; redirects by RFC 9110 §15.4: HEAD stays HEAD, 303 makes anything else a GET, 301/302 make only POST a GET, a kept method resends its body (a streamed upload is refused); a same-origin redirect reuses its kept-alive connection (http-backend-async#84, #85); `https://` proxies: TLS to the proxy (verified against its host name), CONNECT or absolute-form inside it, TLS inside TLS for https origins (http-protocol#53); a redirect through a proxy builds each hop for its own URL: proxy resolved again, absolute-form with `Proxy-Authorization` for `http://`, CONNECT for `https://` with no `Proxy-Authorization` inside the tunnel, `Authorization` dropped on another origin (http-backend-async#82); concurrent streams on one pooled h2 connection (≤ peer MAX_CONCURRENT_STREAMS, needs `http2` ≥ 2.1.2); a burst waits FIFO for a free stream (`*h2-stream-wait-timeout*` 2 s, `*h2-max-stream-waiters*` 32) instead of dialing |
| `http2` | **2.1.8** | fork; 64 KiB HPACK string / header-block limits, reset per block; header stream errors keep HPACK in sync; omit zero-increment `WINDOW_UPDATE`; keep explicit TLS files; intern literal pseudo-headers; ignore unknown SETTINGS; Homebrew `libssl` by absolute path on macOS |
| `http-backend-dexador` | **0.2.5** | sync HTTP/1.1 (CE codecs probed once); `:form-data`, `:data`, `:files` and coded bodies reach the origin as http-protocol encoded them (0.2.0 failed every form post, http-backend-dexador#32); a Content-Type with no body is sent (0.2.5, http-backend-dexador#36: S3 multipart uploads); redirects followed by the backend, so `response-history` lists them, with http-backend-async's rules (http-backend-dexador#33; 0.2.4: only POST becomes GET on 301/302); protocol proxy configs resolved (`no_proxy`, SOCKS5); plain HTTP reaches an HTTP proxy in absolute-form (needs `dexador` 0.9.16.1, published from the egao1980/dexador fork); `https://` proxies refused before any connection with `proxy-tls-unsupported` (dexador dials every proxy in plain TCP; `use-value` restart; http-protocol#53), SOCKS4 and SOCKS5 with credentials refused (`unsupported-operation`); TOTAL deadline + HTTPS read timeout enforced, streamed bodies and `http://` → `https://` redirects included; on Windows (WinHTTP) `send` stops waiting for a call at TOTAL too (http-backend-dexador#29); one connection pool per read timeout / BIO / proxy / `:verify`, POST and PATCH never start on a reused connection |
| `http-backend-winhttp` | **0.1.4** | Windows; HTTP/2 + **H1 WebSocket** (`WinHttpWebSocket*`) |
| `http-backend-java` | **0.1.1** | ABCL `java.net.http` |
| `ws-protocol` | **0.4.2** | CLOS client + `accept` / `make-ws-server` (`:transport` `:auto`/`:http/1.1`/`:http/2`) |
| `ws-backend-websocket-driver` | **0.4.3** | H1 Upgrade + **H2 Extended CONNECT server** (`make-ws-server :transport :http/2`); canary [`ws-parity`](https://github.com/egao1980/ws-parity) |
| `ag-ui-protocol` | **0.4.1** | 36 typed events + `/client` reducer (`stack-ag-ui`) · [cookbook](cookbooks/ag-ui.md) |
| `a2a-protocol` | **0.2.0** | Agent Card + tasks (`stack-a2a`) · [cookbook](cookbooks/a2a.md) |
| `a2a-backend-jsonrpc` | **0.2.2** | JSON-RPC 2.0 + SSE |
| `a2a-backend-httpjson` | **0.2.1** | HTTP+JSON REST |
| `a2a-backend-grpc` | **0.2.0** | `/lf.a2a.v1.A2AService/*` via `rpc-protocol-grpc` |
| `ag-ui-backend-sse` | **0.2.1** | POST `RunAgentInput` → SSE |
| `ag-ui-backend-protobuf` | **0.4.0** | JSON-as-WKT (`google.protobuf.Value`, `+proto`) and official `Event` oneof (`application/vnd.ag-ui.event+oneof`) |
| `ag-ui-backend-tui` | **0.1.1** | event sink + transcript (not a wire client) |
| `terminal-protocol` | **0.2.0** | headless terminal emulator: feed octets, frames, input encoding, viewport search, selection (`stack-terminal`) · [cookbook](cookbooks/terminal.md) |
| `terminal-backend-ghostty` | **0.3.0** | default emulator backend on libghostty-vt 1.0 (`ghostty-vt` **0.3.1** overlays) |
| `terminal-backend-lisp` | **0.2.0** | pure-Lisp VT core backend; same parity corpus |
| `pty-protocol` | **0.1.0** | run programs on pseudo-terminals: spawn, read/write, resize, signal (`stack-pty`) · [cookbook](cookbooks/terminal.md) |
| `pty-backend-native` | **0.2.1** | forkpty-style on Unix, ConPTY on Windows (`libpty-cl`) |
| `tui-protocol` | **0.2.0** | Elm-architecture TUIs on a cell canvas (`stack-tui`) · [tui](capabilities/tui.md) |
| `tui-backend-terminal` | **0.1.0** | headless TUI driver on any `terminal-protocol` emulator (tests, agents) |
| `tui-backend-tty` | **0.1.1** | real terminal for `tui-protocol`: termios raw mode + `SIGWINCH` (Unix), console VT mode (Windows), CFFI into libc / kernel32; restores on any exit · [tui](capabilities/tui.md) |
| `markdown-protocol` | **0.2.0** | CommonMark-subset parser + GFM tables + images (`stack-markdown`) · [brief](capabilities/markdown.md) |
| `tui-markdown` | **0.2.1** | markdown + diff rendering for `tui-protocol` (`stack-tui-md`) · [brief](capabilities/tui-markdown.md) |
| `html-markdown` | **0.1.0** | the markdown AST as html-protocol nodes; safe URL hook, heading ids (`stack-html-markdown`) · [brief](capabilities/html-markdown.md) |
| `org-markup` | **0.1.0** | Org-mode subset → the markdown AST + `#+KEY` keywords (`stack-org`) · [brief](capabilities/org-markup.md) |
| `highlight-protocol` | **0.1.0** | syntax highlighting: lexers → `(class . text)` tokens, `hl-` HTML spans, light / dark stylesheet (`stack-highlight`) · [brief](capabilities/highlight.md) |
| `image-protocol` | **0.3.1** | decode / encode / probe / convert images over several backends, Pillow-equal resize / thumbnail / crop / rotate / flip / composite (`stack-image`); a backend can take over resize (`backend-resize`, 0.3.0); `:reducing-gap` pays off in pure Lisp (image-protocol#9) · [image](capabilities/image.md) |
| `image-backend-stb` | **0.3.0** | stb_image / stb_image_write with Fedora's security patches; stb_image_resize2 fast path for `resize-image` |
| `http-server-protocol` | **0.2.0** | CLOS server; Clack env; Hunchentoot / Woo / **`http-server-backend-http2` 0.2.0** |
| `http-server-backend-hunchentoot` | **0.2.0** | default server backend (Windows + Unix) |
| `http-server-backend-woo` | **0.2.0** | Unix / libev second backend |
| `cli-protocol` | **0.2.1** | CLI parse/run + Windows dialects ([cookbook](cookbooks/cli.md)) |
| `cli-backend-clingon` | **0.2.1** | default CLI backend |
| `cli-backend-adopt` | **0.1.0** | alternate CLI backend |
| `serdes-protocol` | **0.2.2** | format encode/decode + Gray/JSONL/events + media types · [cookbook](cookbooks/serdes.md) |
| `sexp-protocol` | **0.2.2** | serdes `:sexp` implementor |
| `csv-protocol` | **0.1.0** | serdes `:csv` / `:tsv` (RFC 4180 dialects) · [cookbook](cookbooks/csv.md) |
| `encoding-protocol` | **0.3.0** | RFC 4648 / QP / RLE; RFC 3986 `percent-encode` / `percent-decode`; strict UTF-8 decode (`stack-encoding`); serdes via `/serdes` · [encoding-protocol](capabilities/encoding-protocol.md) |
| `binary-protocol` | **0.1.1** | Python `struct` pack/unpack (`stack-binary`); IEEE infinity / NaN as Python; no RFC 4648 · [binary-protocol](capabilities/binary-protocol.md) |
| `compression-protocol` | **0.5.1** | codec + zip/ustar (`compress` / `decompress`; `:tar` / `:tar.gz`; `:bzip2` inflate) |
| `compression-backend-chipz` | **0.3.0** | `:gzip` `:zlib` `:deflate` + `:bzip2` inflate (chipz + salza2) |
| `mime-protocol` | **0.3.4** | serdes `:mime` / `:multipart` (binary); nested multiparts; canonical header names; browser form-data names (UTF-8, literal backslash); header fields: C0 controls but HTAB refused (`mime-header-error`), raw non-UTF-8 fields relayed as their octets (`copy-headers`), long lines folded, RFC 2047 `encode-header-text` / `decode-header-text`; RFC 2231 continuations (none in form-data); `guess-type` / `add-type` · [mime-protocol](capabilities/mime-protocol.md) |
| `mail-protocol` | **0.3.2** | email compose/parse/send (`stack-mail`); Date / Message-ID, `add-alternative` / `add-attachment` (long and non-ASCII filenames as RFC 2231 `filename*`); RFC 5322 addresses (envelope = addr-specs), RFC 2047 headers; Bcc envelope-only; IMAP client · [mail-protocol](capabilities/mail-protocol.md) |
| `mail-backend-memory` | **0.3.2** | record sent messages |
| `mail-backend-smtp` | **0.3.2** | SMTP AUTH PLAIN / LOGIN, STARTTLS, implicit TLS (cl-stack-ssl); 8BITMIME / SMTPUTF8; no CR/LF in a command |
| `cache-protocol` | **0.2.0** | get / put (`:ttl`) / delete / incr / CAS; atomic in-memory TTL cache, monotonic clock (`stack-cache`) · [cache](capabilities/cache.md) |
| `cache-backend-redis` | **0.2.1** | RESP3 Redis / Valkey: host/port or `redis[s]://` URL, AUTH (Redis 5 fallback), SELECT, TLS; a dropped socket or `-LOADING` is retried once on a new connection |
| `mq-protocol` | **0.1.0** | `publish` / `poll-messages` / `ack` / `nack` (`stack-mq`) · [mq](capabilities/mq.md) |
| `mq-backend-amqp` | **0.2.2** | AMQP 0-9-1 (RabbitMQ) in Lisp: SASL PLAIN, heartbeats, Basic.Get, broker Close as conditions, TLS · canary [`mq-parity`](https://github.com/egao1980/mq-parity) **0.2.0** |
| `mq-backend-kafka` | **0.2.2** | Kafka over librdkafka 2.16.0 native overlays (darwin arm64, linux amd64 / arm64, windows amd64): consumer groups, `ack` commits the offset · canary [`mq-parity`](https://github.com/egao1980/mq-parity) **0.2.0** |
| `cbor-protocol` | **0.1.0** | serdes `:cbor` · [cbor-protocol](capabilities/cbor-protocol.md) |
| `messagepack-protocol` | **0.1.0** | serdes `:messagepack` / `:msgpack` · [messagepack-protocol](capabilities/messagepack-protocol.md) |
| `avro-protocol` | **0.1.2** | serdes `:avro` · [avro-protocol](capabilities/avro-protocol.md) |
| `arrow-protocol` | **0.1.1** | serdes `:arrow` / `:parquet` (`stack-arrow`) · [arrow](capabilities/arrow.md) |
| `log-protocol` | **0.1.2** | level + filters + async; text/structured; stream sink ([cookbook](cookbooks/logging.md)) |
| `telemetry-protocol` | **0.2.0** | traces / spans + thin metrics (`stack-telemetry`) |
| `telemetry-backend-otlp` | **0.2.0** | OTLP/HTTP JSON |
| `cl-stack-snappy` | **1.3.1.2** | Snappy raw + framed; HTTP CE uses raw; 4th part = package revision |
| `cl-stack-ssl` | **3.5.9.4** | OpenSSL 3.5.9 LTS overlays for stock `cl+ssl` (linux/darwin/windows); staged `SSL_CERT_*` reach child images; a dumped image makes its SSL context at first use, not at load (cl-stack-ssl#23) |
| `cl-stack-brotli` | **1.2.1.2** | Brotli 1.2.1 overlays + thin CFFI (`br`) |
| `cl-stack-zstd` | **1.5.7.2** | Zstandard 1.5.7 overlays + thin CFFI (`zstd`) |
| `http-encoding-chipz` | **0.1.1** | `gzip` / `deflate` Content-Encoding |
| `http-encoding-brotli` | **0.1.1** | `br` |
| `http-encoding-zstd` | **0.1.1** | `zstd` |
| `http-encoding-snappy` | **0.1.1** | `snappy` (raw, not framed) |
| `log-backend-log4cl` | **0.1.1** | default log backend — **separate repo** |
| `log-backend-vom` | **0.1.1** | alternate log backend — **separate repo** |
| `grpc-protocol` | **0.2.0** | gRPC wire / channel (`:compression` facade) |
| `grpc-backend-http2` | **0.4.2** | unary + server-stream + interleaved bidi; accept handler runs on the HTTP/2 reader; gzip/deflate frames (`http-body-pipe`); canary [`grpc-parity`](https://github.com/egao1980/grpc-parity) |
| `grpc-backend-native` | **0.1.0** | C-core (linux/darwin) |
| `protobuf-protocol` | **0.2.0** | serdes `:protobuf` + proto3 JSON / WKT |
| `protobuf-backend-cl-protobufs` | **0.2.0** | default protobuf backend |
| `event-protocol` | **0.3.0** | event-loop generics (`wake-call` / `submit` / `close-event-loop`); `event-protocol/promises`: `await` a promise, `gather`, `run-promise` (asyncio.run shape) |
| `event-backend-libuv` | **0.2.2** | default (Windows-primary); libuv 1.53.0; per-loop submit pool |
| `event-backend-libev` | **0.2.2** | Unix second backend; per-loop submit pool |
| `event-backend-nio` | **0.1.2** | ABCL / JVM NIO; binds `*event-loop*` in `run` |
| `cl-stack-executors` | **0.1.0** | BT pools backends *may* plug into `submit` |
| `cffi` | **0.24.1** | via cl-stack-systems import |
| `asdf-native` | **0.3.2** | `(:native-library "foo")` ASDF component: natives load at ASDF load by absolute path (env override → `native/` overlay → `lib/<os>-<arch>/`); cl-repo derives overlays from it · [overlays](overlays.md) |

Channel / pin-file format: [pins.md](pins.md). Overlay platforms: [overlays.md](overlays.md).

---

## 3. Minimal HTTP (facade)

```lisp
(cl-repo:load-system "cl-stack-http" :version "0.2.1")
;; optional CE codecs: http-encoding-chipz / -brotli / -zstd / -snappy

(defpackage #:demo (:use #:cl) (:local-nicknames (#:http #:cl-stack-http)))
(in-package #:demo)

;; :auto picks a backend: dexador, then async/libuv, for blocking calls;
;; async/libuv first for get-async and the other -async calls (winhttp first
;; on Windows). :async wires the libuv event backend itself.
(http:ensure-http-backend :auto)

(let ((r (http:get "https://httpbin.org/get" :params '(("q" . "1")))))
  (format t "~a ~a~%" (http:response-status r) (http:response-http-version r))
  (princ (http:response-text r)))
```

### HTTP/2 preference (`http-protocol` 0.3.1+)

```lisp
(cl-repo:load-system "http-protocol" :version "0.3.8")
(cl-repo:load-system "http-backend-async" :version "0.2.8")
(cl-repo:load-system "event-backend-libuv" :version "0.1.4")

(setf http-backend-async:*event-backend-maker*
      (lambda () (event-backend-libuv:make-libuv-backend)))

(let* ((backend (http-backend-async:make-async-backend))
       (client (http-protocol:make-http-client backend :http-version :http/2))
       (req (http-protocol:make-http-request
             :url "https://nghttp2.org/" :http-version :http/2))
       (res (http-protocol:send backend client req)))
  (format t "~a ~a~%"
          (http-protocol:response-status res)
          (http-protocol:response-http-version res)))
```

| Preference | Meaning |
|------------|---------|
| `:auto` | Prefer H2 when backend + peer allow (ALPN) |
| `:http/1.1` | Force 1.1 |
| `:http/2` | Require H2 or signal `http-version-not-available` |

CLOS split: protocol owns preference / ALPN helpers / H2 header policy; backends own wire (or WinHTTP). Brief: [capabilities/http-protocol.md](capabilities/http-protocol.md). Recipes: [cookbooks/http-client.md](cookbooks/http-client.md).

### WebSocket (`ws-protocol` 0.4.0+)

```lisp
(cl-repo:load-system "ws-protocol" :version "0.4.0")
(cl-repo:load-system "ws-backend-websocket-driver" :version "0.4.0") ; H1 Upgrade + H2 CONNECT server
(cl-repo:load-system "http-backend-async" :version "0.2.8") ; :http/2 Extended CONNECT client
;; Windows H1 Upgrade:
;; (cl-repo:load-system "http-backend-winhttp" :version "0.1.3")

(let* ((backend (http-backend-async:make-async-backend))
       (client (ws-protocol:make-ws-client backend :transport :http/2))
       (conn (ws-protocol:connect backend client "wss://example.com/ws")))
  (ws-protocol:on-event conn :message (lambda (msg) (print msg)))
  (ws-protocol:send-text conn "hi")
  (ws-protocol:close-connection conn))
```

| Preference | Meaning |
|------------|---------|
| `:auto` | Prefer `:http/2` when backend lists it, else `:http/1.1` |
| `:http/1.1` | RFC 6455 Upgrade (websocket-driver / WinHTTP) |
| `:http/2` | RFC 8441 Extended CONNECT (async client; H2 server via `make-ws-server :transport :http/2`) |

H2 server (`:ssl-cert` / `:ssl-key` required; `:auto` stays H1):

```lisp
(let* ((backend (ws-backend-websocket-driver:make-websocket-driver-backend))
       (server (ws-protocol:make-ws-server backend :transport :http/2
                                           :host "127.0.0.1" :port 8443 :path "/echo"
                                           :ssl-cert "cert.pem" :ssl-key "key.pem"
                                           :on-connect
                                           (lambda (conn)
                                             (ws-protocol:on-event conn :message
                                               (lambda (msg) (ws-protocol:send-text conn msg)))))))
  (ws-protocol:start-ws-server server))
```

Live gates: `HTTP_ASYNC_WS_H2_LIVE=1`, `WINHTTP_WS_LIVE=1` (or `feature-or-env-enabled-p`). Brief: [capabilities/ws-protocol.md](capabilities/ws-protocol.md). Recipes + demos: [cookbooks/websocket.md](cookbooks/websocket.md).

### OAuth2 / JWT (optional packages)

```lisp
(cl-repo:load-system "cl-stack-oauth2" :version "0.1.0")
(cl-repo:load-system "cl-stack-jwt" :version "0.3.3")

;; OAuth2 client-credentials → pass as :auth to stack-http
(defvar *auth*
  (stack-oauth2:make-oauth2-auth
   :token-url "https://as.example/oauth/token"
   :client-id "cid" :client-secret "sec"
   :scope '("api.read") :grant :client-credentials))
(http:get "https://api.example/v1/me" :auth *auth*)

;; JWT crypto (not HTTP) — crypto-protocol sign/hmac
(stack-jwt:encode :hs256 key '(("sub" . "u")))
(stack-jwt:decode :hs256 key token)
```

---

## 4. Event loop (promises)

```lisp
(cl-repo:load-system "event-protocol" :version "0.3.0")
(cl-repo:load-system "event-backend-libuv" :version "0.2.3")

(let* ((eb (event-backend-libuv:make-libuv-backend))
       (el (event-protocol:make-event-loop eb)))
  (event-protocol:with-event-backend (eb)
    (event-protocol:with-event-loop-var (el)
      ;; defer / sleep* / register-io / wake-call / submit — see capability brief
      )))
```

From synchronous code (`asyncio.run(asyncio.gather(…))`): `run-promise` makes a loop, binds it, awaits the promise and closes the loop.

```lisp
(cl-repo:load-system "event-protocol" :version "0.3.0")   ; + event-protocol/promises
(stack-event-promises:run-promise
 (lambda ()
   (stack-event-promises:gather
    (stack-http:get-async "https://httpbin.org/get")
    (stack-http:get-async "https://httpbin.org/uuid")))
 :backend (event-backend-libuv:make-libuv-backend)
 :timeout 30)
;; => (#<HTTP-RESPONSE> #<HTTP-RESPONSE>)
```

Default backend = **libuv** (Windows-primary). Unix second = **libev**. Brief: [capabilities/event-protocol.md](capabilities/event-protocol.md).

---

## 5. Consumer CI skeleton

```yaml
jobs:
  test:
    uses: egao1980/cl-repository/.github/workflows/test-system.yml@main
```

Rules (non-negotiable):

- Deps from **GHCR via cl-repo**, not sibling git checkouts.
- Unforked third-party → [`cl-stack-systems`](https://github.com/egao1980/cl-stack-systems) import → republish into `cl-systems`.
- Never require `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` for correctness.

---

## 6. Where next

| Want | Go |
|------|----|
| requests/httpx recipes | [cookbooks/http-client.md](cookbooks/http-client.md) |
| WebSocket recipes / demos | [cookbooks/websocket.md](cookbooks/websocket.md) |
| RPC / SSE / MCP | [cookbooks/rpc.md](cookbooks/rpc.md) · [sse.md](cookbooks/sse.md) · [mcp.md](cookbooks/mcp.md) |
| Lisp tools for agents (MCP) | [cookbooks/lisp-mcp.md](cookbooks/lisp-mcp.md) · [tutorial](tutorials/lisp-mcp-session.md) |
| A2A / AG-UI | [cookbooks/a2a.md](cookbooks/a2a.md) · [ag-ui.md](cookbooks/ag-ui.md) |
| AI agent loop | [cookbooks/ai-agent.md](cookbooks/ai-agent.md) · [tutorial: long runs](tutorials/agent-harness.md) |
| Blackboard / capabilities | [cookbooks/blackboard.md](cookbooks/blackboard.md) |
| LLM generate / stream / embed | [cookbooks/llm.md](cookbooks/llm.md) |
| Schema / datetime / conditions | [schema.md](cookbooks/schema.md) · [datetime.md](cookbooks/datetime.md) · [conditions.md](cookbooks/conditions.md) |
| Protocol decisions / RFCs | [capabilities/](capabilities/) |
| Overlay platforms | [overlays.md](overlays.md) |
| Pin channels | [pins.md](pins.md) |
| cl-repository deep dive | [egao1980/cl-repository](https://github.com/egao1980/cl-repository) |
| macOS protobuf/grpc note | [lisp-workspace QUICKSTART-MAC](https://github.com/egao1980/lisp-workspace/blob/main/docs/QUICKSTART-MAC.md) (agent workspace) |

---

## Maintaining this doc

When you **merge + publish** a user-visible feature:

1. Bump the row in [§2 Current stack pins](#2-current-stack-pins-bump-when-publishing).
2. Add or adjust a minimal snippet in §3–4 if the DX entry point changed.
3. Link any new cookbook under [cookbooks/README.md](cookbooks/README.md).
4. Keep capability briefs for design depth — do not dump RFCs here.

Agents: treat an outdated pin table as a bug. Prefer editing this file in the same PR that publishes the OCI tag.

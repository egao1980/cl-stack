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
| Quicklisp | only to bootstrap the **client** |
| [oras](https://oras.land/) | preferred way to pull `cl-repository-client` |

No C toolchain needed for consumer installs — natives ship in overlays.

---

## 1. Bootstrap `cl-repository-client`

Prefer the **`cl-repository/`** GHCR namespace (not the old `cl-systems/cl-repository-client` mirror).

```bash
# :latest is a system-name *anchor* (not a package). Resolve the semver, then pull.
IMG=ghcr.io/egao1980/cl-repository/cl-repository-client
CLIENT_VER=$(oras manifest fetch "${IMG}:latest" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["annotations"]["org.opencontainers.image.version"])')
# Or pin explicitly: CLIENT_VER=0.13.0
DEST="${HOME}/.local/share/cl-repository-client"
rm -rf /tmp/cl-repo-pull "$DEST"
mkdir -p /tmp/cl-repo-pull "$DEST"
oras pull "${IMG}:${CLIENT_VER}" -o /tmp/cl-repo-pull
for f in /tmp/cl-repo-pull/*.tar.gz; do tar -xzf "$f" -C "$DEST"; done
CLIENT_DIR="$(find "$DEST" -maxdepth 1 -type d -name 'cl-oci-*' | head -1)"
echo "Client tree: $CLIENT_DIR (resolved ${CLIENT_VER})"
```

One-time QL deps for the **client only** (not your app):

```bash
ros -e '(ql:quickload '("yason" "ironclad" "babel" "dexador" "quri" "chipz"
                        "flexi-streams" "cl-ppcre" "cl-base64" "trivial-features"
                        "salza2" "archive") :silent t)' -q
```

Then in Lisp (set `*client-dir*` to the `cl-oci-*` path printed above):

```lisp
(defparameter *client-dir*
  #P"/Users/you/.local/share/cl-repository-client/cl-oci-…/") ; ← paste path

(asdf:initialize-source-registry
 `(:source-registry
   (:tree ,*client-dir*)
   :inherit-configuration))
(asdf:load-system "cl-repository-client")
(cl-repo:add-registry "https://ghcr.io"
                      :namespace "egao1980/cl-systems"
                      :priority :prepend)
```

`cl-repo:load-system` pulls the OCI package (and matching overlay), installs deps, then `asdf:load-system`.

**CI pattern:** canned `egao1980/cl-repository/.github/workflows/test-system.yml@main` (or `setup-client` + `ci` with `phase: install|test`). `actions/checkout` **only** the repo under test — never sibling-checkout deps. Do **not** copy `ci-install.lisp`.

---

## 2. Current stack pins (bump when publishing)

| System | OCI tag | Notes |
|--------|---------|--------|
| `cl-repository-client` | **`:latest`** | system-name anchor — resolve semver then pull (see §1) |
| `cl-stack/meta` | hub git | ASDF metapackage — `pins/stable.pins` + `(cl-stack:apply-pins …)` |
| `json-protocol` | **0.2.0** | encode/decode + serdes `:json`; load `json-backend-jzon` (default) or `json-backend-yason`; nick `stack-json` · [cookbook](cookbooks/json.md) |
| `io-protocol` | **0.1.0** | object streams (`read-object` / `write-object`); nick `stack-io` · [cookbook](cookbooks/io.md) |
| `babel` | **0.5.0** | UTF-8 octets ↔ string ([text-unicode](capabilities/text-unicode.md)) |
| `unicode-protocol` | **0.1.2** | UCD/normalize/case/IDNA/breaks/uset (`stack-unicode`) · [cookbook](cookbooks/unicode.md) |
| `unicode-backend-cl-unicode` | **0.1.0** | portable default unicode backend |
| `unicode-backend-sbcl` | **0.1.0** | SBCL `sb-unicode` (no `:idna`) |
| `unicode-backend-icu` | **0.1.1** | ICU4C CFFI backend |
| `unicode-backend-icu4j` | **0.1.2** | ICU4J / ABCL (auto-bind `#+abcl`) |
| `cl-stack-icu` | **78.1.3** | ICU4C overlays + CFFI (linux/darwin/windows) |
| `cl-stack-icu4j` | **78.1.3** | ICU4J jar + ABCL bridge |
| `i18n-protocol` | **0.1.0** | locale / MF2 / plural / catalogs (`stack-i18n`) |
| `i18n-backend-icu` | **0.1.1** | ICU4C i18n |
| `i18n-backend-icu4j` | **0.1.1** | ICU4J i18n (auto-bind `#+abcl`) |
| `l10n-protocol` | **0.1.0** | collate / numfmt / date / locale case (`stack-l10n`) |
| `l10n-backend-icu` | **0.1.1** | ICU4C l10n |
| `l10n-backend-icu4j` | **0.1.2** | ICU4J l10n (auto-bind `#+abcl`) |
| `cl-stack-idna` | **0.1.0** | `to-ascii` / `to-unicode` facade (`stack-idna`) |
| `bordeaux-threads` | **0.9.4** | portable threads / bt2 ([concurrency](capabilities/concurrency.md)) |
| `cl-stack-config` | **0.1.0** | env + TOML ([config](capabilities/config.md) · [cookbook](cookbooks/config.md)) |
| `tomlet` | **0.1.0** | TOML parser (config pin) |
| `http-protocol` | **0.3.1** | wire client; `:http-version` / H2 header policy; `TE: trailers` |
| `cl-stack-http` | **0.1.8** | requests-like facade (`stack-http`); JSON via `json-protocol`/jzon |
| `cl-stack-pathlib` | **0.2.1** | CLOS path + FS (`stack-pathlib`; `zip://`; restarts) · [conditions](cookbooks/conditions.md) |
| `datetime-protocol` | **0.1.1** | instant / duration / period / date / zone (`stack-datetime`) · [cookbook](cookbooks/datetime.md) |
| `cl-stack-tzdata` | **2026.3.0** | IANA tzdb (TZif) — no OS zoneinfo |
| `cl-stack-calendars` | **0.4.0** | holidays / business days / exchange sessions |
| `schema-protocol` | **0.1.0** | CLOS `defschema` (`stack-schema`) · [cookbook](cookbooks/schema.md) |
| `schema-protocol-json` | **0.1.1** | draft-07 emit / compile |
| `sql-protocol` | **0.1.0** | connectivity + pool (`stack-sql`) · [cookbook](cookbooks/sql.md) |
| `sql-query` | **0.2.0** | CLOS SQL DSL |
| `cl-stack-oauth2` | **0.1.0** | OAuth2 scopes/grants/PKCE/401 refresh (`stack-oauth2`) |
| `crypto-backend-ironclad` | **0.1.1** | digest/HMAC/AEAD + secrets (Ironclad) |
| `secrets-protocol` | **0.1.0** | CSPRNG/tokens/UUID/password KDF API |
| `process-protocol` | **0.1.0** | subprocess `run`/`launch` (`stack-process`) · [cookbook](cookbooks/process.md) |
| `process-backend-uiop` | **0.1.0** | UIOP backend (default) |
| `rpc-protocol` | **0.2.0** | RPC modes (`stack-rpc`) · [cookbook](cookbooks/rpc.md) |
| `rpc-protocol-json` | **0.1.0** | JSON-RPC 2.0 codec |
| `rpc-backend-inprocess` | **0.1.0** | in-process unary |
| `rpc-backend-stdio` | **0.1.1** | newline JSON-RPC over process-protocol |
| `rpc-backend-http` | **0.1.1** | JSON-RPC POST (client + Clack) |
| `rpc-backend-sse` | **0.1.1** | JSON-RPC as SSE `data:` |
| `sse-protocol` | **0.1.0** | `text/event-stream` framing (`stack-sse`) · [cookbook](cookbooks/sse.md) |
| `sse-backend-http` | **0.1.0** | SSE client via http-protocol |
| `sse-backend-clack` | **0.1.0** | SSE server (Clack) |
| `mcp-protocol` | **0.2.0** | dual-era MCP (`2026-07-28` / `2025-11-25`) · [cookbook](cookbooks/mcp.md) |
| `mcp-backend-stdio` | **0.1.1** | newline JSON-RPC MCP |
| `mcp-backend-streamable-http` | **0.2.0** | Streamable HTTP (POST JSON/SSE; GET 405) |
| `blackboard-protocol` | **0.1.0** | KSAR board + COW workspaces (`stack-blackboard`) · [cookbook](cookbooks/blackboard.md) |
| `capability-protocol` | **0.1.0** | `defcapability` + registry (`stack-capability`) |
| `llm-protocol` | **0.1.0** | turns + typed parts (`stack-llm`) · [cookbook](cookbooks/llm.md) |
| `llm-protocol-openai` | **0.1.0** | OpenAI-compat `/v1/chat/completions` + `/responses` |
| `cl-stack-jwt` | **0.2.0** | JWT HS* via crypto-protocol:hmac (`stack-jwt`) |
| `jose` | **0.1.0** | cl-stack-systems import (JWT crypto) |
| `http-backend-async` | **0.2.4** | async + HTTP/2 + **RFC 8441 WS** (loop-native) |
| `http-backend-dexador` | **0.1.2** | sync HTTP/1.1 |
| `http-backend-winhttp` | **0.1.3** | Windows; HTTP/2 + **H1 WebSocket** (`WinHttpWebSocket*`) |
| `ws-protocol` | **0.2.2** | CLOS `:transport` + `feature-or-env-enabled-p` + demo |
| `ag-ui-protocol` | **0.2.0** | typed agent↔UI events (`stack-ag-ui`) · [cookbook](cookbooks/ag-ui.md) |
| `a2a-protocol` | **0.2.0** | Agent Card + tasks (`stack-a2a`) · [cookbook](cookbooks/a2a.md) |
| `a2a-backend-jsonrpc` | **0.2.1** | JSON-RPC 2.0 + SSE |
| `a2a-backend-httpjson` | **0.2.0** | HTTP+JSON REST |
| `a2a-backend-grpc` | **0.2.0** | `/lf.a2a.v1.A2AService/*` via `rpc-protocol-grpc` |
| `ag-ui-backend-sse` | **0.2.0** | POST `RunAgentInput` → SSE |
| `ag-ui-backend-protobuf` | **0.2.0** | protobuf-in-SSE (`:format :protobuf` = JSON octets) |
| `http-server-protocol` | **0.1.0** | CLOS server; Clack env; load `http-server-backend-hunchentoot` (default) or `…-woo` ([cookbook](cookbooks/http-server.md)) |
| `http-server-backend-hunchentoot` | **0.1.0** | default server backend (Windows + Unix) |
| `http-server-backend-woo` | **0.1.0** | Unix / libev second backend |
| `cli-protocol` | **0.1.0** | CLI parse/run + Windows dialects ([cookbook](cookbooks/cli.md)) |
| `cli-backend-clingon` | **0.1.0** | default CLI backend |
| `serdes-protocol` | **0.2.1** | format encode/decode + Gray/JSONL/events · [cookbook](cookbooks/serdes.md) |
| `sexp-protocol` | **0.2.0** | serdes `:sexp` implementor |
| `log-protocol` | **0.1.1** | level + filters + async; text/structured ([cookbook](cookbooks/logging.md)) |
| `log-backend-log4cl` | **0.1.1** | default log backend |
| `event-protocol` | **0.1.2** | event-loop generics |
| `event-backend-libuv` | **0.1.1** | default (Windows-primary) |
| `event-backend-libev` | **0.1.2** | Unix second backend |
| `cffi` | **0.24.1** | via cl-stack-systems import |

Channel / pin-file format: [pins.md](pins.md). Overlay platforms: [overlays.md](overlays.md).

---

## 3. Minimal HTTP (facade)

```lisp
(cl-repo:load-system "cl-stack-http" :version "0.1.8")
;; optional CE codecs: http-encoding-chipz / -brotli / -zstd

(defpackage #:demo (:use #:cl) (:local-nicknames (#:http #:cl-stack-http)))
(in-package #:demo)

;; :auto picks a backend (async/libuv preferred; winhttp on Windows)
(http:ensure-http-backend :auto)

(let ((r (http:get "https://httpbin.org/get" :params '(("q" . "1")))))
  (format t "~a ~a~%" (http:response-status r) (http:response-http-version r))
  (princ (http:response-text r)))
```

### HTTP/2 preference (`http-protocol` 0.3.1+)

```lisp
(cl-repo:load-system "http-protocol" :version "0.3.1")
(cl-repo:load-system "http-backend-async" :version "0.2.4")
(cl-repo:load-system "event-backend-libuv" :version "0.1.1")

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

### WebSocket (`ws-protocol` 0.2.2+)

```lisp
(cl-repo:load-system "ws-protocol" :version "0.2.2")
(cl-repo:load-system "http-backend-async" :version "0.2.4") ; :http/2 Extended CONNECT
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
| `:http/2` | RFC 8441 Extended CONNECT (async; needs peer `ENABLE_CONNECT_PROTOCOL`) |

Live gates: `HTTP_ASYNC_WS_H2_LIVE=1`, `WINHTTP_WS_LIVE=1` (or `feature-or-env-enabled-p`). Brief: [capabilities/ws-protocol.md](capabilities/ws-protocol.md). Recipes + demos: [cookbooks/websocket.md](cookbooks/websocket.md).

### OAuth2 / JWT (optional packages)

```lisp
(cl-repo:load-system "cl-stack-oauth2" :version "0.1.0")
(cl-repo:load-system "cl-stack-jwt" :version "0.2.0")

;; OAuth2 client-credentials → pass as :auth to stack-http
(defvar *auth*
  (stack-oauth2:make-oauth2-auth
   :token-url "https://as.example/oauth/token"
   :client-id "cid" :client-secret "sec"
   :scope '("api.read") :grant :client-credentials))
(http:get "https://api.example/v1/me" :auth *auth*)

;; JWT crypto (not HTTP) — jose under the hood
(stack-jwt:encode :hs256 key '(("sub" . "u")))
(stack-jwt:decode :hs256 key token)
```

---

## 4. Event loop (promises)

```lisp
(cl-repo:load-system "event-protocol" :version "0.1.2")
(cl-repo:load-system "event-backend-libuv" :version "0.1.1")

(let* ((eb (event-backend-libuv:make-libuv-backend))
       (el (event-protocol:make-event-loop eb)))
  (event-protocol:with-event-backend (eb)
    (event-protocol:with-event-loop-var (el)
      ;; defer / sleep* / register-io — see capability brief
      )))
```

Default backend = **libuv** (Windows-primary). Unix second = **libev**. Brief: [capabilities/event-protocol.md](capabilities/event-protocol.md).

---

## 5. Consumer CI skeleton

```yaml
# checkout ONLY this repo
- uses: actions/checkout@v4
- uses: egao1980/cl-repository/.github/workflows/test-system.yml@main
  # reads .asd :depends-on + :properties (:cl-repo …)
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
| A2A / AG-UI | [cookbooks/a2a.md](cookbooks/a2a.md) · [ag-ui.md](cookbooks/ag-ui.md) |
| Blackboard / capabilities | [cookbooks/blackboard.md](cookbooks/blackboard.md) |
| LLM generate | [cookbooks/llm.md](cookbooks/llm.md) |
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

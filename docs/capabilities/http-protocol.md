# http-protocol (wave-1)

**Issues:** [#3](https://github.com/egao1980/cl-stack/issues/3) · [#29](https://github.com/egao1980/cl-stack/issues/29) · [#30](https://github.com/egao1980/cl-stack/issues/30) · [#31](https://github.com/egao1980/cl-stack/issues/31) · [#32](https://github.com/egao1980/cl-stack/issues/32) · encoding [#45](https://github.com/egao1980/cl-stack/issues/45)/[#46](https://github.com/egao1980/cl-stack/issues/46)/[#47](https://github.com/egao1980/cl-stack/issues/47)  
**Status:** brief locked (#29 closed); overlays + CE backends done; `#30` sync [`http-backend-dexador`](https://github.com/egao1980/http-backend-dexador) + `http` facade **done**; `#31` async [`http-backend-async`](https://github.com/egao1980/http-backend-async) on `event-protocol` **done** (HTTP/1.1 + HTTPS + redirects/cookies; live CE via `HTTP_ASYNC_LIVE`); `#32` hub corpus + OCI consumer **done**; `#54` `:auth` / `:range` / `http:trace`+`connect` **shipped**; `#71` buffered body Gray streams; `#73` `http-file` CLOS + multipart `:data`/`:files` (FS-free wire; pathlib facade → [`cl-stack-http`](https://github.com/egao1980/cl-stack-http))

**Layering (Python analogy):** `http-protocol` + backends ≈ **urllib3 / httpx** (wire client). **requests-like** DX → [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) (pathlib upload/download, Session, JSON/sexp, MIME, backend select, Digest/netrc, CLOS auth protocol). OAuth2 → [`cl-stack-oauth2`](https://github.com/egao1980/cl-stack-oauth2); JWT crypto → [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt) (crypto-protocol sign).

**Cookbook (quickstart recipes):** [cookbooks/http-client.md](../cookbooks/http-client.md).

httpx-shaped HTTP **client** facade: sync + async over `event-protocol`, TLS via `cl-stack-ssl`. Protocol is method-complete (RFC 9110 + PATCH); backends may stub rare verbs with `unsupported-operation`.

Conventions: [API.md](../API.md). TLS overlays: [overlays.md](../overlays.md). Event DX: [event-protocol.md](event-protocol.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **DX target** | **httpx** (requests-compatible) | Issue #3; sync+async one API shape |
| **requests-like layer** | [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) | Path/`download`/`upload`, Session, JSON/sexp, MIME, Digest/netrc, CLOS auth — wraps protocol (no core FS) |
| **OAuth2 / JWT** | [`cl-stack-oauth2`](https://github.com/egao1980/cl-stack-oauth2) / [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt) | Token flows + JWT via crypto-protocol (jose escape hatch) |
| **Parity refs** | **Java `java.net.http`** + **Boost.Beast verbs/messages** + RFCs below | Java = high-level client bar; Beast = wire vocabulary (not a full client) |
| **Sync backend** | **dexador** | De-facto CL client; pooling, multipart, cookies, proxy |
| **Async** | On **event-protocol** (≥2 backends) | Not hard-wired to libuv/libev; promises at facade |
| **TLS** | **cl+ssl** + `cl-stack-ssl` overlay | #12 done; HTTPS/WSS consumers share OpenSSL |
| **WebSocket** | **Out of this protocol** → `ws-protocol` (#4) | Java puts WS on `HttpClient`; we keep separate per API.md |
| **HTTP versions** | **HTTP/1.1** + prefer/negotiate **HTTP/2** (wave-2); **HTTP/3** = P2 | Protocol = preference + ALPN/header policy (RFC 7301 / 9113 §8); backends = wire (see [HTTP version split](#http-version-clos-split)) |
| **Method surface** | All RFC 9110 methods + **PATCH** (RFC 5789); extension methods via string/keyword escape | Match Beast `http::verb` core + Java `method(...)` |
| **Bodies** | Streams / octets / strings + `http-file` CLOS; httpx `:content` / `:data` / `:files` | Stream large payloads; **no pathnames in protocol** (pathlib+MIME higher layer) |
| **Errors** | Conditions (+ restarts), not status-only | API.md; map 4xx/5xx optionally via policy |
| **IDNA** | [`egao1980/cl-idna`](https://github.com/egao1980/cl-idna) | IDNA2008 + [UTS #46](https://unicode.org/reports/tr46/); supersedes `antifuchs/idna` for stack pin |
| **URI** | **quri** (`egao1980/quri`) | Host/query/IPv6; IDNA via `cl-idna` |
| **Content-Encoding** | **gzip / deflate / br / zstd / snappy** (raw) | httpx parity + Snappy; see [Content encoding](#content-encoding-wave-1) |
| **MIME / multipart** | **[`egao1980/cl-mime`](https://github.com/egao1980/cl-mime)** (fork of [40ants/cl-mime](https://github.com/40ants/cl-mime)) + **trivial-mimes** / **chunga** where dexador already uses them | Full MIME parse/print + CTE; see support libs |

---

## Support libraries (pins)

Wave-1: pin what dexador already uses, **except IDNA** — use stack `cl-idna`.

| Concern | Pin | Status |
|---------|-----|--------|
| IDNA / punycode | **[`cl-idna`](https://github.com/egao1980/cl-idna)** | Stack-owned; `to-ascii` / `to-unicode` (UTR#46). OCI `ghcr.io/egao1980/cl-systems/cl-idna:0.1.0`. Not on Quicklisp (Ultralisp/GitHub). |
| URI parse/build | **[`egao1980/quri`](https://github.com/egao1980/quri)** fork `0.7.1` | Patched to `cl-idna` (not QL `idna`). OCI `ghcr.io/egao1980/cl-systems/quri:0.7.1`. **No upstream PR** until `cl-idna` is on Quicklisp. qlot: `github egao1980/quri`. |
| Content decode gzip/deflate | **chipz** via [`http-encoding-chipz`](https://github.com/egao1980/http-encoding-chipz) | event-backend-shaped method package |
| Content encode gzip/deflate | **salza2** via `http-encoding-chipz` | Wave-1 (request `Content-Encoding`) |
| Content decode/encode **br** | [`http-encoding-brotli`](https://github.com/egao1980/http-encoding-brotli) → [`cl-stack-brotli`](https://github.com/egao1980/cl-stack-brotli) | CFFI + `libbrotli` OCI overlay |
| Content decode/encode **zstd** | [`http-encoding-zstd`](https://github.com/egao1980/http-encoding-zstd) → [`cl-stack-zstd`](https://github.com/egao1980/cl-stack-zstd) | CFFI + `libzstd` OCI overlay |
| Content decode/encode **snappy** | [`http-encoding-snappy`](https://github.com/egao1980/http-encoding-snappy) → [`cl-stack-snappy`](https://github.com/egao1980/cl-stack-snappy) **1.2.2** | CFFI + `libsnappy`; **raw** block (not framed) |
| MIME type guess | **trivial-mimes** | Via dexador (filename → type) |
| MIME parse/print + CTE | **[`egao1980/cl-mime`](https://github.com/egao1980/cl-mime)** | Fork of 40ants/cl-mime (hanshuebner lineage, LGPL+Lisp exception). `mime:decode-content` / `encode-content` = **Content-Transfer-Encoding** (7bit/8bit/base64/qp) — **not** HTTP Content-Encoding. qlot: `github egao1980/cl-mime`. |
| Multipart / chunked | **cl-mime** + **chunga** (+ dexador body) | Prefer cl-mime for structured MIME; chunga for chunked framing |
| Charset | **babel** | Via dexador |
| Cookies | **cl-cookie** | Via dexador |
| HTTP parse | **fast-http** | Via dexador |
| TLS | **cl+ssl** + `cl-stack-ssl` | #12 |

Do **not** add a parallel IDNA dep on `antifuchs/idna` in stack systems.

---

## Normative RFCs (client must respect)

| RFC | Role |
|-----|------|
| **[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html)** | HTTP **semantics**: methods (§9), status (§15), content negotiation (§12), conditionals (§13), ranges (§14), auth framework hooks |
| **[RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html)** | HTTP **caching** (Cache-Control, validators) — client cache = optional P2; still honor/emit cache headers |
| **[RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html)** | HTTP/1.1 **messaging** (wire) |
| **[RFC 9113](https://www.rfc-editor.org/rfc/rfc9113.html)** | HTTP/2 |
| **[RFC 9114](https://www.rfc-editor.org/rfc/rfc9114.html)** | HTTP/3 (P2) |
| **[RFC 5789](https://www.rfc-editor.org/rfc/rfc5789.html)** | **PATCH** |
| **[RFC 3986](https://www.rfc-editor.org/rfc/rfc3986.html)** | URI |
| **[RFC 5890](https://www.rfc-editor.org/rfc/rfc5890.html)**–**[5894](https://www.rfc-editor.org/rfc/rfc5894.html)** / [UTS #46](https://unicode.org/reports/tr46/) | IDNA2008 — implemented by `cl-idna` |
| **[RFC 6265](https://www.rfc-editor.org/rfc/rfc6265.html)** / 6265bis | Cookies |
| **[RFC 6266](https://www.rfc-editor.org/rfc/rfc6266.html)** | `Content-Disposition` (`filename` / `filename*`) |
| **[RFC 8187](https://www.rfc-editor.org/rfc/rfc8187.html)** | Header parameter charset encoding (`ext-value`; obsoletes RFC 5987) |
| **[RFC 7617](https://www.rfc-editor.org/rfc/rfc7617.html)** / **[RFC 7616](https://www.rfc-editor.org/rfc/rfc7616.html)** | Basic / Digest auth |
| **[RFC 6750](https://www.rfc-editor.org/rfc/rfc6750.html)** | Bearer tokens |
| **[RFC 2818](https://www.rfc-editor.org/rfc/rfc2818.html)** | HTTP over TLS |
| **[RFC 7301](https://www.rfc-editor.org/rfc/rfc7301.html)** | ALPN (HTTP/2(/3) negotiation) |
| **[RFC 1950](https://www.rfc-editor.org/rfc/rfc1950.html)** / **[1951](https://www.rfc-editor.org/rfc/rfc1951.html)** / **[1952](https://www.rfc-editor.org/rfc/rfc1952.html)** | zlib / deflate / gzip |
| **[RFC 7932](https://www.rfc-editor.org/rfc/rfc7932.html)** | **Brotli** (`br`) |
| **[RFC 8878](https://www.rfc-editor.org/rfc/rfc8878.html)** | **Zstandard** (`zstd`) content coding |
| **[RFC 7692](https://www.rfc-editor.org/rfc/rfc7692.html)** | (WS) permessage-deflate — owned by `ws-protocol` |
| **[RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.html)** | WebSocket — owned by `ws-protocol` |

Obsolete for new text: RFC 2616 / 7230–7235 (superseded by 911x). Cite 911x only.

---

## Method parity (RFC 9110 §9 + PATCH)

| Method | Safe | Idempotent | Body (typical) | Facade helpers | Wave-1 |
|--------|------|------------|----------------|----------------|--------|
| `GET` | ✓ | ✓ | no | `http:get` / `http:get-async` | **ship** |
| `HEAD` | ✓ | ✓ | no | `http:head` | **ship** |
| `POST` | | | yes | `http:post` | **ship** |
| `PUT` | | ✓ | yes | `http:put` | **ship** |
| `DELETE` | | ✓ | optional | `http:delete` | **ship** |
| `CONNECT` | | | tunnel | `http:connect` / raw | **ship** (proxy tunnels; restricted like Java) |
| `OPTIONS` | ✓ | ✓ | optional | `http:options` | **ship** |
| `TRACE` | ✓ | ✓ | no | `http:trace` | **ship** (may be disabled by default / policy) |
| `PATCH` | | | yes | `http:patch` | **ship** |
| extension / WebDAV / … | per IANA | | | `http:request` / `http:request-async` with `:method` | escape hatch (Beast lists many; not first-class helpers) |

**Java:** first-class `GET`/`POST`/`PUT`/`DELETE`/`HEAD` + generic `method(name, bodyPublisher)`.  
**Boost.Beast:** `http::verb` enum covers all RFC methods + PATCH + WebDAV/CalDAV/etc.; message model is HTTP/1-oriented; **not** a turnkey client (no redirect/cookie/cache stack — Beast FAQ).  
**dexador today:** helpers for get/post/…; `request` takes `:method` (`:GET` `:HEAD` `:OPTIONS` `:PUT` `:POST` `:DELETE` documented — protocol facade must still expose PATCH/CONNECT/TRACE/OPTIONS uniformly).  
**httpx:** `request(method, …)` + helpers for get/options/head/post/put/patch/delete.

---

## Feature parity matrix

Legend: **Y** = first-class · **P** = partial / via headers · **N** = absent · **sep** = separate protocol in cl-stack

| Feature | RFC / note | Java HttpClient | Boost.Beast | httpx | dexador | cl-stack `http-protocol` |
|---------|------------|-----------------|-------------|-------|---------|--------------------------|
| Sync send | — | Y | Y (sync read/write) | Y | Y | **Y** (`send`) |
| Async send | — | Y (`CompletableFuture`) | Y (Asio) | Y | N | **Y** (promises on event-protocol) |
| All RFC methods + PATCH | 9110, 5789 | Y (+ generic) | Y (enum) | Y | P | **Y** |
| Request/response values | 9110 msg model | Y | Y (message) | Y | P (multi-value return) | **Y** (`http-request` / `http-response`) |
| Streaming request body | 9110 content | Y (`BodyPublisher`) | Y (serializer) | Y | P | **Y** — buffered Gray stream / chunked (`*http-stream-buffer-size*`, default 64KiB); `#71` |
| Streaming response body | 9110 | Y (`BodyHandler`/`Subscriber`) | Y (parser) | Y | Y (`want-stream`) | **Y** sync + async H1 **and H2** (`:want-stream` / `http:stream` / `http:stream-async` + CE Gray wrap); async H2 DATA → Gray stream + `response-trailers` (`http-protocol` **0.3.5** / `http-backend-async` **0.2.6**) |
| Multipart upload | 2046 / form | P (manual) | N (app) | Y | Y (pathname alist) | **Y** — `:data`+`:files` as `http-file`/streams; pull Gray multipart (`#73`); **no pathnames in protocol** |
| File upload/download value | — | P | N | Y | P | **Y** — CLOS `http-file` (filename, content-type, length, content stream/octets); `response-as-http-file`; FS open/save → higher lib (pathlib+MIME) |
| JSON convenience | — | N | N | Y | N | **Y** (`:json` → content-type + encode pin) |
| Form urlencoded | — | P | N | Y | Y | **Y** |
| Cookies | 6265 | Y (`CookieHandler`) | N | Y | Y (cl-cookie) | **Y** |
| Basic / Digest / Bearer | 7617/7616/6750 | Y (Authenticator / headers) | N | Y | Y (basic/bearer) | **Y** basic/bearer (`:auth`); Digest in [`cl-stack-http`](https://github.com/egao1980/cl-stack-http); OAuth2/JWT sep packages |
| Redirects | 9110 §15.4 | Y (policy) | N | Y | Y (`max-redirects`) | **Y** (NEVER/ALWAYS/NORMAL policy like Java) |
| Timeouts | — | Y (connect + request) | examples | Y (strict) | Y (connect/read) | **Y** (connect / read / total; cancel token async) |
| Proxy HTTP(S) | — | Y | N | Y | Y (env; Win gaps) | **Y**; SOCKS **P2** unless dexador already covers |
| TLS verify / client cert | 2818 | Y | via Asio SSL | Y | Y | **Y** via cl-stack-ssl |
| HTTP/2 | 9113 | Y | N (msg model ready) | Y (opt) | N | **Y** prefer/negotiate — see [HTTP version split](#http-version-clos-split) |
| HTTP/3 | 9114 | Y (SE 26) | N | N | N | **P2** |
| Expect: 100-continue | 9110 | Y | app | P | N | **P2** |
| Range requests | 9110 §14 | P (headers) | app | P | P | **Y** helpers (`:range`) |
| Conditional reqs | 9110 §13 | P (headers) | app | P | P | **P** via raw headers wave-1; named helpers **P2** |
| Content negotiation | 9110 §12 | P (headers) | app | P | P | **Y** helpers (`:accept` / `:accept-encoding` / `:accept-language`) |
| Auto decompress | Content-Encoding | Y | N | Y | Y (gzip/deflate) | **Y** (gzip/deflate/**br**/**zstd**/**snappy**) |
| Request compress | Content-Encoding | P | N | P | N | **Y** (opt-in `:content-encoding`) |
| Connection pool / keep-alive | 9112 | Y | app | Y | Y | **Y** (client object) |
| Trailers | 9110 §6.5 | P | Y | P | N | **Y** `response-trailers` (H2 END_STREAM; `http-protocol` **0.3.5**) |
| Push promise (H2) | 9113 | Y (`PushPromiseHandler`) | N | N | N | **P2** |
| Client-side cache | 9111 | N | N | N | N | **P2** |
| WebSocket | 6455 | Y (on HttpClient) | Y | N (other libs) | N | **sep** → `ws-protocol` |
| CONNECT tunnel | 9110 §9.3.6 | restricted | app | P | P | **Y** (proxy path) |

---

## HTTP version (CLOS split)

**RFCs:** [9112](https://www.rfc-editor.org/rfc/rfc9112.html) (HTTP/1.1 messaging) · [9113](https://www.rfc-editor.org/rfc/rfc9113.html) (HTTP/2) · [7301](https://www.rfc-editor.org/rfc/rfc7301.html) (ALPN) · [7541](https://www.rfc-editor.org/rfc/rfc7541.html) (HPACK — backend).

| Concern | Owns it | Symbols / notes |
|---------|---------|-----------------|
| Preference on client/request | **protocol** | `:http-version` → `:auto` \| `:http/1.1` \| `:http/2` |
| Capability query | **protocol** generic, **backend** methods | `backend-http-versions` / `backend-supports-http-version-p` |
| ALPN offer / map | **protocol** policy | `alpn-protocols-for-version` / `http-version-from-alpn` |
| Enforce preference | **protocol** | `ensure-http-version-available` / `http-version-not-available`; `send`/`send-async` `:before` |
| H2 header field rules §8.2–8.3 | **protocol** | `make-http2-request-headers`, `filter-headers-for-http-version` (no `Connection`/`Host`/…) |
| TLS ALPN + framing/HPACK/streams | **backend** | async: `http2` + event-protocol pump; winhttp: `WINHTTP_PROTOCOL_FLAG_HTTP2`; dexador: 1.1 only |
| Negotiated result | **backend** → response | `response-http-version` → `:http/1.1` \| `:http/2` |

```lisp
;; protocol — preference only
(make-http-client backend :http-version :auto)   ; prefer 2 when backend can
(make-http-request :url "https://…" :http-version :http/2)

;; backend reports what it can speak
(backend-http-versions async-backend)   ; → (:http/1.1 :http/2)
(backend-http-versions dexador-backend) ; → (:http/1.1)

;; after send
(response-http-version res)             ; negotiated keyword
```

**Out of protocol:** client preface bytes, SETTINGS, stream IDs, flow control, HPACK tables, push promise (P2), h2c prior-knowledge (P2).

---

## Content encoding (wave-1)

Modern clients advertise and decode **br** and **zstd**, not only gzip. Locked for wave-1 (was P2). **`snappy`** (raw block, not framed) is a later first-party coding via `http-encoding-snappy` + `cl-stack-snappy` **1.2.2**.

### Codings

| Token | Spec | Backend package | Natives |
|-------|------|-----------------|---------|
| `identity` | RFC 9110 | in `http-protocol` | — |
| `gzip` | RFC 1952 | [`http-encoding-chipz`](https://github.com/egao1980/http-encoding-chipz) | pure Lisp (chipz/salza2) |
| `deflate` | RFC 1950/1951 | `http-encoding-chipz` | pure Lisp |
| `br` | RFC 7932 | [`http-encoding-brotli`](https://github.com/egao1980/http-encoding-brotli) | [`cl-stack-brotli`](https://github.com/egao1980/cl-stack-brotli) OCI |
| `zstd` | RFC 8878 | [`http-encoding-zstd`](https://github.com/egao1980/http-encoding-zstd) | [`cl-stack-zstd`](https://github.com/egao1980/cl-stack-zstd) OCI |
| `snappy` | raw Snappy (not framed; no HTTP RFC) | [`http-encoding-snappy`](https://github.com/egao1980/http-encoding-snappy) | [`cl-stack-snappy`](https://github.com/egao1980/cl-stack-snappy) **1.2.2** |

Skip obsolete `compress` (LZW). Dictionary transport (`dcb` / `dcz`, RFC 9842) = **P2**.

**Layout (same as event-protocol):** `http-protocol` holds generics + parse + soft-load probe (`*content-coding-systems*`) + shared `http-protocol/conformance`. Encoding backends are **separate repos** that specialize `decode-content-coding` / `encode-content-coding` (octets **and** Gray streams). No plugin registry — load the ASDF system; methods appear. Natives stay in `cl-stack-brotli` / `cl-stack-zstd` / `cl-stack-snappy` (overlays do not depend on `http-protocol`).

### Client policy

1. Default `Accept-Encoding: gzip, deflate, br, zstd` (order = preference; q-values optional). `snappy` is advertised only when `http-encoding-snappy` is loaded.
2. **Auto-decode** response body when `Content-Encoding` is present (httpx/dexador shape). Opt out: `:decompress nil`.
3. Request body compression is **opt-in**: `:content-encoding :gzip` / `:br` / `:zstd` / `:deflate` / `:snappy` (sets header + encodes publisher).
4. Multiple codings in one header (applied left-to-right on wire) — decode in **reverse** order.
5. Unknown coding → `http-protocol-error` (or `unsupported-operation`) unless `:decompress nil`.
6. Missing encoding backend / native overlay for `br`/`zstd`/`snappy`: omit that token from default `Accept-Encoding` **or** signal at client construction (prefer omit + warn once; never advertise what we cannot decode).

### Protocol / facade bits

**Name clash:** `cl-mime` already exports `decode-content` / `encode-content` for CTE.
HTTP Content-Encoding uses distinct names:

```lisp
(defgeneric decode-content-coding (coding input &key)) ; octets/stream → octets/stream
(defgeneric encode-content-coding (coding input &key level quality))
(defun content-coding-supported-p (coding) …)   ; soft-loads http-encoding-* systems
(defun default-accept-encoding () …)
;; cl-mime (package mime): decode-content / encode-content remain CTE only
```

Facade:

```lisp
(http:get url)                              ; Accept-Encoding + auto-decode
(http:get url :decompress nil)              ; raw compressed body
(http:post url :json data :content-encoding :zstd)
```

### Overlay plan

Same policy as OpenSSL ([overlays.md](../overlays.md)): grovel at build time if needed; ship `native-library` per os/arch; Windows primary.

| Package | Native | Matrix |
|---------|--------|--------|
| `cl-stack-brotli` | `libbrotli` (dec+enc) | linux/amd64+arm64, darwin/arm64, **windows/amd64** |
| `cl-stack-zstd` | `libzstd` | same |
| `cl-stack-snappy` | `libsnappy` (raw) | linux/amd64+arm64, darwin/arm64, windows/amd64 |

Thin CFFI in overlay repos; `http-encoding-*` only specializes HTTP generics. Consumers must not need a C toolchain.

### Dexador gap

Stock dexador auto-decodes gzip/deflate via chipz only. Wave-1 facade wraps the body pipeline so `br`/`zstd`/`snappy` work for **both** sync (dexador) and async backends — either post-process the octet body or inject a decompressing gray stream before charset decode.

---

## Protocol surface

Tiny ASDF system `http-protocol`: generics, conditions, value types. Sync backend `http-backend-dexador` (name TBD). Async backend(s) implement the same generics on an event loop.

### Types

| Type | Role |
|------|------|
| `http-client` | Pooling client; holds defaults (base-url, headers, auth, cookie-jar, timeout, version, redirect policy, TLS) |
| `http-request` | Method, URI, headers, body publisher, per-request overrides |
| `http-response` | Status, headers, body (or stream), HTTP version, URL after redirects, trailers (optional) |
| `http-backend` | Class; specialize `send` / `send-async` |
| `body-publisher` | Produces request octets (bytes / string / stream / file / multipart) |
| `body-handler` | Consumes response (string / octets / stream / file / sink fn) |

### Dynamics

| Symbol | Role |
|--------|------|
| `*http-backend*` | Current backend |
| `*http-client*` | Optional default client for facade one-shots |

### Generics (minimum)

```lisp
(defgeneric backend-name (backend))   ; "dexador" | "async-libuv" | …

(defgeneric make-http-client (backend &key
                              base-url headers cookie-jar auth
                              timeout redirect-policy http-version
                              proxy verify ca-path client-cert
                              max-connections))

(defgeneric send (backend client request &key body-handler))
;; → http-response   (blocking)

(defgeneric send-async (backend client request &key body-handler))
;; → promise of http-response   (facade); protocol may take callback+cancel

(defgeneric cancel-request (backend handle))   ; async in-flight
```

### Request construction

```lisp
(make-http-request
  :method :get            ; or "PATCH" / :patch — case-insensitive tokenize
  :url "https://example.com/x"
  :params '(("q" . "1"))  ; query merge
  :headers '(("x-foo" . "bar"))
  :content …              ; octets / string / binary stream / http-file
  :json <lisp-data>       ; encode via pinned JSON lib; sets Content-Type
  :data <alist>           ; form fields (with :files → multipart; alone may urlencode later)
  :files <alist|list>     ; multipart; value = http-file | stream | octets | plist
                          ; or list of http-file (field-name from slot)
  :want-stream t          ; response body as buffered binary input stream
  :auth '(:basic "u" "p") ; or :bearer (Digest / OAuth2 → cl-stack-http / cl-stack-oauth2)
  :cookies …
  :timeout 5.0            ; or (:connect 2 :read 5 :total 10)
  :follow-redirects :normal  ; :never | :always | :normal (Java-like)
  :http-version :http/2   ; preference; actual on response
  ;; :expect-continue — P2
  :range '(0 1023)        ; → Range: bytes=0-1023
  :if-none-match "\"abc\""
  :accept "application/json"
  :accept-encoding '(:gzip :deflate)
  :proxy "http://proxy:8080"
  :verify t)
```

### Facade sketch (all methods)

Package `http` (later `cl-stack/http`):

```lisp
(http:request method url &key …)         ; sync
(http:request-async method url &key …)   ; → promise

(http:get url &key …)
(http:head url &key …)
(http:options url &key …)
(http:trace url &key …)                  ; thin method helper (servers often 405/501)
(http:post url &key …)
(http:put url &key …)
(http:patch url &key …)
(http:delete url &key …)
(http:connect url &key …)                ; tunnel; expert

(http:stream method url &key …)         ; forces :want-stream t (sync)
(http:stream-async method url &key …)   ; async H1 → socket-fed Gray stream (promise)
(http:body-stream response)             ; binary input stream over body
(http:make-http-file content &key filename content-type content-length field-name)
(http:response-as-http-file response &key filename content-type)
;; FS open/save of http-file → higher lib (cl-stack-pathlib + MIME), not protocol
;; *http-stream-buffer-size* — default 65536; peak body memory ≈ buffer, not body

(http:with-client (client &key …) …)
```

Async variants: either `*-async` siblings (httpx) **or** same names under an async client — pick **`*-async` + promises** to match event brief.

```lisp
(bb:attach (http:get-async "https://example.com" :accept "application/json")
  (lambda (res)
    (print (http-protocol:response-status res))))
```

### Response accessors

`response-status`, `response-headers`, `response-header`, `response-url`, `response-http-version`, `response-body` / `body-stream`, `response-cookies`, `response-history`. Facade (`stack-http`) adds `response-text` / `response-json`.

### Conditions

| Condition | When |
|-----------|------|
| `http-error` | Base |
| `http-connection-error` | DNS / TCP / TLS handshake |
| `http-timeout-error` | connect / read / total |
| `http-tls-error` | verify / protocol alert |
| `http-protocol-error` | malformed response / unexpected framing |
| `http-redirect-error` | exceeded `max-redirects` / disallowed scheme |
| `http-client-error` | 4xx (optional raise policy) |
| `http-server-error` | 5xx (optional raise policy) |
| `http-canceled` | async cancel |
| `unsupported-operation` | backend missing verb/feature (e.g. HTTP/3) |

Restarts: `retry`, `use-value` (synthetic response), `continue-without-verify` (TLS — **debug only**), `redirect-manually`.

Default: **do not** signal on 4xx/5xx (httpx/requests style — inspect `status`); opt-in `:raise-for-status t` or `(http:raise-for-status res)`.

---

## Backend plan

| Layer | Repo (planned) | Notes |
|-------|----------------|-------|
| Protocol | `egao1980/http-protocol` | generics + shared conformance |
| Sync | [`http-backend-dexador`](https://github.com/egao1980/http-backend-dexador) | wave-1 `#30` |
| Async | [`http-backend-async`](https://github.com/egao1980/http-backend-async) on `event-protocol` × libuv + libev | `#31` **done** (NB connect + async TLS WANT_*; cookies/redirects) |
| ABCL / JVM | [`http-backend-java`](https://github.com/egao1980/http-backend-java) (`java.net.http` + WebSocket) + [`event-backend-nio`](https://github.com/egao1980/event-backend-nio) | wave-1 scaffold; HTTP/2 via HttpClient |
| TLS natives | `egao1980/cl-stack-ssl` | async: socket-BIO + WANT_READ/WANT_WRITE on `register-io` (not run-to-completion) |

Selection DX: ASDF + `*http-backend*` (same as event — no plugin registry).

---

## Conformance / corpus (#32)

Shared Rove suite ideas (license-clean):

- Method matrix smoke against httpbin-like fixture (synthetic MIT)
- Redirect policies, timeouts, cancel
- Multipart + JSON round-trip
- Range 206 / conditional 304
- TLS verify fail / success with overlay
- Async × both event backends

Provenance file required (same pattern as `event-protocol` conformance).

---

## Implementation order

1. `#29` — this brief + condition taxonomy — **Done when merged**
2. `#45` / `#46` — `cl-stack-brotli` + `cl-stack-zstd` overlays (can parallel `#30`)
3. `#47` + `#30` — encoding pipeline in facade + sync dexador backend + all method helpers
4. `#31` — async `send-async` on event-protocol; green on libuv **and** libev — **done** (cleartext + HTTPS; requests-shaped CE live tests; PR [#6](https://github.com/egao1980/http-backend-async/pull/6) merged)
5. Cookie jar / sessions (`cl-cookie`) on `http-client` + both backends — **done** (protocol + sync/async wire-up)
6. `#23`/`#26` — hub `tests/corpus/` layout + first MIT HTTP slice + `cl-stack/corpus-smoke` — **done**
7. `#32` — OCI consumer (`cl-stack/oci-corpus`) — **done**
8. `#54` — facade `:auth` / `:range` / `trace`+`connect` — **done** (stream/expect/Digest → P2)

---

## Out of scope (wave-1)

- HTTP **server** (Clack/Woo — separate)
- WebSocket (`ws-protocol`)
- Full RFC 9111 client cache
- HTTP/3 / QUIC
- H2 server push consumption
- WebDAV first-class helpers (use `http:request`)
- Browser cookie jar edge cases (ITP etc.)
- ASGI/WSGI in-process transport (httpx novelty — skip)
- Compression dictionary transport (`dcb`/`dcz`, RFC 9842)
- Obsolete `Content-Encoding: compress` (LZW)

---

## Sources

- RFC 9110–9114, 5789, 6265, 6750, 7616/7617, 2818, 7301  
- [Java SE `java.net.http`](https://docs.oracle.com/en/java/javase/26/docs/api/java.net.http/java/net/http/package-summary.html) (`HttpClient`, `HttpRequest.Builder`, BodyPublisher/Handler)  
- [Boost.Beast HTTP](https://www.boost.org/doc/libs/latest/libs/beast/doc/html/beast/using_http.html) + [`http::verb`](https://www.boost.org/doc/libs/latest/libs/beast/doc/html/beast/ref/boost__beast__http__verb.html) + [FAQ](https://www.boost.org/doc/libs/develop/libs/beast/doc/html/beast/design_choices/faq.html) (not a full client)  
- [HTTPX](https://www.python-httpx.org/)  
- [dexador](https://github.com/fukamachi/dexador)

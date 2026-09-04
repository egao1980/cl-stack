# Cookbook: HTTP client (requests / httpx → cl-stack)

**Audience:** people who know [Requests](https://requests.readthedocs.io/en/latest/user/quickstart/) or [HTTPX](https://www.python-httpx.org/quickstart/) and want the same recipes on the Lisp stack.

**Packages:**

| Layer | Python | Lisp |
|-------|--------|------|
| Wire / transport | urllib3 / httpcore | [`http-protocol`](https://github.com/egao1980/http-protocol) + backends |
| DX facade | requests / httpx | [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) (`stack-http`) |
| Canary / demos | — | [`http-parity`](https://github.com/egao1980/http-parity) |

Capability brief (decisions, RFCs): [http-protocol.md](../capabilities/http-protocol.md).

Pins below use current OCI tags; bump with hub releases.

```lisp
(cl-repo:load-system "cl-stack-http" :version "0.1.8")
;; soft CE codecs (optional):
;;   http-encoding-chipz / http-encoding-brotli / http-encoding-zstd / http-encoding-snappy
;; OAuth2 / JWT (optional):
;;   (cl-repo:load-system "cl-stack-oauth2" :version "0.1.0")
;;   (cl-repo:load-system "cl-stack-jwt" :version "0.2.0")
```

Nickname: `#:stack-http` or local nickname `#:http` → `cl-stack-http` (as in http-parity).

---

## Quickstart map

| requests / httpx | cl-stack-http | Status |
|------------------|---------------|--------|
| `requests.get(url)` | `(http:get url)` | have |
| `params=` | `:params '(("k" . "v")…)` | have; multi-value lists + NIL drop (**http-protocol 0.2.2+**) |
| `r.text` / `r.content` / `r.json()` | `response-text` / `response-content` / `response-json` | have |
| `r.encoding` | `detect-encoding` / `response-text :encoding` | have (no mutable setter on response) |
| `headers=` | `:headers '(("User-Agent" . "…")…)` | have |
| `data=` form | `:form-data` alist | have (not bare `:data` for urlencoded — `:data` is typed body) |
| `json=` | `:json` alist/hash-table | have |
| `content=` bytes | `:content` octets/string/stream/`http-file` | have |
| `files=` | `:files` + `path-http-file` / httpx tuples | have |
| `r.status_code` / `r.ok` | `response-status` / `response-ok-p` | have |
| `r.raise_for_status()` | `raise-for-status` or `:raise-for-status t` | have |
| `r.headers['Content-Type']` | `(response-header r "content-type")` | have |
| `r.cookies` / `cookies=` | `response-cookies` / `:cookies` / session jar | have |
| `r.url` / `r.history` | `response-url` / `response-history` | have |
| `Session` / `httpx.Client` | `with-session` / `make-session` | have (`:base-url`, `:headers`, `:params`, pool) |
| `stream=True` / `httpx.stream` | `:want-stream t` / `with-stream` / `iter-bytes` / `iter-lines` | have |
| `auth=(user, pass)` | `:auth '(:basic "u" "p")` or `:bearer` | have |
| `HTTPDigestAuth` | `:auth (digest-auth u p)` | have (sync retry) |
| `timeout=` | `:timeout 5.0` or `make-http-timeout` | have |
| `proxies=` / `trust_env` | `:proxy` / `:trust-env t` | have |
| download to path | `download` / `download-many` (CD filename + MIME ext; streamed) | have |
| upload path | `upload` / `:files` | have |
| `AsyncClient` | `*-async` + blackbird; prefer `:async` backend | have |
| `http2=True` | `:http-version :http/2` / `:auto` on client+request | **have** (http-protocol **0.3.1+** + async/winhttp backends; see [QUICKSTART](../QUICKSTART.md#http2-preference-http-protocol-031)) |
| `hooks=` / `event_hooks=` | `prepare-request` / `handle-response` + `:client-class` | **have** (cl-stack-http **0.1.5+**; see [§12](#12-hooks-via-clos-around)) |
| `r.elapsed` / `num_bytes_downloaded` | `response-elapsed` / `response-bytes-downloaded` | **have** (cl-stack-http **0.1.6+** / http-protocol **0.2.3+**; see [§13](#13-timing--byte-stats)) |
| `PreparedRequest` / `build_request` mutability | build `http-request` + `send` | partial (CLOS, no httpx merge DSL) |
| OAuth2 / JWT | [`cl-stack-oauth2`](https://github.com/egao1980/cl-stack-oauth2) / [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt) | **sep** packages **0.1.0** / **0.2.0** (see [§8](#8-auth)) |

---

## 1. Verbs

```lisp
(http:get "https://httpbingo.org/get")
(http:post "https://httpbingo.org/post" :form-data '(("key" . "value")))
(http:put "https://httpbingo.org/put" :json '(("a" . 1)))
(http:patch "…" :json …)
(http:delete "…")
(http:head "…")
(http:options "…")
```

Prefer **session** for anything beyond one-shots (pooling + cookies + `base-url`):

```lisp
(http:with-backend (:async)          ; or :dexador / :winhttp / :auto
  (http:with-session (s :base-url "https://httpbingo.org/"
                        :trust-env nil
                        :timeout 15.0)
    (http:session-get s "get")
    (http:session-post s "post" :json '(("k" . "v")))))
```

---

## 2. Query params (incl. multi-value)

```python
# requests / httpx
params = {"key1": "value1", "key2": ["value2", "value3"]}
r = httpx.get(url, params=params)
```

```lisp
(let* ((params '(("key1" . "value1")
                 ("key2" . ("value2" "value3"))
                 ("skip" . nil)))           ; NIL omitted
       (r (http:get "https://httpbingo.org/get" :params params)))
  (response-url r))
;; → …?key1=value1&key2=value2&key2=value3
```

Session defaults merge via `:params` on `make-session` / `:default-params` on requests.

---

## 3. Response body

```lisp
(let ((r (http:get url)))
  (response-status r)                 ; 200
  (response-ok-p r)                   ; T for 2xx
  (response-text r)                   ; charset from Content-Type / override
  (response-text r :encoding :utf-8)
  (response-content r)                ; octets or string (decoded CE)
  (response-json r)                   ; yason hash-table / list
  (response-header r "content-type")
  (raise-for-status r))               ; signals on 4xx/5xx
```

Or fail fast:

```lisp
(http:get url :raise-for-status t)
```

**CE:** gzip/deflate via `http-encoding-chipz`; br/zstd/snappy when those systems are loaded (`http-encoding-snappy` = raw Snappy, not framed). After decode, `Content-Encoding` is stripped (httpx-shaped).

---

## 4. JSON in / out

```lisp
(http:post url :json '(("integer" . 123)
                       ("list" . ("a" "b" "c"))))
(http:response-json *)
;; helper that returns (values json response):
(http:json url)   ; GET + decode
```

S-exp serdes (stack extra): `:data … :data-type :sexp`.

---

## 5. Forms + multipart files

```lisp
;; urlencoded (HTML form)
(http:post url :form-data '(("key1" . "value1")
                            ("key2" . ("a" "b"))))

;; multipart — pathlib or httpx tuple
(http:post url
  :form-data '(("message" . "hi"))
  :files `(("upload-file" . ,(http:path-http-file #p"report.xls"))))

;; httpx tuple: (filename content [content-type])
(http:post url :files '(("f" . ("note.txt" "hello" "text/plain"))))
```

Raw body: `:content #(…)` or string (set `Content-Type` yourself if needed).

---

## 6. Download / upload (pathlib)

```lisp
;; file path — overwrite policy explicit
(http:download url #p"/tmp/out.bin" :overwrite t)

;; directory → Content-Disposition filename, else URL basename;
;; missing extension filled from Content-Type (e.g. application/json → .json)
(http:download url #p"/tmp/dl/" :filename :content-disposition :overwrite t)

(http:upload #p"/tmp/out.bin" url :as :files)   ; or :as :content

;; sequential multi-download (wave-1)
(http:download-many
 `(("https://example.com/a.bin" . ,#p"/tmp/a.bin")
   ("https://example.com/b.bin" . ,#p"/tmp/b.bin"))
 :overwrite t)
```

Live CE + CD exercise: `http-parity` `ros -l scripts/finance-demo.lisp`.

---

## 7. Streaming

```lisp
(http:with-stream (r :get url :timeout 30.0)
  (http:map-response-bytes r (lambda (chunk) …))
  ;; or
  (http:map-response-lines r #'print)
  (response-bytes-downloaded r))   ; octets observed while mapping
```

Async: `stream-async` / `session-stream-async` → promise of response with body stream.

---

## 8. Auth

```lisp
(http:get url :auth '(:basic "user" "pass"))
(http:get url :auth '(:bearer "token"))
(http:get url :auth (http:digest-auth "user" "pass"))  ; 401 challenge retry (sync)

;; netrc when :trust-env t (default on session)
(http:get url :trust-env t)
```

OAuth2 / JWT are **separate packages** (Python: `requests-oauthlib` / PyJWT).
They plug into stack-http via CLOS `prepare-auth` / `handle-auth-response`.

```lisp
(cl-repo:load-system "cl-stack-oauth2" :version "0.1.0")

(defvar *oauth*
  (stack-oauth2:make-oauth2-auth
   :token-url "https://as.example/oauth/token"
   :client-id "cid" :client-secret "sec"
   :scope '("api.read" "api.write")
   :grant :client-credentials))

(http:get "https://api.example/v1/me" :auth *oauth*)
;; auto-fetches token, refreshes on expiry / 401

;; Auth code + PKCE
(stack-oauth2:oauth2-authorization-uri *oauth* :pkce t)
(stack-oauth2:oauth2-exchange-code! *oauth* :code "…")
```

```lisp
(cl-repo:load-system "cl-stack-jwt" :version "0.2.0")
(stack-jwt:encode :hs256 key '(("sub" . "u") ("exp" . 9999999999)))
(stack-jwt:decode :hs256 key token)
(stack-jwt:inspect-token token)   ; unverified
(stack-jwt:expired-p token :leeway 60)
```

| Package | OCI | Role |
|---------|-----|------|
| [`cl-stack-oauth2`](https://github.com/egao1980/cl-stack-oauth2) | `0.1.0` | scopes, grants, PKCE, 401 refresh |
| [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt) | `0.2.0` | encode/decode/inspect (HS* via crypto-protocol:hmac) |

---

## 9. Redirects, cookies, timeouts, proxy

```lisp
(http:get "http://github.com/" :allow-redirects t)
(response-history *)          ; prior hops
(response-url *)              ; final URL

(http:get url :cookies '(("peanut" . "butter")))
(response-cookies *)

(http:get url :timeout 0.5)
(http:get url :timeout (make-http-timeout :connect 2.0 :read 10.0))

(http:get url :proxy (make-http-proxy-config :http "http://127.0.0.1:8080"))
(http:get url :trust-env nil)   ; ignore env proxy / netrc
```

---

## 10. Async (httpx AsyncClient shape)

```lisp
(http:with-backend (:async)
  (let ((p (http:get-async url :timeout 20.0)))
    ;; blackbird promise → response; sync SEND also awaits on async backend
    …))
```

Event engine: `event-backend-libuv` (default) or libev. Direction changes use `update-io` (no `uv_poll_init` EEXIST).

---

## 11. Errors

```lisp
(handler-case
    (progn
      (http:get url :timeout 5.0)
      (raise-for-status *))
  (http-timeout-error (e) …)
  (http-connection-error (e) …)
  (http-status-error (e) …)      ; from raise-for-status
  (http-error (e) …))            ; umbrella
```

Exact condition names: `http-protocol` package (`http-error`, `http-status-error`, …).

---

## 12. Hooks via CLOS (`prepare-request` / `handle-response`)

requests `hooks=` / httpx `event_hooks=` are callback lists. Stack equivalent (**cl-stack-http 0.1.5+**): specialize **generic functions on a client mixin**. Loading stack-http installs `send` / `send-async` `:around` that always call:

1. `prepare-request` — before protocol `:before` (base-url + params finalize)
2. backend send
3. `handle-response` — after a successful response (not transport errors)

Auth stays on `prepare-auth` / `handle-auth-response`.

### Pattern

```lisp
(defclass logging-client (http-client) ())

(defmethod http:prepare-request ((client logging-client) request)
  ;; mutate / replace request (headers, params, …)
  request)

(defmethod http:handle-response ((client logging-client) request response)
  (format *trace-output* "~&~A ~A → ~A~%"
          (http-request-method request)
          (or (response-url response) (http-request-url request))
          (response-status response))
  response)

(http:with-session (s :preferred :async
                      :client-class 'logging-client
                      :base-url "https://httpbingo.org/"
                      :trust-env nil
                      :timeout 15.0)
  (http:session-get s "get"))
```

Extra `:around` methods on `send` for your mixin still compose via `call-next-method` if you need onion middleware beyond the two hooks.

### Rules of thumb

| Do | Don't |
|----|-------|
| Specialize on **client** mixins + `:client-class` | Dynamic `add-method` as public API |
| Keep auth on `prepare-auth` / `handle-auth-response` | Stuff 401 challenge/retry into `handle-response` |
| One concern per mixin (`logging-client`, `metrics-client`, …) | Recreate Python `hooks=[fn, …]` unless you need a thin adapter |

---

## 13. Timing / byte stats

`http-response` carries:

| Field | Accessor | Meaning |
|-------|----------|---------|
| `elapsed` | `response-elapsed` | Wall seconds for the transfer (`requests` `r.elapsed`) |
| `bytes-downloaded` | `response-bytes-downloaded` | Decoded body octets (`httpx` `num_bytes_downloaded`) |

Filled by cl-stack-http `send` / `send-async` hooks after `handle-response`:

- **Eager bodies** — `bytes-downloaded` = body size immediately; `elapsed` always set.
- **Streams** — `bytes-downloaded` starts at `0`; `map-response-bytes` / `iter-bytes` recounts as chunks are read (resets then accumulates — safe if annotate already set an eager size).

```lisp
(let ((r (http:get url)))
  (format t "~,3f s, ~a bytes~%"
          (response-elapsed r)
          (response-bytes-downloaded r)))

(http:with-stream (r :get big-url)
  (http:map-response-bytes r (lambda (chunk)
                               (format t "~a / ~a~%"
                                       (length chunk)
                                       (response-bytes-downloaded r)))))
```

No progress-bar / callback API yet — poll `response-bytes-downloaded` inside your mapper (or specialize `handle-response` for metrics).

---

## Recipe: small JSON API client

```lisp
(defun fetch-rates (&key (base "USD") (symbols "EUR,GBP"))
  (http:with-backend (:async)
    (http:with-session (s :base-url "https://api.frankfurter.dev/v1/"
                          :trust-env nil :timeout 25.0)
      (let ((r (http:session-get s "latest"
                                 :params `(("base" . ,base)
                                           ("symbols" . ,symbols))
                                 :raise-for-status t)))
        (http:response-json r)))))
```

---

## Gaps worth closing next

Prioritized from quickstart/cookbooks vs current stack:

| Priority | Gap | Notes |
|----------|-----|-------|
| P0 | ~~Multi-value `params` / `form-data`~~ | **Done** in http-protocol **0.2.2** |
| P1 | Cookbook / parity cases for multi-value + `response-url` after params | add to http-parity |
| P1 | ~~Streaming download progress (`num_bytes_downloaded`)~~ | **Done** — `response-bytes-downloaded` + `map-response-bytes` (0.1.6); no UI progress bar |
| P2 | Mutable `response` encoding setter | low value — `:encoding` kwarg covers it |
| P2 | ~~`r.elapsed` / timing~~ | **Done** — `response-elapsed` (http-protocol **0.2.3** / stack-http **0.1.6**) |
| P2 | ~~First-class `prepare-request` / `handle-response` + `:client-class`~~ | **Done** in cl-stack-http **0.1.5** |
| P2 | ~~OAuth2 / JWT packages~~ | **Done** — [`cl-stack-oauth2`](https://github.com/egao1980/cl-stack-oauth2) / [`cl-stack-jwt`](https://github.com/egao1980/cl-stack-jwt) **0.1.0** |
| P3 | ~~HTTP/2~~ | **Done** — http-protocol **0.3.0** + async/winhttp backends (see QUICKSTART) |
| P3 | httpx `build_request` merge DSL | CLOS already flexible |

Track regressions in [`http-parity`](https://github.com/egao1980/http-parity) (`MATRIX.md`, fixture suite, finance CE demo).

---

## See also

- [cl-stack-http README](https://github.com/egao1980/cl-stack-http#readme)
- [cl-stack-oauth2](https://github.com/egao1980/cl-stack-oauth2) · [cl-stack-jwt](https://github.com/egao1980/cl-stack-jwt)
- [http-protocol capability brief](../capabilities/http-protocol.md)
- Requests: [Quickstart](https://requests.readthedocs.io/en/latest/user/quickstart/) · [Advanced](https://requests.readthedocs.io/en/latest/user/advanced/)
- HTTPX: [QuickStart](https://www.python-httpx.org/quickstart/) · [Clients](https://www.python-httpx.org/advanced/clients/)

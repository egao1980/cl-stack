# session-protocol (P2): anonymous server-side sessions for Clack apps

**Issues:** [#426](https://github.com/egao1980/cl-stack/issues/426) (this protocol) · [rpc-backend-htmx#19](https://github.com/egao1980/rpc-backend-htmx/issues/19) (first consumer, S1) · [#427](https://github.com/egao1980/cl-stack/issues/427) (middleware-protocol, which S0b binds to)
**Status:** S0 [`session-protocol`](https://github.com/egao1980/session-protocol) 0.1.0 **implemented and published**: [session-protocol#1](https://github.com/egao1980/session-protocol/pull/1) (merged; team-solve, 308 tests, 934 assertions, green on ubuntu, macOS and Windows). Follow-ups: [#2](https://github.com/egao1980/session-protocol/issues/2) (decisions through the logic family), [#3](https://github.com/egao1980/session-protocol/issues/3). S0b **implemented and published**: [session-protocol#4](https://github.com/egao1980/session-protocol/pull/4) (merged, 0.2.0; `session-protocol/middleware` 0.2.0, the `session-handler` mixin). S1 is planned.
**Repos:** `session-protocol` (nick `stack-session`)
**Builds on:** [cache-protocol](cache.md) 0.2.0 (the store), [secrets-protocol](secrets.md) 0.1.3 (ids, constant-time compare), [json-protocol](json-protocol.md) 0.2.4 (serialization), [http-server-protocol](http-server.md) (the Clack env and response are normative), cl-cookie 0.2.0 and quri 0.7.2 (cl-stack-systems imports); [middleware-protocol](middleware.md) 0.1.0 and `middleware-protocol/clack` 0.1.0 (#427, S0b only)

Web apps on http-server-protocol (Clack apps such as rpc-backend-htmx and canvas apps) have no per-visitor state. Multi-page flows (a wizard, recent items, per-visitor limits) need an **anonymous server-side session per browser**:
- one cookie with a random id;
- the data on the server, in a store;
- the lifetimes, rotation and ending a session needs.

The user's rule is to reuse the stack's protocols. Lack's session middleware is not used directly. Sessions get their own reusable protocol, as every other problem in the stack does.

session-protocol is **transport-neutral**. It is two functions over a Clack env and a Clack response:
- `begin-session` reads the cookie, then loads the session or starts one;
- `finish-session` commits the session and adds the Set-Cookie.

The middleware that calls them is a mixin on middleware-protocol (S0b). Login, CSRF tokens and framework glue are out of scope (see [Slices](#slices)).

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| **Lack** `lack-middleware-session` (Lack 0.3.0 import) | A store protocol (fetch / store / remove) separate from the cookie "state". A validator that runs on the cookie before any lookup. `keep-empty nil`: a new empty session stores nothing. Rotation (`:change-id`) and ending (`:expire`) as per-request decisions. | **Using it directly** (the user's rule; it is Lack-only middleware, and middleware is middleware-protocol's job). Its store write on every request. Its Set-Cookie only on new / change-id / expire with a fixed Expires, so the cookie never slides with the store entry. Its 40-hex SHA-1 id from `generate-random-id`. Its Redis store's `marshal` + `read-from-string`, which puts the Lisp reader on stored data. |
| **express-session** (Node) | `saveUninitialized: false` (lazy creation). Change detection by **comparing the session's JSON** with the loaded one, so nested in-place changes are saved. A store interface of get / set / destroy. `regenerate` / `destroy`. The first cookie of a name wins (the `cookie` parser). A warning that the memory store is process-local. | `resave`. A separate `touch` operation (we re-put on a refresh interval). Signed cookie values (`cookie-signature`): with a 256-bit random id, signing adds nothing. A `rolling` flag (our cookie always slides with the store). |
| **Rack::Session::Abstract::Persisted** (Ruby) | Lazy loading. `renew` (new id, old one dropped) and `drop`. `expire_after`. | Rack's cookie store (data inside the cookie) |
| **Starlette** `SessionMiddleware` (Python) | SameSite `lax` by default, Path `/`, Secure under `https_only` | Data in a signed cookie (a 4 KB limit, and a session cannot be revoked) |
| **Django** sessions | A JSON serializer, adopted when pickle was dropped for safety. `cycle_key` on login (our rotation). Save only when modified (`SESSION_SAVE_EVERY_REQUEST = False`). Cache and database backends. | A two-week default age (we default to one day idle) |
| **Flask** `session` | — | `session.modified = True` by hand after a nested change (we compare JSON) |
| **OWASP** Session Management Cheat Sheet | At least 64 bits of entropy (we use 256). A new id on a privilege change. Idle and absolute timeouts. HttpOnly, Secure, SameSite, a host-only cookie, `__Host-` prefix support. Ids never in URLs or logs. | — |
| **RFC 6265** (and 6265bis) | Attribute names are case-insensitive (§5.2). Max-Age takes precedence over Expires. SameSite. Cookie prefixes. The client orders cookies of one name, and the first one counts. | — |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | A protocol with two phases: `(begin-session manager env)` → session, env with `:session`; `(finish-session manager session env response)` → response. **No middleware in session-protocol** and no Lack middleware. The binding is S0b, a `session-handler` mixin on middleware-protocol. | One core that any transport binds (Clack, later rpc-protocol handlers). Middleware is middleware-protocol's problem (#427: CLOS method combination). |
| **Session model** | `session`: id, data (an EQUAL hash-table of **string keys** to JSON values), `created-at` and `last-seen` (Unix seconds, integers). Per-request flags: new, changed, rotated, ended, committed. Accessors: `session-value` (with a default; `setf` checks the value), `remove-session-value`, `clear-session`, `regenerate-session-id`, `end-session`. | Small, JSON-shaped, and it maps onto any store |
| **Value domain** | Strings, integers, finite floats, T / NIL, `:null`, proper lists and vectors (arrays), and hash-tables with string keys (objects), nested **at most 64 levels**. Anything else is `session-value-error`: symbols, characters, ratios, NaN, structures, dotted or circular lists, a table that contains itself. On load, arrays become **lists**, objects become EQUAL tables and floats become doubles. | JSON is the stored form, so values are JSON from the start. Lists suit `push` in Lisp code. The depth limit turns a cycle into an error instead of a hang. |
| **Serialization** | json-protocol's deterministic encoding (sorted keys, compact). The record is exactly `{"v":1,"id":…,"created":…,"seen":…,"data":{…}}`, and a later version may add members. **Never the Lisp reader**: `decode-session-record` refuses anything that is not a version 1 record (`session-store-error`). | The same bytes on every backend. Stored data is not code. The version allows migration. |
| **Change detection** | The commit writes a loaded session when an accessor changed it, or when `session-data-json` differs from the text taken at load: a value changed in place (a nested table, a pushed list) is saved as well. | express-session's hash comparison. Flask's manual `modified` flag is a known trap. |
| **Store protocol** | Generic functions `session-store-load store id` → session or NIL, `session-store-save store session ttl`, and `session-store-delete store id` → boolean. Each call is one atomic store operation. A failure is `session-store-error` (`:load`, `:save`, `:delete`, plus a cause). | Three operations cover every store: cache, SQL later |
| **Cache store** | `cache-session-store` over **any** cache-protocol cache (`in-memory-ttl-cache`, cache-backend-redis). The key is the prefix (default `"session:"`) followed by the id; the value is the record text; the TTL is put again on every save, which gives sliding expiry. A `cache-error` is wrapped from a `handler-bind`, so the cache's own restarts (Redis `reconnect`) stay available. | The same text on every cache backend, and no new connection code |
| **Ids** | `(token-urlsafe 32)`: 256 bits, 43 base64url characters. `valid-session-id-p` runs **before any store lookup**: anything malformed never reaches the store. A new id never comes from the request, so an id the client chose is never adopted. The id of a loaded record is checked against the requested id with `constant-time-equal`, so a loose store (a case-insensitive SQL collation) never hands out another visitor's session. | OWASP. Session fixation by adoption is impossible. |
| **Lazy creation** | A request without a valid session gets a new session object with an id at once, but nothing is stored and no cookie is sent unless its data is not empty at the commit. An invalid, unknown, mismatched or expired cookie gives a fresh session and is **never an error** for the client. A junk cookie is not cleared. | Bots and one-page visits cost no store entry. No Set-Cookie on a request that stores nothing. |
| **Idle expiry** | `idle-ttl`, default **86400 s** (one day). Sliding: the store TTL is put again on each write. It is also checked on load (`now >= last-seen + idle-ttl`), and an expired record is deleted, in case a store's TTL lags. | Anonymous visitor state, not a login; a login on top can use a shorter TTL |
| **Refresh-write rule** | An unchanged loaded session is written again (`last-seen`, TTL, cookie) **only when `now - last-seen >= refresh-interval`**. The default is `min(60, floor(idle-ttl / 2))` and the interval must be below `idle-ttl`; 0 writes on every request. So a session lives at least `idle-ttl − refresh-interval` after its last request and at most `idle-ttl`. | Without it every page view is a store write; with it, at most one write a minute per busy visitor |
| **Absolute lifetime** | `absolute-ttl`, optional (default none). It is checked on load (`now >= created-at + absolute-ttl`). Every save's TTL and Max-Age are capped at `created-at + absolute-ttl − now`. When it runs out during a request, the session ends at the commit. Rotation keeps `created-at`. | OWASP's absolute timeout. Rotation cannot be used to live for ever. |
| **Cookie lifetime** | **Max-Age = the TTL of the save that sends it**. It is not a browser-session cookie, and there is no Expires. A Set-Cookie goes out exactly when the store is written or the session ends. | The browser cookie and the store entry expire together and slide together. Lack's fixed Expires drifts away from the store. |
| **Cookie policy** | `make-cookie-policy`: name (default `"sid"`, `[A-Za-z0-9_-]+`; a `__Host-` or `__Secure-` name requires `:secure t`), SameSite `:lax` (default) or `:strict`, Secure `:auto` (https only) or `t`. Fixed, not options: `Path=/`, `HttpOnly`, no Domain (host-only). **SameSite=None is refused in 0.1.0.** | A safe default with nothing to get wrong. None needs Secure and opens cross-site sends. |
| **Secure behind a proxy** | `:auto` reads only the env's `:url-scheme`. Behind a TLS-terminating proxy, use `:secure t`. X-Forwarded-Proto is not read. | Trusting forwarded headers needs a trusted-proxy list (rpc-backend-htmx#15's request context) |
| **Cookie library** | **cl-cookie 0.2.0 writes the Set-Cookie** (`write-set-cookie-header`). It covers Max-Age, Path, SameSite (with the None-needs-Secure check), Secure and HttpOnly, so no private writer was needed. cl-cookie has **no parser for a request `Cookie` header**, so the read is the stack's existing quri split, the one rpc-backend-htmx's token gate uses: `quri:url-decode-params … :delimiter #\; :lenient t :percent-decode nil`, names trimmed, values raw. cl-cookie spells the attribute `Max-age`, which is harmless because names are case-insensitive. Both gaps: [cl-stack-systems#90](https://github.com/egao1980/cl-stack-systems/issues/90). | Reuse what the stack already has. No private mini-implementation of a cookie writer. |
| **Duplicate cookies** | The first cookie of the session's name counts (only one with a `=`); later ones are ignored | RFC 6265 orders the more specific path first; express and Rack do the same |
| **Env** | `begin-session` returns `(list* :session session env)` and does not modify the env. `env-session` reads `:session`. The key is not namespaced (unlike `:lack.session` or middleware-protocol's `:middleware.request`): it is the request's one session, under the same name as the S0b request property, and `env-session` is the accessor. | Clack env keys stay normative. A plist cannot be changed in place for the caller. |
| **Response** | A list response gets a fresh list: the app's headers unchanged and in order, every `:set-cookie` of the app kept, then ours. The app's list is not modified. A response with no Set-Cookie is returned as is. **A streaming response** (a function of a responder) commits when the app calls its responder, before the body; a change after that signals `session-write-error`. A session commits at most once, whatever the status. A condition escaping the app means no commit. | Clack writes each `:set-cookie` as its own header. Headers are gone once a stream starts. |
| **Concurrency** | The store calls are atomic; nothing locks a session across a request. **Last write wins** when one visitor's requests overlap. | As in Lack, Rack, express and Django. Per-key locking is not worth it for visitor state. |
| **Conditions** | `session-error` is the root. `session-value-error` (restarts `use-value`, `skip-value`, at SETF time and at the commit). `session-store-error` (RETRY / CONTINUE around every store call, in both phases). `session-write-error` (CERROR, CONTINUE ignores the change). | cl-stack-conditions: restarts where recovery is possible, policy with the caller |
| **Secrets** | No report, message, `print-object` output or condition slot contains a session id. A wrapped cache error's report (which prints its key) is not repeated. | Ids are bearer credentials; logs leak |
| **Defaults** | `idle-ttl` 86400, no absolute lifetime, refresh interval as above. The store defaults to an in-memory cache, process-local (lost on restart, not shared). | Zero-configuration development. Production passes a Redis-backed store. |
| **Not in 0.1.0** | CSRF tokens (SameSite=Lax covers cross-site POSTs; tokens, if needed, are session values). Signed cookies. Data in the cookie. Login. A fresh session in the same request after `end-session`. | Later slices or separate briefs |

---

## Protocol surface (S0)

```lisp
;; ids
(defconstant +session-id-length+ 43)
(defun generate-session-id ())                         ; (secrets-protocol:token-urlsafe 32)
(defun valid-session-id-p (object))

;; model (class and constructor given in the contract)
(defclass session () ())                               ; id data created-at last-seen + flags
(defun make-session (&key id data created-at last-seen new-p))
(defun session-id (s))  (defun session-data (s))  (defun session-created-at (s))  (defun session-last-seen (s))
(defun session-new-p (s))  (defun session-changed-p (s))  (defun session-rotated-p (s))
(defun session-ended-p (s))  (defun session-committed-p (s))
(defun session-value (session key &optional default))  ; → value, present-p; SETF-able
(defun remove-session-value (session key))  (defun clear-session (session))
(defun regenerate-session-id (session))  (defun end-session (session))

;; JSON
(defconstant +max-value-depth+ 64)
(defun session-data-json (session))  (defun encode-session-record (session))  (defun decode-session-record (text))

;; stores
(defclass session-store () ())
(defgeneric session-store-load (store id))  (defgeneric session-store-save (store session ttl))
(defgeneric session-store-delete (store id))
(defclass cache-session-store (session-store) ())      ; cache, prefix
(defun make-cache-session-store (cache &key (prefix "session:")))

;; cookie
(defclass cookie-policy () ())                         ; name, same-site, secure
(defun make-cookie-policy (&key (name "sid") (same-site :lax) (secure :auto)))
(defun read-session-cookie (policy env))  (defun format-session-cookie (policy env value max-age))

;; manager and the two phases
(defclass session-manager () ())
(defun make-session-manager (&key store cookie-policy (idle-ttl 86400) absolute-ttl refresh-interval clock))
(defun begin-session (manager env))                    ; → session, (list* :session session env)
(defun finish-session (manager session env response))  ; → response (list or streaming function)
(defun env-session (env))
```

### Conditions

```text
session-error (error)                 message
├── session-value-error               key, value — restarts use-value, skip-value
├── session-store-error               store, operation (:load :save :delete), cause — restarts retry, continue (manager)
└── session-write-error               session — CERROR: continue ignores the change
```

Restart functions `skip-value` and `retry` follow CLHS style: they invoke the restart, or return NIL when there is none.

---

## Slices

### S0: the protocol (session-protocol 0.1.0)

**Given:** the package, the conditions and restart functions, and the classes with their constructors and argument checks. **Stubbed:** ids, the accessors, rotation and ending, the value domain and the record, the cache store's methods, the cookie read and write, `begin-session`, `finish-session` and `env-session`. **Tests:**
- multi-request flows through a test-local begin/finish helper, with a browser that keeps cookies;
- lazy creation: no store entry and no Set-Cookie for a request that stores nothing;
- cookie attributes exactly, compared against cl-cookie's own output: Secure on https and not on http, forced Secure, Strict, a custom name, the expiry cookie;
- ids that are malformed (never looked up), forged (never adopted), mismatched (constant-time check), expired or unknown;
- idle expiry, sliding, the refresh rule and the absolute lifetime on an injected clock, including a cache whose TTL lags;
- rotation, with the old id gone and the data and creation time kept, and ending, with the record gone and the cookie expired;
- a JSON round trip with nested values, every non-JSON kind, depth and cycles, and the restarts at SETF time and at the commit;
- data changed in place, and last write wins;
- streaming responses: the commit before the first chunk, and writes after it;
- the app's headers and Set-Cookies kept;
- store failures with RETRY and CONTINUE in both phases, a corrupt record, the cache's own restarts kept live;
- no id in any report.

### S0b: the middleware binding (session-protocol/middleware 0.2.0)

The middleware binding is a **`session-handler` mixin** on [middleware-protocol](middleware.md) 0.1.0. It lives in the secondary system **`session-protocol/middleware`** (package `session-protocol/middleware`, nickname `stack-session-middleware`), which depends on session-protocol, `middleware-protocol` 0.1.0 and `middleware-protocol/clack` 0.1.0. The core system `session-protocol` does not depend on middleware-protocol. Every system in the `.asd` is 0.2.0, and S0's behaviour does not change. rpc-backend-htmx#19 (S1) uses the mixin. `begin-session` and `finish-session` stay the transport-neutral core.

**Contract:** [session-protocol#4](https://github.com/egao1980/session-protocol/pull/4) (draft). The header of `src/middleware.lisp` is the specification.

```lisp
;; session-protocol/middleware (stack-session-middleware)
(defclass session-handler (stack-middleware:handler) ())   ; :session-manager, SESSION-HANDLER-MANAGER
(defmethod stack-middleware:prepare-request ((h session-handler) (r clack-request)))           ; → request
(defmethod stack-middleware:finish-response ((h session-handler) (r clack-request) response))  ; → response
(defun request-session (request))                          ; → session or NIL

(stack-middleware-clack:clack-app
 (stack-middleware:make-handler '(response-headers-handler session-handler clack-handler)
                                :session-manager manager :app #'my-app …))
```

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Where it lives** | A secondary system of session-protocol, not part of middleware-protocol, so the core stays lean. This answers S0's open question. | Each protocol owns its binding. middleware-protocol does not know about sessions. |
| **Configuration** | `:session-manager` (the initarg is named after the mixin, and the slot is a symbol of its package). The default is a fresh `(make-session-manager)` for each handler instance: process-local, for development. Anything that is not a `session-manager` is a `type-error` from `make-instance` and `make-handler`. | middleware.md, "Slot names". Zero-configuration development, as in S0. |
| **Hooks only** | `session-handler` has no `handle` method (no `:around`, `:before` or `:after`). It specializes `prepare-request` and `finish-response` on `clack-request` and nothing else. | The hooks run inside middleware-protocol's base method, which is what the short-circuit and error rules below rest on |
| **Env propagation** | `prepare-request` calls `begin-session` on `(clack-request-env request)`. It puts the session on the request as `:session` and installs the env that `begin-session` returns with `(setf clack-request-env)`; that env is `(list* :session session env)`. Then it returns `(call-next-method)`. `clack-handler` calls the app with `(list* :middleware.request request env*)`. Inside the app, `(env-session env)` and `(request-session (env-request env))` are the same session. The server's env is not modified: it is the tail of the new env. | middleware M0: "layers that change the env install a new plist". S0's key `:session` is in the app's env, unchanged. |
| **Hook order** | The session is begun before the `prepare-request` methods of inner mixins (those after it in the class precedence list), so they see it on the request and in the env. Outer mixins see it only after their `call-next-method`. `finish-response` commits the response that the inner mixins' `finish-response` methods return. Outer hooks, and every `:around` that maps the response (`response-headers-handler`, `timing-handler`), see the response with the Set-Cookie, wherever they sit. | The onion of M0's hooks |
| **The commit** | `(finish-session manager session (clack-request-env request) response*)`. The base method calls `finish-response` through `map-response`, so `response*` is always an immediate list. For a Clack streaming response, it is the head the app hands its responder. **The commit runs when the app calls its responder, before the body** (verified against middleware-protocol/clack's `map-response` on `function`). A later write signals `session-write-error`. An app that never calls its responder commits nothing. `finish-session`'s own streaming case is not used here. A request whose session is missing (an inner `prepare-request` replaced it, or a direct call) passes through unchanged. | D7, D8. The head is the last moment headers can change. |
| **Short-circuit** | An `:around` that answers without `call-next-method` skips both hooks, wherever it sits in the class precedence list (for example, a gate's 403). No `begin-session` runs, the store is not called, nothing is committed, no Set-Cookie is sent, and the request has no session. Outer `:around`s still map the answer. | middleware M0: "hooks belong to requests that reach the primary" |
| **Errors** | A condition escaping the app unwinds the base method before `finish-response`. The session was begun but is not committed. That holds also when `error-handler` maps the condition to a response, wherever `error-handler` sits: its `:around` is outside the base method. So the 500 has no session Set-Cookie, nothing is stored, the request's changes are lost and the stored session is unchanged. The error function still sees the begun session through `request-session`. An error page that must keep the session calls `finish-session` itself. S0's store restarts stay live inside an error function, because `handle-error` runs before unwinding. A store failure while a streamed response commits propagates out of the responder call, outside `error-handler` (middleware M2). | S0: "a condition escaping the app means no commit". A half-done request should not persist its changes. |
| **Pass-through** | A request that is not a `clack-request` gets no session, because neither method applies. That covers a plain `request`, later an rpc request, and any other object. The manager is not called, and the answer is unchanged. Subclasses of `clack-request` (`clack-app`'s `:request-class`) get sessions. `request-session` returns NIL for anything that is not a `request`, so code that may get any request can ask. | D5: inapplicable methods are the pass-through |
| **No special variable** | The channels are the request property and the env key. A streamed body still reaches both. | D6 |
| **Tests layout** | The existing `session-protocol/tests` system gets four files, `tests/middleware-*.lisp`, in their own package `session-protocol/middleware/tests`. They reuse S0's world, counting cache and cookie jar (`browser`). `session-protocol/middleware`'s test-op is the same system. One `cl-repo test --system session-protocol` runs S0 and S0b, and CI is unchanged. | One verdict, with S0 as the regression guard and no copied helpers |

**Tests (49, Rove, `deftest-parametrize` for the CPL tables).** Clack apps built with `make-handler`, driven over several requests with S0's cookie jar:
- configuration, and hooks only;
- persistence; a new browser; no cookie when nothing is stored (the app's response comes back `eq`); a read within the refresh interval;
- rotation and ending through the handler;
- the env and request seen by the app; Secure on https; a `clack-request` subclass; the default manager;
- streaming: the commit at the responder call, before the first chunk; writes after it; an app that never responds; a read-only head passed through `eq`; a loaded session; the server's writer passed through; the head through header and timing mixins in three orders; a store failure at the responder call, with CONTINUE;
- the hook order; CPL variants that give the same headers and cookies (session outside and inside `response-headers-handler`, with timing, with errors, and a `defclass` handler); an app cookie with the session's name;
- timing seeing the cookie in either order;
- the gate in three positions, and for a new browser;
- an error mapped in three positions, for a new browser, and committed by hand; an error that propagates with no `error-handler`;
- load failures through the handler, with RETRY and CONTINUE; a save failure decided by an error function;
- pass-through for four request kinds.

### S1: rpc-backend-htmx (rpc-backend-htmx#19)

These parts belong to rpc-backend-htmx, not to session-protocol:
- a `:sessions` option;
- the session on `*htmx-request*`, where handlers read, write, rotate and end it;
- SSE streams read the session; after the commit a write is `session-write-error`;
- `htmx-client` keeps a cookie jar, so tests can walk a multi-page flow;
- the request context of rpc-backend-htmx#15 (client address with trusted proxies, `Last-Event-ID`).

S1 uses S0b.

### Later

- **A SQL store**: a `session-store` over sql-protocol, with a JSON column, an expiry column and a sweep. It reuses `encode-session-record` / `decode-session-record`.
- **A refresh without a rewrite**: Redis `EXPIRE`. cache-protocol has no touch operation; that gap is filed only once refresh writes show up in measurements.
- **CSRF tokens**, if ever needed: a synchronizer token kept as a session value.
- **Login on top**, a separate brief: OIDC through cl-stack-oauth2, `regenerate-session-id` on login, a shorter idle TTL for authenticated sessions.

---

## Progress

| Slice | Package | State |
|-------|---------|-------|
| S0 | session-protocol 0.1.0 | **implemented, published 0.1.0**: [session-protocol#1](https://github.com/egao1980/session-protocol/pull/1) (merged). team-solve: 308 tests, 934 assertions. Contract: On the stubs, 308 tests: 250 fail, 58 pass (the given conditions and constructors). An independent reference implementation passes all 308 tests (934 assertions). |
| S0b | session-protocol/middleware 0.2.0 | **implemented, published 0.2.0**: [session-protocol#4](https://github.com/egao1980/session-protocol/pull/4) (merged; team-solve: 357 tests, 1198 assertions, green on ubuntu, macOS and Windows). Contract: 49 new tests. On the stubs, S0's 308 tests pass (934 assertions); of the 49, 2 pass (the given configuration) and 47 fail. A throwaway reference implementation passes all 357 tests (1198 assertions), and eleven mutations of it (an `:around` instead of the hooks, a commit before the inner hooks, no env install, and others) are each caught. Next: team-solve. |
| S1 | rpc-backend-htmx | planned ([rpc-backend-htmx#19](https://github.com/egao1980/rpc-backend-htmx/issues/19)) |

### Follow-ups

- [cl-stack-systems#90](https://github.com/egao1980/cl-stack-systems/issues/90): cl-cookie has no request `Cookie` parser (the quri split is now in two places), and it writes `Max-age`.

---

## Open questions

- A fresh session in the same request after `end-session`, for a logout that leaves a flash message. In 0.1.0 such a write is `session-write-error`.
- Whether S1 wants a shorter default idle TTL than one day.

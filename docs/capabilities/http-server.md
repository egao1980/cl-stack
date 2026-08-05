# http-server-protocol (wave-2)

**Issues:** [#93](https://github.com/egao1980/cl-stack/issues/93) · [#100](https://github.com/egao1980/cl-stack/issues/100)  
**Status:** brief **locked** (#100) — CLOS protocol + backends (not “pin Clack alone”)

Pluggable HTTP **servers**. One app DX; multiple accept-loop backends. Client stack stays [`http-protocol`](http-protocol.md) / [`cl-stack-http`](https://github.com/egao1980/cl-stack-http).

Conventions: [API.md](../API.md). Event loops: [event-protocol.md](event-protocol.md). JSON: [json-protocol.md](json-protocol.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | **CLOS protocol + backends** (same as http/event/json) | Issue disposition upgraded from “pin Clack only”; stack rule is protocol → backend → facade |
| **App contract** | **[Clack](https://github.com/fukamachi/clack) env** (Lack-compatible) | De-facto CL WSGI; don’t invent a second app plist. Protocol **owns lifecycle + CLOS types**; apps are still `(lambda (env) → response)` Clack functions |
| **Middleware** | **[Lack](https://github.com/fukamachi/lack)** | Compose around Clack apps; not reimplemented in protocol |
| **Default backend (A)** | **[Hunchentoot](https://github.com/edicl/hunchentoot)** via Clack adapter | **Windows primary** + linux/darwin; no libev; mature; good for dev + portable prod |
| **Second backend (B)** | **[Woo](https://github.com/fukamachi/woo)** | Fast Unix accept loop on **libev**; shares native story with `event-backend-libev` |
| **Not wave-2 default** | Bare Clack-without-protocol | Apps that want raw Clack still can; stack DX goes through protocol |
| **Selection DX** | ASDF + `*http-server-backend*` | Load `http-server-backend-hunchentoot` (default) or `…-woo`; no plugin registry |
| **JSON APIs** | `json-protocol` / `stack-json` in handlers | Cookbook = minimal JSON API over protocol |
| **TLS terminate** | Backend-specific in wave-2; prefer reverse-proxy in cookbooks | Full TLS accept = follow-on (cl-stack-ssl server path) |
| **WebSocket upgrade** | Out of this protocol → `ws-protocol` server later | Keep upgrade path documented only |

**Supersedes** epic #93 wording “Non-goals: new server protocol reinventing Clack.” We **do not reinvent the Clack env**. We **do** add a thin CLOS server protocol so backends swap like the client stack.

---

## Bakeoff scorecard (#100)

Scores: **1** (poor) … **5** (excellent) for cl-stack needs.

| Criterion | Hunchentoot | Woo | “Clack pin only” |
|-----------|-------------|-----|------------------|
| Windows primary | **5** | **1** (libev) | **3** (depends on handler) |
| Unix perf / accept | **3** | **5** | n/a |
| Clack/Lack ecosystem | **5** (clack.handler.hunchentoot) | **5** (native Clack handler) | **5** |
| Overlay / native cost | **5** (pure Lisp + usocket) | **3** (libev overlay) | **4** |
| Aligns with event-backend-libev | **2** | **5** | **2** |
| Maintenance | **4** | **4** | **4** |
| **Wave-2 role** | **Default (A)** | **Second (B)** | reject as sole story |

**Verdict:** protocol + **Hunchentoot default**, **Woo second (Unix)**. Pin Clack/Lack as the app/middleware layer both backends speak.

---

## Repo layout (locked)

Separate repos per layer (event/http precedent):

| Layer | Repo |
|-------|------|
| Protocol + shared conformance | `egao1980/http-server-protocol` |
| Default backend A | `egao1980/http-server-backend-hunchentoot` |
| Second backend B (Unix) | `egao1980/http-server-backend-woo` |
| Optional thin facade (later) | `egao1980/cl-stack-http-server` — only if cookbooks need more than protocol DX |

Wave-2 MVP may ship A (+ protocol) in one repo with two ASDF systems **only if** publish stays simple; prefer split before metapackage pin.

**Third-party imports** (`cl-stack-systems`): `clack`, `lack` (+ needed lack modules), `hunchentoot`, `woo` (+ deps). First-party protocol/backends publish from owning repos.

---

## Protocol surface

Package nick: `stack-http-server` (system `http-server-protocol`).

### Value types

```lisp
;; App = Clack application
;;   (lambda (env) → (status headers body))   ; body = list of octets/strings | path | stream

(defclass http-server () ())          ; backend instance (listener)
(defvar *http-server-backend* nil)    ; factory / current backend object
```

Clack `env` keys remain normative (`:request-method`, `:script-name`, `:path-info`, `:query-string`, `:headers`, `:raw-body`, `:remote-addr`, …). Protocol may expose thin accessors that read/write that plist — **not** a parallel env schema.

### Generics / DX

```lisp
(defgeneric backend-make-server (backend &key host port app ssl-cert ssl-key backlog)
  (:documentation "Return a stopped HTTP-SERVER ready to START."))

(defgeneric start (server &key background)
  (:documentation "Bind/listen/accept. BACKGROUND T → return immediately (thread/loop)."))

(defgeneric stop (server &key soft)
  (:documentation "Stop accepting; SOFT drains when backend supports it."))

(defgeneric running-p (server))

;; Facade helpers (functions)
(defun serve (app &key (host "127.0.0.1") (port 8080) background
                       (backend *http-server-backend*))
  "Make + start. Returns SERVER.")

(defmacro with-server ((server app &rest keys) &body body)
  "START around BODY; STOP with unwind-protect.")
```

### Conditions

```text
http-server-error
├── http-server-bind-error      ; address in use / permission
├── http-server-start-error
└── http-server-not-running
```

### Conformance (shared tests)

- Start on ephemeral port → `cl-stack-http` / `http-protocol` GET `/` → 200  
- POST JSON body → handler uses `stack-json:decode` / `encode` → round-trip  
- `stop` is idempotent; second `start` after stop works  
- Woo tests **skip on Windows** / non-Unix CI

---

## Backend notes

### A — Hunchentoot

- Implement via `clack:clackup` / `clack.handler.hunchentoot` **or** direct Hunchentoot easy-handler bridge that still accepts a Clack app (prefer Clack handler for one app shape).
- No libev; Windows CI must run A.

### B — Woo

- `clack.handler.woo` / Woo directly with Clack app.
- Depends on libev (system package or future overlay alignment with `event-backend-libev`).
- Document: Unix-only; not the Windows default.

### Escape hatch

```lisp
;; Raw Clack still fine:
(clack:clackup #'my-app :server :hunchentoot :port 8080)
```

Protocol is the **stack default** for cookbooks / meta — not a ban on Clack.

---

## Cookbook (with impl)

Minimal JSON API:

```lisp
(asdf:load-system "http-server-backend-hunchentoot")
(asdf:load-system "json-backend-jzon")

(defun app (env)
  (let* ((method (getf env :request-method))
         (path (getf env :path-info)))
    (cond
      ((and (eq method :get) (string= path "/health"))
       '(200 (:content-type "text/plain") ("ok")))
      ((and (eq method :post) (string= path "/echo"))
       (let* ((raw (alexandria:read-stream-content-into-string
                    (getf env :raw-body)))
              (data (stack-json:decode raw)))
         (list 200 '(:content-type "application/json")
               (list (stack-json:encode data)))))
      (t '(404 (:content-type "text/plain") ("nope"))))))

(stack-http-server:with-server (s #'app :port 8080)
  …)  ; hit with stack-http:get / post :json
```

---

## Non-goals (this wave)

- Full ASGI/HTTP2 server stack  
- Production Woo hardening / multi-worker supervisors  
- Replacing Clack env with a new app DSL  
- Server-side WebSocket (follow-on)  
- Built-in TLS as the default deploy story (proxy-first)

---

## Implementation tasks

- [x] #100 Brief + bakeoff (this doc)
- [x] Import Clack/Lack/Hunchentoot/(Woo) into `cl-stack-systems` (#114)
- [x] `http-server-protocol` + Hunchentoot backend + GHCR + pins (#115)
- [x] Woo backend (Unix) + skip-on-Windows CI (#116)
- [x] Cookbook + smoke (SBCL × Hunchentoot; Woo Ubuntu job) — [http-server.md](../cookbooks/http-server.md)

Child issues: #114 / #115 / #116 under #93.

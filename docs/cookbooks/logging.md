# Cookbook: Logging (SLF4J / structlog)

**Audience:** Java SLF4J/Logback or Python logging/structlog users who want one Lisp call site for text + structured logs.

**Packages:**

| Layer | Role |
|-------|------|
| [`log-protocol`](https://github.com/egao1980/log-protocol) (`stack-log`) | `info` / `with-context` / `configure` + stream sink |
| [`log-backend-log4cl`](https://github.com/egao1980/log-backend-log4cl) | **default** (separate repo) |
| [`log-backend-vom`](https://github.com/egao1980/log-backend-vom) | alternate (`use-vom-backend`; separate repo) |
| [`serdes-protocol`](https://github.com/egao1980/serdes-protocol) | structured encode |
| `sexp-protocol` | `:sexp` structured format |
| `json-protocol` + jzon | `:json` structured (register serdes `:json`) |

Brief: [logging.md](../capabilities/logging.md).

```lisp
(cl-repo:load-system "log-backend-log4cl" :version "0.1.1")
(cl-repo:load-system "sexp-protocol" :version "0.2.0")  ; for structured :sexp
```

---

## 1. Text (dev / REPL)

```lisp
(asdf:load-system "log-backend-log4cl")  ; sets *log-backend*

(stack-log:configure :level :info :layout :text)
(stack-log:info "boot" :version "0.1.0")
;; 2026-08-05T18:00:00Z INFO COMMON-LISP-USER - boot version=0.1.0
```

---

## 2. Context + fields

```lisp
(stack-log:with-context (:request-id "abc")
  (stack-log:info "handled" :status 200))
;; … handled request-id=abc status=200
```

Levels: `trace` `debug` `info` `warn` `log-error` `fatal` (no export of `error` — clashes with `cl:error`).

---

## 3. Structured SEXP

```lisp
(asdf:load-system "sexp-protocol")       ; registers serdes :sexp
(asdf:load-system "log-backend-log4cl")
(stack-log:configure :level :info :layout :structured :format :sexp)
(stack-log:with-context (:request-id "abc")
  (stack-log:info "handled" :status 200))
;; (:OBJECT ("ts" . "…") ("level" . "INFO") … ("fields" . (:OBJECT …)))
```

---

## 4. Structured JSON

Load a JSON implementor that registers serdes `:json` (jzon backend after soft/hard serdes wire), then:

```lisp
(asdf:load-system "json-backend-jzon")
(stack-log:configure :layout :structured :format :json)
(stack-log:info "handled" :status 200)
;; {"ts":"…","level":"INFO","logger":"…","msg":"handled","fields":{"status":200}}
```

---

## 5. Level + filters + async (protocol)

```lisp
(stack-log:set-level :info)
(stack-log:level-enabled-p :debug) ; => NIL

(stack-log:add-filter
 (lambda (level logger msg fields)
   (declare (ignore level logger fields))
   (not (search "password" msg)))
 :name :no-secrets)

(stack-log:configure :async t)   ; protocol mailbox + worker
(stack-log:info "queued")
(stack-log:flush)                ; drain before exit / tests
(stack-log:shutdown-async)
```

Appenders / multi-sink / log4cl hierarchy = **backend config**, not protocol.

---

## 6. Alternate vom backend

```lisp
(asdf:load-system "log-backend-vom")
(log-backend-vom:use-vom-backend)
(stack-log:configure :level :debug :layout :text)
(stack-log:debug "probe")
```

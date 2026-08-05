# Cookbook: Logging (SLF4J / structlog)

**Audience:** Java SLF4J/Logback or Python logging/structlog users who want one Lisp call site for text + structured logs.

**Packages:**

| Layer | Role |
|-------|------|
| [`log-protocol`](https://github.com/egao1980/log-protocol) (`stack-log`) | `info` / `with-context` / `configure` |
| `log-backend-log4cl` | **default** |
| `log-backend-vom` | alternate (`use-vom-backend`) |
| [`serdes-protocol`](https://github.com/egao1980/serdes-protocol) | structured encode |
| `sexp-protocol` | `:sexp` structured format |
| `json-protocol` + jzon | `:json` structured (register serdes `:json`) |

Brief: [logging.md](../capabilities/logging.md).

```lisp
(cl-repo:load-system "log-backend-log4cl" :version "0.1.0")
(cl-repo:load-system "sexp-protocol" :version "0.1.0")  ; for structured :sexp
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

## 5. Alternate vom backend

```lisp
(asdf:load-system "log-backend-vom")
(log-backend-vom:use-vom-backend)
(stack-log:configure :level :debug :layout :text)
(stack-log:debug "probe")
```

# log-protocol (P2)

**Issues:** [#102](https://github.com/egao1980/cl-stack/issues/102)  
**Status:** brief **locked** — CLOS protocol + backends (SLF4J-shaped; not “pin log4cl alone”)

One app DX for **leveled + structured** logging. Stack libraries depend on the protocol only; apps pick a backend. Mirrors Java **SLF4J** (API) + Logback/Log4j (impl) and Python **logging** / **structlog**.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md) (Logging → protocol + pin).

---

## Prior art (shape targets)

| Ecosystem | Library | What we steal |
|-----------|---------|---------------|
| **Java** | [SLF4J](https://www.slf4j.org/) + Logback/Log4j2 | Stable API; swappable impl; MDC/context map |
| **Python** | [`logging`](https://docs.python.org/3/library/logging.html) | Levels, hierarchical loggers, handlers/formatters |
| **Python** | [structlog](https://www.structlog.org/) | **Key-value fields** first-class; bind context |
| **Go** | zap / zerolog | Structured fields + low alloc (aspirational; not wave-1 bar) |

ANSI has `*standard-output*` and conditions — not a logging framework. Stack needs one dependency surface for `http-*`, `event-*`, cookbooks.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | **CLOS protocol + backends** | #102 “pin one after bakeoff” → pin is the **default backend**; API is protocol so libs don’t hard-depend on log4cl |
| **DX target** | structlog/SLF4J: `(log:info "msg" :k v …)` + context bind | Cookbooks + HTTP middleware need fields (`:request-id`, `:status`), not only `format` strings |
| **Default backend (A)** | **[log4cl](https://github.com/sharplispers/log4cl)** (Sharplispers) | De-facto CL logger; hierarchical categories; appenders/layouts; Slime/Sly; Apache-2.0; CLOS-native internals |
| **Alternate (B)** | **[vom](https://github.com/orthecreedence/vom)** | Tiny, fast, already imported (`cl-stack-systems` / blackbird); good for constrained binaries |
| **Watchlist** | **[cl-llog](https://github.com/atgreen/cl-llog)** (llog) | Structured-native (zap-shaped); young (≤0.1.x); revisit when versioned + CI-proven — **not** wave-1 default |
| **Also considered** | **Verbose** (Shinmera) | Powerful pipeline model; heavier mental model / deps for stack default |
| **Also considered** | **cl-grip** | Pluggable journals; smaller ecosystem than log4cl |
| **Not default** | Fluentd-only (`cl-fluent-logger`) | Sink, not app API — optional appender later |
| **Levels** | `:trace :debug :info :warn :error :fatal` | Map onto backend levels (vom’s syslog-ish set collapses as needed) |
| **Fields** | Keyword plist after message; values = printable / json-protocol-friendly | Backend A: pattern layout + kv suffix or JSON layout opt-in; B: format into message |
| **Context** | `log:with-context ((&key …) &body)` dynamic bind | SLF4J MDC / structlog `bind_contextvars` |
| **Logger name** | Package / explicit string category | log4cl hierarchy; vom per-package levels |
| **Selection DX** | ASDF + `*log-backend*` | Load `log-backend-log4cl` (default) or `log-backend-vom` |
| **Libs vs apps** | Stack libs call **protocol only** | Never `ql:quickload :log4cl` from `http-protocol` et al. |
| **Windows** | A/B pure Lisp | Primary target |

**Supersedes** #102 “pin one.” Winner of the pin bakeoff is **log4cl as backend A**; structured DX lives in the protocol.

---

## Bakeoff scorecard (#102)

Scores: **1** … **5** for cl-stack needs.

| Criterion | log4cl | vom | Verbose | cl-llog |
|-----------|--------|-----|---------|---------|
| Ecosystem / de-facto | **5** | **3** | **3** | **2** |
| Structured fields (native) | **3**† | **2** | **3** | **5** |
| Hierarchy / categories | **5** | **3** | **4** | **4** |
| REPL / Slime UX | **5** | **3** | **3** | **4** |
| Dep weight | **3** | **5** | **2** | **4** |
| Already in stack | **1** | **5** (import) | **1** | **1** |
| Maintenance / liveliness | **3** | **3** | **4** | **3** (young) |
| Windows / pure Lisp | **5** | **5** | **5** | **5** |
| **Wave role** | **Default (A)** | **Alternate (B)** | reject as pin | **watchlist** |

† Protocol supplies structured DX; log4cl backend adapts fields → layout/format.

**Verdict:** protocol + **log4cl default**, **vom second**. Track **cl-llog** for a future structured-native backend if it stabilizes.

---

## Repo layout (locked)

| Layer | Repo / system |
|-------|----------------|
| Protocol + shared tests | `egao1980/log-protocol` (nick `stack-log`) |
| Default backend A | `log-backend-log4cl` |
| Alternate backend B | `log-backend-vom` |
| Optional facade | only if pattern-config DSL needed beyond protocol |

**Third-party imports:** `log4cl` (+ deps). `vom` already imported — ensure pin/version in `stable.pins`.

---

## Protocol surface

Package nick: `stack-log` (system `log-protocol`).

### Value types

```lisp
(defclass log-backend () ())
(defvar *log-backend* nil)
(defvar *log-context* nil)   ; plist or equal hash-table of bound fields
```

### Generics / DX

```lisp
(defgeneric backend-log (backend level logger-name message &key fields)
  (:documentation "LEVEL keyword; FIELDS plist. Message = string."))

;; Facade (functions — what cookbooks + libs call)
(defun log:trace (message &rest fields))
(defun log:debug (message &rest fields))
(defun log:info  (message &rest fields))
(defun log:warn  (message &rest fields))
(defun log:error (message &rest fields))
(defun log:fatal (message &rest fields))

(defmacro log:with-context ((&rest field-plist) &body body)
  "Bind fields for dynamic extent; merged into each log call.")

(defun log:set-level (level &key logger)
  "Process/backend minimum level.")

(defun log:configure (&key backend level json stream file)
  "App bootstrap helper — optional sugar over backend config.")
```

Logger name default: `(package-name *package*)`.

### Conditions

Logging must **not** signal on normal paths. Optional `log-error` only for misconfiguration (missing backend, bad file appender).

---

## Cookbook (with impl)

```lisp
(asdf:load-system "log-backend-log4cl")   ; sets *log-backend*

(stack-log:configure :level :info)
(stack-log:info "boot" :version "0.1.0")

(stack-log:with-context (:request-id "abc" :path "/health")
  (stack-log:info "handled" :status 200))
```

JSON lines (ops): backend config flag or `log:configure :json t` → layout that encodes fields via `json-protocol`.

---

## Non-goals (this wave)

- Full OpenTelemetry export  
- Shipping a log aggregation SaaS client as default  
- Replacing log4cl’s properties-file configurator in wave-1 (escape hatch OK)  
- Making cl-llog the default before it has a clear release + Windows CI story  

---

## Implementation tasks

- [x] Brief lock (this doc) — [#122](https://github.com/egao1980/cl-stack/issues/122)
- [ ] Import log4cl (+ pin vom) — [#123](https://github.com/egao1980/cl-stack/issues/123)
- [ ] `log-protocol` + log4cl backend — [#124](https://github.com/egao1980/cl-stack/issues/124)
- [ ] vom backend + cookbook — [#125](https://github.com/egao1980/cl-stack/issues/125)

Child issues under #102. Start after CLI wave (#119–#121).

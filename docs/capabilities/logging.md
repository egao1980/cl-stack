# log-protocol (P2)

**Issues:** [#102](https://github.com/egao1980/cl-stack/issues/102)  
**Status:** brief **locked** — CLOS protocol + backends; **text (log4j) + structured (JSON/SEXP via serdes)**

One app DX for leveled logging with **two first-class layouts**:

1. **Text** — Log4j/Logback-style pattern lines (human / REPL / classic ops)  
2. **Structured** — one event record encoded as **JSON** or **SEXP** (machines / aggregators)

Libs depend on the protocol only; apps pick logger backend + layout/format. Mirrors **SLF4J** + Logback layouts and **structlog** processors.

Conventions: [API.md](../API.md). Serdes: [serdes.md](serdes.md). JSON values: [json-protocol.md](json-protocol.md).

---

## Prior art (shape targets)

| Ecosystem | Library | What we steal |
|-----------|---------|---------------|
| **Java** | Log4j2 / Logback | **PatternLayout** (text); JSON layout / encoder for structured |
| **Java** | SLF4J | Stable API; MDC → our `with-context` |
| **Python** | `logging` + formatters | Handlers / formatters split |
| **Python** | structlog | KV fields + renderers (JSON) |
| **Go** | zap | Structured fields (aspirational perf — not wave-1 bar) |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + logger backends + **layout** axis | Backend = how/where (log4cl/vom); layout = text vs structured |
| **Text layout** | Log4j-style **pattern** (default for REPL/dev) | `%d %p %c — %m` + optional kv; familiar ops |
| **Structured layout** | Event record → **[`serdes-protocol`](serdes.md)** | One encoder path for JSON **and** SEXP; no private log JSON |
| **Structured formats** | `:json` (default for structured) and `:sexp` | JSON for ELK/fluentd; SEXP for Lisp-native pipes / `cl-stack-http` kinship |
| **Serdes dependency** | Depend on **`serdes-protocol`**; load **`json-protocol`** / sexp **implementors** | json-protocol *implements* serdes (not wrapped by a serdes-backend-json shim) |
| **Default logger backend (A)** | **[log4cl](https://github.com/sharplispers/log4cl)** | Hierarchy, appenders, Slime; text patterns native; structured via protocol layout wrapper |
| **Alternate logger (B)** | **[vom](https://github.com/orthecreedence/vom)** | Tiny; already imported |
| **Watchlist** | **cl-llog** | Structured-native; young |
| **App call shape** | `(log:info "msg" :k v …)` same for both layouts | Layout chosen at configure time, not per call |
| **Levels** | `:trace :debug :info :warn :error :fatal` | Map to backend |
| **Fields / context** | plist after message; `with-context` | Merged into event record / MDC |
| **Event record (structured)** | Normative keys below | Stable for aggregators |
| **Selection DX** | ASDF + `*log-backend*` + `log:configure :layout …` | |
| **Libs vs apps** | Libs → protocol only | |
| **Windows** | Pure Lisp; text + JSON/SEXP all required on `windows-latest` | |

### Event record (structured, normative)

Encoded via serdes as object/hash (JSON) or property list / alist (SEXP policy in serdes brief):

| Key | Type | Notes |
|-----|------|-------|
| `ts` | string (ISO-8601) or unix ms | UTC |
| `level` | string or keyword | `info` / `:info` — JSON uses string |
| `logger` | string | category / package |
| `msg` | string | |
| `fields` | object | merged context + call-site kv (no reserved-key clashes) |

Optional later: `thread`, `file`, `condition` — not wave-1 required.

### Text pattern (wave-1 minimum)

Default pattern (log4j-ish):

```text
%d{yyyy-MM-dd'T'HH:mm:ss.SSSX} %p %c - %m%n
```

When fields non-empty, append ` %k` style or ` {k=v, …}` — exact pattern token TBD in impl; must be readable on consoles. Full Log4j pattern language = **not** required; subset is fine.

---

## Bakeoff scorecard (#102)

| Criterion | log4cl | vom | Verbose | cl-llog |
|-----------|--------|-----|---------|---------|
| Text / pattern (log4j-like) | **5** | **2** | **3** | **3** |
| Structured via serdes (stack) | **4**† | **4**† | **3** | **5** |
| Ecosystem / hierarchy / Slime | **5** | **3** | **3** | **2** |
| Dep weight | **3** | **5** | **2** | **4** |
| Already in stack | **1** | **5** | **1** | **1** |
| **Wave role** | **Default (A)** | **Alternate (B)** | reject | watchlist |

† Layout implemented in `log-protocol`; backend supplies appenders/streams.

**Verdict:** log4cl default for text heritage; **structured always goes through serdes** (`:json` / `:sexp`).

---

## Repo layout

| Layer | System |
|-------|--------|
| Serdes interface | `serdes-protocol` — [serdes.md](serdes.md) |
| JSON implementor | `json-protocol` (implements serdes `:json`) |
| SEXP implementor | `sexp-protocol` (implements serdes `:sexp`) |
| Log protocol | `egao1980/log-protocol` (`stack-log`) |
| Logger A/B | `log-backend-log4cl`, `log-backend-vom` |

**Imports:** `log4cl`; `vom` pin. App loads `json-protocol` / sexp to register serdes formats.

---

## Protocol surface

Package nick: `stack-log`.

```lisp
(defclass log-backend () ())
(defvar *log-backend* nil)
(defvar *log-context* nil)
(defvar *log-layout* :text)          ; :text | :structured
(defvar *log-serdes-format* :json)   ; when structured: :json | :sexp

(defgeneric backend-log (backend level logger-name message &key fields))

(defun log:trace (message &rest fields))
(defun log:debug (message &rest fields))
(defun log:info  (message &rest fields))
(defun log:warn  (message &rest fields))
(defun log:error (message &rest fields))
(defun log:fatal (message &rest fields))

(defmacro log:with-context ((&rest field-plist) &body body))

(defun log:configure (&key backend level
                          (layout :text)          ; :text | :structured
                          (format :json)          ; serdes format when structured
                          stream file pattern)
  "LAYOUT :text → pattern (log4j-ish). :structured → serdes encode of event record.")
```

Implementation sketch: protocol builds the event (text line **or** record), then backend writes to appenders; for structured, `(serdes:encode record :format *log-serdes-format*)` then write line (JSONL / one sexp per line).

### Conditions

No signal on hot path. `log-error` only for misconfiguration (missing backend/serdes format).

---

## Cookbook (with impl)

**Text (dev):**

```lisp
(asdf:load-system "log-backend-log4cl")
(stack-log:configure :level :info :layout :text)
(stack-log:info "boot" :version "0.1.0")
;; 2026-08-05T18:00:00.123Z INFO common-lisp-user - boot version=0.1.0
```

**Structured JSONL:**

```lisp
(asdf:load-system "json-backend-jzon")   ; json-protocol implements serdes :json
(asdf:load-system "log-backend-log4cl")
(stack-log:configure :level :info :layout :structured :format :json)
(stack-log:with-context (:request-id "abc")
  (stack-log:info "handled" :status 200))
;; {"ts":"…","level":"info","logger":"…","msg":"handled","fields":{"request-id":"abc","status":200}}
```

**Structured SEXP:**

```lisp
(asdf:load-system "sexp-protocol")       ; implements serdes :sexp
(stack-log:configure :layout :structured :format :sexp)
```

---

## Non-goals (this wave)

- OpenTelemetry export  
- Full Log4j pattern language compatibility  
- cl-llog as default  
- Binary log formats (protobuf)  

---

## Implementation tasks

- [x] Brief lock (logging) — [#122](https://github.com/egao1980/cl-stack/issues/122)
- [x] **`serdes-protocol` + sexp** (minimal whole-value; Gray stubs) — [#133](https://github.com/egao1980/cl-stack/issues/133) ([egao1980/serdes-protocol](https://github.com/egao1980/serdes-protocol) `0.1.0`; json hard-wire follow-on)
- [x] Import log4cl (+ pin vom) — [#123](https://github.com/egao1980/cl-stack/issues/123) (PR [cl-stack-systems#15](https://github.com/egao1980/cl-stack-systems/pull/15))
- [x] `log-protocol` + log4cl: **text + structured** — [#124](https://github.com/egao1980/cl-stack/issues/124) ([egao1980/log-protocol](https://github.com/egao1980/log-protocol) `0.1.0`)
- [x] vom backend + cookbook — [#125](https://github.com/egao1980/cl-stack/issues/125) · [cookbooks/logging.md](../cookbooks/logging.md)

**Order:** serdes → log imports → log-protocol. Still after CLI (#119–#121) unless serdes is pulled earlier for http sexp — prefer **serdes just before logging**.

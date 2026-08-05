# serdes-protocol (P2)

**Issues:** [#132](https://github.com/egao1980/cl-stack/issues/132) · impl [#133](https://github.com/egao1980/cl-stack/issues/133)  
**Status:** brief **locked** — CLOS protocol; **implemented by** format protocols (`json-protocol`, sexp, …)

Generic **ser**ialize / **des**erialize of Lisp values ↔ string or octets.

**Layering (locked):** `serdes-protocol` is the **interface**. Format stacks **implement** it — they are not wrapped *by* a separate `serdes-backend-json` that calls down into them.

```text
serdes-protocol              ← generics + format dispatch + conditions
    ▲ implemented by
json-protocol (+ jzon/yason) ← RFC 8259; provides serdes methods for :json
sexp-protocol (or system)    ← prin1/read policies; provides serdes methods for :sexp
    ▲ used by
log-protocol / cl-stack-http
```

Conventions: [API.md](../API.md). JSON details: [json-protocol.md](json-protocol.md). Logging: [logging.md](logging.md).

---

## Why

| Need | Approach |
|------|----------|
| One call site for “encode as JSON or SEXP” | `(serdes:encode v :format :json|:sexp)` |
| JSON value rules stay coherent | Owned by **`json-protocol`** (still); it **implements** serdes |
| SEXP without bloating json-* | Separate implementor of serdes |
| Logging structured layouts | Depend on **serdes-protocol** only; load json/sexp implementors |

**Reject:** `serdes-backend-json` as a thin shim *over* json-protocol (extra ASDF hop, wrong ownership).  
**Accept:** json-protocol (when loaded) **is** the JSON serdes implementor.

---

## Prior art

| Ecosystem | Analogue |
|-----------|----------|
| **Rust** | `serde` traits; `serde_json` / other crates **implement** them |
| **Java** | Jackson `JsonSerializer` modules implement a shared API |
| **Python** | codecs / format plugins behind one encode/decode surface |
| **CL stack** | Same as `http-protocol` ← backends; here format protocols **are** the backends |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | Tiny **serdes-protocol** + **implementors** | Interface ≠ wrapper layer |
| **JSON implementor** | **[`json-protocol`](json-protocol.md)** (+ existing jzon/yason backends) | Already shipped; owns `:null` / string keys; adds `defmethod`s on serdes GFs |
| **SEXP implementor** | **`sexp-protocol`** (new, small) or colocated `serdes` sexp system that still **implements** the GFs | Lisp-native wire; not a child of json |
| **No** | Separate `serdes-backend-json` package that depends on json-protocol and re-exports | Wrong direction of dependency |
| **DX** | `(serdes:encode value :format :json)` / `:sexp` | Format keyword resolves to implementor backend object |
| **Registration** | Load implementor ASDF → installs into format table / sets methods on backend class | Same “load backend” DX as http/json |
| **json-protocol public API** | **Keep** `stack-json:encode` / `decode` | Serdes is the generic façade; json API remains for JSON-only call sites |
| **Dependency direction** | `json-protocol` **depends on** `serdes-protocol` (implements it) | Not the reverse |
| **SEXP policies** | `*read-eval* nil` on decode; package policy on encode; circularity → error | Safe-ish logs/IPC |
| **SEXP value subset** | Prefer json-shaped data (hash-tables, vectors, … `:null`) | Round-trip parity with JSON logs |
| **Octets** | UTF-8 via Babel for text formats | |
| **Not wave-1** | msgpack, edn, yaml, cl-store, protobuf | Future **implementors** of serdes |
| **Selection** | `:format` keyword and/or `*serdes-backend*` | Load `json-backend-jzon` (via json-protocol) or sexp implementor |

---

## Repo layout

| Layer | Repo / system | Role |
|-------|----------------|------|
| Interface | `egao1980/serdes-protocol` (`stack-serdes`) | GFs, conditions, format registry, `encode`/`decode` |
| JSON implementor | existing `egao1980/json-protocol` | `depends-on` serdes-protocol; `defmethod backend-encode/decode` for JSON backend class |
| SEXP implementor | `egao1980/sexp-protocol` (or system inside serdes repo **named** as implementor, not “backend wrapper over json”) | same pattern |

Bump `json-protocol` minor when it grows the serdes dependency + methods.

---

## Protocol surface (`serdes-protocol`)

```lisp
(defclass serdes-backend () ())
(defvar *serdes-format* :json)
(defvar *serdes-backend* nil)

(defgeneric backend-encode (backend value &key stream))
(defgeneric backend-decode (backend source &key))

;; Format registry — implementors register on load
(defun register-format (format backend) …)
(defun find-backend (format) …)

(defun encode (value &key (format *serdes-format*) stream (backend (find-backend format)))
  …)
(defun decode (source &key (format *serdes-format*) (backend (find-backend format)))
  …)
```

### JSON implementor (in `json-protocol`)

```lisp
;; json-protocol.asd :depends-on ("serdes-protocol" …)
(defclass json-serdes-backend (serdes:serdes-backend) ())
(defmethod serdes:backend-encode ((b json-serdes-backend) value &key stream)
  (json:encode value :stream stream))   ; existing json API
(defmethod serdes:backend-decode ((b json-serdes-backend) source &key)
  (json:decode source))
(serdes:register-format :json (make-instance 'json-serdes-backend))
;; still set by loading json-backend-jzon / yason as today for *json-backend*
```

### SEXP implementor (sketch)

```lisp
(defclass sexp-serdes-backend (serdes:serdes-backend) ())
(defmethod serdes:backend-encode …)  ; prin1 policies
(defmethod serdes:backend-decode …)  ; read, *read-eval* nil
(serdes:register-format :sexp …)
```

### Conditions

```text
serdes-error
├── serdes-encode-error
├── serdes-decode-error
└── serdes-unsupported-format
```

JSON implementor may wrap/resignal `json-error` as `serdes-*-error` or allow both to be visible — prefer **wrap with cause** for log/http callers that only handle serdes.

---

## Consumers

```text
log-protocol     → serdes:encode event :format :json|:sexp
                   (asdf depends on serdes-protocol; app loads json-protocol and/or sexp)
cl-stack-http    → migrate :json / :sexp onto serdes (optional follow-on)
```

---

## Non-goals

- Replacing json-protocol’s public API  
- cl-store object graphs  
- Config TOML/YAML as serdes formats (stays [`cl-stack-config`](config.md))  

---

## Implementation tasks

- [x] Brief lock — [#132](https://github.com/egao1980/cl-stack/issues/132)
- [ ] `serdes-protocol` interface package — [#133](https://github.com/egao1980/cl-stack/issues/133)
- [ ] **`json-protocol` implements serdes** (depend + methods + register `:json`) — part of #133 / json-protocol bump
- [ ] SEXP implementor registers `:sexp` — part of #133
- [ ] Wire `log-protocol` structured layouts — [#124](https://github.com/egao1980/cl-stack/issues/124)

Ship serdes interface + json implementor **before** structured logging.

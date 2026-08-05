# serdes-protocol (P2)

**Issues:** [#132](https://github.com/egao1980/cl-stack/issues/132) · impl [#133](https://github.com/egao1980/cl-stack/issues/133)  
**Status:** brief **locked** — CLOS protocol + **Gray stream GFs from wave-1**; **implemented by** format protocols (`json-protocol`, sexp, …)

Generic **ser**ialize / **des**erialize of Lisp values ↔ string, octets, or **streams**.

**Layering (locked):** `serdes-protocol` is the **interface** (whole-value + Gray streams). Format stacks **implement** it — not wrapped *by* a `serdes-backend-*` shim.

```text
serdes-protocol              ← GFs + Gray stream classes + format registry
    ▲ implemented by (wave-1)
json-protocol (+ jzon/yason) ← :json (+ JSONL streams)
sexp-protocol                ← :sexp (+ stream-*-value)
    ▲ later implementors (same Gray GFs)
xml-protocol / protobuf-… / arrow-… / msgpack-… / …
    ▲ used by
log-protocol / cl-stack-http / …
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
| Later XML / protobuf / Arrow / … | New **implementors**; reuse wave-1 Gray GFs |
| Streaming / pipes / JSONL | **Gray streams in protocol from day one** (`trivial-gray-streams`) — same as http-protocol |

**Reject:** `serdes-backend-json` shim; deferring streams “until Arrow.”  
**Accept:** json-protocol **implements** serdes (value + character Gray + JSONL).

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
| **Gray streams** | **In protocol wave-1** — binary + character base classes; `backend-make-*-stream`; `stream-encode-value` / `stream-decode-value` | http-protocol precedent; Arrow/protobuf specialize later |
| **Wave-1 formats** | `:json`, `:sexp` | Character streams + `stream-*-value` required |
| **Future implementors** | XML, protobuf, Arrow, msgpack, edn, … | § Future implementors |
| **Selection** | `:format` / `*serdes-backend*` | Load json-protocol / sexp-protocol |

---

## Repo layout

| Layer | Repo / system | Role |
|-------|----------------|------|
| Interface | `egao1980/serdes-protocol` (`stack-serdes`) | GFs, Gray stream classes, format registry, conditions |
| JSON implementor | existing `egao1980/json-protocol` | `depends-on` serdes-protocol; whole-value + stream methods |
| SEXP implementor | `egao1980/sexp-protocol` (or colocated implementor system) | same pattern |

Bump `json-protocol` minor when it grows the serdes dependency + methods.

---

## Protocol surface (`serdes-protocol`)

Dep: **`trivial-gray-streams`** (pin via cl-stack-systems — already in tree).

### Whole-value

```lisp
(defclass serdes-backend () ())
(defvar *serdes-format* :json)
(defvar *serdes-backend* nil)

(defgeneric backend-encode (backend value &key stream)
  (:documentation "Encode VALUE. If STREAM given, write there (character or binary per backend); else → string or octets."))
(defgeneric backend-decode (backend source &key)
  (:documentation "SOURCE = string | octets | stream → Lisp value."))

(defun register-format (format backend) …)
(defun find-backend (format) …)

(defun encode (value &key (format *serdes-format*) stream (backend (find-backend format))) …)
(defun decode (source &key (format *serdes-format*) (backend (find-backend format))) …)
(defun encode-to-octets (value &key format) …)
(defun decode-octets (octets &key format) …)
```

### Gray streams (wave-1 — required)

Protocol owns base classes + factory / value-stream GFs. Implementors specialize Gray methods (`stream-read-byte`, `stream-write-byte`, `stream-read-sequence`, `stream-write-sequence`, `stream-read-char`, … as applicable) and the value GFs.

```lisp
;;; Binary (protobuf / Arrow / msgpack later; also UTF-8 octet pipes)
(defclass serdes-binary-input-stream
    (trivial-gray-streams:fundamental-binary-input-stream) …)
(defclass serdes-binary-output-stream
    (trivial-gray-streams:fundamental-binary-output-stream) …)

;;; Character (JSON / SEXP text)
(defclass serdes-character-input-stream
    (trivial-gray-streams:fundamental-character-input-stream) …)
(defclass serdes-character-output-stream
    (trivial-gray-streams:fundamental-character-output-stream) …)

(defgeneric backend-make-input-stream (backend underlying &key element-type)
  (:documentation "Wrap UNDERLYING input stream; element-type :character | '(unsigned-byte 8)."))
(defgeneric backend-make-output-stream (backend underlying &key element-type)
  (:documentation "Wrap UNDERLYING output stream for encoded writes."))

;;; Value-at-a-time (JSONL / one-sexp-per-line / framed records)
(defgeneric stream-encode-value (stream value &key)
  (:documentation "Write one VALUE to a serdes output stream (e.g. one JSON line)."))
(defgeneric stream-decode-value (stream &key)
  (:documentation "Read one value from a serdes input stream, or :eof."))

;; Façade
(defun make-input-stream (underlying &key (format *serdes-format*) element-type) …)
(defun make-output-stream (underlying &key (format *serdes-format*) element-type) …)
```

**Wave-1 implementor bar:**

| Format | Whole-value | Gray wrap | `stream-*-value` |
|--------|-------------|-----------|------------------|
| `:json` | required | character streams required | required (JSONL) |
| `:sexp` | required | character streams required | required (one form / line or `read` framing) |

Binary Gray classes ship in protocol even if json/sexp only use character streams — protobuf/Arrow plug in without relocating base classes.

### JSON implementor (in `json-protocol`)

```lisp
;; json-protocol.asd :depends-on ("serdes-protocol" …)
(defclass json-serdes-backend (serdes:serdes-backend) ())
(defmethod serdes:backend-encode ((b json-serdes-backend) value &key stream) …)
(defmethod serdes:backend-decode ((b json-serdes-backend) source &key) …)
(defmethod serdes:backend-make-output-stream ((b json-serdes-backend) underlying &key element-type) …)
(defmethod serdes:backend-make-input-stream ((b json-serdes-backend) underlying &key element-type) …)
;; Gray methods + stream-encode-value / stream-decode-value for JSONL
(serdes:register-format :json (make-instance 'json-serdes-backend))
```

### SEXP implementor (sketch)

```lisp
(defclass sexp-serdes-backend (serdes:serdes-backend) ())
;; prin1/read policies + character Gray streams + stream-*-value
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

## Future implementors (explicitly in scope later)

Same contract as json/sexp — **implement** serdes, don’t wrap it:

| Format | Notes (when we get there) |
|--------|---------------------------|
| **XML** | After CSV/XML gap work; value mapping TBD (DOM vs event vs map-shaped) |
| **Protobuf** | Likely ties to `cl-protobufs` / overlays; binary octets path first-class |
| **Apache Arrow** | Columnar IPC/flight on **binary** Gray streams + `stream-*-value` / sequence ops already in protocol |
| MessagePack / EDN / CBOR | Compact / Lisp-adjacent |
| Avro / Cap’n Proto | Only if demand; same registration pattern |

No second streaming façade — Arrow/protobuf **specialize** the wave-1 Gray GFs.

## Non-goals (wave-1)

- Replacing json-protocol’s public API  
- Shipping XML / protobuf / Arrow implementors in this wave  
- Full pull-parser / SAX event APIs (XML implementor may add later)  
- cl-store object graphs  
- Config TOML as a serdes format (stays [`cl-stack-config`](config.md))  

---

## Implementation tasks

- [x] Brief lock — [#132](https://github.com/egao1980/cl-stack/issues/132)
- [ ] `serdes-protocol` interface: whole-value GFs + **Gray stream classes/GFs** — [#133](https://github.com/egao1980/cl-stack/issues/133)
- [ ] **`json-protocol` implements serdes** (value + character streams + JSONL) — part of #133 / json bump
- [ ] SEXP implementor (value + character streams) — part of #133
- [ ] Wire `log-protocol` structured layouts — [#124](https://github.com/egao1980/cl-stack/issues/124)

Ship serdes interface (incl. Gray streams) + json implementor **before** structured logging.

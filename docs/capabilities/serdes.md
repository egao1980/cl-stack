# serdes-protocol (P2)

**Issues:** [#132](https://github.com/egao1980/cl-stack/issues/132) · impl [#133](https://github.com/egao1980/cl-stack/issues/133)  
**Status:** wave-1 **shipped** — `serdes-protocol` OCI **0.2.1** / `sexp-protocol` **0.2.0**; `json-protocol` OCI **0.2.0** implements `:json` (JSONL + event pull). [`csv-protocol`](csv-protocol.md) OCI **0.1.0** implements `:csv` / `:tsv`. [`xml-protocol`](xml-protocol.md) OCI **0.1.0** implements `:xml`. [`arrow-protocol`](arrow.md) OCI **0.1.0** implements `:arrow` / `:parquet`. [`protobuf-protocol`](protobuf.md) OCI **0.2.0** implements `:protobuf`.

Generic **ser**ialize / **des**erialize of Lisp values ↔ string, octets, or **streams**.

**Layering (locked):** `serdes-protocol` is the **format** interface (whole-value + Gray/JSONL/events). Format stacks **implement** it — not wrapped *by* a `serdes-backend-*` shim.

**Not ObjectInput/Output:** Java-like object streams live in [`io-protocol`](io.md) — a **CLOS shell with no serdes reference**. Adapters that bridge the two are optional and out of both cores.

```text
serdes-protocol              ← GFs + Gray stream classes + format registry
    ▲ implemented by (wave-1)
json-protocol (+ jzon/yason) ← :json (+ JSONL streams)
sexp-protocol                ← :sexp (+ stream-*-value)
csv-protocol                 ← :csv / :tsv (dialects + row streams + events)
xml-protocol (+ native)      ← :xml (Infoset + events + writer)
arrow-protocol               ← :arrow (IPC) + :parquet
protobuf-protocol            ← :protobuf (octets + proto3 JSON / WKT)
    ▲ later implementors (same Gray GFs)
msgpack-… / edn / cbor / …
    ▲ used by
log-protocol / cl-stack-http / …
```

Conventions: [API.md](../API.md). JSON details: [json-protocol.md](json-protocol.md). Logging: [logging.md](logging.md).  
**Cookbook:** [cookbooks/serdes.md](../cookbooks/serdes.md).

---

## Why

| Need | Approach |
|------|----------|
| One call site for “encode as JSON or SEXP” | `(serdes:encode v :format :json|:sexp)` |
| JSON value rules stay coherent | Owned by **`json-protocol`** (still); it **implements** serdes |
| SEXP without bloating json-* | Separate implementor of serdes |
| Logging structured layouts | Depend on **serdes-protocol** only; load json/sexp implementors |
| Later msgpack / EDN / CBOR / Avro | New **implementors**; reuse wave-1 Gray GFs |
| Streaming / pipes | **Gray streams from day one** + **JSONL** + **event/pull JSON** (large files) |

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
| **Future implementors** | msgpack, EDN, CBOR, Avro, … | § Future implementors |
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
  (:documentation "Write one VALUE (e.g. one JSON line + newline)."))
(defgeneric stream-decode-value (stream &key)
  (:documentation "Read one complete value, or :eof. JSONL = one JSON value per line."))

;; Façade
(defun make-input-stream (underlying &key (format *serdes-format*) element-type) …)
(defun make-output-stream (underlying &key (format *serdes-format*) element-type) …)

;;; JSONL convenience (format :json — required for json implementor)
(defun map-jsonl (function source &key (format :json))
  "Call FUNCTION with each decoded top-level value from a JSONL SOURCE (stream/path/string).")
(defmacro do-jsonl ((var source &key format) &body body) …)
```

### Event / pull parse (large single documents) — protocol GFs, json implements

For multi‑GB **one** JSON value (array/object), whole-value `decode` is wrong. Protocol owns a SAX-like pull API; **json-protocol** implements via jzon `parse-next` (already streaming).

```lisp
(defclass serdes-event-parser () ())

(defgeneric backend-make-event-parser (backend source &key max-depth max-string-length)
  (:documentation "SOURCE = stream | pathname | octets | string."))
(defgeneric parse-next-event (parser)
  (:documentation "→ (values event value). EVENT nil at EOF.
Events (JSON, jzon-aligned): :begin-array :end-array :begin-object :end-object
  :object-key :value  (value carries string/number/bool/null for scalars)."))
(defgeneric parse-next-element (parser &key)
  (:documentation "Optional: consume next complete sub-value as one Lisp object (jzon:parse-next-element)."))

(defun make-event-parser (source &key (format *serdes-format*) &allow-other-keys) …)
(defmacro with-event-parser ((var source &key format) &body body) …)
(defun map-events (function source &key format) …)
```

**Wave-1 vs follow-on:**

| Capability | Wave-1 (#133) | Follow-on (event JSON / large files) |
|------------|---------------|--------------------------------------|
| Whole-value encode/decode | required | — |
| Gray character streams | required | — |
| **JSONL** `stream-*-value` + `map-jsonl` / `do-jsonl` | **required** (json) | harden pathnames, backpressure notes |
| **Event/pull** `parse-next-event` | GFs **in protocol** (stubs OK) | **json implementor required** — jzon parser |
| Event writer (streaming encode) | optional | jzon writer / symmetric API |

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

| Format | Notes |
|--------|-------|
| **CSV** | **Shipped** — [`csv-protocol`](csv-protocol.md) OCI **0.1.0**; dialects; row streams; events |
| **XML** | **Shipped** — [`xml-protocol`](xml-protocol.md) **0.1.0** + `xml-backend-native` (Infoset + events + writer) |
| **Protobuf** | **Shipped** — [`protobuf-protocol`](protobuf.md) **0.2.0** + cl-protobufs **0.2.0**; octets + proto3 JSON / WKT |
| **Apache Arrow** | **Shipped** — [`arrow-protocol`](arrow.md) (`stack-arrow`) native IPC + Parquet subset; serdes `:arrow` / `:parquet`. Flight / C Data Interface later. |
| MessagePack / EDN / CBOR | Compact / Lisp-adjacent — **later** |
| Avro / Cap’n Proto | Only if demand; same registration pattern |

No second streaming façade — Arrow/protobuf **specialize** the wave-1 Gray GFs.

## Non-goals (wave-1)

- Replacing json-protocol’s public API  
- Shipping msgpack / EDN / CBOR implementors (CSV / XML / Arrow / protobuf have their own briefs)  
- Building a full in-memory DOM for huge files (use events / JSONL instead)  
- cl-store object graphs  
- Config TOML as a serdes format (stays [`cl-stack-config`](config.md))  

---

## Implementation tasks

- [x] Brief lock — [#132](https://github.com/egao1980/cl-stack/issues/132)
- [x] `serdes-protocol` whole-value + format registry + Gray streams — [#133](https://github.com/egao1980/cl-stack/issues/133) ([repo](https://github.com/egao1980/serdes-protocol) **0.2.1**)
- [x] **JSONL helpers** + **event-parser GFs** — `map-jsonl` / `do-jsonl` / `stream-*-value`
- [x] **`json-protocol` hard-depends / implements serdes** (value + JSONL) — **0.2.0**
- [x] **json event/pull parser** (jzon `parse-next`) — [#138](https://github.com/egao1980/cl-stack/issues/138)
- [x] SEXP implementor (whole-value + line streams) — `sexp-protocol` **0.2.0**
- [x] **CSV implementor** — `csv-protocol` **0.1.0** (`:csv` / `:tsv`)
- [x] **XML implementor** — `xml-protocol` **0.1.0** + `xml-backend-native` (Infoset + events + writer)
- [x] **Protobuf implementor** — `protobuf-protocol` **0.2.0** + `protobuf-backend-cl-protobufs` **0.2.0**
- [x] Wire `log-protocol` structured layouts — [#124](https://github.com/egao1980/cl-stack/issues/124)

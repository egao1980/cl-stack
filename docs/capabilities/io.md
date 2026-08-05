# io-protocol (P2)

**Issues:** [#140](https://github.com/egao1980/cl-stack/issues/140)  
**Status:** brief **locked** — **CLOS shell only** (ObjectInput / ObjectOutput–like streams)

Portable **object streams**: read/write Lisp values on Gray streams. **No format, no serdes, no JSON.** Pure protocol classes + generics. Apps (or later adapters) choose how `read-object` / `write-object` are implemented.

[`serdes-protocol`](serdes.md) stays a **separate** capability (format encode/decode, JSONL, event parse). **io-protocol does not reference serdes.**

Conventions: [API.md](../API.md). Gray streams: `trivial-gray-streams` (stack pin).

---

## Prior art

| Ecosystem | Analogue |
|-----------|----------|
| **Java** | `ObjectInput` / `ObjectOutput` (+ `ObjectInputStream` / `ObjectOutputStream`) — typed object I/O over a byte stream |
| **Java** | `DataInput` / `DataOutput` — primitives (optional later on same shell) |
| **CL** | Gray streams (`trivial-gray-streams`); no std ObjectInput |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | **Protocol only** — classes + GFs | No backends, no format registry, no serdes dep |
| **DX** | `(read-object stream)` / `(write-object stream value)` | Java ObjectInput/Output shape |
| **Stream classes** | CLOS subclasses of Gray fundamental streams | Portable; Windows-primary |
| **Serdes** | **Out of scope for this protocol** | Wiring format codecs is app/adapter layer, not io-protocol |
| **Default methods** | None that encode JSON/sexp | Empty shell — signal `io-unimplemented` if not specialized |
| **Element types** | Binary and character object-stream variants | Match Gray split; both expose `read-object` / `write-object` |
| **Underlying stream** | Slot / constructor arg | Wrap file/socket/memory stream |
| **Not in wave-1** | DataInput primitives, Java serialization semantics, cl-store | Optional follow-ons |

---

## Layering (locked)

```text
io-protocol          ← ObjectInput/Output-like CLOS shell (THIS)
                       NO dependency on serdes-protocol

serdes-protocol      ← format codecs (JSON/sexp/…); separate track
json-protocol        ← implements serdes

;; Optional later (NOT part of io-protocol):
;;   adapter lib that specializes read-object/write-object using serdes
```

**Reject:** io-protocol `:depends-on serdes-protocol`.  
**Reject:** baking `:format :json` into `make-object-input-stream`.  
**Accept:** thin shell; specialization elsewhere when needed.

---

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol only | `egao1980/io-protocol` (nick `stack-io`) |

No `io-backend-*` in this wave.

---

## Protocol surface

Dep: **`trivial-gray-streams`** only (plus ASDF).

```lisp
(defpackage #:io-protocol
  (:nicknames #:stack-io)
  (:use #:cl)
  (:export #:io-error #:io-unimplemented
           #:object-input-stream #:object-output-stream
           #:binary-object-input-stream #:binary-object-output-stream
           #:character-object-input-stream #:character-object-output-stream
           #:read-object #:write-object
           #:make-object-input-stream #:make-object-output-stream
           #:underlying-stream))

(define-condition io-error (error) …)
(define-condition io-unimplemented (io-error) …)

;;; Shell classes — wrap an underlying Gray/CL stream
(defclass object-input-stream ()
  ((underlying :initarg :underlying :reader underlying-stream)))
(defclass object-output-stream ()
  ((underlying :initarg :underlying :reader underlying-stream)))

(defclass binary-object-input-stream
    (object-input-stream
     trivial-gray-streams:fundamental-binary-input-stream) …)
(defclass binary-object-output-stream
    (object-output-stream
     trivial-gray-streams:fundamental-binary-output-stream) …)
(defclass character-object-input-stream
    (object-input-stream
     trivial-gray-streams:fundamental-character-input-stream) …)
(defclass character-object-output-stream
    (object-output-stream
     trivial-gray-streams:fundamental-character-output-stream) …)

(defgeneric read-object (stream &key)
  (:documentation "→ next Lisp object, or :eof. Default: signal io-unimplemented."))
(defgeneric write-object (stream object &key)
  (:documentation "Write OBJECT. Default: signal io-unimplemented."))

(defun make-object-input-stream (underlying &key (element-type 'character))
  "Return an unspecialized shell stream. Callers subclass or mixin methods.")
(defun make-object-output-stream (underlying &key (element-type 'character)) …)
```

Gray byte/char methods on the shell may **delegate** to `underlying-stream` (pass-through) so the object stream *is* a usable stream; `read-object` / `write-object` stay unimplemented until something specializes them.

### Conditions

```text
io-error
└── io-unimplemented     ; read-object/write-object not specialized
```

---

## Non-goals

- Format selection (`:json`, `:sexp`, …)  
- Any import of / mention of serdes in `.asd` or API  
- Java `Serializable` / handle tables / class descriptors  
- Replacing http-protocol body Gray streams  

---

## Implementation tasks

- [x] Brief lock (this doc) — [#140](https://github.com/egao1980/cl-stack/issues/140)
- [ ] Repo `io-protocol`: classes + GFs + pass-through Gray delegation + Rove (unimplemented signals; wrap memory stream)
- [ ] OCI + pin
- [ ] Optional later: external adapter (separate system) that specializes via serdes — **not** required for io Done-when

---

## Cookbook (later)

```lisp
(asdf:load-system "io-protocol")
;; Shell only — read-object signals until an adapter specializes:

(with-open-file (raw "data.bin" :element-type '(unsigned-byte 8))
  (let ((in (stack-io:make-object-input-stream raw :element-type '(unsigned-byte 8))))
    (stack-io:read-object in)))  ; → io-unimplemented unless specialized
```

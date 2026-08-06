# io-protocol (P2)

**Issues:** [#140](https://github.com/egao1980/cl-stack/issues/140)  
**Status:** wave-1 **shipped** — OCI **0.1.0** · **CLOS shell** + default **print/read** (ObjectInput / ObjectOutput–like)

Portable **object streams**: `read-object` / `write-object` on Gray streams. **No serdes, no JSON.** Default = CL readable **print** / **read** (repr-like). Specialize when you need another wire form.

[`serdes-protocol`](serdes.md) stays **separate**. **io-protocol does not reference serdes.**

Conventions: [API.md](../API.md). Gray streams: `trivial-gray-streams`.

---

## Prior art

| Ecosystem | Analogue |
|-----------|----------|
| **Java** | `ObjectInput` / `ObjectOutput` |
| **Python** | `repr` / `eval` — CL analogue is `prin1` / `read` (REPL) |
| **CL** | `prin1` + `read` as in the REPL; Gray streams |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | Protocol — classes + GFs | No format registry; no serdes dep |
| **DX** | `(read-object stream)` / `(write-object stream value)` | Java ObjectInput/Output |
| **Default `write-object`** | **`prin1`** to stream (+ trailing whitespace separator) | Usable out of the box; Lisp-native print |
| **Default `read-object`** | Plain **`read`** (same as REPL) — ambient `*package*` / `*read-eval*`; EOF → `:eof` | No sanitizing; caller owns dynamics |
| **Package / reader dynamics** | **Leave ambient** (whatever the REPL/caller has bound) | Matches `read` / `prin1` at the REPL |
| **Circularity / unreadable** | `prin1` signals / fails as today; no custom printer protocol in wave-1 | Keep shell thin |
| **Character streams** | Default print/read on underlying character stream | Primary path |
| **Binary streams** | Default = UTF-8 encode/decode of the same printed text (Babel) then prin1/read | One default story on both element-types; still not serdes |
| **Serdes** | Out of scope | Optional external specialization later |
| **`io-unimplemented`** | Reserved for subclasses that **disable** default print/read | Not the base default anymore |
| **Not wave-1** | DataInput primitives, Java serialization, cl-store | Follow-on |

---

## Layering (locked)

```text
io-protocol          ← object streams + default prin1/read
                       NO serdes-protocol dependency

serdes-protocol      ← separate format track
```

**Reject:** io → serdes.  
**Accept:** default printable Lisp; specialize `read-object`/`write-object` elsewhere when needed.

---

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol | `egao1980/io-protocol` (nick `stack-io`) |

Deps: `trivial-gray-streams`, **`babel`** (UTF-8 for binary default only).

---

## Protocol surface

```lisp
(defpackage #:io-protocol
  (:nicknames #:stack-io)
  (:use #:cl)
  (:export #:io-error #:io-read-error #:io-unimplemented
           #:object-input-stream #:object-output-stream
           #:binary-object-input-stream #:binary-object-output-stream
           #:character-object-input-stream #:character-object-output-stream
           #:read-object #:write-object
           #:make-object-input-stream #:make-object-output-stream
           #:underlying-stream))

(defclass object-input-stream ()
  ((underlying :initarg :underlying :reader underlying-stream)))
(defclass object-output-stream ()
  ((underlying :initarg :underlying :reader underlying-stream)))

;; + Gray binary/character subclasses (delegate byte/char I/O to underlying)

(defgeneric write-object (stream object &key)
  (:documentation "Default on object-output-stream: prin1 + space."))

(defgeneric read-object (stream &key)
  (:documentation "Default on object-input-stream: plain read (REPL); :eof at end."))

(defmethod write-object ((s character-object-output-stream) object &key)
  (prin1 object (underlying-stream s))
  (write-char #\Space (underlying-stream s))
  object)

(defmethod read-object ((s character-object-input-stream) &key)
  (handler-case (read (underlying-stream s))
    (end-of-file () :eof)))

;; binary-*-stream defaults: same via Babel UTF-8 bridge to a string stream
;; (or flexi-streams if already loaded — prefer Babel-only to match stack pins)
```

Gray pass-through for `stream-read-byte` / `stream-write-char` / … onto `underlying-stream` unchanged.

### Conditions

```text
io-error
├── io-read-error          ; unreadable / reader error
└── io-unimplemented       ; explicit opt-out / abstract subclass
```

---

## Non-goals

- Format selection (`:json`, …) inside io-protocol  
- serdes in `.asd` or exports  
- Guaranteeing round-trip for all CLOS instances (only what `prin1`/`read` already do)  
- Replacing http-protocol body streams  

---

## Implementation tasks

- [x] Brief lock — [#140](https://github.com/egao1980/cl-stack/issues/140)
- [x] Repo `io-protocol`: classes + **default prin1/read** + binary UTF-8 bridge + Rove round-trip
- [x] OCI + pin — `ghcr.io/egao1980/cl-systems/io-protocol:0.1.0`

---

## Cookbook

```lisp
(asdf:load-system "io-protocol")

(with-output-to-string (raw)
  (let ((out (stack-io:make-object-output-stream raw)))
    (stack-io:write-object out '(:a 1))
    (stack-io:write-object out "hi"))
  ;; raw => "(:A 1) \"hi\" "
  )

(with-input-from-string (raw "(:A 1) \"hi\"")
  (let ((in (stack-io:make-object-input-stream raw)))
    (list (stack-io:read-object in)
          (stack-io:read-object in)
          (stack-io:read-object in))))
;; => ((:A 1) "hi" :EOF)
```

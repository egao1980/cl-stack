# Cookbook: object streams (`io-protocol`)

**Audience:** Java `ObjectInput` / `ObjectOutput` or “write Lisp values to a stream” — not JSON/format codecs.

**Package:** [`io-protocol`](https://github.com/egao1980/io-protocol) (`stack-io`) · OCI **0.1.0**

Capability brief: [io.md](../capabilities/io.md). Format codecs → [serdes cookbook](serdes.md).

```lisp
(cl-repo:load-system "io-protocol" :version "0.1.0")
;; nick: stack-io
```

**No serdes dependency.** Default wire form is CL `prin1` / `read` (REPL-shaped). Specialize `read-object` / `write-object` elsewhere when you need another representation.

---

## 1. Character streams

```lisp
(asdf:load-system "io-protocol")

(with-output-to-string (raw)
  (let ((out (stack-io:make-object-output-stream raw)))
    (stack-io:write-object out '(:a 1))
    (stack-io:write-object out "hi")))
;; ⇒ "(:A 1) \"hi\" "

(with-input-from-string (raw "(:A 1) \"hi\"")
  (let ((in (stack-io:make-object-input-stream raw)))
    (list (stack-io:read-object in)
          (stack-io:read-object in)
          (stack-io:read-object in))))
;; ⇒ ((:A 1) "hi" :EOF)
```

| Call | Behavior |
|------|----------|
| `write-object` | `prin1` + trailing space |
| `read-object` | plain `read`; EOF → `:eof` |
| Package / `*read-eval*` | **ambient** — caller owns dynamics |

Gray pass-through: `read-char` / `write-char` / … hit the underlying stream.

---

## 2. Binary streams

Same printed text, UTF-8 via Babel:

```lisp
(let ((out (stack-io:make-object-output-stream binary-stream
                                               :element-type '(unsigned-byte 8))))
  (stack-io:write-object out 42))

(let ((in (stack-io:make-object-input-stream binary-stream
                                             :element-type '(unsigned-byte 8))))
  (stack-io:read-object in))
```

---

## 3. Opt out of default print/read

Subclass and signal `io-unimplemented` (or provide your own methods):

```lisp
(defclass sealed-out (stack-io:character-object-output-stream) ())

(defmethod stack-io:write-object ((s sealed-out) object &key)
  (declare (ignore object))
  (error 'stack-io:io-unimplemented :message "sealed"))
```

Conditions: `io-error` → `io-read-error` / `io-unimplemented`.

---

## Layer pick

| Need | Use |
|------|-----|
| Lisp-readable object stream | **`io-protocol`** |
| JSON / SEXP / JSONL / event pull | **`serdes-protocol`** (+ json/sexp) |
| Both | keep separate; optional adapter outside both cores |

# Cookbook: serdes (JSON / SEXP / XML / JSONL / events)

**Audience:** one call site for “encode as JSON or SEXP”, log shipping (JSONL), or SAX-like pull over large JSON/XML.

**Packages:**

| Layer | Role | OCI |
|-------|------|-----|
| [`serdes-protocol`](https://github.com/egao1980/serdes-protocol) (`stack-serdes`) | GCF registry, Gray streams, JSONL, event GFs | **0.2.1** |
| `sexp-protocol` (same repo) | `:sexp` implementor | **0.2.0** |
| [`json-protocol`](https://github.com/egao1980/json-protocol) + `json-backend-jzon` | `:json` implementor (value + JSONL + events) | **0.2.0** |
| [`csv-protocol`](https://github.com/egao1980/csv-protocol) (`stack-csv`) | `:csv` / `:tsv` (dialects, row streams, events) | **0.1.0** |
| [`xml-protocol`](https://github.com/egao1980/xml-protocol) + `xml-backend-native` | `:xml` implementor (Infoset + events + writer) | **0.1.0** |
| [`arrow-protocol`](https://github.com/egao1980/arrow-protocol) (`stack-arrow`) | `:arrow` / `:parquet` | **0.1.0** |

Capability brief: [serdes.md](../capabilities/serdes.md). JSON-only API: [json cookbook](json.md). XML-only API: [xml cookbook](xml.md). Object streams (no formats): [io cookbook](io.md).

```lisp
(cl-repo:load-system "json-backend-jzon" :version "0.2.0")  ; pulls json-protocol + serdes
;; optional:
(cl-repo:load-system "sexp-protocol" :version "0.2.0")
(cl-repo:load-system "csv-protocol" :version "0.1.0")
(cl-repo:load-system "xml-backend-native" :version "0.1.0")
(cl-repo:load-system "arrow-protocol" :version "0.1.0")
```

Load an implementor ASDF → registers `:json` / `:sexp` / `:csv` / `:tsv` / `:xml` / `:arrow` / `:parquet`. Logging structured path depends on `serdes-protocol` only; the app loads the format it wants. CSV dialects: [csv cookbook](csv.md).

---

## Value mapping (JSON-shaped)

| Wire | Lisp |
|------|------|
| object | hash-table (`equal`), **string** keys |
| array | vector |
| `null` | `:null` |
| `false` / `true` | `nil` / `t` |

SEXP uses the same shape (`:object` lists under the hood); decode binds `*read-eval*` to `nil`.

---

## 1. Whole-value encode / decode

```lisp
(asdf:load-system "json-backend-jzon")

(let ((ht (make-hash-table :test 'equal)))
  (setf (gethash "msg" ht) "hi"
        (gethash "n" ht) :null)
  (stack-serdes:encode ht :format :json))
;; ⇒ "{\"msg\":\"hi\",\"n\":null}"

(stack-serdes:decode "{\"ok\":false}" :format :json)
;; ⇒ hash-table, "ok" → NIL

(asdf:load-system "sexp-protocol")
(stack-serdes:encode ht :format :sexp)
(stack-serdes:decode-octets (stack-serdes:encode-to-octets ht :format :json)
                            :format :json)
```

| Call | Notes |
|------|-------|
| `encode` / `decode` | `:format` → registered backend (`*serdes-format*` default `:json`) |
| `encode-to-octets` / `decode-octets` | UTF-8 via Babel |
| `register-format` / `find-backend` | load-time install from implementors |

JSON-only call sites can keep using `stack-json:encode` / `decode` — serdes is the generic façade.

---

## 2. JSONL (one value per line)

```lisp
(asdf:load-system "json-backend-jzon")

(let ((raw (with-output-to-string (o)
             (let ((out (stack-serdes:make-output-stream o :format :json)))
               (stack-serdes:stream-encode-value out 1)
               (let ((ht (make-hash-table :test 'equal)))
                 (setf (gethash "k" ht) "v")
                 (stack-serdes:stream-encode-value out ht))))))
  ;; raw => "1\n{\"k\":\"v\"}\n"
  (stack-serdes:map-jsonl #'print raw :format :json))

(stack-serdes:do-jsonl (v raw :format :json)
  (format t "~&got ~S~%" v))
```

Works for `:sexp` too (one readable form per line). Source may be a stream, string, octets, or pathname.

---

## 3. Event / pull parse (large single JSON)

Never build a full DOM for multi‑GB arrays/objects — walk tokens:

```lisp
(asdf:load-system "json-backend-jzon")

(let ((parser (stack-serdes:make-event-parser "[1,null,true]" :format :json)))
  (loop
    (multiple-value-bind (event value) (stack-serdes:parse-next-event parser)
      (unless event (return))
      ;; event: :begin-array :end-array :begin-object :end-object
      ;;        :object-key :value  (nil at EOF)
      (format t "~&~S ~S~%" event value))))

(stack-serdes:map-events
 (lambda (event value) …)
 "[{\"a\":1}]"
 :format :json)
```

Optional: `parse-next-element` → next complete sub-value as one Lisp object (jzon).  
`:sexp` does not implement events — signals `serdes-error`.

---

## 4. Gray streams

```lisp
(let ((out (stack-serdes:make-output-stream some-char-stream :format :json)))
  (stack-serdes:stream-encode-value out payload)
  (write-char #\Space out))   ; pass-through to underlying
```

Binary Gray classes: json/sexp use character streams; [`arrow-protocol`](../capabilities/arrow.md) uses binary (`:arrow` IPC stream / `:parquet` file).

---

## 5. Arrow / Parquet

```lisp
(cl-repo:load-system "arrow-protocol" :version "0.1.0")

(let* ((schema (stack-arrow:make-arrow-schema
                (list (stack-arrow:make-arrow-field :name "n" :type :int32)
                      (stack-arrow:make-arrow-field :name "s" :type :utf8))))
       (table (stack-arrow:table-from-rows
               (list (alexandria:plist-hash-table '("n" 1 "s" "a") :test #'equal))
               :schema schema)))
  (stack-serdes:encode table :format :arrow)
  (stack-serdes:encode table :format :parquet))
```

`:arrow` whole-value = IPC **file**. `stream-*-value` = IPC **stream** (schema on first write, one record batch per value, EOS on close). `:parquet` is file-only — `stream-*-value` signals.

`defschema` → Arrow schema + table↔objects: load [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) and call `table-from-objects` / `objects-from-table`. Do not rely on `dump obj :format :arrow` to wrap a single object as a 1-row table.

---

## Layer pick

| Need | Use |
|------|-----|
| JSON only, existing API | `stack-json:encode` / `decode` |
| CSV / TSV / dialects | [`csv-protocol`](csv.md) (`:csv` / `:tsv`) |
| Format keyword / logging / multi-format | **`serdes-protocol`** |
| Line-oriented records | JSONL `stream-*-value` / `map-jsonl` |
| Huge single JSON | event parser |
| Lisp object streams (no format) | [`io-protocol`](io.md) |

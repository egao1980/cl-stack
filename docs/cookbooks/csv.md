# Cookbook: CSV (encode / decode / streams / dialects)

**Audience:** Python `csv` / `csv.DictReader` users who want one Lisp API.

**Package:** [`csv-protocol`](https://github.com/egao1980/csv-protocol) (`stack-csv`) — implements [serdes](serdes.md) `:csv` / `:tsv`.

Brief: [csv-protocol.md](../capabilities/csv-protocol.md).

```lisp
(cl-repo:load-system "csv-protocol" :version "0.1.0")
;; nick: stack-csv — registers serdes :csv and :tsv
```

---

## Value mapping

| Wire | Lisp |
|------|------|
| document | vector of rows |
| row, `:header t` | hash-table (`equal`), string keys |
| row, `:header nil` | vector of strings |
| field | string (`:quoting :nonnumeric` may yield numbers) |

`encode` takes a **sequence of rows** (not a lone hash-table).

---

## 1. Round-trip

```lisp
(stack-csv:decode "name,age
alice,30")
;; ⇒ #(#<hash-table "name"→"alice" "age"→"30">)

(stack-csv:encode '(#("a" "b") #("1" "2")) :header nil)
;; ⇒ "a,b\r\n1,2\r\n"
```

---

## 2. Dialects

Presets: `:rfc4180` (default), `:excel`, `:excel-tab` / `:tsv`, `:excel-eu` (`;`), `:unix`.

```lisp
(stack-csv:encode rows :dialect :excel-eu)
(stack-csv:encode rows :delimiter #\| :quoting :all)
(stack-csv:encode rows :dialect :excel :line-terminator (string #\Newline))
```

Overrides after `:dialect` win. Invalid combo (`:quoting :none` without `escape-char`, delimiter = quote-char) signals `csv-error`.

Serdes façade does **not** take dialect kwargs:

```lisp
(let ((csv-protocol:*csv-dialect* :tsv))
  (serdes-protocol:encode rows :format :csv))
(serdes-protocol:encode rows :format :tsv)
```

---

## 3. Streaming (one row)

Quoted fields may contain newlines — do **not** `read-line`.

```lisp
(let ((out (stack-csv:make-csv-output-stream s :header t :dialect :excel-eu)))
  (serdes-protocol:stream-encode-value out '(("name" . "alice"))))

(let ((in (stack-csv:make-csv-input-stream s :header t)))
  (loop for row = (serdes-protocol:stream-decode-value in)
        until (eq row :eof)
        do (print row)))
```

---

## 4. Event / pull

```lisp
(let ((p (stack-csv:make-csv-event-parser source)))
  (loop
    (multiple-value-bind (event value) (serdes-protocol:parse-next-event p)
      (unless event (return))
      ;; :header :begin-row :field :end-row
      (print (list event value)))))
```

`parse-next-element` → next complete row.

# Cookbook: JSON (encode / decode / HTTP)

**Audience:** Python `json` / httpx `r.json()` users who want one Lisp API.

**Packages:**

| Layer | Role |
|-------|------|
| [`json-protocol`](https://github.com/egao1980/json-protocol) (`stack-json`) | encode / decode contract |
| `json-backend-jzon` | **default** — [jzon](https://github.com/Zulu-Inuoe/jzon) |
| `json-backend-yason` | alternate — [yason](https://github.com/phmarek/yason) |
| [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) | `:json` / `response-json` (uses protocol) |

Brief: [json-protocol.md](../capabilities/json-protocol.md).

```lisp
(cl-repo:load-system "json-backend-jzon" :version "0.2.0")
;; nick: stack-json — also registers serdes :json (see [serdes cookbook](serdes.md))
```

---

## Value mapping

| JSON | Lisp |
|------|------|
| object | hash-table (`equal`), **string** keys |
| array | vector |
| `null` | `:null` |
| `false` / `true` | `nil` / `t` |

Encoding `nil` → JSON `false`. Pass `:null` for JSON null.

---

## 1. Round-trip

```lisp
(asdf:load-system "json-backend-jzon")   ; sets *json-backend*

(stack-json:encode '(("a" . 1) ("b" . :null) ("ok" . t)))
;; => "{\"a\":1,\"b\":null,\"ok\":true}"

(let ((v (stack-json:decode "{\"a\":false,\"xs\":[1,2]}")))
  (list (gethash "a" v)                 ; => NIL
        (stack-json:null-p (gethash "missing" v)) ; missing key → NIL, not :null
        (aref (gethash "xs" v) 0)))     ; => 1
```

Octets (HTTP bodies):

```lisp
(stack-json:encode-to-octets ht)
(stack-json:decode-octets octets)
```

---

## 2. HTTP JSON body

With [`cl-stack-http`](https://github.com/egao1980/cl-stack-http) **0.1.8+** (jzon via protocol):

```lisp
(cl-repo:load-system "cl-stack-http" :version "0.1.8")
(stack-http:with-backend (:async)       ; or :dexador / :auto
  (let ((res (stack-http:post "https://httpbingo.org/post"
                              :json '(("q" . "hi")))))
    (stack-http:response-json res)))    ; hash-table; null → :null
```

Escape hatch — bind yason instead:

```lisp
(asdf:load-system "json-backend-yason")  ; sets *json-backend*
(stack-json:install-http-json-hooks)
```

---

## 3. Via serdes (JSONL / events / `:format :json`)

```lisp
(asdf:load-system "json-backend-jzon")

(stack-serdes:encode ht :format :json)
(stack-serdes:map-jsonl #'print jsonl-source :format :json)

(let ((p (stack-serdes:make-event-parser huge-json :format :json)))
  (loop (multiple-value-bind (ev val) (stack-serdes:parse-next-event p)
          (unless ev (return))
          …)))
```

Full recipes: [serdes.md](serdes.md).

---

## 4. Errors

```lisp
(handler-case (stack-json:decode "{")
  (stack-json:json-parse-error (e)
    (stack-json:json-error-message e)))
```

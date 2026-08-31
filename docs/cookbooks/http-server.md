# Cookbook: HTTP server (Clack app + protocol)

**Audience:** Python Flask/FastAPI / WSGI users who want one Lisp serve path.

**Packages:**

| Layer | Role |
|-------|------|
| [`http-server-protocol`](https://github.com/egao1980/http-server-protocol) (`stack-http-server`) | `serve` / `with-server` / start·stop |
| `http-server-backend-hunchentoot` | **default** — Windows + Unix |
| `http-server-backend-woo` | Unix / libev — call `use-woo-backend` |
| [`json-protocol`](https://github.com/egao1980/json-protocol) | JSON body encode/decode |

Brief: [http-server.md](../capabilities/http-server.md). App contract = **Clack env** → `(status headers body)`.

```lisp
(cl-repo:load-system "http-server-backend-hunchentoot" :version "0.1.0")
(cl-repo:load-system "json-backend-jzon" :version "0.2.0")
;; nick: stack-http-server
```

---

## 1. Minimal GET

```lisp
(asdf:load-system "http-server-backend-hunchentoot")  ; sets *http-server-backend*

(defun app (env)
  (declare (ignore env))
  '(200 (:content-type "text/plain") ("ok")))

(stack-http-server:with-server (s #'app :host "127.0.0.1" :port 8080)
  …)  ; curl http://127.0.0.1:8080/
```

---

## 2. JSON API

```lisp
(asdf:load-system "http-server-backend-hunchentoot")
(asdf:load-system "json-backend-jzon")

(defun %slurp (stream)
  (when stream
    (with-output-to-string (out)
      (loop for c = (read-char stream nil nil)
            while c
            do (write-char c out)))))

(defun app (env)
  (let ((method (getf env :request-method))
        (path (getf env :path-info)))
    (cond
      ((and (eq method :get) (string= path "/health"))
       '(200 (:content-type "text/plain") ("ok")))
      ((and (eq method :post) (string= path "/echo"))
       (let* ((raw (%slurp (getf env :raw-body)))
              (data (stack-json:decode (or raw "{}"))))
         (list 200 '(:content-type "application/json")
               (list (stack-json:encode data)))))
      (t '(404 (:content-type "text/plain") ("nope"))))))

(stack-http-server:with-server (s #'app :port 8080)
  ;; client: (stack-http:post "http://127.0.0.1:8080/echo" :json '(("q" . 1)))
  (sleep most-positive-fixnum))
```

---

## 3. Woo (Unix)

Needs system **libev** (`libev4` / Homebrew `libev`). Does **not** auto-bind — keep Hunchentoot as default.

```lisp
(asdf:load-system "http-server-backend-woo")
(http-server-backend-woo:use-woo-backend)
(stack-http-server:serve #'app :port 8080 :background t)
```

---

## 4. Errors

```lisp
(handler-case (stack-http-server:serve #'app :port 1)  ; privileged / bind fail
  (stack-http-server:http-server-bind-error (e)
    (stack-http-server:http-server-error-message e)))
```

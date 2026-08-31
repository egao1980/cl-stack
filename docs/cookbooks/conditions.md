# Cookbook: conditions + restarts

**Audience:** map HTTP / FS / subprocess failures onto CLHS 9 — not status codes, not Java exceptions.

Brief: [conditions.md](../capabilities/conditions.md) (#107).

Signal a condition. Detection signals; the lowest frame that can recover establishes **restarts**; callers install **policy** with `handler-bind`.

```lisp
;; Policy — stack still live
(handler-bind ((stack-pathlib:path-not-found
                (lambda (c) (use-value #() c))))
  (stack-pathlib:read-bytes path))

;; Unwind / translate only
(handler-case (stack-schema:parse 'card source)
  (stack-schema:schema-validation-error (c)
    (translate c)))
```

---

## 1. Filesystem (`cl-stack-pathlib`, nick `stack-pathlib`)

Gold standard. Domain restarts at the **signal** site; `retry` at the **op** site (`with-path-restarts` / `call-with-path-restarts`).

| Condition | Typical recoveries |
|-----------|-------------------|
| `missing-parent` | `create-parents` then `retry` |
| `path-not-found` | `create-file` / `create-directory` / `ignore-missing` / `use-value` |
| `path-exists-error` | `overwrite` then `retry` |

```lisp
(asdf:load-system "cl-stack-pathlib")

(stack-pathlib:with-auto-create-parents
  (stack-pathlib:mkdir "/deep/nested" :parents nil))   ; CREATE-PARENTS + RETRY

(stack-pathlib:with-auto-create-file
  (stack-pathlib:read-bytes "/new.txt"))               ; empty file + RETRY

(handler-bind ((stack-pathlib:missing-parent
                (lambda (c)
                  (invoke-restart 'create-parents))))
  (stack-pathlib:with-path-restarts
    (stack-pathlib:mkdir "/x/y" :parents nil)))
```

`invoke-create-parents` / `with-auto-*` are sugar over `find-restart`. Call CLHS `use-value` by name.

---

## 2. HTTP (`http-protocol` + `cl-stack-http`)

Taxonomy is the API. Bind on **type**. Status lives in slots. Facade nick is **`stack-http`** (or a local `http` nickname) — not a package named `http`.

| Condition | When |
|-----------|------|
| `http-status-error` → `http-client-error` / `http-server-error` | 4xx / 5xx (`http-status-error-status`, `http-status-error-response`) |
| `http-timeout-error` / `http-connection-error` / `http-tls-error` | transport |
| `http-version-not-available` | `:http/2` required, peer/backend cannot |
| `http-redirect-error` / `http-canceled` | policy / cancel token |

`raise-for-status` (http-protocol) turns a 4xx/5xx **response** into `http-client-error` / `http-server-error`. Facade: `:raise-for-status t` on `stack-http:get`.

Retry is an **`http-retry` policy object** on the client/request (urllib3 shape) — **not** an ASDF `retry` restart. Don't write `handler-case` + recursive resend.

```lisp
(asdf:load-system "cl-stack-http")
(handler-case (stack-http:get url :raise-for-status t)
  (http-protocol:http-client-error (c)
    (format t "status ~A~%" (http-protocol:http-status-error-status c))))
```

usocket / dexador types: bind **those**. `http-error` has a `:message` slot — it does **not** have `:cause`.

---

## 3. Subprocess (`process-protocol`, nick `stack-process`)

| Condition | When |
|-----------|------|
| `process-error` | no backend / bad command shape |
| `process-timeout-error` | `:timeout` on `run` / `wait` |

```lisp
(asdf:load-system "process-backend-uiop")   ; binds *process-backend*
(handler-case (stack-process:run '("sleep" "5") :timeout 1)
  (stack-process:process-timeout-error (c)
    (declare (ignore c))
    :timed-out))
```

No inventing a `retry` restart that re-spawns — put that in the caller if you need it.

---

## 4. Schema / datetime

`schema-protocol`: `use-value` / `skip-field` / `use-default` are live **while that field is parsed**. `schema-fail` signals immediately (restart still active). Collected `schema-issue` raises after the field `restart-case` — too late for `use-value`. See [schema.md](schema.md).

`datetime-protocol`: `moment-in-zone` defaults `:on-gap :later` / `:on-overlap :earlier`. Pass `:strict` to get `nonexistent-local-time` / `ambiguous-local-time`. See [datetime.md](datetime.md).

---

## What not to do

- Status codes / `(values nil err)` as the only failure channel
- `handler-case` + recursive retry instead of a `retry` restart (FS) or `http-retry` (HTTP)
- Shadowing `use-value` / `continue` with a different meaning
- Catch-all `error` in a backend
- Putting retry/skip policy inside the protocol GF default method
- Assuming `http:get` is `http-protocol` — that's `stack-http:get`

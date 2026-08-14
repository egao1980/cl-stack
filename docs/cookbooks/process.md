# Cookbook: subprocess (`process-protocol`)

**Audience:** Python `subprocess` / Java `ProcessBuilder` — portable spawn, capture, pipes.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-process`) | [`process-protocol`](https://github.com/egao1980/process-protocol) | **0.1.0** |
| Default backend | [`process-backend-uiop`](https://github.com/egao1980/process-backend-uiop) | **0.1.0** |

Capability brief: [process.md](../capabilities/process.md) (#106). **Not** RPC — see [rpc.md](../capabilities/rpc.md).

```lisp
(cl-repo:load-system "process-backend-uiop" :version "0.1.0")
;; binds *process-backend*; nick stack-process via process-protocol
```

No competing process libs in default pins — UIOP only.

---

## 1. Sync `run` (capture)

```lisp
(use-package :stack-process)

(multiple-value-bind (code out err)
    (run '("uname" "-s"))
  (list code
        (babel:octets-to-string out :encoding :utf-8)
        (babel:octets-to-string err :encoding :utf-8)))
;; ⇒ (0 "Darwin\n" "")
```

| Kwarg | Meaning |
|-------|---------|
| `:input` | string / octets / stream → stdin |
| `:directory` | cwd |
| `:env` | alist of extra env |
| `:timeout` | seconds → `process-timeout-error` |
| `:discard-stderr` | drop stderr |
| `:shell t` | string command via shell (**discouraged**; argv list preferred) |

Windows: argv is a string list — UIOP quotes; prefer list form over `:shell t`.

---

## 2. Async `launch` / `wait` / `kill`

```lisp
(let ((h (launch '("sleep" "2"))))
  (alive-p h)          ; ⇒ T
  (wait h :timeout 5)  ; ⇒ 0
  (exit-code h))
```

Streams while alive:

```lisp
(let ((h (launch '("cat") :input :stream :output :stream)))
  (write-line "hi" (stdin h))
  (finish-output (stdin h))
  (close (stdin h))
  (read-line (stdout h))   ; ⇒ "hi"
  (wait h))
```

`kill` / `kill … :force t` → UIOP terminate / force-kill.

---

## 3. Errors

| Condition | When |
|-----------|------|
| `process-error` | no backend / bad command shape |
| `process-timeout-error` | `:timeout` exceeded on `run` / `wait` |

---

## 4. What not to do

- Don’t pull `external-program` / `inferior-shell` into default pins — use this protocol.
- Don’t put JSON-RPC framing here — `rpc-protocol` (+ process as a transport later).
- Don’t pass shell strings without `:shell t` — that signals `process-error`.

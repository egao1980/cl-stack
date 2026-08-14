# process-protocol (P2) — subprocess

**Issues:** [#106](https://github.com/egao1980/cl-stack/issues/106)  
**Status:** brief **locked** — CLOS protocol + UIOP backend **shipped** (OCI **0.1.0**) · cookbook [process.md](../cookbooks/process.md)

Portable process spawn / pipes / wait / kill. Python `subprocess`, Java `ProcessBuilder`, UIOP `run-program` — one app DX; backends wrap UIOP (default) or impl-private escapes.

**RPC** is a **separate** capability — see [rpc.md](rpc.md). A process may be an RPC *transport*, but process-protocol does not define request/response framing.

Conventions: [API.md](../API.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backends | Match stack; allow async backend later |
| **Default (A)** | **UIOP** `launch-program` / `run-program` | Portable; already everywhere |
| **Watchlist (B)** | SBCL `sb-ext:run-program` / Windows CreateProcess details | Only if UIOP gaps hurt |
| **DX** | `run` (sync capture) + `launch` (async handle) | Python `run` vs `Popen` |
| **I/O** | octet streams + optional UTF-8 string helpers | No silent external-format footguns |
| **Windows** | Required | UIOP path; argv quoting documented |
| **Not here** | JSON-RPC / sexp-RPC / gRPC | → rpc-protocol |

```lisp
(defclass process-backend () ())
(defvar *process-backend* nil)

(defgeneric backend-run (backend command &key input output error directory env
                          timeout discard-stderr))
;; → (values exit-code stdout-octets stderr-octets)

(defgeneric backend-launch (backend command &key …) → process-handle)
(defgeneric process-wait (handle &key timeout) → exit-code)
(defgeneric process-kill (handle &key force))
(defgeneric process-alive-p (handle))
(defgeneric process-stdin (handle))
(defgeneric process-stdout (handle))
(defgeneric process-stderr (handle))

(defun run (command &rest keys)
  (apply #'backend-run *process-backend* command keys))
(defun launch (command &rest keys)
  (apply #'backend-launch *process-backend* command keys))
```

`command` = list of strings (preferred) or a string (shell — opt-in `:shell t`, discouraged).

---

## Non-goals

- Job control / ptys as wave-1
- Container runtimes
- Embedding an RPC codec

---

## Implementation tasks

- [x] Brief lock — this doc (#106)
- [x] `process-protocol` + `process-backend-uiop` + Rove
- [x] Cookbook — [cookbooks/process.md](../cookbooks/process.md)
- [x] OCI publish — `process-protocol` / `process-backend-uiop` **0.1.0**

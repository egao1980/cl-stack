# process-protocol (P2) — subprocess

**Issues:** [#106](https://github.com/egao1980/cl-stack/issues/106)  
**Status:** brief **locked** — CLOS protocol + UIOP backend **shipped** (OCI protocol **0.3.0** / uiop **0.2.0**; **0.4.0** / **0.3.0** add process groups + tree kill — [process-protocol#9](https://github.com/egao1980/process-protocol/issues/9)) · cookbook [process.md](../cookbooks/process.md)

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
| **Process tree** (0.4.0) | Opt-in `:process-group t` + `kill :tree t`; Unix process group (`killpg`), Windows `taskkill /T /F` | Default behaviour unchanged; a shell's grandchildren die with it |
| **Windows tree** | `taskkill /T`, not a job object | UIOP / SBCL cannot create the child suspended (a job assigned later races the first grandchildren); no CFFI native. A backend may switch later without an API change |
| **Not here** | JSON-RPC / sexp-RPC / gRPC | → rpc-protocol |

```lisp
(defclass process-backend () ())
(defvar *process-backend* nil)

(defgeneric backend-run (backend command &key input output error directory env
                          timeout discard-stderr))
;; → (values exit-code stdout-octets stderr-octets)

(defgeneric backend-launch (backend command &key …) → process-handle)
(defgeneric process-wait (handle &key timeout) → exit-code)
(defgeneric process-kill (handle &key force tree))   ; tree: 0.4.0
(defgeneric process-alive-p (handle))
(defgeneric process-stdin (handle))
(defgeneric process-stdout (handle))
(defgeneric process-stderr (handle))
(defgeneric process-pid (handle))                   ; 0.4.0 → OS pid or NIL
(defgeneric backend-supports-p (backend capability)) ; 0.4.0 → :process-group, :pid

(defun run (command &rest keys)
  (apply #'backend-run *process-backend* command keys))
(defun launch (command &rest keys)
  (apply #'backend-launch *process-backend* command keys))
```

`command` = list of strings (preferred) or a string (shell — opt-in `:shell t`, discouraged).

### Process trees (0.4.0)

- `launch` / `run` `:process-group t` — start the child so a tree kill reaches its descendants. Unix: the child leads a new process group (SBCL already does this when stdin is not inherited; `:input :interactive` is refused). Default `nil` = 0.3 behaviour. A backend / platform that cannot honour it signals **`process-group-error`** (a `process-error`) instead of launching a lone child.
- `kill h :tree t` — Unix `killpg` (SIGTERM, SIGKILL with `:force`), also after the shell exited; descendants that left the group (`setsid`, pty) are not reached. Windows `taskkill /T /F /PID` (parent pids walked at kill time; orphans missed). Handle without a group → `process-group-error` with a **`continue`** restart (direct child only).
- `run … :process-group t :timeout n` — leaving `run` early (timeout, unwind) kills the whole tree.
- `pid` / `process-pid` — OS pid of the direct child (Unix: also the group id with `:process-group t`), `nil` if unknown.
- `supports-p cap` / `backend-supports-p` — `:process-group`, `:pid`; unknown → `nil`. UIOP backend: `:pid` always, `:process-group` on SBCL and Windows.
- Consumers: agent-tools `:process` executor (timeouts, `job_kill`) — [agent-tools-shell.md](agent-tools-shell.md).

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
- [x] OCI publish — `process-protocol` **0.2.0** / `process-backend-uiop` **0.1.0**
- [x] P1 `signal` — `set-signal` / `get-signal` / `raise-signal` / `valid-signals`. Unix: OS signals. Windows: in-process (no `enable-interrupt`).
- [ ] Process trees — `:process-group` / `kill :tree` / `process-pid` / `supports-p` ([process-protocol#9](https://github.com/egao1980/process-protocol/issues/9)): protocol **0.4.0** ([#10](https://github.com/egao1980/process-protocol/pull/10)), uiop **0.3.0** ([#12](https://github.com/egao1980/process-backend-uiop/pull/12)) — protocol first

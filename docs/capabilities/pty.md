# pty-protocol (P2) — pseudo-terminals

**Issues:** [#270](https://github.com/egao1980/cl-stack/issues/270) · terminal [#264](https://github.com/egao1980/cl-stack/issues/264)
**Status:** brief **locked** — no code yet

Run a program attached to a pseudo-terminal. Read the bytes it writes, write the bytes a user types, resize the window, signal it and wait for it. This is what [`terminal-protocol`](terminal.md) leaves out: the emulator parses the bytes, and this protocol carries them.

[`process-protocol`](process.md) is for pipes. Use this one when the child must see a TTY: shells, editors, `top`, REPLs with line editing, anything that checks `isatty`.

Conventions: [API.md](../API.md). Errors: [conditions.md](conditions.md).

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| node-pty | `spawn(file, args, {cols, rows, cwd, env})`, `resize`, `kill`; forkpty on Unix, ConPTY on Windows behind one API | Event-emitter callbacks as the only read path |
| Python `pty` / `ptyprocess` | `spawn` returns a handle; blocking `read` with timeout; `isalive`, `wait`, `exitstatus` | `pexpect` pattern matching (belongs above, in tests or tools) |
| Rust `portable-pty` | Master/child split, `PtySize` | Trait-object soup |
| Windows ConPTY | `CreatePseudoConsole` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`, `ResizePseudoConsole` | winpty |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backend | Matches the stack |
| **Backend** | `pty-backend-native`: CFFI over a small C library, `libpty-cl` | Opening a pty and starting a session needs fork/setsid/TIOCSCTTY or ConPTY. Neither is portable Lisp. |
| **No Lisp after fork** | The child runs only async-signal-safe C (`setsid`, `ioctl`, `dup2`, `chdir`, `execve`, `_exit`), then execs | A forked multithreaded Lisp image is undefined behaviour |
| **One C ABI, every OS** | `pty_cl_spawn / read / write / resize / signal / wait / close`; Unix and Windows implement the same functions | The Lisp side has no `#+windows` branches beyond paths |
| **Builds** | Zig cross-compiles `libpty-cl` for linux amd64/arm64 (glibc 2.31), darwin arm64, windows amd64 | Same toolchain as `ghostty-vt`, one build host |
| **Bytes** | Octets in and out | The emulator decodes, not the pipe |
| **Reads** | `pty-read` blocks up to `:timeout` seconds. It returns octets, empty on timeout, or `nil` at end of output | Simple loops without an event loop. `event-protocol` integration is P1. |
| **Command** | List of strings; `argv[0]` is looked up in `PATH` unless it has a slash | No shell parsing in the protocol. `("sh" "-c" "…")` when you want one. |
| **Exit** | `pty-wait` → `(values code signal)`. On Windows `signal` is always NIL. | POSIX status split, like `subprocess` returncode vs negative |
| **Errors** | `pty-error` tree; errno / `GetLastError` kept as a slot | Typed, not status codes |
| **Resources** | `with-pty` / `pty-close` (kills if still running, then reaps); a finalizer as backstop | [API.md](../API.md) |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| [`pty-protocol`](https://github.com/egao1980/pty-protocol) (`stack-pty`) | GFs, conditions, `spawn-pty` / `with-pty` |
| [`pty-backend-native`](https://github.com/egao1980/pty-backend-native) | CFFI + `native/pty-cl.c` + OCI overlays |

---

## Protocol surface

```lisp
(defclass pty-backend () ())
(defvar *pty-backend* nil)

(defgeneric backend-spawn-pty (backend command &key cols rows directory environment))
(defun spawn-pty (command &key (cols 80) (rows 24) directory environment
                               (inherit-environment t) (backend *pty-backend*)))
;; ENVIRONMENT: alist (("TERM" . "xterm-256color") …) merged over the parent's
;; environment when INHERIT-ENVIRONMENT, else used alone. TERM defaults to
;; xterm-256color.
(defmacro with-pty ((var command &rest keys) &body body))

(defgeneric pty-read (pty &key timeout max))   ; → octets (empty on timeout) | NIL at EOF
(defgeneric pty-write (pty octets &key start end))
(defgeneric pty-resize (pty cols rows))
(defgeneric pty-size (pty))                    ; → (values cols rows)
(defgeneric pty-signal (pty signal))           ; :hup :int :term :kill (Windows: :kill / :term terminate)
(defgeneric pty-alive-p (pty))
(defgeneric pty-wait (pty &key timeout))       ; → (values code signal), or NIL on timeout
(defgeneric pty-pid (pty))
(defgeneric pty-close (pty))                   ; idempotent
(defgeneric pty-closed-p (pty))
```

### Conditions

```text
pty-error (error)                     ; slot: pty
├── pty-spawn-error                   ; slots: command, errno / win32 code, message
│                                     ; restart use-value (another command)
├── pty-closed-error
└── pty-io-error                      ; slots: errno, operation
pty-native-unavailable (pty-error)    ; overlay missing at ASDF load
```

Writing after the child exits signals `pty-io-error`. A `continue` restart drops the write.

---

## C ABI (`native/pty-cl.c`)

```c
int  pty_cl_abi(void);
int  pty_cl_spawn(const char *file, char *const argv[], char *const envp[],
                  const char *cwd, uint16_t cols, uint16_t rows,
                  pty_cl_t **out, int *out_errno);
long pty_cl_read(pty_cl_t *p, uint8_t *buf, size_t len, int timeout_ms); // >0 bytes, 0 timeout, -1 EOF, -2 error
long pty_cl_write(pty_cl_t *p, const uint8_t *buf, size_t len);
int  pty_cl_resize(pty_cl_t *p, uint16_t cols, uint16_t rows);
int  pty_cl_signal(pty_cl_t *p, int signal);          // portable numbers: 1 HUP, 2 INT, 15 TERM, 9 KILL
int  pty_cl_wait(pty_cl_t *p, int timeout_ms, int *code, int *signal); // 1 exited, 0 timeout, -1 error
long pty_cl_pid(pty_cl_t *p);
void pty_cl_close(pty_cl_t *p);
```

- **Unix:** `posix_openpt` + `grantpt` + `unlockpt` + `ptsname_r`. `fork`, then in the child only: `setsid`, open the slave, `TIOCSCTTY`, `dup2` to 0/1/2, close other fds, `chdir`, `execvp`-style lookup through `PATH`, `execve`. An exec failure is reported to the parent through a `CLOEXEC` pipe as errno. The parent uses `poll` for reads and `waitpid` (WNOHANG) for waits. `EIO` after the child exits counts as EOF.
- **Windows:** pipes + `CreatePseudoConsole` + `STARTUPINFOEXW` with `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` + `CreateProcessW`. Arguments are quoted per `CommandLineToArgvW` rules. `PeekNamedPipe` and a wait give the read timeout. `ResizePseudoConsole` resizes. `ClosePseudoConsole` ends output, which then reads as EOF.

---

## Non-goals

- Pattern matching over output (`expect`). That belongs in tests or tools above.
- Job control and process groups beyond the child's own session
- Event-loop readiness (`event-protocol register-io`), which is P1
- Running Lisp code in the child

---

## Implementation tasks

- [x] Brief lock — this doc
- [ ] `pty-protocol` + Rove (mock backend)
- [ ] `pty-backend-native` — `pty-cl.c` (Unix + ConPTY), Zig cross builds, CFFI, Rove (real shells)
- [ ] OCI publish
- [x] Terminal cookbook: PTY ↔ `terminal-protocol` loop ([terminal.md](../cookbooks/terminal.md) §5–6)

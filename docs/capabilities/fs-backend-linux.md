# fs-backend-linux — the inotify change journal (R4b-1)

**Repo:** [`egao1980/fs-backend-linux`](https://github.com/egao1980/fs-backend-linux) (nick `stack-fs-linux`) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) R4 detail, rung R4b · protocol brief [pathlib.md, R4b-0](pathlib.md#r4b-0--locked)
**Status:** **R4b-1 brief locked**, version 0.1.0. Contract on branch `agent/r4b1-contract-9592` (`fs-backend-linux/tests`, Rove): the exports, the `inotify-journal` class, the libc bindings and the registration are given; the behaviour is stubbed (`%r4b1-pending`). Implementation via **team-solve**.

The first OS mechanism for cl-stack-pathlib's change journals. Loading `fs-backend-linux` registers `:inotify` with `register-watch-mechanism`. On Linux, for a directory on a `local-filesystem`, `fs-watch … :mechanism :auto` (and so `fs-open-area … :journal :auto`) then gets an inotify journal instead of `:poll`, and `fs-area-changes` re-examines only the paths it drains. The result never changes (the R4b law), only the cost.

---

## R4b-1 — locked

### Decisions

| Decision | Choice |
|----------|--------|
| **Package** | `fs-backend-linux`, nickname `stack-fs-linux`, local nickname `pathlib` for `cl-stack-pathlib`. |
| **Dependencies** | `cl-stack-pathlib` ≥ 0.9.0, `cffi` (0.24.1 from GHCR), `uiop`. Tests: `rove`, `cl-stack-pathlib/journal-suite`. No new third-party code. |
| **FFI** | **CFFI**, the stack's FFI (cl-stack-ssl, pty-backend-native, event-backend-libuv), not `sb-alien`, so the backend is not SBCL-only. The calls are all in libc: `inotify_init1`, `inotify_add_watch`, `inotify_rm_watch`, `read`, `close`, `__errno_location` (glibc and musl). Every Lisp image already has libc open, so there is **no foreign library to load or ship** and no overlay. The CFFI rule in AGENTS.md (natives at ASDF load) is met trivially. Constants (`IN_*`, the 16-byte `inotify_event` header, errno values) are the generic Linux ABI, the same on x86-64, arm64 and riscv, so there is no grovel step. `IN_NONBLOCK` / `IN_CLOEXEC` are `O_NONBLOCK` / `O_CLOEXEC`, which differ on alpha, sparc, mips and parisc (not supported). |
| **Every OS loads it** | Off Linux, the bindings are Lisp functions that signal `inotify-error`, so the system loads (no undefined-alien warnings) and registers `:inotify` everywhere. The probe makes it unavailable off Linux, so `:auto` never picks it there. |
| **Registration** | At load time: `(register-watch-mechanism :inotify '%make-inotify-journal :rank +inotify-rank+ :available-p 'inotify-available-p)`, with `+inotify-rank+` = 20 (above the default rank 0; `:poll` is always last). |
| **Availability** | `inotify-available-p fs directory`: Linux, FS a `local-filesystem`, and `inotify_init1` succeeding **now**: the probe opens an instance and closes it. Once `fs.inotify.max_user_instances` (default 128) is used up, `:auto` falls back to `:poll` instead of failing to open areas. Network filesystems are not detected in 0.1.0 (see Out of scope). |
| **One instance per journal** | `inotify_init1 (IN_NONBLOCK \| IN_CLOEXEC)`, one fd per journal, so `journal-close` frees exactly what one journal holds, and a child process never inherits it. |
| **Watches** | One watch per directory: the root and every real (not a symlink), **non-ignored** directory below it, found by listing (`lstat` semantics, symlinks never followed). A directory the ignore matcher drops is not watched (its whole subtree is ignored in git semantics, and the drain `:around` drops those paths anyway). The mask is at least `IN_CREATE IN_DELETE IN_MODIFY IN_ATTRIB IN_MOVED_FROM IN_MOVED_TO IN_DELETE_SELF IN_MOVE_SELF`, with `IN_ONLYDIR IN_DONT_FOLLOW IN_EXCL_UNLINK`. A watch on a directory that is already watched (same inode, `inotify_add_watch` returns the same wd) updates the path of that wd. |
| **No thread** | Events wait in the **kernel** queue between drains, and `journal-drain` reads them all with non-blocking `read` until `EAGAIN`. No reader thread, no locks, no finalizers. A journal is used by one thread at a time (the area's owner), like an area. |
| **Settle** | The kernel queues an inotify event inside the system call that made the change, before it returns, so every write that returned before the drain is already in the queue. The drain never sleeps: `:settle` is accepted and not waited on, and `:settle 0` gives the same answers. |
| **Paths** | An event named N on the watch of directory D reports `D/N` (`N` at the root). Name-less events (a watched directory itself: `IN_ATTRIB`, `IN_MOVE_SELF` of a subdirectory, …) report nothing, because the parent's watch reports the entry by name. In particular the root's own events never report `""`, which would mean "rescan everything". Names are decoded as UTF-8. A name that does not decode makes the drain incomplete. |
| **The add-watch race** | A directory that appears (`IN_CREATE` with `IN_ISDIR`, or an unpaired `IN_MOVED_TO` with `IN_ISDIR`) is reported **by its own path**, which covers its subtree, so anything written into it before its watch existed is covered. Then it is watched first and listed second, recursively, so that a subdirectory created during the listing is either listed or reported by the new watch. |
| **Moves** | `IN_MOVED_FROM` and `IN_MOVED_TO` with the same cookie, both under the root: both paths are reported, and the watches at and below the old path are renamed to the new one (the wds stay valid; the kernel moved the directory). An `IN_MOVED_FROM` with no `IN_MOVED_TO` once the queue is empty is a **move out** of the root: its path is reported, and every watch at or below it is removed with `inotify_rm_watch` (otherwise the moved tree would report events outside the root under stale paths). An unpaired `IN_MOVED_TO` is a **move in**: as a create. A pair split across two `read` calls is still paired, and pending pairs are resolved only when the queue is empty. |
| **Lost track (recoverable)** | `IN_Q_OVERFLOW`; a watch that cannot be added (`ENOSPC`: `fs.inotify.max_user_watches`; `EACCES`; the soft cap `*inotify-max-watches*`); a name that is not UTF-8. That drain answers `(values nil nil)` (the caller rescans), throws away the events it read, and **resyncs**: it walks the tree, adds a watch to every directory that lacks one, renames the wds whose directory moved, and removes the watches of directories that are gone. `ENOENT` / `ENOTDIR` on add (the directory vanished) is not a failure, since its parent reports its removal. Later drains answer NIL for as long as some directory still lacks a watch (each one retries the resync), and the first drain after a complete resync is complete again. |
| **Lost track (for good)** | The root deleted, moved or unmounted (`IN_DELETE_SELF`, `IN_MOVE_SELF`, `IN_UNMOUNT` or `IN_IGNORED` on the root's watch). Every later drain answers `(values nil nil)` until `journal-close`, even if a directory of the same name comes back. The area's full rescan then reports what is actually there. |
| **Watch cap** | `*inotify-max-watches*` (NIL, or a positive integer, read when the journal is made): the most watches one journal holds. One past it fails as if the kernel returned `ENOSPC`. This keeps a huge tree from eating the user's watch budget, and it is how the tests reach "the watch limit" deterministically. |
| **Test hook** | `(inject-inotify-event journal mask &key (wd :root) (cookie 0) name)` queues a synthetic event that the next drain handles before the kernel's events, through the same code path. It is exported, documented "for tests", and used to make `IN_Q_OVERFLOW` and `IN_IGNORED` on the root deterministic. A real overflow is tested too, when `fs.inotify.max_queued_events` ≤ 100000. |
| **Close** | `journal-close` (once, through the `:around` on `journal`) removes the watches, closes the fd, and empties the tables. It never signals for a root or watches the kernel has already dropped. `inotify-journal-fd` is then NIL, `inotify-journal-watch-count` 0, and `inotify-journal-watched-directories` NIL. A constructor that fails after `inotify_init1` closes the fd before it signals. |
| **Errors** | `inotify-error` (a `pathlib:journal-error`, readers `inotify-error-operation`, `inotify-error-errno`) only where no answer can say "rescan": `inotify_init1` failing inside `fs-watch` (`EMFILE` between the probe and the open), or a binding called off Linux. Everything that happens after the journal exists is COMPLETE-P NIL, never a condition. |

### Surface

```lisp
;;; The mechanism (registered at load time)
+inotify-rank+                         ; 20
(inotify-available-p &optional fs directory) → generalized boolean   ; the registry probe
*inotify-max-watches*                  ; NIL | positive integer, read by FS-WATCH

;;; The journal (made by PATHLIB:FS-WATCH … :MECHANISM :INOTIFY or :AUTO)
inotify-journal                        ; a PATHLIB:JOURNAL, JOURNAL-MECHANISM = :INOTIFY
(inotify-journal-p x)
(inotify-journal-fd journal) → fd | NIL                  ; NIL once closed
(inotify-journal-watch-count journal) → integer          ; 0 once closed
(inotify-journal-watched-directories journal) → ("" "src" "src/deep" …) | NIL
    ; relative POSIX paths, sorted STRING<, "" = the root
(inject-inotify-event journal mask &key (wd :root) (cookie 0) name) → journal   ; for tests
;; PATHLIB:JOURNAL-DRAIN and PATHLIB:JOURNAL-CLOSE are specialized on INOTIFY-JOURNAL

;;; Conditions
inotify-error (pathlib:journal-error): inotify-error-operation inotify-error-errno

;;; inotify(7) bits
+in-access+ +in-modify+ +in-attrib+ +in-close-write+ +in-close-nowrite+ +in-open+
+in-moved-from+ +in-moved-to+ +in-create+ +in-delete+ +in-delete-self+ +in-move-self+
+in-unmount+ +in-q-overflow+ +in-ignored+ +in-onlydir+ +in-dont-follow+ +in-excl-unlink+
+in-mask-add+ +in-isdir+ +in-oneshot+
```

Given in the contract (shape locked): the package and exports, `src/ffi.lisp` (constants, `inotify-error`, the libc bindings and their off-Linux stand-ins), the `inotify-journal` class and its slots, `inotify-journal-p`, `inotify-journal-fd`, `+inotify-rank+`, `*inotify-max-watches*`, the registration, and the off-Linux / non-local branches of `inotify-available-p`. Stubbed: the Linux branch of `inotify-available-p`, `%make-inotify-journal`, `journal-drain` and `journal-close` on `inotify-journal`, `inotify-journal-watch-count`, `inotify-journal-watched-directories` and `inject-inotify-event`.

### Semantics, by example

| Edit before the drain | Drain |
|-----------------------|-------|
| write `a.txt`, `src/deep/b.lisp`; delete `gone.txt`; `chmod run.sh` (all watched) | `(("a.txt" "gone.txt" "run.sh" "src/deep/b.lisp" "src/deep/new.lisp") t)`: exact paths |
| `chmod` of the root itself | `(nil t)` |
| `mkdir -p d/e/f/g`, files in `d` and `d/e` | complete, every new path covered (by `"d"`); afterwards `d`, `d/e`, `d/e/f`, `d/e/f/g` are watched and `d/e/f/g/3.txt` is reported exactly |
| `mv a b` (a directory, inside the root) | `"a"` and `"b"`; watches now under `b`; `b/sub/y.txt` reported as such |
| `mv root/out ../outside/out` | `"out"`; no watch left at or below `out`; edits under `outside/out` report nothing |
| `mv ../outside/tree root/tree` | `"tree"`; `tree` and its subdirectories watched |
| `IN_Q_OVERFLOW` (real or injected) | `(nil nil)`; the next drain is complete; directories made meanwhile are watched, vanished ones forgotten |
| a watch past `*inotify-max-watches*` | `(nil nil)` at that drain and every drain while a directory lacks a watch; complete again once all fit |
| root deleted / moved / `IN_IGNORED` on it | `(nil nil)` for good |

### Contract (tests)

`fs-backend-linux/tests` (Rove). Tests that need inotify are `deflinux`: on another OS each one is a single `skip` with the note "inotify is Linux only: skipped on this OS (CI runs it on ubuntu-latest)". CI is the canned `test-system.yml` (ubuntu in the ci-base container, macOS, Windows) plus `publish-checkout.yml`.

| File | Covers |
|------|--------|
| `registry-test.lisp` | registered at load, ranked above `:poll`, `let` scoping; unavailable on a memory filesystem (`unsupported-operation`); off Linux: unavailable for a local directory, `:auto` does not pick it; on Linux: available, `:auto` gives an `inotify-journal` with an fd, readers; `open-area` with `:journal :auto` attaches it |
| `suite-test.lisp` | `(run-journal-suite :inotify)` with no failures and every applicable step run (the R4b law on the whole corpus, including the 2000-file burst and the child-process edits); with `:settle 0`; with `:auto` |
| `inotify-test.lisp` | exact paths and the kernel's watch count (`/proc/self/fdinfo`); root self-events report nothing; child-process edits; **the add-watch race**: a directory created and filled at once, 40 `mkdir -p` + write in a child process, a new subdirectory of a watched directory; **overflow**: injected (recovery on the next drain), resync adds and drops watches, a real overflow of `fs.inotify.max_queued_events`; **watch limit**: at open and on new directories, retry, recovery; **the root**: deleted, moved, `IN_IGNORED`, sticky NIL; **moves**: in, out (watches removed, kernel agrees), within, across directories; ignored and symlinked directories are not watched |
| `lifecycle-test.lisp` | `journal-close` closes the fd (`/proc/self/fd` → `anon_inode:inotify`) and drops the watches; idempotent; drain and inject after close → `journal-error`; `close-area` closes it; **no inotify fd left after 50 open/close cycles**, with drains and overflows, after 50 lost roots, and after 50 `fs-watch` calls on missing directories |
| `support.lisp` | helpers (scratch trees by truename, `sh`, `mv`, `/proc` readers) |

**Verdict:** the contract must be graded **on Linux**. On macOS every inotify test is a skip, so a macOS `cl-repo test` passes vacuously. Run `check-feature.sh` in the ci-base container (`ghcr.io/egao1980/cl-repository/ci-base:latest`, checkout mounted, `cl-repo test --system fs-backend-linux`), or read the ubuntu job of the PR's CI.

### Out of scope (later)

fanotify (`FAN_REPORT_DFID_NAME`, whole-filesystem marks, needs `CAP_SYS_ADMIN`) · detecting network and FUSE filesystems (`statfs` magic: NFS, SMB/CIFS, FUSE do not report remote changes) for the availability probe · changes inotify never sees (writes through `mmap`, edits on another host of a network filesystem), which a journal cannot report and the law cannot test · `FICLONE` / reflink copy areas on Linux (an R4a `:mechanism` for fs-backend-linux) · a reader thread to keep the kernel queue short · ECL / CCL CI jobs (the CFFI bindings are portable, but 0.1.0 is tested on SBCL).

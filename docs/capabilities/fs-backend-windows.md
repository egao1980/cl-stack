# fs-backend-windows (R4b-3) — ReadDirectoryChangesW change journals

**Repo:** [`egao1980/fs-backend-windows`](https://github.com/egao1980/fs-backend-windows) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) R4 detail, rung R4b · **Protocol:** [pathlib.md § R4b-0](pathlib.md#r4b-0--locked) (`cl-stack-pathlib` 0.9.0) · siblings [fs-backend-linux.md](fs-backend-linux.md) (R4b-1), [fs-backend-darwin.md](fs-backend-darwin.md) (R4b-2)
**Status:** **R4b-3 locked**, version **0.1.0**. Contract on branch `agent/r4b3-contract-d82f` ([PR #1](https://github.com/egao1980/fs-backend-windows/pull/1); `fs-backend-windows/tests`, Rove): given code, stubs (`%r4b3-pending`) and the failing tests. Implementation via **team-solve**.

The Windows mechanism for the R4b-0 journal protocol. Loading the system registers `:rdcw`. On Windows, `fs-watch … :mechanism :auto` and `fs-open-area … :journal :auto` then pick it for directories on local volumes with no consumer change, and `fs-area-changes` rehashes only the drained paths. The verdict is the same as for every R4b backend: `cl-stack-pathlib/journal-suite` passes with `:rdcw`, so the journal result is EQUAL to the full rescan after every corpus step.

**Testability.** The team-solve verdict runs on macOS, where every Win32 test skips. So the logic that does not need Win32 is in `src/notify.lisp` as plain Lisp, and it is tested on **every OS**: the `FILE_NOTIFY_INFORMATION` parser, UTF-16LE decoding, the action mapping (rename pairs included), relative paths, case folding, the 8.3 alias rule, the listing-based name resolver, final-path comparison, the accumulator (pending names plus the overflow and lost marks) and the drain barrier. The tests use hand-built octet buffers and a fake directory lister. The Win32 half (`src/journal.lisp`) is thin glue, and the Windows CI job grades it.

---

## Decisions

| Decision | Choice |
|----------|--------|
| **Package** | `fs-backend-windows`, local nickname `sp` for `cl-stack-pathlib`. One system plus `fs-backend-windows/tests`. |
| **Dependencies** | `cl-stack-pathlib` 0.9.0, `cffi` (the stack's FFI), `bordeaux-threads` (bt2 API, [concurrency.md](concurrency.md)), `uiop`. Tests also use `rove` and `cl-stack-pathlib/journal-suite`. There is no other library: UTF-16 decoding is our own (pure, tested), and `GetLastError` codes are compared with our own constants. |
| **Natives** | None to build. kernel32 is a system DLL (a KnownDLL). `src/ffi.lisp` opens it with `cffi:load-foreign-library` at ASDF load time, by absolute path (`%SystemRoot%\System32\kernel32.dll`), under `#+(or windows win32)` only (AGENTS.md CFFI rule). No overlay and no `:cl-repo` properties. It is published with `publish-source.yml`. |
| **Every OS loads it** | Each binding is defined through `%define-kernel32`, a stdcall `cffi:defcfun` on Windows. Elsewhere it is a Lisp function of the same arguments that signals `rdcw-error`, so there are no undefined-alien warnings and `:rdcw` registers everywhere. |
| **Registration** | At load time: `(register-watch-mechanism :rdcw 'make-rdcw-journal :rank 100 :available-p 'rdcw-available-p)`. |
| **Availability** | `rdcw-available-p fs directory` is true on Windows, for a `local-filesystem`, when the volume of DIRECTORY is local: `GetVolumePathNameW`, then `GetDriveTypeW` ∈ {FIXED, REMOVABLE, RAMDISK}. Network drives (`DRIVE_REMOTE`: 64 KiB buffer limit, remote changes not reported) and CD-ROMs fall back to `:poll`. Off Windows, or for memory and zip filesystems, it is NIL, so `fs-watch :mechanism :rdcw` signals `unsupported-operation` (protocol rule). |
| **Handle** | One directory handle per journal, on the root's **truename**: `CreateFileW(FILE_LIST_DIRECTORY, share READ \| WRITE \| DELETE, OPEN_EXISTING, BACKUP_SEMANTICS \| OVERLAPPED)` (`+rdcw-share-mode+`, `+rdcw-create-flags+`). The handle shares everything, so the root and everything below it can still be written, deleted and renamed while it is watched (tested). At open, the journal records `GetFinalPathNameByHandleW` of the handle for the root check. |
| **Request** | `ReadDirectoryChangesW` is **overlapped** (an event in the `OVERLAPPED`, no completion routine and no IOCP) and **recursive** (`bWatchSubtree` TRUE). The filter is `+rdcw-notify-filter+` = FILE_NAME \| DIR_NAME \| ATTRIBUTES \| SIZE \| LAST_WRITE \| CREATION (#x5F). It leaves out LAST_ACCESS, since reads are not changes, and SECURITY, since ACLs are not part of an area's state. A recursive watch reports every descendant, so a directory created and filled at once has no race to handle (unlike inotify). |
| **Buffer** | `*rdcw-buffer-size*` is 65536 octets by default, read by `fs-watch`. It must be a multiple of 4 from 4096 to 1048576, else `type-error` (with nothing left open). 64 KiB is the most a network redirector accepts. The kernel's own queue for the handle has the size of the first request, so this value also bounds how much can pile up between two completions. The buffer and the `OVERLAPPED` are `cffi:foreign-alloc`ed (DWORD-aligned) and freed by close after the watcher is joined. |
| **Thread** | Each journal owns a **watcher thread** (`bt2:make-thread`), which issues every request itself, so a thread that exits never cancels a journal's I/O. Its loop is `WaitForMultipleObjects` on {the request's event, a wake event}. On a completion it calls `GetOverlappedResult`, feeds the bytes and the error to `rdcw-accumulate`, and re-issues the request at once. On a wake it answers barrier tickets, pause and close. The thread only touches Lisp data through the accumulator's and the barrier's locks. An error in the watcher marks the accumulator LOST and fails the barrier, so no drain can claim completeness after the thread is gone. The first request is pending before `fs-watch` returns, so every change after it is reported. |
| **Parsing** | `parse-file-notify-information octets &key start end` turns the bytes into `((action . native-name) …)` in buffer order. Each entry is little-endian: NextEntryOffset, Action, FileNameLength in octets, then UTF-16LE FileName, and entries are DWORD-aligned. A broken chain signals `malformed-notify-buffer` (offset, reason): a header or a name past END, an odd name length, a next offset that is not a multiple of 4, or one that does not move past the name. A name with an unpaired surrogate (NTFS allows those, UTF-8 paths cannot hold them) parses as NIL. |
| **Actions** | Each of ADDED, REMOVED, MODIFIED, RENAMED_OLD_NAME and RENAMED_NEW_NAME adds `(rdcw-relative-path name)`. So **both names of a rename** are reported, which covers a directory rename's subtree under both names. Pairs need no matching, because each name is a touched path. A move out of or into the root arrives as REMOVED or ADDED. These make the take **incomplete**: an unknown action, a NIL name, a name that maps to `""` (the root itself), or a malformed buffer. |
| **Paths** | `rdcw-relative-path` turns `\` (and `/`) into `/`, collapses runs of separators, and drops leading and trailing separators. The spelling is kept. |
| **Accumulator** | `rdcw-accumulator` (pure, with its own lock) holds the pending names, exact spellings each once, plus two marks. INCOMPLETE is cleared by the next take. LOST is sticky. `rdcw-accumulator-take` gives `(values names t)`, or `(values nil nil)` when either mark is set. |
| **Overflow** | A completion with **0 bytes and no error** (the buffer overflowed) or `ERROR_NOTIFY_ENUM_DIR` (1022) sets INCOMPLETE and drops the pending names. The drain answers `(values nil nil)`, the caller rescans, and the drain after it is complete again: the request was re-issued at once, and anything between the overflow and that rescan is covered by the rescan. A real overflow is tested with a 4096-octet buffer, a paused watcher and 2000 creates. Injected overflows are tested too. |
| **Root lost (for good)** | A completion with any other error sets LOST: `ERROR_ACCESS_DENIED` (the root was deleted and the handle is delete-pending), `ERROR_NOTIFY_CLEANUP`, `ERROR_INVALID_HANDLE`, and so on. `ERROR_OPERATION_ABORTED` is our own close and changes nothing. **Every drain also checks the root**: `GetFinalPathNameByHandleW` must still be `rdcw-same-final-path-p` to the path recorded at open (else the root or an ancestor was renamed), and `GetFileAttributesW` of the root must be a directory (else it was deleted). Failing either marks LOST. A lost journal answers `(values nil nil)` until `journal-close`, even when a directory of the same name comes back, as in R4b-1. |
| **Settle and drain** | NTFS queues a change notification **inside the call that made the change**, before that call returns: it either completes our pending request or goes into the handle's kernel queue. (Size and last-write changes are reported when the writer's handle is cleaned up, i.e. at close, which every corpus edit does.) So what a drain has to do is collect, not wait, and it does that through a **barrier with the watcher**. `journal-drain` takes a ticket (`rdcw-barrier-request`), sets the wake event and waits at most `*rdcw-barrier-timeout*` (default 1 s) for the ack. The watcher reads `rdcw-barrier-requested`, handles every completed request and re-issues, until its request is **pending and unsignalled**. At that point the kernel holds no undelivered event. Then it acks the ticket it read. A ticket that is acked means every event of a write that returned before the drain is in the accumulator. Then the drain checks the root, takes, and resolves the names. If the ack does not come in time, the drain still takes, to clear, and answers `(values nil nil)`, following the protocol rule that a mechanism that is unsure answers NIL. `:settle` is checked by the protocol `:around` and is not otherwise waited on: the barrier usually answers in microseconds, and if settle 0 meant "skip the barrier", every settle-0 drain would be NIL. This rule is testable: the barrier is pure and tested on every OS (tickets, ack, timeout, several waiters, fail). On Windows, 20 write-then-drain rounds at settle 0 and 0.05 are each complete and covering in < 0.5 s, and a **paused** watcher (`rdcw-journal-pause`) makes the drain answer `(nil nil)` after the timeout. |
| **Names: case and 8.3** | ReadDirectoryChangesW may report a name the way the caller spelled it: another case, or an 8.3 alias (`LONGFI~1.TXT`). The area looks drained paths up **by exact name in the parent's listing** (R4b-0), so the drain maps each name to its on-disk spelling with `rdcw-resolve-path name lister`. The LISTER is `FindFirstFileW`/`FindNextFileW` in the drain thread, giving `(long-name . short-name)` per entry, at most once per directory per drain. The walk goes component by component from the root. An exact long-name match is taken first. Next comes a unique `rdcw-fold-key` match on the long name (case correction), then a unique fold match on the short name (8.3 expansion). Otherwise the walk stops: the name is missing, or ambiguous in a case-sensitive directory. A missing component that has the form of an 8.3 alias (`rdcw-short-name-p`), or an ambiguous one, reports the **resolved ancestor directory**: a deleted alias has no knowable long name, and the directory covers it. At the root this is `""`, so the drain rescans. Any other missing component reports the resolved ancestor joined with the rest as reported. **The name as reported is always reported too** (a path not on disk only drops state). That keeps both names of a case-only rename, and it covers a removal whatever its case. `GetLongPathNameW` is not used: it does not correct the case of components that are already long, and it fails for exactly the deleted names that matter. The listing does both jobs, and it can be faked in pure tests. |
| **Case folding** | `rdcw-fold-key` maps each character through `char-upcase`, a simple one-to-one uppercase like NTFS's `$UpCase` table (`ß` stays `ß`). The accumulator dedupes **exact** spellings only. Folding them there would lose one name of a case-only rename. Names that fold together are resolved once (one listing) by `rdcw-resolve-paths`, which returns the union, deduplicated and sorted `string<`. |
| **UTF-16** | `utf16le-octets-to-string` decodes surrogate pairs, and gives NIL for an odd length or an unpaired surrogate. Wide arguments to Win32 are CFFI `(:string :encoding :utf-16le)`. |
| **Close** | `journal-close` runs once (protocol `:around`) and works from any thread, on a paused journal, and after the root was deleted. It sets closing, calls `CancelIoEx(handle, overlapped)` and sets the wake event. The watcher waits for the cancelled request (`GetOverlappedResult`, wait TRUE, `ERROR_OPERATION_ABORTED`), so the kernel is done with the buffer, then exits. Close then joins it, fails the barrier, closes the directory handle and both events, and frees the buffer and the `OVERLAPPED`. Afterwards `rdcw-journal-handle` and `rdcw-journal-thread` are NIL and `rdcw-handle-count` is down by one. No finalizers: an unclosed journal keeps its handle and thread until exit, as in R4b-1 and R4b-2. |
| **Errors** | `rdcw-error` (a `sp:journal-error`, readers `rdcw-error-operation` and `rdcw-error-code` = `GetLastError`, read right after the failing call). It is signalled only where no answer can say "rescan": `CreateFileW` (for example the root is not a directory), `CreateEventW`, the watcher thread, the first `ReadDirectoryChangesW` (`ERROR_INVALID_FUNCTION` on a filesystem without change notification), or any binding off Windows. The constructor leaves nothing open or running when it signals. Everything after the journal exists is COMPLETE-P NIL, never a condition. `malformed-notify-buffer` (a plain `error`) is internal to the parser: the accumulator turns it into INCOMPLETE. |
| **Test hooks** | `rdcw-journal-inject journal octets &key bytes code` applies a completion through the watcher's own code (`rdcw-accumulate`). `rdcw-journal-pause` / `rdcw-journal-resume` stop the watcher from handling completions and tickets. Pause returns once the watcher has acknowledged it, and drains meanwhile time out. Also `short-path-name` (`GetShortPathNameW`), `process-handle-count` (`GetProcessHandleCount`) and `rdcw-handle-count`. |
| **Stubs** | The contract calls `%r4b3-pending` (internal, `src/notify.lisp`). The implementation removes it and every call. |

## Surface

```lisp
;;; Mechanism (registered at load)
+rdcw-rank+                                   ; 100
(rdcw-available-p fs directory) → generalized boolean   ; Windows, local-filesystem, local volume
(make-rdcw-journal fs directory matcher) → rdcw-journal ; the registered constructor
rdcw-journal (sp:journal)                     ; :mechanism :rdcw
(rdcw-journal-thread j) → thread | NIL   (rdcw-journal-handle j) → pointer | NIL
(rdcw-journal-buffer-size j) → octets   (rdcw-handle-count) → integer
*rdcw-buffer-size*                            ; 65536, multiple of 4 in [4096, 1048576]
*rdcw-barrier-timeout*                        ; 1 (seconds)

;;; Test hooks and Windows helpers
(rdcw-journal-inject j octets &key (bytes (length octets)) (code 0)) → NIL   ; closed → sp:journal-error
(rdcw-journal-pause j) → NIL   (rdcw-journal-resume j) → NIL
(short-path-name pathname) → native namestring   (process-handle-count) → integer   ; RDCW-ERROR off Windows

;;; Pure (every OS)
(utf16le-octets-to-string octets &key start end) → string | NIL
(parse-file-notify-information octets &key start end) → ((action . native-name-or-NIL) …)
(rdcw-action-keyword action) → :added | :removed | :modified | :renamed-old | :renamed-new | NIL
(rdcw-relative-path native-name) → "a/b"   (rdcw-fold-key string) → string
(rdcw-short-name-p component) → boolean
(rdcw-resolve-path name lister) → (resolved [name])   (rdcw-resolve-paths names lister) → sorted union
    ; lister: (funcall lister "rel/dir") → ((long . short-or-NIL) …) | NIL
(rdcw-same-final-path-p a b) → boolean
rdcw-accumulator: (make-rdcw-accumulator) (rdcw-accumulate acc octets &key bytes code)
                  (rdcw-accumulator-take acc) → (values names complete-p)
                  (rdcw-accumulator-mark-lost acc) (rdcw-accumulator-lost-p acc)
rdcw-barrier: (make-rdcw-barrier) (rdcw-barrier-request b) → ticket (rdcw-barrier-requested b)
              (rdcw-barrier-ack b ticket) (rdcw-barrier-wait b ticket timeout) → T | NIL
              (rdcw-barrier-fail b)

;;; Conditions
rdcw-error (sp:journal-error): rdcw-error-operation rdcw-error-code
malformed-notify-buffer (error): malformed-notify-buffer-offset malformed-notify-buffer-reason

;;; Constants (winnt.h / winerror.h)
+file-action-added+ … +file-action-renamed-new-name+
+file-notify-change-file-name+ … +file-notify-change-security+ +rdcw-notify-filter+
+file-list-directory+ +file-share-read+ +file-share-write+ +file-share-delete+ +rdcw-share-mode+
+open-existing+ +file-flag-backup-semantics+ +file-flag-overlapped+ +rdcw-create-flags+
+error-success+ +error-file-not-found+ +error-path-not-found+ +error-access-denied+
+error-invalid-handle+ +error-invalid-function+ +error-operation-aborted+ +error-io-incomplete+
+error-io-pending+ +error-notify-enum-dir+ +error-notify-cleanup+
```

Given in the contract (shape locked): the package and exports, `src/ffi.lisp` (constants, conditions, library loading, the kernel32 bindings and their off-Windows stand-ins, `OVERLAPPED` and `WIN32_FIND_DATAW` layout; the implementation may add or correct a binding but keeps the names), `*rdcw-buffer-size*`, `*rdcw-barrier-timeout*`, `+rdcw-rank+`, the `rdcw-journal` class and its readers (slots may be added), the portable branches of `rdcw-available-p`, and the registration. Stubbed: all of `src/notify.lisp`, `%rdcw-volume-watchable-p`, `make-rdcw-journal`, `journal-drain` / `journal-close` on `rdcw-journal`, the hooks, `rdcw-handle-count`, `short-path-name` and `process-handle-count`.

## Semantics, by example

| Before the drain | Drain |
|------------------|-------|
| write `sub\a.txt`; create `new.txt`; delete `top.txt`; `mkdir made` | `(("made" "new.txt" "sub/a.txt" "top.txt") t)` |
| `ren src\c.lisp d.lisp`; `ren docs manual` | both names of each: `"docs" "manual" "src/c.lisp" "src/d.lisp"` |
| case-only rename `README.md` → `readme.md` | `"README.md" "readme.md"` |
| write through `src\X.LISP` (disk: `Src\x.lisp`) | `"Src/x.lisp"` (plus `"src/X.LISP"` as reported) |
| write through `sub\LONGFI~1.TXT` | `"sub/Long File Name.txt"` (plus the alias) |
| delete through `sub\LONGFI~1.TXT` | `"sub"` (plus the alias): complete, covers it |
| delete through `LONGFI~1.TXT` at the root | `(nil nil)` (`""`: rescan) |
| 0-byte completion / `ERROR_NOTIFY_ENUM_DIR` | `(nil nil)`; the next drain is complete |
| root deleted, root renamed, `ERROR_ACCESS_DENIED` | `(nil nil)` for good |
| rename of an ancestor of the root attempted (NTFS refuses it: `ERROR_ACCESS_DENIED`) | nothing changed: `(nil t)`; later edits are reported, complete |
| watcher paused (barrier not acked within `*rdcw-barrier-timeout*`) | `(nil nil)` |

## Contract (tests)

`fs-backend-windows/tests` (Rove, 145 tests). Win32 tests are `deftest-windows`: on another OS each one is a single **skip with a note**. The pure tests and the registry tests run everywhere. CI is the canned `test-system.yml` (Linux, macOS, Windows) plus `publish-checkout.yml`. On macOS today, 4 tests pass (given code), 117 fail on the stubs only, and 24 skip.

| File | OS | Covers |
|------|----|--------|
| `registry-test.lisp` | all | `:rdcw` registered above `:poll`, rank; the filter, share and flag constants; conditions; unavailable on a memory filesystem; off Windows unavailable, `unsupported-operation`, `:auto` ≠ `:rdcw`, bindings signal `rdcw-error`; on Windows first for the temp directory |
| `notify-test.lisp` | all | UTF-16LE (BMP, surrogate pairs, unpaired → NIL, odd length, ranges, non-simple vectors); parser: single, empty, chains with DWORD padding, native names kept, unknown actions passed through, bad UTF-16 → NIL name, START/END (bytes-returned), seven malformed chains → `malformed-notify-buffer` with offset and reason; action keywords |
| `paths-test.lisp` | all | relative paths; fold keys; the 8.3 alias table; the resolver table with a fake lister (exact, case-corrected, 8.3 files and directories, missing leaves, a missing alias → its directory or `""`, a missing directory chain, a case-sensitive directory: exact, ambiguous, unique), lister arguments by on-disk spelling, one listing per directory per call, the union sorted; final-path comparison (`\\?\`, UNC, case, trailing, slashes) |
| `accumulator-test.lisp` | all | names relative and sorted, exact dedupe, both spellings kept, rename pairs and unpaired names, Unicode, BYTES respected; overflow (0 bytes, 0 bytes with a stale buffer, 1022) → `(nil nil)` then recovery; lost codes (5, 745, 6, 87) sticky; aborted (995) changes nothing; unknown action, bad UTF-16, root name, malformed → incomplete with no condition, then recovery; `mark-lost`; two writer threads and a taker: 1000 names, each once |
| `barrier-test.lisp` | all | tickets increase, ack up to a ticket, an older ack changes nothing, timeout 0 does not block; a responder thread; a timeout; one ack wakes four waiters; fail wakes waiters and later waits are NIL |
| `journal-test.lisp` | Windows | basics (class, mechanism, handle, buffer size, live thread, handle count; empty drain; precise edit; create / delete / mkdir / rename covered; POSIX paths); ignore; only post-watch changes; child-process edits (cmd.exe); UTF-16 names (BMP, and a surrogate pair created, edited and deleted through `CreateFileW`/`DeleteFileW` test helpers, since SBCL's `OPEN` cannot name it); case (root watched in another case, write and delete through another case, case-only rename); 8.3 (write and delete through the alias; skipped when the volume makes none); injected overflow (0 bytes, 1022) and injected events; **real overflow** (4096 buffer, paused watcher, 2000 files); buffer-size checks; 2000-file burst; **root deleted** (allowed while watched; NIL for good, even once recreated), **root renamed**, **ancestor rename refused** (`MoveFileExW` → `ERROR_ACCESS_DENIED`; the next drain is `(nil t)`, then an edit is reported complete), injected `ERROR_ACCESS_DENIED`; **barrier**: 20 rounds at settle 0 and 0.05 complete in < 0.5 s, paused watcher → `(nil nil)` and recovery; **close** (thread joined, handle closed, count restored, idempotent, drain / inject / pause after close → `journal-error`, after the root was deleted, from another thread, while paused); areas get `:rdcw` by `:auto`; **no leak**: 50 cycles with drains and overflows leave thread count and `rdcw-handle-count` unchanged, and `GetProcessHandleCount` within `before + 50 × per-thread + 5`, where per-thread is measured in the test by 50 bare `bt2:make-thread`/`join-thread` cycles (a journal adds no handle a bare thread does not) |
| `suite-test.lisp` | Windows | `run-journal-suite :rdcw` at settle 0.05 and 0, with every applicable step run (incl. case-only rename, burst, child process); `run-journal-suite :auto` |

**Verdict.** `check-feature.sh` on macOS grades the pure layer, which is most of the logic, and requires that the system loads with no warnings off Windows. The Win32 glue is graded by the **windows-latest job** of the contract PR's CI. Read it, `gh run view --log-failed`, before calling R4b-3 done.

## As shipped on Windows (0.1.0)

The windows-latest job (SBCL 2.6.7) showed three platform facts that the first contract contradicted. The contract was amended for them ([fs-backend-windows#3](https://github.com/egao1980/fs-backend-windows/issues/3)); the implementation did not change.

- **Non-BMP names and SBCL.** SBCL's own file calls (`OPEN`, `PROBE-FILE`, `DELETE-FILE`, `RENAME-FILE`) pass names to Win32 as UCS-2 (`sb-win32` `system-string`), so they cannot create or name a file outside the BMP (`😀.txt` → `c-string-encoding-error :ucs-2le`). The journal is not affected: it reads `FILE_NOTIFY_INFORMATION` and lists directories with `FindFirstFileW` as UTF-16, so it reports such a name exactly. The test makes, edits and deletes the file through `CreateFileW`/`WriteFile`/`DeleteFileW` (`put-wide`, `delete-wide` in `tests/support.lisp`). A consumer that needs to read such a file needs the same kind of path; that is SBCL's limitation, not the journal's.
- **Ancestors of a watched root cannot be renamed.** NTFS refuses to rename a directory while a handle is open below it, whatever its share mode: `MoveFileExW` (or `ren`) of an ancestor fails with `ERROR_ACCESS_DENIED` while the journal is open, and succeeds once it is closed. The watched root itself can be renamed and deleted (`FILE_SHARE_DELETE`). So an ancestor rename cannot happen under an open journal: the failed attempt changes nothing, the next drain is `(nil t)` and later edits are reported, complete. The per-drain final-path check stays; it still catches a renamed root, and an ancestor rename on a file system that allows it.
- **SBCL leaks a process handle per Lisp thread (upstream SBCL limitation).** On SBCL 2.6.7 for Windows, every Lisp thread created and joined leaves one process handle open: `create_lisp_thread` stores the `_beginthreadex` handle in `th->os_thread`, `new_thread_trampoline` then overwrites it with a `DuplicateHandle` copy (`ASSOCIATE_OS_THREAD`), and the join closes only the copy. Measured with 50 bare `sb-thread:make-thread`/`join-thread` cycles and no journal code: 117 → 167 handles. Each journal owns one watcher thread, so each `fs-watch`/`journal-close` cycle costs one handle until SBCL fixes it; the journal itself leaks none (its directory handle and events are closed, `rdcw-handle-count` returns to its value). The no-leak test measures the per-thread leak itself and allows exactly that. Not filed upstream.

## Out of scope

The USN change journal (`FSCTL_READ_USN_JOURNAL`: volume-wide, needs admin for some operations, would give resumable ids) · fanotify (Linux) · IOCP or completion-routine variants (one thread per journal is fine at area scale) · `ReadDirectoryChangesExW` with `FILE_NOTIFY_EXTENDED_INFORMATION` (Windows 10 1709+; would give file ids for rename pairing) · network volumes (`:poll`) · writes through a handle still open at drain time (NTFS reports size and last-write at cleanup; the next drain after close reports them) · memory-mapped writes · journals on zip or memory filesystems · ECL / CCL CI jobs.

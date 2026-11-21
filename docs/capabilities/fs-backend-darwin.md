# fs-backend-darwin (R4b-2) — FSEvents change journals

**Repo:** [`egao1980/fs-backend-darwin`](https://github.com/egao1980/fs-backend-darwin) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) R4 detail, rung R4b · **Protocol:** [pathlib.md § R4b-0](pathlib.md#r4b-0--locked) (`cl-stack-pathlib` 0.9.0)
**Status:** **R4b-2 locked**, version **0.1.0**. Contract on branch `agent/r4b2-contract-65ba` (`fs-backend-darwin/tests`, Rove): given code, stubs (`%r4b2-pending`) and the failing tests. Implementation via **team-solve**. **R4c-1 locked** (below): `:clonefile` APFS clones, version **0.2.0**, on `cl-stack-pathlib` 0.10.0's clone protocol; contract not yet authored (`%r4c1-pending`).

The macOS mechanism for the R4b-0 journal protocol. Loading the system registers `:fsevents`; on macOS, `fs-watch … :mechanism :auto` and `fs-open-area … :journal :auto` then pick it for local directories with no consumer change, and `fs-area-changes` rehashes only the drained paths. The verdict is the same as every R4b backend: `cl-stack-pathlib/journal-suite` passes with `:fsevents`, i.e. the journal result is EQUAL to the full rescan after every corpus step.

---

## Decisions

| Decision | Choice |
|----------|--------|
| **Package** | `fs-backend-darwin`, local nickname `sp` for `cl-stack-pathlib`. One system plus `fs-backend-darwin/tests` |
| **Dependencies** | `cl-stack-pathlib` 0.9.0, `cffi` 0.24.1, `bordeaux-threads` 0.9.4 (bt2 API, [concurrency.md](concurrency.md)), `uiop`. CFFI because it is the stack's FFI (the libuv, ICU, SSL, pty and WinHTTP backends use it); no other library |
| **Natives** | None to build: CoreServices (FSEvents) and CoreFoundation are system frameworks. `src/ffi.lisp` opens both through `cffi:use-foreign-library` at ASDF load time by absolute path (`/System/Library/Frameworks/<F>.framework/<F>`, served from the dyld shared cache), `#+darwin` only (AGENTS.md CFFI rule). No overlay, no `:cl-repo` properties; published with `publish-source.yml` |
| **Registration** | At load, on every OS: `(register-watch-mechanism :fsevents 'make-fsevents-journal :rank 100 :available-p 'fsevents-available-p)`. The probe is true on macOS for a `local-filesystem` (memory, zip and off-macOS → NIL), so `:fsevents` ranks above `:poll` where it works and is invisible elsewhere. Off macOS the system still loads and `fs-watch :mechanism :fsevents` signals `unsupported-operation` (protocol rule) |
| **Stream** | One `FSEventStream` per journal over the root's **truename**, `kFSEventStreamEventIdSinceNow`, flags `+fsevents-create-flags+` = `NoDefer \| WatchRoot \| FileEvents` (per-file events; the first event of a batch at once; RootChanged when the root or an ancestor moves). Latency `*fsevents-latency*` (default 0.01 s) — drains never wait for it |
| **Threading** | The stream is scheduled on the **run loop of a Lisp thread the journal owns** (`bt2:make-thread`, `FSEventStreamScheduleWithRunLoop` + `CFRunLoopRun`). The FSEvents callback (`cffi:defcallback`) therefore only runs on a Lisp thread; no dispatch-queue (foreign) thread ever enters Lisp. The callback adds root-relative paths to a pending set under a lock, or sets an "incomplete" mark. `fsevents-journal-thread` exposes the thread (NIL once closed) |
| **Drain** | `FSEventStreamFlushSync`, then take and clear the pending set and the mark under the lock: `(values paths t)`, or `(values nil nil)` when marked. `:settle` bounds any further wait; a mechanism that cannot be sure answers NIL. Normalization (dedup, sort, ignore, `""` → rescan) is the protocol's `:around` |
| **Drain, as shipped (0.1.0)** | `FSEventStreamFlushSync` only hands over events fseventsd already holds, and fseventsd receives them ~10 ms after the write returns, so one flush per drain reports every write one drain late (measured: 0/8). The drain therefore flushes every 2 ms for `max(settle, *fsevents-minimum-settle*)` (internal, default 0.05 s; 8/8 delivered), also at `:settle 0`. `fs-watch` runs the same window once after start and discards it, so pre-watch writes stay out of the first drain. Cost ≈ 50 ms per drain and per watch. A drain whose root is gone answers `(nil nil)` | Measured during team-solve R4b-2; the alternative is a late report, which breaks the journal law |
| **Incomplete** | An event carrying any of `+incomplete-event-flags+` — MustScanSubDirs, UserDropped, KernelDropped, EventIdsWrapped, RootChanged, Mount, Unmount — makes the next drain `(values nil nil)`; the drain after it is complete again. MustScanSubDirs is not narrowed to its directory in 0.1.0 (simple and safe; a later version may). HistoryDone and item flags never do |
| **Paths** | `fsevents-relative-path root path &key case-sensitive` (pure, every OS): by whole components; `/var`, `/tmp`, `/etc` ≡ `/private/…` on either side; ROOT's components compared ignoring case unless CASE-SENSITIVE; the relative part keeps the event's (on-disk) spelling. The journal passes its root truename and `(volume-case-sensitive-p root)` (`pathconf _PC_CASE_SENSITIVE`). Paths outside the root are dropped; the root itself gives `""` (rescan) |
| **Close** | `journal-close` (runs once, protocol `:around`): `FSEventStreamStop`, `Invalidate`, `Release`, `CFRunLoopStop` on the journal's run loop, join the thread. Works from any thread and after the root was deleted. `fsevents-journal-stream` and `-thread` become NIL; `fsevents-stream-count` drops by one |
| **Close, as shipped (0.1.0)** | Same calls, different threads: close takes the ops lock (excludes a drain mid-flush), asks the run loop to stop (re-sent every 2 ms until the loop has exited, since a stop that lands before `CFRunLoopRun` starts is lost), and the run-loop thread itself does `Stop` / `Invalidate` / `Release` before close joins it. Close on the run-loop thread sends one stop and does not join | Teardown never races a callback in flight |
| **Errors** | `fsevents-error` (a `cl-stack-pathlib:journal-error`, slot `operation`): stream create / schedule / start failed. The constructor leaves no thread or stream behind when it signals |
| **Test hook** | `fsevents-journal-inject journal paths flags` delivers events through the callback's own code (absolute native paths, FSEvents flag integers). Real overflow cannot be forced reliably, so the incomplete-flag tests inject; RootChanged is also tested for real (root renamed, root deleted) |
| **Stubs** | The contract calls `%r4b2-pending` (internal, `src/paths.lisp`). The implementation removes it and every call |

## Surface

```lisp
;;; Mechanism (registered at load)
+fsevents-rank+                         ; 100
(fsevents-available-p fs directory) → generalized boolean   ; macOS and local-filesystem
(make-fsevents-journal fs directory matcher) → fsevents-journal   ; the registered constructor
fsevents-journal (sp:journal)           ; :mechanism :fsevents
(fsevents-journal-thread journal) → thread | NIL
(fsevents-journal-stream journal) → foreign pointer | NIL
(fsevents-stream-count) → integer       ; streams open in this image
*fsevents-latency*                      ; 0.01d0 seconds

;;; Paths
(fsevents-relative-path root path &key (case-sensitive t)) → string | "" | NIL
(volume-case-sensitive-p directory) → boolean        ; T off macOS

;;; Test hook
(fsevents-journal-inject journal paths flags) → NIL  ; closed → sp:journal-error

;;; Conditions
fsevents-error (sp:journal-error): fsevents-error-operation

;;; Constants (FSEvents.h)
+create-flag-use-cf-types+ +create-flag-no-defer+ +create-flag-watch-root+
+create-flag-ignore-self+ +create-flag-file-events+ +fsevents-create-flags+
+event-flag-none+ +event-flag-must-scan-sub-dirs+ +event-flag-user-dropped+
+event-flag-kernel-dropped+ +event-flag-event-ids-wrapped+ +event-flag-history-done+
+event-flag-root-changed+ +event-flag-mount+ +event-flag-unmount+
+event-flag-item-created+ … +event-flag-item-cloned+ +incomplete-event-flags+

;;; Through the protocol
(sp:fs-watch fs dir :mechanism :fsevents) (sp:journal-drain j) (sp:journal-close j)
(sp:open-area base)                     ; :journal :auto → :fsevents on macOS
```

## Contract (tests)

`fs-backend-darwin/tests` (Rove). Off macOS every FSEvents test records a **skip with a note**; the registry, availability and path-table tests run everywhere. CI: the canned `test-system.yml` on macOS, Linux and Windows.

| File | Covers |
|------|--------|
| `registry-test.lisp` | `:fsevents` registered and ahead of `:poll`; rank and flag constants; unavailable on a memory filesystem; macOS: first for a local directory; elsewhere: unavailable, `unsupported-operation`, `:auto` → `:poll` |
| `paths-test.lisp` | `fsevents-relative-path` table (child, nested, root → `""`, outside and sibling-prefix → NIL, `/private/var` ↔ `/var`, `/tmp`, `/etc`, non-alias `/private/opt`, case-insensitive root with the event's spelling kept, case-sensitive default, non-ASCII); `volume-case-sensitive-p` against a probe (macOS) |
| `journal-test.lisp` | basics (class, mechanism, stream, live thread, stream count; empty drain `(nil t)`; an edit reported precisely, siblings not covered; create / delete / mkdir / rename covered; drains consume); ignore matcher; only post-watch changes; **incomplete flags** (MustScanSubDirs, UserDropped, KernelDropped, EventIdsWrapped, RootChanged, Mount, Unmount, injected) → `(nil nil)` then recovery; injected plain events (canonical and `/var` spellings, outside paths dropped, root event → rescan); **root renamed / deleted for real** → `(nil nil)`; **`/var` vs `/private/var`** watch spellings; **case-insensitive volume** (root watched in another case, on-disk spelling, case-only rename reports both names); **flush on drain** (latency 5 s, drains with settle 0 and 0.05 report at once, < 1.5 s); 2000-file burst (all covered, or incomplete with no paths); **close** (thread joined, stream released, count restored, idempotent, drain / inject after close → `journal-error`, after the root was deleted, from another thread); areas get `:fsevents` by `:auto` and close it; **no leak**: 50 open / write / drain / close cycles leave thread and stream counts unchanged |
| `suite-test.lisp` | `run-journal-suite :fsevents` (settle 0.05 and 0) with every applicable step run (incl. case-only rename, burst, child process); `run-journal-suite :auto` |

## Out of scope

Narrowing MustScanSubDirs to its subtree · persistent event ids across journals (`sinceWhen` resume) · `FSEventStreamSetDispatchQueue` (a later version may switch once foreign-thread callbacks are proven on every supported SBCL) · per-volume device streams (`FSEventStreamCreateRelativeToDevice`) · journals on zip or memory filesystems · Linux (R4b-1, `fs-backend-linux`) and Windows (R4b-3, `fs-backend-windows`).

---

## R4c-1 — locked

APFS clones for the R4c-0 clone protocol ([pathlib.md § R4c-0](pathlib.md#r4c-0--locked), `cl-stack-pathlib` 0.10.0), in **fs-backend-darwin 0.2.0**. Loading the system also registers `:clonefile`. On macOS, `clone-tree … :mechanism :auto` and `open-area` (default `:auto`) then clone on APFS with no consumer change. The verdict is the same as for every R4c backend: `cl-stack-pathlib/clone-suite` passes with `:clonefile`, so the tree, its metadata and `fs-area-changes` equal those of `:copy`. Unlike R4b-1, the whole contract runs on macOS, so `check-feature.sh` on a Mac is the real verdict.

### Decisions

| Decision | Choice |
|----------|--------|
| **Dependencies** | `cl-stack-pathlib` ≥ 0.10.0 (bump the `:version` dep), `cffi`, `uiop`, as in 0.1.0. `clonefile`, `getattrlist` and `stat` are in libSystem, which every image already has open: no library to load, nothing new to ship. Off macOS each binding is a Lisp stand-in that signals `clonefile-error` (the 0.1.0 pattern), so the system loads everywhere with no undefined-alien warnings. |
| **Registration** | At load, on every OS: `(register-clone-mechanism :clonefile 'clonefile-file :rank +clonefile-rank+ :available-p 'clonefile-available-p :clone-tree 'clonefile-tree)`, `+clonefile-rank+` = 100. |
| **Availability** | `clonefile-available-p fs source-dir destination-dir` → `(values available-p reason)`, checked in this order. Off macOS: `(nil :unavailable)`. FS not a `local-filesystem`: `(nil :unsupported-filesystem)`. The source volume lacks `VOL_CAP_INT_CLONE`: `(nil :unsupported-volume)`. The capability comes from `getattrlist(ATTR_VOL_INFO \| ATTR_VOL_CAPABILITIES)` on the directory: bit #x00010000 of the `VOL_CAPABILITIES_INTERFACES` word, set in both `capabilities` and `valid`. HFS+, exFAT, FAT, SMB and NFS answer NIL. `st_dev` of the two directories differ: `(nil :cross-volume)`. Two APFS volumes of one container are two devices, and `clonefile` refuses them with `EXDEV`. Otherwise T. No cache: both calls are microseconds, and a cache keyed by `st_dev` goes stale when an image is detached and the number reused. |
| **Per file** | `clonefile-file fs source destination` → `clonefile(src, dst, CLONE_NOFOLLOW \| CLONE_NOOWNERCOPY)` (#x1 \| #x2) on the native namestrings (UTF-8). Results: 0 → T. `ENOTSUP` → `(nil :unsupported-volume)`. `EXDEV` → `(nil :cross-volume)`. Anything else (`EACCES`, `EPERM`, `ENOSPC`, `EDQUOT`, `EIO`, `ENAMETOOLONG`, `EEXIST` — pathlib guarantees DST is absent) → **`clonefile-error`**, a `cl-stack-pathlib:clone-error` (`clone-error-operation` "clonefile", `clone-error-code` = errno), so pathlib's `use-copy` restart applies. `clonefile` either makes DST or leaves nothing, so there is nothing to clean up. The clone keeps mode, mtime, flags and xattrs on its own, and pathlib sets bits and mtime afterwards anyway (no harm). |
| **Tree hook** | `clonefile-tree fs source destination matcher`. With a MATCHER it declines (NIL), because `clonefile` of a directory cannot skip ignored paths. With MATCHER NIL it first walks SOURCE with `lstat` only (no reads). It declines if it finds anything the R4c-0 walk would treat differently: an entry that is not a regular file, directory or symlink, a regular file with more than one link, or a setuid / setgid / sticky bit. Otherwise it `clonefile`s each top-level entry of SOURCE into the empty DESTINATION (one call per entry clones a whole subtree) and returns the number of regular files the walk counted. A failing call removes what the hook made and signals as per file. (Areas use `:ignore :auto`, so they take the per-file path; `clone-tree` with no ignore takes the hook.) |
| **Volume helpers** | `volume-supports-clone-p directory` → boolean. `volume-device directory` → `st_dev` integer. Both follow symlinks and signal `clonefile-error` off macOS or for a missing directory. |
| **Stubs** | The contract calls `%r4c1-pending` (internal, `src/clone.lisp`). The implementation removes it and every call. |

### Surface

```lisp
+clonefile-rank+                                            ; 100
(clonefile-available-p fs source-dir destination-dir) → (values available-p reason)
(clonefile-file fs source destination) → T | (values nil reason)   ; signals CLONEFILE-ERROR
(clonefile-tree fs source destination matcher) → count | NIL
(volume-supports-clone-p directory) → boolean    (volume-device directory) → integer
clonefile-error (cl-stack-pathlib:clone-error)  ; operation "clonefile" | "getattrlist" | "stat"
+clone-nofollow+ +clone-noownercopy+ +vol-cap-int-clone+ +attr-vol-info+ +attr-vol-capabilities+
;; through the protocol
(sp:clone-tree src dst)  (sp:clone-supported-p dir)  (sp:open-area base)   ; :auto → :clonefile
```

### Contract (tests)

`fs-backend-darwin/tests` (Rove, beside the R4b-2 files). Tests that need macOS record a skip with a note elsewhere. Test volumes are **disk images the tests make themselves**: `tests/support.lisp` has `with-disk-image ((dir &key (fs "APFS") (size "64m")) &body)`, which runs `hdiutil create -fs <fs> -size <size> -volname r4c-<hex>` in a temp directory and `hdiutil attach -nobrowse -noautoopen -noverify -mountpoint <dir>`, and always `hdiutil detach -force` afterwards. No root is needed: tried on macOS 26 as a normal user, and GitHub's macOS runners run as an admin user. A failed `hdiutil` is a **failure, not a skip**, so CI can never pass by skipping.

| File | Covers |
|------|--------|
| `clone-registry-test.lisp` | `:clonefile` registered, rank 100, ahead of `:copy`, beside `:fsevents`; constants; memory → `:unsupported-filesystem`; off macOS `(nil :unavailable)` and `clone-tree :mechanism :clonefile` → `unsupported-operation` |
| `clone-test.lisp` | macOS. **Detection:** the temp directory (APFS) is supported; an HFS+ image `(nil :unsupported-volume)`; temp → APFS image `(nil :cross-volume)`; within the APFS image, supported; `volume-device` differs across images. **Per file:** content, mode, mtime; `ENOTSUP` (HFS+ to HFS+ called directly) → `(nil :unsupported-volume)`; `EXDEV` (temp → image) → `(nil :cross-volume)`; `EACCES` (destination directory #o555) → `clonefile-error` with errno 13, and `use-copy` offered. **Sharing is real:** on a fresh APFS image, `statfs` free blocks drop by less than 1 MiB when a 32 MiB random file is cloned, and by at least 32 MiB when it is copied; a 1 MiB write into the clone costs about 1 MiB, and the source's hash is unchanged. **Hook:** used with no ignore (one `clonefile` per top-level entry, recorded through `*clonefile-trace*`), declined with a matcher, a FIFO, a hard link, or a setuid file, and the tree equals the per-file one; a hook failure leaves the destination empty. **Areas:** `open-area` on APFS is `:clone` with `:clonefile`; on an HFS+ image it is `:copy` with `:unsupported-volume` |
| `clone-suite-test.lisp` | `(run-clone-suite :clonefile)` in the temp directory; `(run-clone-suite :clonefile :directory apfs :other-volume hfs)` in images (every step, `:cross-volume` included); `(run-clone-suite :clonefile :other-volume apfs)` from the temp volume (APFS → APFS across volumes) |

CI is the canned `test-system.yml` (macOS grades, Linux and Windows load and skip) plus `publish-checkout.yml`. No workflow change.

### Out of scope

APFS snapshots (need an entitlement) · `copyfile(3)` `COPYFILE_CLONE` (does the same through more layers) · ACLs, xattrs and flags beyond what `clonefile` keeps by itself · cloning across APFS volumes (impossible) · `fclonefileat` / `clonefileat` (pathlib works with absolute paths).

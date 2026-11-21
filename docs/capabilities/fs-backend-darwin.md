# fs-backend-darwin (R4b-2) — FSEvents change journals

**Repo:** [`egao1980/fs-backend-darwin`](https://github.com/egao1980/fs-backend-darwin) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) R4 detail, rung R4b · **Protocol:** [pathlib.md § R4b-0](pathlib.md#r4b-0--locked) (`cl-stack-pathlib` 0.9.0)
**Status:** **R4b-2 locked**, version **0.1.0**. Contract on branch `agent/r4b2-contract-65ba` (`fs-backend-darwin/tests`, Rove): given code, stubs (`%r4b2-pending`) and the failing tests. Implementation via **team-solve**.

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

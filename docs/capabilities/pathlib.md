# cl-stack-pathlib — CLOS paths and pluggable filesystems

**Repo:** [`egao1980/cl-stack-pathlib`](https://github.com/egao1980/cl-stack-pathlib) (nick `stack-pathlib`) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H (H2) and R4
**Status:** 0.8.0 shipped (local / memory / `zip://`, restarts, H2a agent-tool operations, R4a snapshots + copy areas, store GC). **R4b-0 brief locked** (change journals: protocol + `:poll` fallback, 0.9.0); contract on branch `agent/r4b0-contract-c0af` (`cl-stack-pathlib/tests`, Rove, with the reusable `cl-stack-pathlib/journal-suite`). Implementation via **team-solve**. **R4b-2 brief locked:** [fs-backend-darwin.md](fs-backend-darwin.md) (`:fsevents`, `egao1980/fs-backend-darwin` 0.1.0). **R4b-3 brief locked:** [fs-backend-windows.md](fs-backend-windows.md) (`:rdcw`, `egao1980/fs-backend-windows` 0.1.0). **R4c-0 brief locked** (copy-on-write clones: protocol + the portable `:copy` rung, 0.10.0); contract on branch `agent/r4c0-contract-d65b` ([PR #46](https://github.com/egao1980/cl-stack-pathlib/pull/46); `cl-stack-pathlib/tests`, Rove, with the reusable `cl-stack-pathlib/clone-suite`). **R4c-1 / R4c-2 / R4c-3 briefs locked:** `:clonefile` ([fs-backend-darwin.md](fs-backend-darwin.md#r4c-1--locked)), `:ficlone` ([fs-backend-linux.md](fs-backend-linux.md#r4c-2--locked)), `:block-clone` ([fs-backend-windows.md](fs-backend-windows.md#r4c-3--locked)), 0.2.0 each.

A `path` is a value bound to a `filesystem`; the `fs-*` generic functions are the SPI (shaped like Java NIO `FileSystemProvider`), and the facade (`read-text`, `walk`, `glob`, …) is the pathlib / NIO `Files` DX over them. Backends today: `local-filesystem`, `memory-filesystem`, `zip-filesystem` (read-only). Errors are CLHS 9 conditions with restarts at the signal site (`create-parents`, `create-file`, `overwrite`, `ignore-missing`, `use-value`) and `retry` at the operation site — the stack's reference for [conditions.md](conditions.md).

---

## Packaging (locked, from the plan)

`cl-stack-pathlib` is a base dependency of `cl-stack-http`, `cl-stack-calendars`, `cl-stack-tzdata`, `spec-backend-quint` and others. It gets new GFs and **portable** code only, stays pure Lisp, and takes **no new dependencies** (today: `uiop`, `sb-posix` on SBCL, `compression-protocol`, `compression-backend-chipz`). OS mechanisms (`clonefile`, `FICLONE`, FSEvents, …) live in `egao1980/fs-backend-darwin` / `-linux` / `-windows` (R4b+), which specialize the same GFs.

---

## H2a — locked

First slice of the H2 tool layer: what `agent-tools` read / write / edit / glob / grep need from the filesystem. Implemented for **local and memory**; **zip** gets every read-side operation (read-only). Version **0.4.0**.

### Decisions

| Decision | Choice |
|----------|--------|
| **Dependencies** | None added. |
| **Where code goes** | Portable default methods on `filesystem` (over `fs-read-bytes`, `fs-iterdir`, `fs-file-size`, `fs-last-modified`, …), so memory and zip work unchanged and a third-party backend gets everything by implementing the base protocol. `local-filesystem` specializes where streaming or the OS matters: `fs-read-range` (`file-position`), `fs-read-lines` (stops after END), `fs-content-hash` (chunked), `fs-write-atomic`, `fs-stat` (mode), `fs-open`. `memory-filesystem` specializes `fs-write-atomic` and `fs-open`. |
| **Hash algorithm** | **SHA-256, pure Lisp, inside pathlib** (FIPS 180-4) with an incremental core (init / update over an octet range / final). `crypto-protocol` is not used: it needs a backend (Ironclad) at run time, a new dependency for every pathlib consumer. `sxhash` / FNV are not content hashes (not stable across implementations, collisions). |
| **Hash format** | OCI digest string `"sha256:" + 64 lowercase hex`. Same token for `fs-content-hash`, `file-stat-hash`, `:expected-hash` and R4a content-addressed blob ids. (`lisp-source-protocol`'s `expected_hash` is an FNV-1a form/text hash with its own meaning; it is not replaced.) |
| **Regex** | **No regex engine** (cl-ppcre is not a pathlib dependency). `fs-grep` takes a literal string, or a function `line → start index or NIL`, so a caller can pass `(lambda (l) (ppcre:scan re l))`. `:regex t` goes through the hook GF `fs-grep-matcher (fs pattern &key case-insensitive)`; its default signals `unsupported-operation`. |
| **Ignore syntax** | gitignore(5) semantics, verified against real git (corpus below). `.ignore` uses the same syntax (ripgrep convention) and wins over `.gitignore` in the same directory. |
| **Text** | UTF-8 only (same as `read-text`). Lines split at LF; one trailing CR removed. |
| **Stubs** | The contract calls `%h2a-pending` (internal, `src/protocol.lisp`); the implementation removes it and every call. |

### Surface

```lisp
;;; Ranged / streaming reads
(fs-read-range fs pathname start end)          ; → octets [START, END); END NIL = EOF; END clamped;
                                               ;   START >= size → #(); START > END → ERROR; missing → PATH-NOT-FOUND
(fs-read-lines fs pathname &key (start 1) end) ; → (values lines more-p); 1-based, both inclusive
(fs-open fs pathname &key (direction :input) (element-type '(unsigned-byte 8)))  ; → input stream
(read-range designator start &optional end)  (read-lines designator &key start end)
(open-path designator &key direction element-type)  (with-open-path (var designator &rest keys) &body body)

;;; Hashes
(octets-hash octets &key (start 0) end)        ; → "sha256:…"; any vector of octets
(fs-content-hash fs pathname)  (content-hash designator)   ; missing → PATH-NOT-FOUND; directory → PATH-ERROR

;;; Atomic + compare-and-swap writes
(fs-write-atomic fs pathname bytes &key expected-hash)     ; → (values pathname hash written-p)
(write-bytes designator bytes &key append atomic expected-hash)   ; ATOMIC / EXPECTED-HASH → (values path hash written-p)
(write-text designator text &key encoding append atomic expected-hash)
content-hash-mismatch (path-error): content-hash-mismatch-expected, content-hash-mismatch-actual
restarts: overwrite (existing symbol), use-current (new);  invoke-use-current (new), invoke-overwrite / auto-overwrite work

;;; Stat
(fs-stat fs pathname &key (follow-symlinks t))  (stat designator &key follow-symlinks)  ; → file-stat
file-stat-path file-stat-kind file-stat-size file-stat-mtime file-stat-mode file-stat-hash

;;; Ignore matcher
(parse-ignore source &key (base ""))           ; SOURCE: file text or list of lines; BASE "" or "sub/"
(merge-ignore &rest matchers)                  ; later = higher precedence; NIL skipped
(ignore-path-status matcher relpath &key directory)  ; → :ignored | :included | NIL  (RELPATH alone)
(ignore-path-p matcher relpath &key directory) ; → T when RELPATH or an ancestor directory is :ignored
(load-ignore-files fs root &key (names '(".gitignore" ".ignore")))  ; → matcher for every ignore file under ROOT
ignore-matcher, ignore-matcher-p

;;; walk / glob
(fs-walk fs pathname &key top-down follow-symlinks ignore)       ; IGNORE added to the GF
(fs-glob fs pathname pattern &key recursive ignore)              ; IGNORE added to the GF
(walk designator &key top-down follow-symlinks ignore)  (glob designator pattern &key recursive ignore)  (rglob designator pattern &key ignore)

;;; Grep
(fs-grep fs root pattern &key (ignore :auto) include regex case-insensitive max-results)  ; → (values matches truncated-p)
(fs-grep-matcher fs pattern &key case-insensitive)               ; regex hook
(grep root pattern &key ignore include regex case-insensitive max-results)   ; GREP-MATCH-PATH is a PATH
grep-match: grep-match-path grep-match-line grep-match-column grep-match-text
```

### Semantics

**`fs-read-lines`.** `"a\nb"` → `("a" "b")`; `"a\n"` → `("a")`; `"\n\n"` → `("" "")`; `""` → `()`. `more-p` is true when at least one line exists after END. START past the last line → `(values nil nil)`. Local reads only as far as END + 1 lines.

**`fs-open`.** `:direction :input` only (else `unsupported-operation`); missing → `path-not-found`. Octet streams support `read-byte` / `read-sequence`; `'character` streams decode UTF-8 and support `read-char` / `read-line`. Local: `cl:open`. Memory / zip: an octet input stream over the content built on the implementation's own Gray streams (`sb-gray` on SBCL, `gray` on ECL; no `trivial-gray-streams`), and `make-string-input-stream` over the decoded text for characters. Output streams are not in H2a (writes go through `fs-write-bytes` / `fs-write-atomic`).

**`fs-write-atomic`.**
- Readers see the old or the new content, never a mix. Local: write a temp file **in the target's directory** (name `.<name>.<random hex>.tmp`), `finish-output`, then `rename(2)` over the target (`sb-posix:rename` on SBCL, the ECL equivalent; not `cl:rename-file`, which merges pathname defaults). Memory: one table update. Zip: `unsupported-operation`.
- No temp file survives, on success or on failure (`unwind-protect` deletes it). On failure the target keeps its old content.
- Missing parent directories are created. A target that is a directory → `path-error`.
- A symlink target is written **through**: the link stays a link, the file it points to gets the content. Local keeps the permission bits of the file it replaces.
- `:expected-hash` NIL: no check. A digest string: the current content must have that hash. `:absent`: the file must not exist (create-only). Otherwise `content-hash-mismatch` (expected = the argument, actual = current digest or NIL when missing) with restarts **`overwrite`** (write anyway) and **`use-current`** (write nothing, return `(values pathname current-hash nil)`).
- Returns `(values pathname hash written-p)`; HASH is the token for the next CAS write.
- The check and the rename are not one atomic step against **other processes** (no OS file locks in H2a); in-process races between harness tools are the caller's to serialize (`agent-tools`, H2). The window is one hash + one rename.
- Facade: `:atomic` or `:expected-hash` routes `write-bytes` / `write-text` to `fs-write-atomic`; combining either with `:append` signals an error.

**`fs-stat`.** Kind `:file` / `:directory` / `:symlink` (only with `:follow-symlinks nil`) / `:other`. Size in octets, 0 for directories. Mtime a universal time, or NIL where the backend does not track it (memory and zip directories). Mode = `(logand st_mode #o7777)` on local (SBCL / ECL on unix), NIL for memory and zip. `file-stat-hash` is computed by `fs-content-hash` **at its first call, not by `fs-stat`**, then cached; NIL for non-files. Missing → `path-not-found`.

**Ignore matcher** (gitignore(5)):
- Blank lines and `#` lines are not rules; `\#` and `\!` escape a leading `#` / `!`. Trailing spaces are dropped unless escaped (`foo\ `). A trailing CR is dropped (pathlib choice, for CRLF files).
- `!pat` re-includes. `pat/` matches directories only. A `/` at the start or in the middle anchors the pattern to BASE; otherwise it matches at any depth.
- `*`, `?`, `[a-z]`, `[!x]`, `[^x]` never match `/`. `**/x`, `x/**`, `a/**/b` span any number of directories (zero included); any other `**` is a plain `*`. POSIX classes (`[[:alpha:]]`) are out of scope for H2a.
- Case-sensitive.
- The last matching rule wins. A path under an ignored directory is ignored whatever later rules say: `ignore-path-status` can return `:included` while `ignore-path-p` is true (`build/` + `!build/keep.txt`).
- Nested files: `parse-ignore` with `:base "sub/"`, merged root first. `load-ignore-files` reads NAMES in each directory under ROOT (in NAMES order, so `.ignore` beats `.gitignore`), deeper beats shallower, skips directories already ignored and never reads inside `.git/`. Ignore files above ROOT are not read; callers that want them merge their own matcher.
- **Corpus:** `tests/fixtures/gitignore-corpus.sexp`, 18 cases / 76 path verdicts recorded from real git 2.54.0 (`git check-ignore`, cross-checked with `git ls-files --others --ignored --exclude-standard`; `core.ignorecase=false`). Regenerate with `tests/fixtures/gen-gitignore-corpus.py`. Edge cases git confirmed: `file?.txt` does not match `file10.txt`; `[ab]*.c` matches `ax.c`; `node_modules` (no slash) ignores `pkg/node_modules/z.js`; `a/**/b` matches `a/b` but not `c/a/b`; `!build/keep.txt` cannot re-include under `build/`; `/*` + `!/foo` + `/foo/*` + `!/foo/bar` keeps only `foo/bar`; `logs/` + `!logs/` re-includes `logs/a.txt`; `*` + `!*/` + `!*.lisp` keeps `.lisp` files at any depth.

**`:ignore` on walk / glob.** NIL (default; unchanged behaviour), an `ignore-matcher` (patterns relative to the walk / glob base) or **`:auto`** = `load-ignore-files` under the base **plus `.git/` always pruned**. Ignored files are left out of FILES; ignored directories are left out of DIRS and **not descended** (`top-down` either way). The base itself is never tested. Ignore files are ordinary files and are listed. `glob` / `rglob` drop ignored results and do not descend into ignored directories.

**`fs-grep`.**
- ROOT is a directory (walked with IGNORE, default **`:auto`**) or a single file.
- PATTERN: a string — literal substring (`char-equal` when CASE-INSENSITIVE), or a regex through `fs-grep-matcher` when REGEX — or a function of the line returning the match start or NIL.
- INCLUDE: NIL, a string or a list of strings in `.gitignore` glob syntax relative to ROOT; a file is searched when `ignore-path-p` of the INCLUDE matcher is true for it (`"*.lisp"` at any depth, `"src/"` everything under src, `"!x"` to subtract). INCLUDE filters files only; it never prunes directories.
- Skipped: files with a NUL octet in their first 8000 octets (git / ripgrep heuristic) and files that are not valid UTF-8 (strict decoding; the lenient `utf8-octets-to-string` is not enough).
- One `grep-match` per matching line: path, 1-based line, 0-based column of the first match, the line without terminator. Sorted by path namestring (`string<`), then line.
- MAX-RESULTS: at most that many matches; `truncated-p` true when at least one more existed (exactly MAX-RESULTS matches → NIL).
- Facade `grep` wraps paths as `path` objects.

### Contract (tests)

`cl-stack-pathlib/tests`, Rove `deftest-parametrize` over `(:local :memory)` (temp directory / fresh memory fs, `tests/h2a-support.lisp`), plus zip cases. 59 existing tests pass; 97 new tests fail on the stubs.

| File | Covers |
|------|--------|
| `hash-test.lisp` | SHA-256 vectors (FIPS 180-2 + padding boundaries + UTF-8), subranges, non-simple vectors; `content-hash` on local / memory (multi-chunk 300 KB file, empty, missing, directory) and zip |
| `read-range-test.lisp` | byte ranges (clamping, empty, START > END, missing), line ranges (CRLF, no final LF, blank lines, empty, UTF-8, `more-p`), `with-open-path` octet / character streams, `:output` refused; zip |
| `atomic-write-test.lisp` | no temp file after create / replace / failed write / directory target; parents created; CAS match, `:absent`, mismatch slots, ACTUAL NIL when missing; both restarts offered, `use-current`, `overwrite`, `auto-overwrite`, restarts on the protocol call; local symlink write-through + mode kept; zip unsupported |
| `ignore-test.lisp` | git corpus per case, pure (`parse-ignore` + `merge-ignore`) and loaded from a filesystem (`load-ignore-files`); status values, directory flag, text vs lines, CRLF, BASE scoping, merge order, `.ignore` precedence, `.git/` never read, `:names` |
| `walk-ignore-test.lisp` | walk unchanged without IGNORE; explicit matcher and `:auto` (files, dirs, pruned descent, bottom-up); glob / rglob with IGNORE; zip |
| `grep-test.lisp` | literal results and order, `:auto` ignore, binary / bad UTF-8 skipped, case-insensitive, `:ignore nil`, include forms, MAX-RESULTS / truncation, single-file root, function pattern, default regex hook refused, a specialized hook, zip |
| `stat-test.lisp` | kind / size / mtime / path, lazy and cached hash, directories, missing, symlinks followed or not, local mode, memory / zip mode NIL |

### Out of scope (later H2 slices / R4)

`fs-watch` (R4b, OS backends) · `jailed-filesystem` (H2b) · `agent-tools` read / write / edit / glob / grep / shell (H2b+) · output streams · regex engine in pathlib · OS file locks · R4a areas, snapshots, manifests (they reuse `fs-stat`, `fs-content-hash` and the ignore matcher from this slice).

---

## R4a — locked

First rung of the R4 ladder in the plan ("R4 detail — filesystem snapshots and sandboxed areas"): **content-addressed snapshots** and **sandboxed areas by folder copy with change tracking**. Portable code only, on the `filesystem` base protocol plus H2a (`fs-stat`, `fs-content-hash`, `fs-write-atomic`, ignore matcher). Local and memory backends; zip is not required. Version **0.5.0**. Journals (R4b), COW clones (R4c), confinement (R4d) and containers (R4e) live in `fs-backend-*` / `compute-backend-*` and specialize the same generics; consumers never change.

### Decisions

| Decision | Choice |
|----------|--------|
| **Dependencies** | None added. No `object-store-protocol`: pathlib has its own small `snapshot-store` protocol (memory and directory stores). An adapter onto `object-store-protocol` can live elsewhere. |
| **Snapshot id** | `octets-hash` (SHA-256, `"sha256:…"`) of the canonical **flat manifest** below. The manifest is itself a blob, so the snapshot id is the manifest's blob id. Same tree → same id on every run, machine, backend and store. |
| **Entries** | Regular files and symlinks under ROOT, minus ignored paths. **Directories are not entries** (git semantics: an empty directory does not change the id). Symlinks are not followed. |
| **Modes** | Three: `:file` (100644), `:executable` (100755), `:symlink` (120000). `:executable` = the **owner execute bit** of `st_mode` on a backend that reports modes (local on SBCL / ECL unix). Every other bit is ignored, so umask and group/other bits never change an id. Backends without modes (memory, local on Windows, zip) always give `:file`. A tree with an executable script therefore has a different id on Windows than on unix, which is the price of portable ids (git's `core.fileMode=false` has the same effect). |
| **Hashes** | File entry = `octets-hash` of the content. Symlink entry = `octets-hash` of the UTF-8 posix namestring that `fs-read-symlink` returns, stored as-is (memory stores absolute targets, local the raw `readlink(2)` string). |
| **Paths** | Relative POSIX strings, `/` separators, no leading or trailing `/`, exactly as named on disk (no Unicode normalization, case-sensitive). Sorted by `string<`, which is UTF-8 octet order. |
| **Change records** | `fs-change` values (kind, relative path, old/new mode, old/new hash), not `diff-protocol` diffs; an adapter elsewhere converts them. Same type for snapshot diffs, restores, area rescans and commits. |
| **Ignore** | `:ignore` NIL (default, as `fs-walk`), an `ignore-matcher` relative to ROOT / BASE, or `:auto` (`load-ignore-files` + `.git/` pruned). Ignored paths never enter snapshots, stores, area copies, area changes or commits, and restore / commit never touch them. An area resolves `:auto` **once, at open**, against the base (`area-ignore` returns the matcher). |
| **Area mtime check** | Manifest records path, mode, size, mtime and hash (the hash is taken while copying, since the content is read anyway; the plan's "hash on demand" would need the base content, which may have changed). Rescan: a file is hashed when its size or mtime differs from the record **or** its recorded mtime is not older than the open time minus 2 s (mtime is a universal time with 1 s granularity, FAT has 2 s: the racy-git rule). So same-size edits in the same second are found. The implementation may refresh records of unchanged files once they are no longer racy. |
| **Conflict restarts** | `overwrite` (existing pathlib restart), `skip-path` (new), `abort-commit` (new). **Not `cl:abort`**: a missing or misplaced `abort` restart would unwind to the toplevel or the test runner. Helpers `invoke-skip-path`, `invoke-abort-commit` (`invoke-overwrite` exists). |
| **Stubs** | The contract calls `%r4a-pending` (internal, `src/snapshot.lisp`); the implementation removes it and every call. |

### Manifest encoding (locked)

UTF-8 octets:

```
"cl-stack-pathlib tree v1" LF
entry*                                ; sorted by path, string< (= UTF-8 octet order)
entry := mode SP hash SP n SP path LF
mode  := "100644" | "100755" | "120000"
hash  := "sha256:" 64 lowercase hex   ; octets-hash of the content / symlink target
n     := decimal UTF-8 octet length of path   ; paths may contain SP or LF
```

Duplicate paths → `error` when encoding. A malformed manifest (bad header, bad mode, length mismatch, unsorted or duplicate paths) → `snapshot-error` when parsing.

Recorded ids (tests, `tests/r4a-support.lisp`, computed with `printf | shasum -a 256` and cross-checked with `octets-hash`):

| Tree | Id |
|------|----|
| empty (directories only) | `sha256:1b284e6bd3fc9dfcfe2a2b144e85535a790497a1671d5a5f9c6577fb7feeaba5` |
| fixed: `README.md` "hello\n", `src/a.lisp` "(defun a () 1)\n", `src/b/c.txt` "", `dir with space/é.txt` "ü\n", empty dir `empty/` | `sha256:2939372bedfa08ff2051af61095ae505cf23e2e5e8f73be092e55d11790c93c5` |
| fixed + `bin/run.sh` "#!/bin/sh\necho hi\n" with the execute bit | `sha256:1ead55ccb6ef37ce2bb4d759da189ff2dd27720195d455c1437bce84e5d48cba` |

### Surface

```lisp
;;; Values
(make-snapshot-entry path mode hash)    ; snapshot-entry: snapshot-entry-path / -mode / -hash
fs-change: fs-change-kind (:added :removed :modified :mode-changed) fs-change-path
           fs-change-old-mode fs-change-new-mode fs-change-old-hash fs-change-new-hash
(snapshot-manifest-octets entries) → octets      (parse-snapshot-manifest octets) → entries

;;; Stores
snapshot-store (protocol class), snapshot-store-p
(make-memory-snapshot-store)                     ; memory-snapshot-store
(make-directory-snapshot-store designator)       ; directory-snapshot-store; directory-snapshot-store-root → PATH
*snapshot-store*                                 ; default :STORE, a process-wide memory store
(snapshot-store-put store octets) → id           ; idempotent
(snapshot-store-get store id) → octets           ; absent → SNAPSHOT-NOT-FOUND
(snapshot-store-contains-p store id)

;;; Snapshots (protocol + facade)
(fs-snapshot fs root &key ignore store) → id
(fs-restore fs root snapshot &key store ignore) → changes
(fs-snapshot-changes store a b) → changes        ; NIL = the empty tree
(snapshot designator &key ignore store)  (restore-snapshot designator snapshot &key store ignore)
(snapshot-changes a b &key store)  (snapshot-entries snapshot &key store)

;;; Areas (protocol + facade)
(fs-open-area fs base &key (mechanism :copy) ignore directory) → area
(fs-area-changes area) → changes
(fs-close-area area &key (action :discard)) → (values changes status)
(open-area base &key mechanism ignore directory)  (area-changes area)  (close-area area &key action)
(with-area (var base &rest keys) &body body)     ; :discard on exit when still open
area: area-p area-filesystem area-base area-root (PATHs) area-mechanism area-ignore
      area-manifest (snapshot-entry list) area-open-p

;;; Conditions
snapshot-error (error): snapshot-error-store snapshot-error-id;  snapshot-not-found
area-error (error): area-error-area
area-conflict (area-error): area-conflict-path area-conflict-open-entry
                            area-conflict-base-entry area-conflict-area-entry
restarts: overwrite, skip-path, abort-commit;  invoke-skip-path, invoke-abort-commit
```

### Semantics

**Stores.** Memory: a hash table digest → octets. Directory: blob `sha256:<h>` is the file `blobs/sha256/<h[0..2]>/<h[2..64]>` under the store root, raw octets, written with `fs-write-atomic`; a blob already present is not rewritten; reads do not re-verify. The directory is created on the first write and reused by later store objects (snapshots outlive the process). A directory store may live on any backend; it must not be under a snapshotted ROOT unless ignored there.

**`fs-snapshot`.** Stores every entry blob, then the manifest, and returns the id. ROOT is not modified. A missing ROOT → `path-not-found`. Content of ignored paths is never read into the store.

**`fs-restore`.** Makes the tree under ROOT equal the snapshot: writes files whose content or mode differ (execute bit set or cleared to match the entry, where the backend has modes), creates symlinks, deletes files and symlinks not in the snapshot, then removes directories left empty (never ROOT). Ignored paths are neither written nor deleted. ROOT is created when missing. The manifest and every blob are checked first: an unknown snapshot → `snapshot-not-found` and nothing is touched. Returns the change list from the tree before the call to the snapshot (NIL when it already matched).

**`fs-snapshot-changes`.** Sorted by path. Same mode and hash → unchanged. Only the mode differs (`:file` ↔ `:executable`) → `:mode-changed`. Anything else that differs (content, or file ↔ symlink) → `:modified`. `:added` has NIL old fields, `:removed` NIL new fields. `(fs-snapshot-changes s a a)` is NIL; A or B NIL means the empty tree; unknown id → `snapshot-not-found`.

**Areas.**
- `fs-open-area`: MECHANISM `:copy` only; `:clone`, `:overlay`, `:virtual` and anything else → `unsupported-operation` before anything is created. BASE missing → `path-not-found`. DIRECTORY NIL → a fresh temp directory on FS (`fs-make-temp`, prefix `area-`; outside BASE); a given DIRECTORY must be absent or empty, else `path-exists-error` (left untouched). Copies files (content + execute bit), symlinks (as symlinks) and directories (empty ones too) of BASE minus IGNORE; records the manifest.
- `area-base` / `area-root` return directory PATHs on the area's filesystem. `area-manifest`: the base entries as copied, sorted by path.
- `fs-area-changes`: rescans the copy (see the mtime rule above), returns the change list from the manifest to the copy now, ignored paths left out. Edits from anything count: pathlib, `cl:open`, `/bin/sh`, another Lisp image. A file edited back to its original content is not a change. Equal to `fs-snapshot-changes` between a snapshot of the base at open and a snapshot of the area root with `area-ignore`.
- `fs-close-area :discard` (default): deletes the copy → `(values nil :discarded)`. `:keep`: leaves it → `(values nil :kept)`. Both leave the base untouched.
- `fs-close-area :commit`: computes the area changes, then checks **every** changed path against the base before writing. Path P conflicts when the base's entry now (absent, or mode + hash) differs from the manifest entry **and** from the area's entry (so identical edits and removals on both sides do not conflict). For each conflict, `area-conflict` is signalled with restarts `overwrite` (apply the area's version), `skip-path` (keep the base's version), `abort-commit` (write nothing: `(values nil :aborted)`, the area stays open). An unhandled conflict escapes the same way: nothing written, area open. Then changes are applied: files through `fs-write-atomic`, the execute bit following the entry, removals unlinked and directories left empty by them removed (never the base). Base paths the area did not change, and ignored paths, are never touched. The copy is deleted. Returns `(values changes :committed)`, CHANGES = what was written (skipped paths left out).
- Any operation on a closed area (rescan, second close) → `area-error`. Closing is the only state change; `with-area` discards an area still open on exit.
- No locking against other processes between the check and the writes (as `fs-write-atomic` in H2a); no confinement in R4a: the shell runs unconfined in the copy (R4d adds fences).

**Laws on areas** (plan laws 3 and 6): `diff(a, a)` empty; restore then snapshot gives the same id; after a conflict-free commit with no base edits, `snapshot(base, :ignore :auto)` = the area's snapshot before the commit (projection = execution).

### Contract (tests)

`cl-stack-pathlib/tests`, Rove `deftest-parametrize` over `(:local :memory)` and, for snapshots, backend × store (`:memory` / `:directory`). Helpers in `tests/r4a-support.lisp` (on top of `h2a-support.lisp`): edits through `cl:open` (local) or the raw `fs-write-bytes` protocol call (memory), `/bin/sh` edits through `uiop:run-program`, `chmod` via the local backend. Mode and shell tests skip without unix modes; local symlink tests skip on Windows. 156 existing tests pass; 41 new tests fail on the stubs.

| File | Covers |
|------|--------|
| `snapshot-test.lisp` | locked encoding (sort, modes, duplicates, malformed manifests), recorded ids; store put / get / contains / not-found slots / directory layout; fixed-tree id on local / memory × memory / directory stores, other location and creation order, manifest blob = id; empty tree, missing root; execute bit and umask independence; ignore (explicit, `:auto`, ignored content not stored); restore round trip (returned changes, emptied directories removed, missing root created, protocol call), ignore kept on restore, unknown snapshot touches nothing; restore of execute bits; directory store reused by a second store object; changes between snapshots (all kinds, inverse, NIL = empty, unknown id); mode changes; symlinks |
| `area-test.lisp` | copy honours `:auto` / explicit matcher / no ignore, empty directories, manifest, base untouched; rescans see `cl:open` / protocol edits (same size, same second), ignored edits left out, base edits not area changes, agreement with snapshot changes, revert; `/bin/sh` edits incl. `chmod +x`; discard / keep / default action / `with-area` / temp directory; commit (writes, removals, ignored base files kept, untouched base edits kept, copy deleted), law 6, protocol calls, execute bit; conflict restarts (offered names, slots, `skip-path`, `overwrite`, `abort-commit`, helpers, unhandled); conflict cases (same edit, both removed, added both, removed vs edited, edited vs removed); open errors (mechanisms, missing base, non-empty / empty directory) |

### Out of scope (later rungs)

`fs-clone-tree` / `:clone` / `:overlay` (R4c, `fs-backend-*`) · `fs-watch` journals (R4b) · confinement of processes in an area (R4d / R4e, `compute-backend-*`) · `revision-protocol` / `diff-protocol` adapters over `fs-change` and snapshots (R1 tree engine, V1) · store GC · `object-store-protocol` stores · zip areas.

---

## R4b-0 — locked

First milestone of R4b in the plan ("R4 detail", rung R4b: change journals): the **journal protocol and its portable fallback** in `cl-stack-pathlib` **0.9.0**. Portable code only, no new dependencies. The OS mechanisms come after it, one repo per OS, each running the same journal suite: R4b-1 `fs-backend-linux` 0.1.0 (inotify), R4b-2 `fs-backend-darwin` 0.1.0 (FSEvents), R4b-3 `fs-backend-windows` 0.1.0 (`ReadDirectoryChangesW`). A journal only makes `fs-area-changes` cheaper: the result never changes, so consumers (H5 through `fs-area-changes`) get the speed-up through `:journal :auto` with no code change.

### Decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `fs-watch` returns a `journal` object, and the caller **pulls** with `journal-drain`. There is no callback (the plan's `(fs-watch fs root fn)` sketch): areas need "what changed since I last looked", and a pull with a settle bound gives the ordering rule below. |
| **Drain result** | `(values relative-paths complete-p)`. A path P means "the entry at P, or anything below P if P is or was a directory, may have changed". `complete-p` T promises that every changed entry is at or below some returned path. `complete-p` NIL (an overflow, a dropped root, a mechanism that can't tell) means "rescan everything", and the paths are then NIL. |
| **Portable fallback** | The `:poll` journal, made by the method on the base `filesystem`. Every drain returns `(values nil nil)`, so it is correct with no OS support. |
| **Dispatch** | Through a registry, `*watch-mechanisms*`, not through methods. A backend calls `register-watch-mechanism` at load time with a constructor, a rank and an `available-p` probe of `(fs directory)` (the volume, the OS, the filesystem class). `:auto` picks the best-ranked available mechanism, else `:poll`. `register` / `unregister` never modify the old list, so a `let` binding of `*watch-mechanisms*` scopes registrations, which is how the tests register fakes. The names `:poll` and `:auto` are reserved. |
| **Normalization in one place** | The `:around` method of `journal-drain` on `journal` does the shared work, so backends return raw paths. It signals `journal-error` on a closed journal, checks `:settle`, strips trailing `/`, drops paths below an ignored directory or ignored as a file, removes duplicates and sorts with `string<`. A `""` path (the root itself) or `complete-p` NIL becomes `(values nil nil)`. The `:around` of `journal-close` makes close idempotent: the backend's close method runs once. |
| **Settle rule** | Every write that **returned before `journal-drain` was called** is reported, or `complete-p` is NIL. `:settle` (seconds, default `*journal-settle*` = 0.05) is how long a mechanism may wait for OS events in flight (flush, read the queue) before it gives up and answers NIL. A mechanism that is unsure answers NIL and never guesses. |
| **Areas** | `fs-open-area … :journal` attaches a journal to the area's root, with the area's ignore matcher. The default `:auto` attaches one only when a non-`:poll` mechanism is available, so with no backend loaded, areas behave exactly as in R4a (`area-journal` is NIL). `fs-area-changes` drains and re-examines only the drained paths. `:rescan t` is the full R4a rescan, which leaves the journal and the area state alone. That keyword makes the law testable. |
| **Existence by listing** | A drained path is looked up **by exact name in its parent directory's listing**, never by probing the path. On a case-insensitive volume (macOS, Windows), `README.md` still opens after a rename to `readme.md`. Only the listing shows the new name, which is what the R4a rescan uses. |
| **Trust** | With `complete-p` T the area does not look outside the drained paths. A journal that hides an edit hides it from `fs-area-changes` (but not from `:rescan t`). This is the speed-up, and the journal suite is what proves a mechanism never lies. |
| **Commit** | `fs-close-area :commit` uses the full rescan, never the journal. Commits are rare, and the copy is deleted afterwards, so an edit a journal missed would be lost for good. |
| **Stubs** | The contract calls `%r4b0-pending` (internal, `src/journal.lisp`). The implementation removes it and every call. |

### Surface

```lisp
;;; Journals (protocol)
(fs-watch fs directory &key ignore (mechanism :auto)) → journal
    ; ignore: NIL | ignore-matcher (relative to DIRECTORY) | :auto (resolved once, here)
    ; mechanism: :auto | :poll | a registered keyword (unknown / unavailable → UNSUPPORTED-OPERATION)
    ; missing DIRECTORY → PATH-NOT-FOUND
(journal-drain journal &key (settle *journal-settle*)) → (values relative-paths complete-p)
(journal-close journal) → NIL                 ; idempotent
journal: journal-p journal-filesystem journal-root (PATH) journal-ignore
         journal-mechanism (:poll :fsevents :inotify :rdcw …) journal-open-p
*journal-settle*                              ; 0.05
journal-error (error): journal-error-journal  ; drain after close

;;; Mechanism registry
*watch-mechanisms*                            ; opaque; LET-bind to scope registrations
(register-watch-mechanism name constructor &key (rank 0) available-p) → name
    ; (funcall constructor fs directory matcher) → an open journal with JOURNAL-MECHANISM = NAME
    ; (funcall available-p fs directory) → generalized boolean; NIL = always available
    ; same NAME again: replaced in place; :poll / :auto → ERROR
(unregister-watch-mechanism name) → T | NIL
(watch-mechanisms &optional fs directory) → names, best first (rank desc, then registration
    order), then :poll; with FS and DIRECTORY only the available ones

;;; Areas (changed)
(fs-open-area fs base &key (mechanism :copy) ignore directory (journal :auto)) → area
    ; journal: :auto (attach when (first (watch-mechanisms fs root)) is not :poll)
    ;          | T (fs-watch :auto, may be :poll) | a mechanism keyword | NIL (none)
    ; unknown / unavailable mechanism → UNSUPPORTED-OPERATION, nothing left on disk
(fs-area-changes area &key rescan) → changes  ; rescan T: full R4a rescan, state untouched
(open-area base &key mechanism ignore directory journal)  (area-changes area &key rescan)
(area-journal area) → journal | NIL

;;; Backends subclass JOURNAL and specialize the primary methods:
(defmethod journal-drain ((j my-journal) &key settle) …)  ; raw paths; the :around normalizes
(defmethod journal-close ((j my-journal)) …)              ; runs once
```

### Semantics

**Journal lifetime.** A journal reports paths touched after `fs-watch` returns. Each drain reports the paths touched since the previous drain. A closed journal signals `journal-error` on drain, and its backend's close method has already run exactly once. The journal never changes the tree.

**`fs-area-changes` with a journal** (`rescan` NIL). The area keeps the entry state from its previous call, which starts as the manifest at open. It drains the journal:

- `complete-p` NIL: it does the full R4a rescan and takes its entries as the new state.
- `complete-p` T: for each drained path P, it drops the state at and below P, then re-examines P from the root. Every ancestor must be listed by exact name and be a real (non-symlink), non-ignored directory. If P is listed: a file or symlink gives one entry (hashed; the racy-git shortcut does not apply), and a directory gives a scan of its subtree. Nothing else is touched.

The result is the R4a diff from the manifest to that state. The journal is attached before the copy is written (or the copy is otherwise accounted for), so the first call is correct whatever the backend reported about the copy itself.

**`fs-close-area`.** It closes the journal before the copy is deleted, on `:discard`, `:keep` and a completed `:commit`. An aborted commit leaves the area and its journal open. A commit computes what it writes with the **full rescan** (`:rescan t`): a journal speeds up the frequent `fs-area-changes` calls, but it is never trusted with what reaches the base, because the copy is deleted afterwards and a missed edit would be lost.

**The law (the contract).** For every area, every mechanism and every edit, `(fs-area-changes area)` is EQUAL, field by field (kind, path, modes, hashes), to `(fs-area-changes area :rescan t)`.

### The journal suite (`cl-stack-pathlib/journal-suite`)

A secondary system in `cl-stack-pathlib` (`tests/journal-suite.lisp`, package `cl-stack-pathlib/journal-suite`, public API only, no test framework). Every backend runs it with its own mechanism:

```lisp
(run-journal-suite mechanism &key (backend :local) (settle *journal-settle*) directory)
  → (values failures steps)   ; FAILURES NIL = the law holds; STEPS = step names run
(journal-suite-steps &key (backend :local)) → step names for this OS and backend
;; in a backend's Rove tests:
(ok (null (run-journal-suite :inotify)))
```

It opens one area (base tree with `.gitignore` ignoring `*.log` and `build/`, `:ignore :auto`, `:journal mechanism`). It fails at once if the area's journal is not MECHANISM, so a backend that silently falls back to `:poll` cannot pass. Then it applies the steps in order, and after each step it compares `(fs-area-changes area)` with `:rescan t`. Each step also checks the rescan against expected changes, so an edit that silently did nothing shows up as a `:corpus` failure rather than a pass. Failure plists have the kinds `:law`, `:corpus`, `:error`, `:mechanism` and `:journal-open` (the journal is still open after `close-area`).

| Step | Edit | Runs on |
|------|------|---------|
| `:no-edits` | nothing (the rescan must be empty) | all |
| `:create` | `new.txt`, `src/new.lisp` | all |
| `:modify-same-size` | `a.txt` "aaa" → "zzz", same second as the copy; the only path touched (it catches a dropping mechanism) | all |
| `:modify-size` | `b.txt` grows | all |
| `:revert` | `a.txt` back to its content at open (no longer a change) | all |
| `:delete` | `b.txt` | all |
| `:rename-in-directory` | `src/c.lisp` → `src/d.lisp` | all |
| `:rename-across-directories` | `new.txt` → `docs/new.txt` | all |
| `:directory-create` | `tree/x/1.txt`, `tree/x/y/2.txt`, empty `tree/empty/` | all |
| `:directory-delete` | `tree/` with its contents | all |
| `:directory-rename` | `docs/` → `manual/` with its contents | all |
| `:ignored` | `x.log`, `y.log`, `build/new.o`, `build/sub/z.o` (none may show up) | all |
| `:symlink-create` | `link` → `a.txt`, `lnk-dir` → `src` (not followed) | memory; local except Windows |
| `:symlink-retarget` | `link` → `src/d.lisp` (not dangling: cl-stack-pathlib#41) | memory; local except Windows |
| `:mode-change` | `chmod 755 run.sh` | local with unix modes |
| `:case-only-rename` | `README.md` → `readme.md` | all |
| `:burst` | 2000 files under `burst/` (an overflow candidate) | all |
| `:burst-delete` | `burst/` | all |
| `:child-process` | `uiop:run-program` command line: `/bin/sh` on unix, `cmd.exe` on Windows: create, modify, delete, mkdir, rename | local |

Local edits use `cl:rename-file` and the pathlib facade, and the child-process step uses a shell. The work directory is a fresh subdirectory of `uiop:temporary-directory` (or of `:directory`, so a backend can test a given volume), referred to by its truename. Nothing is hard-coded to `/tmp`.

### Contract (tests)

`cl-stack-pathlib/tests` (Rove), which now depends on `cl-stack-pathlib/journal-suite`. The fake mechanisms live in `tests/journal-fakes.lisp` and are registered only inside a `let` of `*watch-mechanisms*`. The scan-based fakes find changes by snapshotting the journal root on each drain:

- `:fake-exact` returns every changed entry.
- `:fake-coarse` returns the parent directory of each change, as a coalescing mechanism would.
- `:fake-overflow` acts as exact up to 100 paths, then returns `complete-p` NIL.
- `:fake-liar` acts as exact minus the greatest path, while still claiming `complete-p` T.
- `:fake-scripted` answers each drain from a queue the test fills, and records drains, settles and closes.

| File | Covers |
|------|--------|
| `journal-test.lisp` | the law: the suite on `:poll`, `:fake-exact`, `:fake-coarse`, `:fake-overflow` × local / memory, and `:auto` / T; the suite **catches `:fake-liar`** (a `:law` failure at `:modify-same-size`); open errors reported by the suite; `fs-watch` (`:poll` with nothing registered, readers, `:ignore :auto`, explicit `:poll` beside a registered fake, `:auto` picks the fake, missing directory, unknown or unavailable mechanism); the registry (rank order, ties, replace in place, availability per filesystem, `:poll` last, unregister, reserved names, `let` scoping); drain normalization (dedup, sort, trailing `/`, ignored paths, `""` and `complete-p` NIL → `(nil nil)`); settle (0.05 default, explicit, `*journal-settle*`, bad values → `type-error` before the mechanism is called); close (idempotent, close method runs once, drain after close → `journal-error` with the journal); areas: attach (`:auto` none / fake, T → `:poll`, NIL, `:poll`, unknown → `unsupported-operation` with nothing created, root and matcher shared), closed with the area before the copy is deleted (discard / keep / commit; an aborted commit leaves it open; a commit writes an edit the journal hid), narrowing (a complete empty drain hides an edit, `:rescan t` does not drain, a drained file or directory is re-examined, removal by listing, ignored paths, `complete-p` NIL → full rescan, the area's drain uses `*journal-settle*`) |
| `journal-suite.lisp` | the corpus and the runner (sealed with `tests/`) |

All R4a and earlier tests pass unchanged, because `:journal :auto` attaches nothing when nothing is registered. Tests must pass on macOS, Linux and Windows (CI matrix). Symlink steps skip local Windows, the mode step needs unix modes, and the child-process step runs on local only.

### Out of scope (R4b-1 … R4b-3 and later)

The OS mechanisms (`fs-backend-linux` inotify, `fs-backend-darwin` FSEvents, `fs-backend-windows` `ReadDirectoryChangesW`) · fanotify and the USN journal · using journals for drift detection outside areas · a callback / push API · `fs-watch` on zip filesystems · using journals directly in cl-stack-code (H5 benefits through `:auto`).

---

## R4c-0 — locked

First milestone of R4c in the plan ("R4 detail", rung R4c: COW copies): the **clone protocol and its portable copy rung** in `cl-stack-pathlib` **0.10.0**. Portable code only, no new dependencies. The OS mechanisms come after it, one repo per OS, each running the same clone suite: R4c-1 [fs-backend-darwin](fs-backend-darwin.md#r4c-1--locked) 0.2.0 (`clonefile`), R4c-2 [fs-backend-linux](fs-backend-linux.md#r4c-2--locked) 0.2.0 (`FICLONE`), R4c-3 [fs-backend-windows](fs-backend-windows.md#r4c-3--locked) 0.2.0 (ReFS block cloning). A clone only makes materializing a tree cheaper (no data written, no space used until a side is written): the tree, its metadata and `fs-area-changes` never change, so consumers (H5 areas, subagent areas) get the speed-up through `:mechanism :auto` with no code change.

**Overlay areas move to R4d** (the plan lists "overlayfs in a user namespace" under R4c). An overlay mount made in a user + mount namespace is visible only inside that namespace. The harness image cannot enter it: `unshare(CLONE_NEWUSER)` fails with `EINVAL` in a multithreaded process, and SBCL always has threads (finalizer, timers, and our own journal threads). So `fs-open-area :overlay` could never hand the harness a readable merged tree. An overlay only makes sense for a process **spawned** inside the namespace, which is exactly what R4d's `compute-backend-landlock` does (user + mount namespaces, Landlock, bubblewrap). R4d also has to solve the same CI problem: ubuntu-24.04 restricts unprivileged user namespaces through AppArmor (`kernel.apparmor_restrict_unprivileged_userns`). The pathlib side of an overlay area (reading an upper directory, with whiteouts and opaque directories, into `fs-change` values) is specified there. R4c's verdict, equivalence with `:copy`, does not need overlays. `:overlay` stays `unsupported-operation` in 0.10.0.

### Decisions

| Decision | Choice |
|----------|--------|
| **Dependencies** | None added. `fs-set-mtime` on local uses `sb-posix:utimes`, and `sb-posix` is already a dependency on SBCL. |
| **Shape** | Two generics, **`fs-clone-tree fs source destination &key ignore mechanism`** and **`fs-clone-file fs source destination &key mechanism replace`**. Both return a **`clone-report`**: the mechanism that made the tree, the reason when `:copy` was used instead of a clone, how many regular files were cloned and how many copied, and the per-file fallbacks. Plus **`fs-clone-supported-p fs directory &optional destination`** → `(values mechanism reason)` and **`fs-set-mtime`**. |
| **Mechanism names** | `:auto` (default): the best-ranked clone mechanism available for SOURCE and DESTINATION, else `:copy` with the reason in the report. `:copy`: the portable rung. `:clone`: the best available clone mechanism, else `unsupported-operation`. A registered name (`:clonefile`, `:ficlone`, `:block-clone`): that mechanism, else `unsupported-operation`. An unknown keyword signals `unsupported-operation`. `:auto`, `:copy` and `:clone` are reserved names. Every refusal happens **before anything is created**. |
| **Dispatch** | Through a registry, **`*clone-mechanisms*`**, ranked like `*watch-mechanisms*` (R4b-0). A backend calls `register-clone-mechanism` at load time with a per-file `clone-file` function, a rank, an `available-p` probe of `(fs source-dir destination-dir)` → `(values available-p reason)`, and an optional `clone-tree` hook. `register` and `unregister` never modify the old list, so a `let` binding scopes registrations, which is how the tests register fakes. |
| **Probe arguments** | SOURCE-DIR is the source directory, or the source file's directory. DESTINATION-DIR is the destination when it is an existing directory, else its **nearest existing ancestor**, so nothing has to be created to ask. A probe answers for the pair: the filesystem class, the volume's capability, and whether both are on one volume. It never signals. A probe that signals is a bug in the backend, and the error propagates. |
| **Reasons (locked set)** | Whole call (`clone-report-reason`, `fs-clone-supported-p`): `:no-mechanism` (none registered), `:unsupported-filesystem` (memory, zip, …), `:unsupported-volume` (HFS+, ext4, NTFS, …), `:cross-volume`, and `:unavailable` (a probe said NIL without a reason). With several mechanisms registered and none available, the reason is the one given by the best-ranked mechanism. Per file (`clone-report-fallbacks`): the same set plus `:clone-failed`. |
| **Who walks** | **pathlib** walks the tree in every case, with the `%scan-tree` walk of snapshots: sorted, ignored paths skipped, ignored directories not descended, `.git` pruned by `:auto`. It makes the directories (empty ones too, default modes), makes symlinks itself (`fs-create-symlink` with the raw `fs-read-symlink` target, never followed), skips other kinds (FIFOs, sockets, devices), and calls the mechanism's `clone-file` **for regular files only**. Then it sets permission bits and mtime on each file. The OS code stays a per-file primitive, and the tree semantics are written once. |
| **Tree hook** | A mechanism may register `clone-tree` `(fs source destination matcher)`, where DESTINATION is an existing empty directory and MATCHER the resolved ignore matcher or NIL. pathlib calls the hook first. It returns the number of regular files it cloned, or NIL to decline, and then pathlib walks per file. A hook must make **exactly** the tree the walk would, and the suite checks that through the hook path too. (R4c-1 uses it for a whole-directory `clonefile` when MATCHER is NIL.) |
| **Per-file fallback** | `clone-file` returns true (DESTINATION holds SOURCE's content), or `(values nil reason)` (it made nothing, and pathlib copies the file and records `(rel . reason)`, where a NIL reason counts as `:clone-failed`), or it signals **`clone-error`**. pathlib establishes the restart **`use-copy`** around every call. The restart removes a partial destination and copies the file, recording `:clone-failed`. Any other condition propagates. |
| **Metadata (locked list)** | Kept: content; regular files as regular files; symlinks as symlinks with the same target string (never followed, a link to a directory included); **permission bits** `(logand mode #o777)` where the backend reports modes (local on SBCL / ECL unix); **mtime** to the second where the backend can set it (memory, local on SBCL unix: `fs-set-mtime`). Not kept: owner and group, setuid / setgid / sticky bits, ACLs, xattrs, flags, atime and birth time, symlink mtimes, directory modes and mtimes, hard links (each link becomes its own file), and holes on the `:copy` rung (content is equal; sparseness is a mechanism's bonus). Left out: ignored paths, other kinds. |
| **Destination** | `fs-clone-tree`: DESTINATION absent (created with its parents) or an empty directory. Non-empty → `path-exists-error`; inside SOURCE → `path-error`; SOURCE missing → `path-not-found`; SOURCE not a directory → `path-error`. `fs-clone-file`: parents created. An existing DESTINATION → `path-exists-error` with the restart `overwrite`, unless `:replace t`. A replacement is made under a temp name in the destination's directory and renamed over it, so no temp file survives and readers see the old file or the new one. A directory SOURCE or DESTINATION → `path-error`; SOURCE missing → `path-not-found`; a symlink SOURCE gives a symlink. |
| **Failure** | Any condition escaping `fs-clone-tree` (`clone-error` with no handler, an I/O error, …) leaves DESTINATION **as it was**: removed when it was absent, emptied when it was an empty directory. |
| **Report** | `clone-report-mechanism` is the mechanism that made the tree (`:copy` or a name, the outer name when a hook nests calls). `clone-report-reason` is NIL when the mechanism was the one asked for or picked, and when `:copy` was asked for; with `:auto` and no clone available it is the reason. `clone-report-cloned` + `clone-report-copied` = the number of regular files made. `clone-report-fallbacks` is `((rel . reason) …)` sorted `string<`; for `fs-clone-file`, REL is the source's file name. With a hook, `cloned` is the hook's count. |
| **`fs-set-mtime`** | `(fs-set-mtime fs pathname universal-time)` → T, or NIL where the backend or platform cannot set it (zip; local off SBCL unix), where it is a no-op like `fs-chmod`. It follows symlinks. A missing path signals `path-not-found` on every backend. Memory: the entry's timestamp. Local: `utimes(2)` with atime = mtime. Facade `set-mtime`. |
| **Areas** | `fs-open-area` builds the area's tree with `fs-clone-tree` for every mechanism. **`:mechanism` now defaults to `:auto`**: it clones when a clone mechanism is available for BASE and the area directory, else it copies. `:copy`, `:clone` and a registered name are strict. `:overlay` (R4d) and `:virtual` (R4f) still signal `unsupported-operation`. A strict mechanism that turns out to be unavailable once the area directory exists signals `unsupported-operation` and leaves nothing on disk (a given empty DIRECTORY stays empty). `area-mechanism` → `:clone` or `:copy`; **`area-clone-report`** → the report. With nothing registered, `:auto` is the R4a copy, so every R4a / R4b test passes unchanged. |
| **Areas: what changes for `:copy`** | Built by the same walk, a `:copy` area now keeps **all permission bits and mtimes**. R4a kept only the execute bit and gave copies the copy time. `fs-area-changes` does not change: entries still carry only the execute bit, so umask and group bits never make a change. The manifest still records hashes taken at open (read from the clone or the copy; the same content), plus size and mtime of the area's file. The racy-git rule is unchanged: an old preserved mtime is not racy, so a later edit, which sets a new mtime, is found by the size / mtime check. A same-size edit that also restores the old mtime is missed, as in R4a (a rescan cannot see it either). |
| **Copy streaming** | The `:copy` rung on local streams files in chunks (≤ 1 MiB) and hashes them incrementally for the area manifest, so a large file is never held in memory whole. Not tested; the suite's 4 MiB and 16 MiB files are only correctness cases. |
| **Equivalence by construction** | `:clone` and `:copy` areas differ only in the per-file primitive. The law (`fs-area-changes` EQUAL for the same edits) is still tested end to end, because a backend's primitive can be wrong (short writes, a lost tail, shared data) in ways only real edits show. |
| **Stubs** | The contract calls `%r4c0-pending` (internal, `src/clone.lisp`). The implementation removes it and every call. |

### Surface

```lisp
;;; Clones (protocol + facade)
(fs-clone-tree fs source destination &key ignore (mechanism :auto)) → clone-report
(fs-clone-file fs source destination &key (mechanism :auto) replace) → clone-report
(fs-clone-supported-p fs directory &optional destination) → (values mechanism reason)
(fs-set-mtime fs pathname universal-time) → T | NIL
(clone-tree source destination &key ignore mechanism)  (clone-file source destination &key mechanism replace)
(clone-supported-p directory &optional destination)    (set-mtime designator universal-time)

clone-report: clone-report-p clone-report-source clone-report-destination (PATHs)
              clone-report-mechanism clone-report-reason clone-report-cloned
              clone-report-copied clone-report-fallbacks

;;; Mechanism registry
*clone-mechanisms*                            ; opaque; LET-bind to scope registrations
(register-clone-mechanism name clone-file &key (rank 0) available-p clone-tree) → name
    ; (funcall clone-file fs source destination) → true | (values nil reason); may signal CLONE-ERROR
    ;    SOURCE: absolute pathname of a regular file; DESTINATION: absent, its directory exists
    ; (funcall available-p fs source-dir destination-dir) → (values available-p reason); NIL = always
    ; (funcall clone-tree fs source destination matcher) → count | NIL (declined)
    ; same NAME again: replaced in place; :copy / :auto / :clone → ERROR; CLONE-FILE not a
    ; function designator, RANK not an integer → TYPE-ERROR
(unregister-clone-mechanism name) → T | NIL
(clone-mechanisms &optional fs source destination) → names, best first (rank desc, then
    registration order), then :copy; with FS, SOURCE, DESTINATION only the available ones

;;; Conditions and restarts
clone-error (path-error): clone-error-mechanism clone-error-operation clone-error-code
use-copy (restart around every CLONE-FILE call)   (invoke-use-copy &optional condition)

;;; Areas (changed)
(fs-open-area fs base &key (mechanism :auto) ignore directory (journal :auto)) → area
    ; mechanism: :auto | :copy | :clone | a registered clone mechanism name
    ;            :overlay / :virtual / unknown → UNSUPPORTED-OPERATION, nothing created
(open-area base &key (mechanism :auto) ignore directory journal)
(area-mechanism area) → :clone | :copy      (area-clone-report area) → clone-report
```

### The clone suite (`cl-stack-pathlib/clone-suite`)

A secondary system in `cl-stack-pathlib` (`tests/clone-suite.lisp`, package `cl-stack-pathlib/clone-suite`, public API only, no test framework). Every clone backend runs it with its own mechanism, on a volume where the mechanism works, and gives it a directory on another volume when it can:

```lisp
(run-clone-suite mechanism &key (backend :local) directory other-volume)
  → (values failures steps)   ; FAILURES NIL = every law holds
(clone-suite-steps &key (backend :local) (mechanism :copy) other-volume) → step names
(clone-suite-edits &key (backend :local)) → equivalence edit names
;; in a backend's Rove tests:
(ok (null (run-clone-suite :clonefile :directory apfs-dir :other-volume hfs-dir)))
```

The base tree has `.gitignore` (ignoring `*.log` and `build/`), `.git/HEAD`, text files, `run.sh` (#o755), `private.txt` (#o600), a non-ASCII name under a directory with a space, an empty file, a 4 MiB pseudo-random `large.bin`, ignored `x.log` / `build/…`, empty directories, the symlinks `link` → `a.txt` and `lnk-dir` → `src` (no dangling or `..` links: cl-stack-pathlib#41), and, on local, a 16 MiB `sparse.bin` with data only at both ends. Every regular file gets a distinct mtime in 2001 (`set-mtime`), so a mechanism that does not keep mtimes cannot pass by luck. Failure plists carry `:step` and `:kind`: `:error`, `:mechanism`, `:report`, `:content`, `:metadata`, `:protocol`, `:independence`, `:equivalence`, `:corpus`, `:fallback`. Steps are independent: an error in one is recorded and the next one runs.

| Step | Law | Runs on |
|------|-----|---------|
| `:supported` | `clone-mechanisms` ends with `:copy`; `fs-clone-supported-p` answers `(name nil)` or `(nil reason)` with a locked reason; for a real mechanism, it is available within the work directory | all |
| `:tree` | `fs-clone-tree :ignore :auto`: report (mechanism, no reason, counts, at least one file cloned for a tree, fallbacks well-formed); **metadata**: the destination's snapshot equals the source's with `:auto` (content, modes, symlink targets, ignored paths absent), the same directories (empty ones included), equal #o777 bits (unix modes) and mtimes (SBCL unix, memory) per file | all |
| `:no-ignore` | the same with `:ignore nil` (`.git`, `x.log`, `build/` cloned too; a hook gets a NIL matcher) | all |
| `:matcher` | the same with an explicit matcher | all |
| `:file` | `fs-clone-file`: content, mode and mtime of `large.bin`, `private.txt`, `run.sh`, the empty file; parents made; `path-exists-error` with `overwrite` (the old content untouched until then); `:replace t`; no temp file left; a symlink source → a symlink; a directory source or destination, a missing source, an unknown mechanism → the locked conditions, nothing left | all |
| `:sparse` | `sparse.bin` cloned: size and content equal | local |
| `:errors` | `fs-clone-tree` refusals (missing source, non-empty destination untouched, destination inside source, file source, unknown mechanism), nothing left; an empty existing destination is used | all |
| `:independence` | after a clone, writes to the clone (in place with `cl:open :overwrite` on local, append, truncate, atomic replace, chmod, `set-mtime`, delete, rename, create, a write into the sparse hole) change nothing in the source: snapshot, modes, mtimes, directories | all |
| `:equivalence` | areas opened with the mechanism and with `:copy` over the same base (`:ignore :auto`): `area-mechanism` `:clone` / `:copy`, the report names the mechanism, equal manifests; then each edit of the script below goes to both, and after each one `fs-area-changes` of the clone area (default and `:rescan t`) is EQUAL, field by field, to the copy area's, which also matches the expected changes; the base is unchanged after both are discarded | all |
| `:cross-volume` | with OTHER-VOLUME: `fs-clone-supported-p` → `(nil :cross-volume)`, the mechanism is not listed as available, `:auto` gives a `:copy` report with reason `:cross-volume` and a correct tree; the mechanism by name, `:clone` and a `:clone` area refuse with `unsupported-operation`, leaving nothing; an `:auto` area is a `:copy` area with that reason | local, mechanism ≠ `:copy` |
| `:independence-reverse` | writes to the source (in place, append, chmod) change nothing in a clone made before | all |

Equivalence edits, in order (cumulative expectations): `:none`, `:create`, `:modify-same-size`, `:in-place` (4 octets inside `large.bin`, written in place), `:append`, `:truncate`, `:revert`, `:delete`, `:rename`, `:directory-create`, `:directory-delete`, `:directory-rename`, `:ignored`, `:symlink-create` and `:symlink-retarget` (memory; local except Windows), `:mode-change` and `:private-mode` (group bits are no change) (unix modes), `:sparse-write` (local), `:child-process` (`/bin/sh` or `cmd.exe`: create, modify, delete). The suite has no 2000-file burst, so the slow Windows rescan (cl-stack-pathlib#44) does not dominate CI. In-place and append edits use `cl:open` directly, because pathlib has no output stream yet (cl-stack-pathlib#45).

### Contract (tests)

`cl-stack-pathlib/tests` (Rove) now depends on `cl-stack-pathlib/clone-suite` too. The fakes live in `tests/clone-fakes.lisp` and are registered only inside `with-clone-fakes` (a `let` of `*clone-mechanisms*`). They all "clone" by copying through the protocol (`fs-read-bytes` / `fs-write-bytes`), except where noted, and they log their calls:

- `:fake-clone`: exact, rank 10.
- `:fake-tree`: a tree hook that clones the whole tree through `fs-clone-tree :mechanism :fake-clone`.
- `:fake-decline`: a hook that always declines.
- `:fake-partial`: hands files over 1 MiB back to the copy rung (`:clone-failed`).
- `:fake-signal`: signals `clone-error` for `a.txt`.
- `:fake-shared` (SBCL unix): **hard-links** the file, so the clone and its source share data. The suite must catch it.
- `:fake-lossy`: a hook that resets mtimes and modes. The suite must catch it.
- `:fake-cross-volume`: unavailable (`:cross-volume`) for destinations under `other-volume/`.
- `:fake-unsupported`: rank 50, `:unsupported-volume`.
- `:fake-unavailable`: rank 40, NIL without a reason.
- `:fake-local-only`: `:unsupported-filesystem` off `local-filesystem`.
- `:fake-recorder`: logs probe arguments.

| File | Covers |
|------|--------|
| `clone-test.lisp` | the laws: the suite on `:copy` and on `:fake-clone`, `:fake-tree`, `:fake-decline`, `:fake-partial` × local / memory, with every applicable step; the cross-volume step with `:fake-cross-volume`; the suite **catches `:fake-shared`** (`:independence` at `:independence` and `:independence-reverse`) and **`:fake-lossy`** (`:metadata` mtime, and mode on unix, at `:tree`); an unavailable or unknown mechanism fails `:supported`. Registry: rank order, ties, replace in place, unregister, `let` scoping, the old list never modified, reserved names and type checks. Availability: `:no-mechanism`, `:unsupported-volume`, `:unavailable`, the best-ranked reason, `:unsupported-filesystem` on memory, unavailable mechanisms skipped, the facade; probe arguments (the destination defaults to the directory; a missing destination → its nearest existing ancestor). `fs-clone-tree`: `:auto` (no mechanism, best available, `:unsupported-volume`), `:copy` / `:clone` / named / unavailable / unknown (nothing created), the hook (called once with the resolved matcher, its count; a declining hook → per-file calls), per-file fallbacks (sorted, counts, tree whole), `clone-error` (slots; destination removed or emptied; `use-copy` offered and invoked), destinations, ignore (`:auto`, NIL, a matcher, empty and ignored directories), local metadata (all permission bits, mtime, a directory link and a `..` link kept as links, a FIFO left out) and memory mtimes. `fs-clone-file`: reports, parents, `path-exists-error` + `overwrite`, `:replace`, no temp file, refusals, symlinks made by pathlib (not by the mechanism), per-file and whole-call fallbacks. `fs-set-mtime` on local / memory / zip. Areas: `:auto` → `:copy` with `:no-mechanism`, `:copy`, `:auto` / `:clone` / named → `:clone` with the report, `:unsupported-volume`; refusals (`:overlay`, `:virtual`, unknown, unavailable; `:clone` with none available, nothing left, an empty directory left empty); a clone area equals a copy area and commits (law 6); a `:copy` area keeps modes and mtimes, and an old preserved mtime is not racy |
| `clone-suite.lisp` | the base tree, the edit script and the runner (sealed with `tests/`) |

On macOS today: **288 existing test cases pass; the 56 new ones fail on the stubs.** All R4a / R4b tests pass unchanged, because `:mechanism :auto` with nothing registered is the R4a copy and `:clone` with nothing registered still signals `unsupported-operation`. Tests must pass on macOS, Linux and Windows (CI matrix). Symlink tests skip local Windows, mode checks need unix modes, local mtime checks need SBCL unix, and the hard-link fake needs SBCL unix.

### Out of scope (R4c-1 … R4c-3 and later)

The OS mechanisms (R4c-1 `clonefile`, R4c-2 `FICLONE`, R4c-3 block cloning) · overlay areas (R4d, see above) · lazy manifest hashes (an area still reads every file once at open to hash it; skipping that needs base-change detection) · cloning across `filesystem` objects (local → memory) · preserving owners, ACLs, xattrs, flags, hard links, directory metadata · sparse output on the `:copy` rung · making the area's temp directory on the base's volume (today `fs-make-temp` decides, and `:auto` reports `:cross-volume` when they differ) · subvolume snapshots (btrfs, APFS) · zip destinations.

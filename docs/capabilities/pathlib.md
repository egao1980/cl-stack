# cl-stack-pathlib — CLOS paths and pluggable filesystems

**Repo:** [`egao1980/cl-stack-pathlib`](https://github.com/egao1980/cl-stack-pathlib) (nick `stack-pathlib`) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H (H2) and R4
**Status:** 0.3.2 shipped (local / memory / `zip://`, restarts). **H2a brief locked**; contract on branch `agent/pathlib-h2a-7a35` (`cl-stack-pathlib/tests`, Rove). Implementation via **team-solve**.

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

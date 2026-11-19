# agent-tools (H2b) — the coding agent's file tools

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H2 (Decisions: agent-tools is its own repo, so the agent core gains no dependencies)
**Status:** milestone **H2b locked**. Contract in [`egao1980/agent-tools`](https://github.com/egao1980/agent-tools) (`agent-tools/tests`, Rove); every function calls `%not-implemented`. Implementation through **team-solve**. Shell / pty tools, background jobs and the shell command scanner are **H2c**: [agent-tools-shell.md](agent-tools-shell.md).

`agent-tools` gives an `ai-agent-protocol` agent the small core toolset a coding agent needs on files: `read`, `write`, `edit`, `multi_edit`, `glob`, `grep`, `ls`. One `file-tools` object is one tool source over one directory tree of any `cl-stack-pathlib` filesystem. It builds on the H2a pathlib surface ([pathlib.md](pathlib.md): ranged reads, SHA-256 content hashes, atomic + CAS writes, ignore matcher, `fs-grep`) and on diff-protocol's `:text` engine ([diff.md](diff.md)) for edit previews.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| pi (`read` / `write` / `edit` / `grep` / `find` / `ls`) | A small core toolset; truncation with a "continue at offset" notice | No permissions; `bash` (H2c) |
| Claude Code (Read / Write / Edit / MultiEdit / Glob / Grep / LS) | `cat -n` numbered reads with offset / limit; exact `old_string` → `new_string` that must match once unless `replace_all`; MultiEdit all-or-nothing; Glob / Grep shapes | "Must read before write" session state; mtime-sorted glob; ripgrep regex |
| opencode | Permission resources per path | — |
| cl-stack-pathlib H2a | Content hash as the CAS token (`sha256:…`); `fs-write-atomic :expected-hash` and its restarts; gitignore matcher; `fs-grep` literal search | — |

---

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| **Repo / system** | `egao1980/agent-tools`, system `agent-tools` (nickname `stack-agent-tools`), test system `agent-tools/tests`. Version 0.1.0. |
| **Dependencies** | `ai-agent-protocol` ≥ 0.10.0, `cl-stack-pathlib` ≥ 0.4.0, `diff-protocol` ≥ 0.2.0, `json-protocol` + `json-backend-jzon` (the stack default, so `(asdf:load-system "agent-tools")` is enough). Tests add `event-backend-libuv`, `llm-protocol` (mock backend) and `rove`. No regex engine, no schema-protocol. |
| **Source shape** | One `file-tools` class specializing the ai-agent-protocol GFs (`list-agent-tools`, `tool-executable-p`, `invoke-tool-async`, `tool-permission-resources`, `tool-instruction-paths`). An agent lists the object itself in `:tools`; `find-agent-tool` returns it as the invocation source. |
| **Confinement** | **Path resolution in agent-tools**, not a jailed filesystem: pathlib 0.4.0 has no `jailed-filesystem`, and resolution must give the model a typed, actionable error anyway. `resolve-tool-path` normalizes lexically and, for the part of the path that exists, refuses a symlink that resolves outside the root. A later `jailed-filesystem` can sit under the same function. Shell commands (H2c) run unconfined; confinement of processes stays in `compute-backend-*`. |
| **Arguments** | A JSON object string (what the model sends) or a string-keyed hash table (json-protocol's decoded shape). Decoded with `json-protocol:decode`. Unknown keys are ignored. Wrong types, missing required keys, malformed JSON or a non-object → `tool-input-error` naming the key. |
| **Schemas** | Draft-07 JSON Schema written as json-protocol values (string-keyed hash tables, vectors for arrays, `nil` for `false`), so every LLM backend serializes them as-is. No `$schema` key; `"additionalProperties": false`; `"required"` only when non-empty; every property has a `"description"`. |
| **Hash** | pathlib's `"sha256:" + 64 hex` of the bytes on disk. Read, write, edit and multi_edit results end with `hash: <digest>`; `expected_hash` takes it back. |
| **Text** | UTF-8. Content is written verbatim (no line-ending conversion). Matching in edit is exact on the decoded text: a CRLF file needs `\r\n` in `old_string`. |
| **Regex** | `grep` is literal (`search`, `char-equal` when `case_insensitive`). `regex: true` is a `tool-input-error` while no system specializes `cl-stack-pathlib:fs-grep-matcher`; agent-tools loads none. |
| **Threads** | Handlers run off the event loop in worker threads: they use `file-tools-filesystem`, never the dynamic `*filesystem*`. |
| **Stubs** | `%not-implemented` (internal, `src/file-tools.lisp`). The implementation removes it and every call. |

---

## Surface

```lisp
(make-file-tools &key root filesystem (ignore :auto) (max-read-lines 2000)
                      (max-output 50000) (max-results 100) (tools +file-tool-names+))
  ;; ROOT: string, pathname or PATH naming an existing directory; FILESYSTEM defaults
  ;;   to ROOT's (a PATH) or *FILESYSTEM*. Missing root → PATH-NOT-FOUND; not a
  ;;   directory → PATH-ERROR; unknown tool name → ERROR.
  ;; IGNORE: :AUTO (.gitignore / .ignore files under ROOT, read per call), NIL, or an
  ;;   IGNORE-MATCHER (patterns relative to ROOT) that replaces them.
  ;; TOOLS: names to expose; kept in +FILE-TOOL-NAMES+ order.
file-tools  file-tools-p
file-tools-root            ; absolute directory PATH (the truename on the local fs)
file-tools-filesystem  file-tools-ignore  file-tools-names
file-tools-max-read-lines  file-tools-max-output  file-tools-max-results
+file-tool-names+          ; ("read" "write" "edit" "multi_edit" "glob" "grep" "ls")

(call-file-tool tools name arguments)   ; → result string; synchronous; signals tool failures.
                                        ;   A name not enabled → AGENT-UNKNOWN-TOOL.
(resolve-tool-path tools designator &key (allow-root t))  ; → (values path relative)

;; conditions — all AI-AGENT-PROTOCOL:TOOL-INPUT-ERROR; the report is the MESSAGE slot
path-outside-root   path-outside-root-path            ; the argument as given
edit-match-error    edit-match-error-path  edit-match-error-count  edit-match-error-index
stale-file-error    stale-file-error-path  stale-file-error-expected  stale-file-error-actual

;; methods on ai-agent-protocol GFs, specialized on FILE-TOOLS
list-agent-tools  tool-executable-p  invoke-tool-async
tool-permission-resources  tool-instruction-paths
```

---

## Paths

- A path argument is a string, **relative to the root** with `/` separators, or **absolute and under the root** (in the filesystem's POSIX form, `as-posix`). `~` is not expanded.
- Resolution is **lexical**: empty segments and `.` drop, `..` pops. `../w/a.txt` from root `w/` is inside. Anything that ends outside the root (`..`, `/etc/passwd`, `<root>-sibling/x`) signals `path-outside-root` with message `"<arg> is outside the project root…"` (must contain the argument and `outside`).
- **Symlinks:** for each existing prefix of the resolved path, a symlink must resolve under the root's truename, else `path-outside-root`. A link that stays inside works (`lnk/a.txt`).
- `relative` is the root-relative POSIX string without `./` or trailing `/`; the root itself is `"."`. An empty string is a `tool-input-error` (not `path-outside-root`); so is the root when `:allow-root nil` (file tools use that).
- `.git/` is never listed or searched, whatever `:ignore` says. Glob and grep **do not descend into directory symlinks**; `ls` leaves out a symlink that resolves outside the root.
- Ignore rules apply to `glob`, `grep` and `ls` only, and are evaluated **relative to the root**: a root `.gitignore` applies when the search path is a subdirectory, a nested `.gitignore` applies below its directory only. An explicit path (`read x.log`, `edit x.log`) is never refused for being ignored.

---

## Tools

Results are plain strings; lines are LF-separated with **no trailing LF**. `<rel>` is the root-relative path.

### read — `file_path`*, `offset`, `limit`

- Output: one line per file line, `(format nil "~6d~c~a" n #\Tab line)` (CR before LF not shown), then the notices, then `hash: <digest of the whole file>`.
- `offset` 1-based (default 1), `limit` default and cap `max-read-lines`. Both integers ≥ 1.
- Lines remaining after the shown range → `[truncated: lines A-B shown; call read with offset=B+1 for more]`.
- `max-output` caps the characters of the numbered lines (each counted with its LF); lines stop at the last that fits, then the same truncation notice. Notices and the hash line are not counted.
- Empty file → `[empty file]` then the hash line. `offset` past the last line → `tool-input-error` containing `offset` and `<n> lines`.
- Missing → `tool-input-error` with `<rel>` and `not found`. Directory → `tool-input-error` with `directory` and `ls`. NUL in the first 8000 bytes → `tool-input-error` with `binary`.

### write — `file_path`*, `content`*, `expected_hash`

- `fs-write-atomic` with `:expected-hash` (NIL when absent: blind overwrite / create). Parents are created. No temp file survives.
- Output: `Wrote <rel> (<n> bytes)` (UTF-8 octets) then `hash: <new digest>`.
- Mismatch → `stale-file-error` (expected = the argument, actual = current digest or NIL when missing), message `"<rel> changed since it was read (expected E, now A); read it again and retry"`. It is signalled **inside pathlib's `content-hash-mismatch` handler**, so `cl-stack-pathlib:overwrite` and `use-current` are visible (`find-restart` by name; they belong to pathlib's condition). Invoking `overwrite` writes and the tool returns its normal result.
- A directory target → `tool-input-error` (`directory`). `unsupported-operation` (zip, read-only) → `ai-agent-protocol:tool-unavailable` with `read-only`.

### edit — `file_path`*, `old_string`*, `new_string`*, `replace_all`, `expected_hash`

- Count non-overlapping occurrences of `old_string` left to right. 0 → `edit-match-error` count 0, `"old_string not found in <rel>; read the file and copy the exact text"`. More than one without `replace_all` → count n, `"old_string matched <n> times in <rel>; add surrounding context to make it unique, or set replace_all"`. `replace_all` replaces every occurrence.
- `old_string` empty, or equal to `new_string` (`identical`) → `tool-input-error`. Empty `new_string` deletes. Missing file → `tool-input-error` with `not found` and `write`.
- `expected_hash` given and different from the current digest → `stale-file-error` before anything else.
- **Always CAS:** the write uses `:expected-hash` = digest of the content the tool read, so a concurrent writer between read and write gives `stale-file-error` and their content stays.
- Output:

  ```
  Edited <rel>: <n> replacement(s)        ; (format nil "~d replacement~:p" n)
  --- a/<rel>
  +++ b/<rel>
  <(render-diff (compute-diff (find-diff-engine :text) old new :context 3) :unified nil)>hash: <new digest>
  ```

  The hunks end with LF, so `hash:` starts its own line.
- Read-only filesystem → `tool-unavailable`.

### multi_edit — `file_path`*, `edits`* (`[{old_string*, new_string*, replace_all}]`, `minItems` 1), `expected_hash`

Edits apply in order, each to the text the previous one produced, each with edit's rules. Any failure → nothing written; `edit-match-error-index` is the 1-based edit and the message starts `edit <i>: `. One CAS write, one diff (original → final), first line counts all replacements. An empty or non-array `edits`, or an item missing `new_string`, is a `tool-input-error`.

### glob — `pattern`*, `path` (default the root)

- gitignore glob syntax (`*`, `?`, `[…]`, `**`), matched against the whole path **relative to `path`**, as if anchored with a leading `/`: `*.lisp` is top level only, `**/*.lisp` any depth (zero directories included), `src/*.lisp` one level. Brace expansion is not supported. (Implementable with `parse-ignore (list (concat "/" pattern))` + `ignore-path-status` = `:ignored`.)
- Files only, root-relative, sorted `string<`, one per line. More than `max-results` → the first `max-results` then `[truncated: showing M of N matches; narrow the pattern or path]`. None → `No files matched <pattern>`.
- `path` missing → `not found`; a file → `not a directory`.

### grep — `pattern`*, `path` (dir or file, default the root), `include`, `regex`, `case_insensitive`, `max_results`

- One `<rel>:<line>:<text>` per matching line, sorted by path then line. Skips files with a NUL in the first 8000 bytes.
- `include`: `.gitignore` syntax relative to the search path, as `fs-grep :include` (`*.lisp` at any depth).
- `max_results` integer ≥ 1, default and cap `max-results`. More matches → `[truncated at N match|matches; narrow the pattern or path]` ("match" when N is 1). Exactly N → no notice.
- Output over `max-output` characters (lines with their LF) → whole lines that fit, then `[truncated: output over <max-output> characters; narrow the pattern or path]`.
- None → `No matches for <pattern>`. Empty pattern or `regex: true` (message contains `regex`) → `tool-input-error`.

### ls — `path` (default the root)

Entries directly in the directory, sorted by name (`string<`, ignoring the slash), directories with a trailing `/`, one per line. Empty → `[empty directory]`. A file → `not a directory` and `read`; missing → `not found`.

---

## Permissions and instructions

- `tool-permission-resources` → `("path:<rel>")`: `file_path` for read / write / edit / multi_edit, `path` (default `"."`) for glob / grep / ls. **Never signals:** a path that does not resolve gives `("path:<argument as given>")` (the tool still refuses it); unparsable arguments or a missing / non-string path key give `("*")`, the protocol default. Rules then read `("edit" "path:secret/*" :deny)`.
- `tool-instruction-paths` → `("<rel>")`, the same path, so `:instructions-discovery` / steer `instruction-discovery` rooted at the same directory finds `AGENTS.md` from the root down to it; NIL when the path does not resolve.

---

## Contract (tests)

`agent-tools/tests`, Rove. Backend tests are `deftest-parametrize` over `(:memory :local)` (`/work` on a fresh memory fs, a temp directory truename; `tests/support.lisp`). 124 test cases (~350 `ok` forms, ~730 checks across both backends); all fail on the stubs. A throwaway prototype (not committed) passed all 124 on SBCL / macOS before sealing, which also found [cl-stack-pathlib#23](https://github.com/egao1980/cl-stack-pathlib/issues/23).

| File | Covers |
|------|--------|
| `construct-test` | defaults, root designators, missing / non-directory root, unknown tool name, `:tools` subset (canonical order, `agent-unknown-tool`) |
| `schema-test` | 7 descriptors in order, descriptions, per-tool properties / types / required, `additionalProperties`, no `$schema`, `multi_edit` item schema, JSON-encodable |
| `paths-test` | lexical normalization, absolute under root, `.`, refusals (`..`, `/etc/passwd`, sibling-prefix), empty path, `:allow-root`, every tool refuses an escape and writes nothing |
| `symlink-test` | (not on Windows: `:if-feature (:not (:or :windows :win32))`) link out refused for read / write / edit / ls / grep; root-wide grep / glob do not follow; inside link works |
| `read-test` | exact numbered output + hash, no final LF, empty, blank lines, UTF-8, CRLF fixture (`tests/fixtures/crlf.txt`, `-text`), offset / limit, `max-read-lines` cap, `max-output`, argument and file errors, hash-table arguments, ignored file readable, zip |
| `write-test` | create with parents, overwrite, byte count, verbatim CRLF, CAS match / stale / missing, OVERWRITE restart, errors, zip → `tool-unavailable` |
| `edit-test` | exact result text, 3-line context, 0 / n matches, `replace_all` and non-overlap, delete, CRLF exactness, argument errors, `expected_hash`, **concurrent write detected** (racing memory fs), ignored file, zip |
| `multi-edit-test` | ordered application, `replace_all` per edit, all-or-nothing with index, argument errors, `expected_hash` |
| `glob-test` | anchored patterns, `**`, `?`, `[..]`, files only, ignore (`:auto`, NIL, matcher, nested, root rules under a subdir), `.git/`, truncation, errors |
| `grep-test` | literal and case-insensitive, metacharacters literal, path / file / include, ignore option, `max_results` and cap, `max-output`, no match, regex refusal, errors |
| `ls-test` | listing, `.`, empty dir, ignore option, `.git/`, errors |
| `permissions-test` | resources per tool, normalization, never signals, `"*"` fallback, instruction paths |
| `agent-run-test` | mock-LLM runs on a libuv loop: tools collected / found, write → read results, failures as tool results (`tool-failure-text`), a `path:secret/*` deny rule, AGENTS.md discovery from a read |

Checklist applied: handlers recording restarts sit inside the `ok` form; restarts are looked up inside the handler; vectors compared with `equalp`; no `~<newline>` in FORMAT strings; CRLF fixture marked `-text`.

# revision-backend-git (V0) — revision-protocol over the git CLI

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track V · protocol brief [revision.md](revision.md) · diffs [diff.md](diff.md)
**Status:** milestone **V0 locked** (contract). Repo [`egao1980/revision-backend-git`](https://github.com/egao1980/revision-backend-git) (`stack-rev-git`), version 0.1.0: exports, conditions, classes, documented behaviour, stub methods and the Rove suite that specifies them. Implementation runs through **team-solve**.

A `revision-store` and a `revision-target` over one git repository, driven through the `git` program only (no libgit2, no gitoxide). V0 = graph, refs, drift, diffs (summary and content), a read-only revision filesystem. Projections, `commit-projection`, `execute-plan`, merges as projections and linked worktrees are **V1**.

---

## Decisions (V0)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Package** | `revision-backend-git`, nickname `stack-rev-git`; local nicknames `rev` `diff` `dt` `proc` `pathlib` | Stack naming |
| **Dependencies** | `revision-protocol` 0.2.0, `diff-protocol` 0.2.0 (tree engine, `parse-diff :unified`), `datetime-protocol` 0.1.3, `process-protocol` 0.2.0 + `process-backend-uiop` 0.1.0, `cl-stack-pathlib` 0.4.0, `encoding-protocol` 0.2.0, `bordeaux-threads` 0.9.4 | Own stack first; git runs through `process-protocol` |
| **Store** | `(make-git-store path &key git env permit-force)` → `git-store`. PATH: any directory inside a worktree, or a bare repo / git dir; outside a repository → `git-command-error`. Readers `git-store-path` (worktree top-level, NIL when bare), `git-store-git-dir`, `git-store-bare-p`, `git-store-env` (copy) | One store per repository |
| **Version** | `*minimum-git-version*` = **"2.43.0"**. `make-git-store` probes `git --version` (cached per program) and compares on every call: older → `vc-tool-version-error` (tool "git", found "2.42.1", required); a program that cannot start → found NIL. No other git command runs first; no fallback paths. `parse-git-version`, `git-version` | Plan: one minimum, no fallbacks; later features become capabilities from the probed version |
| **Locked minimum** | Plan rule = latest stable when V0 starts (local 2.54.0). CI probe 2026-11-19: ubuntu-latest VM **2.56.1**, macos-latest **2.56.0**, windows-latest **2.56.0.windows.4**, cl-repository **ci-base** container (Ubuntu 24.04, where ubuntu tests run) **2.43.0** → locked to **2.43.0**. V0 needs ≥ 2.36 (`cat-file --batch-command`, `ls-tree --format`). Raise when ci-base gets a newer git ([cl-repository#101](https://github.com/egao1980/cl-repository/issues/101)); V1 `replay` needs ≥ 2.44 | "What all three have" |
| **Fixed environment** | Added to the inherited environment for every command, winning over `:env`: `LC_ALL=C`, `GIT_TERMINAL_PROMPT=0`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_OPTIONAL_LOCKS=0`, `GIT_PAGER=cat`, `GIT_EDITOR=:`. Options before the caller's: `-c core.quotepath=off -c color.ui=never -c core.autocrlf=false -c core.safecrlf=false -c diff.noprefix=false -c diff.mnemonicPrefix=false -c core.disambiguate=commit --no-pager`; per command `-z`, `--no-color`, `--no-ext-diff`, `--no-textconv` where accepted | Output does not depend on the user's locale or config; never prompts |
| **`:env`** | Alist added to every command (HOME, GIT_CONFIG_GLOBAL, identity …) | Tests isolate the user's config; harness passes credentials helpers' env |
| **`run-git`** | `(run-git store args &key input (output :string) (ok-exit-codes '(0)))` → `(values stdout exit-code stderr)`; `:octets` = exact bytes; input string (UTF-8) or octets; other exits → `git-command-error` | Escape hatch for callers and the backend's own plumbing |
| **Batch process** | One long-lived `cat-file --batch-command` per store for object reads, started on first read; `close-git-store` (idempotent, store stays usable), `with-git-store`, `git-store-batch-active-p` | No process per blob |
| **Revisions** | Commits. `revision-id` = full lowercase hex; `revision-parent-ids` in commit order; `recorded-at` = committer date, `valid-at` = author date (whole seconds); `revision-message` without its final newline; `revision-provenance` `(:author-name :author-email :committer-name :committer-email :tree)`; `revision-content` = tree id | Plan: `:recorded` committer, `:valid` author |
| **Graph set** | `heads`, `revision-children` and walks consider commits reachable from `refs/heads/*`, `refs/tags/*` and HEAD. Any commit object resolves by id (reachable or not) | No `--all` surprises (stash, notes, remotes) |
| **String designators** | In order: full commit id; hex prefix ≥ 4 over **commit** objects (several → `ambiguous-revision` with every matching full id); git revspec (`rev-parse --verify --end-of-options SPEC^{commit}`: `HEAD`, `main~2`, `v1^{}`). Nothing → `revision-not-found` | Protocol: ids first; plan: "git revspecs accepted" |
| **Refs** | Short names. `:movable` = `refs/heads/NAME`, `:tag` = `refs/tags/NAME` whose target peels to a commit (tags of trees / blobs are left out). `ref-target` = peeled commit; `ref-annotation` = annotated tag message without final newline, else NIL. Same name as branch and tag: `rev-ref` / `find-ref` pick the tag (git's rule); `list-refs` lists both, branch first | One protocol namespace over git's two |
| **CAS** | `move-ref`, `delete-ref`, `commit-revision :ref` via `update-ref refs/heads/NAME NEW OLD` (OLD = zero id for `:expected nil`); failure → `ref-conflict` with the actual id, restarts `use-current`, `retry`, `force` (gated by `:permit-force` NIL / T / predicate). Holds against other git processes | git's own ref lock = linearizable |
| **Tags** | `tag-revision` lightweight, or annotated (`tag -a`) with `:annotation`; same target + annotation → idempotent, nothing rewritten; otherwise `tag-immutable` (`create-new-tag`); over a branch name → `ref-conflict` (expected NIL). `move-ref` / `delete-ref` / `commit-revision :ref` on a tag → `tag-immutable` | Protocol R0a rules |
| **Listener** | `(setf ref-listener)`; events `(:ref-moved name old new)` for changes made **through this store** (tags: old NIL, new = peeled commit) | git has no notification channel |
| **commit-revision content** | Tree value (blobs + trees written) · string = existing tree (id or revspec, `"HEAD^{tree}"`) · `:index` = `write-tree` of the real index (index file untouched) · `diff-protocol:diff` = applied to the first parent's state (root: empty tree) · `revision-payload` · else `revision-error`. Committer date `(dt:now)`, author date `:valid-at` or `(dt:now)`, both UTC seconds → `dt:with-fixed-clock` gives deterministic ids. Provenance overrides identity. Message gets one final newline. `:id` → `revision-error`. A failed CAS may leave an unreferenced commit object; no ref moves | "From a tree state or the index" |
| **Graph** | Walks via `rev-list` (`--topo-order` / `--date-order` / `--first-parent`, reversed so parents come first; `:reverse t` = git's order). `merge-base` (`--all`; ALL NIL = git's single answer; unrelated → NIL), `ancestor-p` = `merge-base --is-ancestor`, `revision-range` = `rev-list INCLUDE ^EXCLUDE` topo, parents first. `:footprint` uses each revision's first-parent delta, **not** pathspec simplification (which drops merges). `rev-as-of` compares committer (`:recorded`) / author (`:valid`) dates along first parents | Tests compare with rev-list output exactly |
| **Content** | `content-primary` `:state`; `content-engine` a `tree-diff-engine`; empty state `(diff:make-tree)`. `revision-state`: blob with NUL in the first 8000 bytes, or invalid UTF-8 → `:binary` octets; else `:text` string (CRLF kept); modes as git (`#o100644` `#o100755`); symlink = `:text` target, `#o120000`; submodule = type `:gitlink`, content commit id, `#o160000`. `revision-delta` of a root = diff from the empty tree | One state value for tree, filesystem and diff laws |
| **state-diff** | A / B: designators or a `git-working-copy`. `:summary` from `diff-tree -r -z -M --name-status` — file-level, lazy before / after nodes, no children, `"tree:/path"` footprints. `:changes` (default) = `git diff -M` → `parse-diff :unified` leaves. `:content` = file-level with hunk children. Binary / gitlink / type-changing files are whole-file changes with both nodes — **never** `opaque-change` — so every git diff applies and inverts (law 3). Rename detection = git's 50%. C-quoted paths (control characters, `"`, `\`) only at `:summary` in V0 ([diff-protocol#4](https://github.com/egao1980/diff-protocol/issues/4)) | Plan table |
| **Working copy** | `(make-git-working-copy store &key stamp-ref)`; bare store or a stamp-ref that is not a full valid ref → `revision-error`. **State** = what `git add -A` would record (tracked files on disk + untracked not ignored), via a temporary index; the index does not count. **Stamp** = HEAD (`target-stamp` moves HEAD like `reset --soft`; NIL → `revision-error`; unborn → NIL) or `stamp-ref` (HEAD, branches, index never touched; absent ref = unstamped; NIL deletes it). One stamp: more → `revision-error`. `target-fidelities` NIL, `target-transactional-p` NIL in V0 | Agent checkpoints without moving the user's branch |
| **Drift** | NIL iff the working-copy tree equals the stamp's tree (empty tree when unstamped); else `state-diff` stamp → working copy at `:changes`. Empty `status --porcelain=v2 -z --untracked-files=all` is a sufficient shortcut with the HEAD stamp | Plan: drift from status |
| **capture-revision** | Commit of `target-state` (temp index → `write-tree` → `commit-tree`), parents default `target-revisions`, message default "capture", then stamp → drift NIL. Worktree files and the real index stay byte-identical. **Not `stash create`**: it skips untracked files, so drift would remain | Deviation from the plan table, recorded |
| **Revision filesystem** | `revision-filesystem` (a `pathlib:filesystem`), `make-revision-filesystem store designator` (pinned to the resolved commit id; `revision-filesystem-revision`), `revision-path store designator &optional path`. POSIX paths from `/`; `ls-tree -z -l` + the batch process. Symlinks are files with `fs-symlink-p` / `fs-read-symlink` (not followed); `fs-executable-p` = mode 100755; `fs-file-size` = blob size; `fs-last-modified` = committer date; `iterdir` in git tree order; `fs-stat` mode `#o644` / `#o755`; gitlinks are empty directories; writes, `fs-make-temp`, `fs-as-uri` → `unsupported-operation`; missing → `path-not-found` | Pathlib tools on any revision (plan: `project-state` view in V1) |
| **Parsers** | `parse-status-porcelain-v2`, `parse-name-status`, `parse-ls-tree`: pure functions of `-z` output → plists (keys in the docstrings); malformed → `revision-error`. Fuzzed in tests | Plan acceptance: parsers fuzzed from corpora |
| **Conditions** | Protocol types for protocol failures. Git-specific: `vc-tool-version-error` (tool found required) and `git-command-error` (command exit-code stderr), both `revision-error`. `vc-tool-version-error` moves to revision-protocol for jj ([revision-protocol#4](https://github.com/egao1980/revision-protocol/issues/4)); this package then re-exports it | No backend error dialect |
| **Threads** | A store may be shared; ref operations linearizable (git's ref lock); the batch process is guarded by a lock | Law 1 CAS under threads |

### Condition tree

```
revision-error                       (revision-protocol)
├── revision-not-found / ambiguous-revision / ref-conflict / tag-immutable …   (protocol, signalled by the backend)
├── vc-tool-version-error (tool found required)     make-git-store
└── git-command-error (command exit-code stderr)    run-git and any git failure without a protocol meaning
```

---

## Protocol surface (V0)

```lisp
;;; Store
(make-git-store path &key git env permit-force)    ; → git-store
(git-store-path s) (git-store-git-dir s) (git-store-bare-p s) (git-store-env s)
*git-program* *minimum-git-version* (parse-git-version string) (git-version s)
(run-git s args &key input output ok-exit-codes)    ; → (values stdout exit-code stderr)
(git-store-batch-active-p s) (close-git-store s) (with-git-store (s path &rest keys) …)
;; revision-protocol GFs on git-store: resolve-revision commit-revision move-ref tag-revision
;; delete-ref find-ref list-refs revision-parents revision-children walk-revisions merge-base
;; ancestor-p revision-range heads ref-listener permit-force-p content-primary content-engine
;; revision-state revision-delta state-diff (delta-inverse / delta-footprint from the protocol)

;;; Working copy
(make-git-working-copy store &key stamp-ref)        ; → git-working-copy
(working-copy-store wc) (working-copy-path wc) (working-copy-stamp-ref wc)
;; target-revisions target-stamp target-state target-drift capture-revision
;; target-fidelities target-transactional-p

;;; Revision filesystem
(make-revision-filesystem store designator) (revision-path store designator &optional path)
(revision-filesystem-store fs) (revision-filesystem-revision fs)

;;; Parsers
(parse-status-porcelain-v2 s) (parse-name-status s) (parse-ls-tree s)

;;; Conditions
vc-tool-version-error (-tool -found -required)  git-command-error (-command -exit-code -stderr)
```

---

## Contract tests (V0)

`revision-backend-git/tests`, Rove — **131 tests** including parametrized rows; against the stubs 130 fail and 1 (`minimum-git-version-is-locked`) passes. Each test builds a throwaway repository with the **real git** in a fresh temp directory: own `HOME` with an empty `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM=1`, `user.name` / `user.email` / `core.autocrlf=false` / no signing per repo, fixed author and committer dates (so ids are deterministic). Expected values come from running git in the test (`rev-list`, `merge-base`, `diff-tree`, `ls-tree`, `for-each-ref`, `cat-file`, `status`) or from the fixture's known content; the store gets the same `:env`. Tests run git through UIOP with output redirected to files (byte-exact), independent of the code under test.

| File | Covers |
|------|--------|
| `support`, `fixtures` | Temp repos, git runner, histories: linear with lightweight + annotated tags and a backdated author; branch + `--no-ff` merge; criss-cross + an unrelated root; content history (rename with edit, pure rename, `+x`, binary with NUL, invalid UTF-8, CRLF, empty file, symlink and file → directory via the index, `core.fileMode` / `core.symlinks` off so Windows behaves the same); 600 `hash-object` commits for an ambiguous 4-hex prefix; dirty working copies |
| `version-test` | `parse-git-version` rows, the locked minimum, installed git ≥ minimum, `git-version`, `vc-tool-version-error` (too old via a bound minimum, missing program), store paths (subdir, bare), not-a-repo, `run-git` output / exit codes / octets / input, fixed environment (an alias echoing the variables) and options, batch process lifecycle |
| `parse-test` | Hand corpora with spaces, newlines, unicode, gitlinks, unmerged entries; live `status` / `diff-tree` / `ls-tree` output; malformed input; 5 seeded fuzz rounds × 3 parsers |
| `resolve-test` | Revision fields vs `git log`, merge parent order, prefixes, ambiguity candidates, not-found rows, revspec rows, refs / annotated tags / tag-wins, `rev-parent` / `rev-ancestor` |
| `ref-test` | `find-ref` / `list-refs`, `move-ref` CAS incl. a concurrent external `update-ref`, `use-current` / `retry`, gated `force`, tags never move, `tag-revision` light / annotated / idempotent / over a branch / `create-new-tag`, `delete-ref` CAS, listener events |
| `commit-test` | Tree values (modes, binary, CRLF), parents and refs, tree ids and revspecs, `:index`, diffs and payloads, identity / dates / deterministic ids, refusals and atomicity, bare repos |
| `graph-test` | Parents, children, heads vs `rev-list --children`; walk orders vs `rev-list` rows; `:footprint` on a merge; `merge-base` / `:all` / unrelated; `ancestor-p`; `revision-range`; as-of rows on both axes |
| `content-test` | `revision-state` of every file kind and gitlinks, `revision-delta`, `state-diff` `:summary` vs `diff-tree`, `:changes` / `:content` shapes (hunks, whole-file binary, moves), law 3 rows at every level, `:footprint` |
| `working-copy-test` | Values and refusals, HEAD stamp, `target-state` = `add -A`, drift rules, `state-diff` with the working copy, capture with the HEAD stamp and with a stamp ref (HEAD / branch / status / worktree / index untouched), unborn branch |
| `filesystem-test` | Reads at several revisions (pinned), listing / predicates / symlinks / modes / sizes / mtime / walk / glob, stat and hashes, read-only and missing paths, `revision-path`, 200 reads on one batch process |
| `law-test` | **Law 1** (revisions never change, lists not shared, CAS linearizable with 2×10 and 4×5 threads), **law 2** (as-of monotonic rows, both axes), **law 3** (delta composition associative) |

---

## Prerequisites (stack fixes before team-solve)

The backend must run git through `process-protocol`, and `process-backend-uiop` 0.1.0 cannot yet do what git needs. Fix in the stack, publish, bump the pins here:

- [process-backend-uiop#8](https://github.com/egao1980/process-backend-uiop/issues/8) — `backend-run` decodes output as text: binary or non-UTF-8 output errors.
- [process-backend-uiop#9](https://github.com/egao1980/process-backend-uiop/issues/9) / [process-protocol#7](https://github.com/egao1980/process-protocol/issues/7) — `:env` replaces the whole environment on SBCL; semantics undefined.
- [process-backend-uiop#10](https://github.com/egao1980/process-backend-uiop/issues/10) — `backend-launch` has no octet streams (batch process); `:timeout` ignored.

---

## Non-goals (V0)

- Projections, `project-merge` (`merge-tree --write-tree`), `commit-projection`, `plan-transition` / `execute-plan`, `(setf target-state)`, linked worktrees (V1)
- Network (`fetch` / `push`), signing, GC, multi-ref atomic updates (`update-ref --stdin` transactions)
- libgit2 / gitoxide; jj (V2)

---

## Implementation tasks

- [x] V0 contract: this brief, `egao1980/revision-backend-git` skeleton, Rove suite, CI git-version probe
- [ ] process-protocol / process-backend-uiop fixes above, published
- [ ] V0 implementation through team-solve
- [ ] ci-base git upgrade → raise `*minimum-git-version*`
- [ ] V1: projections, `commit-projection`, `execute-plan`, worktrees

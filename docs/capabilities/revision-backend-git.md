# revision-backend-git (V0, V1) — revision-protocol over the git CLI

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track V · protocol brief [revision.md](revision.md) · diffs [diff.md](diff.md)
**Status:** milestone **V0 locked** and implemented; milestone **V1 locked** (contract) — see [V1 — locked](#v1--locked). Repo [`egao1980/revision-backend-git`](https://github.com/egao1980/revision-backend-git) (`stack-rev-git`), version 0.1.0 (0.2.0: revision-protocol 0.3.0, diff-protocol 0.2.1): exports, conditions, classes, documented behaviour, stub methods and the Rove suite that specifies them. Implementation runs through **team-solve**.

A `revision-store` and a `revision-target` over one git repository, driven through the `git` program only (no libgit2, no gitoxide). V0 = graph, refs, drift, diffs (summary and content), a read-only revision filesystem. Projections, `commit-projection`, `execute-plan`, merges as projections and linked worktrees are **V1** ([below](#v1--locked)).

---

## Decisions (V0)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Package** | `revision-backend-git`, nickname `stack-rev-git`; local nicknames `rev` `diff` `dt` `proc` `pathlib` | Stack naming |
| **Dependencies** | `revision-protocol` 0.3.0, `diff-protocol` 0.2.1 (tree engine, `parse-diff :unified` with C-quoted paths), `datetime-protocol` 0.1.3, `process-protocol` 0.2.0 + `process-backend-uiop` 0.1.0, `cl-stack-pathlib` 0.4.0, `encoding-protocol` 0.2.0, `bordeaux-threads` 0.9.4 | Own stack first; git runs through `process-protocol` |
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
| **state-diff** | A / B: designators or a `git-working-copy`. `:summary` from `diff-tree -r -z -M --name-status` — file-level, lazy before / after nodes, no children, `"tree:/path"` footprints. `:changes` (default) = `git diff -M` → `parse-diff :unified` leaves. `:content` = file-level with hunk children. Binary / gitlink / type-changing files are whole-file changes with both nodes — **never** `opaque-change` — so every git diff applies and inverts (law 3). Rename detection = git's 50%. C-quoted paths (control characters, `"`, `\`) at every level since 0.2.0 (diff-protocol 0.2.1 unquotes them, [diff-protocol#4](https://github.com/egao1980/diff-protocol/issues/4)); V0 had them at `:summary` only | Plan table |
| **Working copy** | `(make-git-working-copy store &key stamp-ref)`; bare store or a stamp-ref that is not a full valid ref → `revision-error`. **State** = what `git add -A` would record (tracked files on disk + untracked not ignored), via a temporary index; the index does not count. **Stamp** = HEAD (`target-stamp` moves HEAD like `reset --soft`; NIL → `revision-error`; unborn → NIL) or `stamp-ref` (HEAD, branches, index never touched; absent ref = unstamped; NIL deletes it). One stamp: more → `revision-error`. `target-fidelities` NIL, `target-transactional-p` NIL in V0 | Agent checkpoints without moving the user's branch |
| **Drift** | NIL iff the working-copy tree equals the stamp's tree (empty tree when unstamped); else `state-diff` stamp → working copy at `:changes`. Empty `status --porcelain=v2 -z --untracked-files=all` is a sufficient shortcut with the HEAD stamp | Plan: drift from status |
| **capture-revision** | Commit of `target-state` (temp index → `write-tree` → `commit-tree`), parents default `target-revisions`, message default "capture", then stamp → drift NIL. Worktree files and the real index stay byte-identical. **Not `stash create`**: it skips untracked files, so drift would remain | Deviation from the plan table, recorded |
| **Revision filesystem** | `revision-filesystem` (a `pathlib:filesystem`), `make-revision-filesystem store designator` (pinned to the resolved commit id; `revision-filesystem-revision`), `revision-path store designator &optional path`. POSIX paths from `/`; `ls-tree -z -l` + the batch process. Symlinks are files with `fs-symlink-p` / `fs-read-symlink` (not followed); `fs-executable-p` = mode 100755; `fs-file-size` = blob size; `fs-last-modified` = committer date; `iterdir` in git tree order; `fs-stat` mode `#o644` / `#o755`; gitlinks are empty directories; writes, `fs-make-temp`, `fs-as-uri` → `unsupported-operation`; missing → `path-not-found` | Pathlib tools on any revision (plan: `project-state` view in V1) |
| **Parsers** | `parse-status-porcelain-v2`, `parse-name-status`, `parse-ls-tree`: pure functions of `-z` output → plists (keys in the docstrings); malformed → `revision-error`. Fuzzed in tests | Plan acceptance: parsers fuzzed from corpora |
| **Conditions** | Protocol types for protocol failures. Git-specific: `vc-tool-version-error` (tool found required) and `git-command-error` (command exit-code stderr), both `revision-error`. `vc-tool-version-error` is revision-protocol's since 0.2.0 ([revision-protocol#4](https://github.com/egao1980/revision-protocol/issues/4)), imported and re-exported here (same symbol as `stack-rev:vc-tool-version-error`). Capability queries: `ref-cas-p` T (`update-ref` CAS), `conflicted-revisions-p` NIL. `capture-revision` takes `:valid-at` / `:provenance` (as `commit-revision`) and refuses `:id` | No backend error dialect |
| **Threads** | A store may be shared; ref operations linearizable (git's ref lock); the batch process is guarded by a lock | Law 1 CAS under threads |

### Condition tree

```
revision-error                       (revision-protocol)
├── revision-not-found / ambiguous-revision / ref-conflict / tag-immutable …   (protocol, signalled by the backend)
├── vc-tool-version-error (tool found required)     make-git-store   (revision-protocol's, re-exported)
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

## V1 — locked

**Plan row:** V1 = projections, `commit-projection`, `capture-revision`, `execute-plan`, worktrees (depends on V0 and R4's pathlib view). **Acceptance (binding, from the plan):** `project-state`, `project-merge`, `commit-projection` and `capture-revision` leave the store's working tree and its real index byte-identical, checked by `git status` and an index hash. The V1 suite checks that around every one of them, and also around `apply-patch`, `project-plan`, `discard-projection` and `remove-worktree`.

Contract on branch `agent/git-v1-contract-2532` of [`egao1980/revision-backend-git`](https://github.com/egao1980/revision-backend-git). Version **0.3.0** (new API, minor). The branch has the exports, two git-specific conditions, the `git-projection` class, docstrings that state the behaviour, stubs that call `%not-implemented` (internal, `src/projection.lisp`), and the Rove files that specify them. The implementation removes `%not-implemented` and every call to it. It runs through **team-solve**.

### Decisions (V1)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Files** | `src/projection.lisp` (projections, `apply-patch`, tree filesystem), `src/plan.lisp` (plans, `execute-plan`, `project-plan`, `(setf target-state)`), `src/worktree.lisp` (linked worktrees, replay). No new dependencies: pathlib stays at 0.4.0, because V1 uses only `make-path`, the local filesystem and the V0 revision filesystem | Small diff against V0 |
| **Projection kinds** | `git-projection` (a `rev:projection`) is one of two kinds. **Virtual**: a tree object in the repository; nothing is checked out. `project-state` without `:writable`, `project-merge`, `apply-patch` and `project-plan :exact` return one. **Materialized**: a detached linked worktree. `project-state :writable t` and `project-plan :shadow` return one. `git-projection-tree` is the tree id; `git-projection-worktree` is the worktree directory, or NIL for a virtual projection | The plan's rule: anything an image loads is materialized, and everything else stays virtual and cheap |
| **Fidelity** | Every projection is `:exact`, whatever `:fidelity` asks for (the protocol allows a better fidelity than requested). The one exception is `project-plan :shadow` | Git trees are exact |
| **`project-state` designators** | A revision designator (parents = its id); a `git-working-copy` (a snapshot of `target-state` with uncommitted and untracked files, not ignored ones; parents = `target-revisions`); or a `git-projection` (its state and parents; **conflicts are not carried over**, so a writable copy of a merge projection is how you resolve the merge by hand) | Covers the plan's area over a git working copy: clone it with its uncommitted changes, then commit back through `commit-projection` |
| **Views** | A virtual projection's view is a `pathlib:path` on a read-only `revision-filesystem` over the projection's tree. New: `make-tree-filesystem store tree`, with `revision-filesystem-revision` NIL, `revision-filesystem-tree` set, and every mtime the Unix epoch. A materialized projection's view is a `pathlib:path` on `pathlib:local-filesystem` at the worktree's top level | `projection-view` = the domain's normal read API (pathlib), so the agent tools run unchanged |
| **Materialized state** | `projection-state` / `git-projection-tree` of a materialized projection = what `git add -A` would record in the worktree (a temporary index seeded from **that worktree's** index, so `core.fileMode` / `core.symlinks` = false keep the recorded modes, as in V0). Whatever writes the files (pathlib, `cl:open`, a shell, an image) shows up. `(setf projection-state)` writes the worktree so that the state equals STATE afterwards: tracked and untracked files outside STATE are deleted, and ignored files (by the rules in effect after the write) are left alone | The same state rule as the V0 working copy |
| **Where worktrees go** | `*projection-directory*` (NIL = the OS temp directory) gets one fresh subdirectory per materialized projection, outside the store's worktree. `git worktree add --detach` (`--no-checkout`, then `read-tree -u --reset TREE` with the linked worktree's own index). A bare store can materialize too. `discard-projection` runs `worktree remove --force`, deletes the directory and prunes | A linked worktree has its own HEAD and index, so the main checkout is never touched |
| **`project-merge`** | `merge-tree --write-tree -z --allow-unrelated-histories A B`; git picks the base (criss-cross: ort's virtual base; unrelated: empty). Parents `(A-id B-id)`, a virtual projection. **Conflicts as data**: one `diff:diff-conflict` per conflicted path (from the conflicted-file-info section). `conflict-ours` / `conflict-theirs` are V0 file-level changes from git's stage 1 (absent → `:add`) to stage 2 / stage 3 (absent → `:remove`), and the footprint is `"tree:/path"`. **`projection-state` keeps the base value at each conflicted path** (stage 1, or absent), as the protocol says. `merge-projection-marker-tree` = git's own result tree, with conflict markers. The second value = `projection-conflicts` | Protocol R0b `project-merge` semantics over git's merge engine |
| **`commit-projection`** | The tree (`git-projection-tree`) is committed through V0 `commit-revision` (`commit-tree`, then `update-ref` CAS when `:ref` is given), so V0's `ref-conflict` restarts, `tag-immutable` and the `:id` refusal all apply. Parents default to `projection-parents`. A conflicted projection signals `merge-conflict`: `take-ours` / `take-theirs` resolve each conflicted path to that side's file (removal included), `use-merged` commits the base values, `abort` returns NIL and commits nothing | One commit path for V0 and V1 |
| **`apply-patch`** (the plan's `apply-diff` on a projection) | `(apply-patch projection patch)` returns a **new** virtual projection (parents copied, no conflicts); the source does not change. A `git diff` patch (string, or octets for non-UTF-8 and `--binary` patches) is applied with `git apply --cached` into a temporary `GIT_INDEX_FILE` seeded with the source tree, then `write-tree`. A refusal signals `patch-rejected` (slots projection, stderr) and writes nothing. A `diff:diff` value is applied with `diff:apply-diff` to `projection-state`, and its `apply-conflict` restarts propagate | Cheap "does this patch apply to X / to the merge" for H5. Never touches the real index |
| **Plans** | `plan-transition` (git-store, git-working-copy) uses the protocol's path rule: down to the merge-base, up to TO, one parent edge per step, and at a merge the first parent that is or reaches the base. **Step diffs are `:summary`** (file-level, lazy nodes, one `diff-tree` per step; they apply and invert, per V0 law 3). Every step is reversible, so this backend never signals `irreversible-step`. `describe-plan` and `step-footprint` are the protocol's own methods. Pure: no ref, file or index changes | `:changes` would read every blob of every step at plan time. This is a recorded deviation from the R0b "level :changes" wording |
| **`execute-plan`** | The protocol's flow: a drift check first (`capture-and-continue` / `discard-drift` / `abort`), a stamp after every step, resume from a step's TO, a foreign stamp → `revision-error`, and `step-failed` with `retry-step` / `skip-step` / `rollback-to-start`. **HEAD stamp**: each step is `read-tree -m -u FROM-TREE TO-TREE` on the real index, then `update-ref HEAD TO`, so the current branch moves and a whole plan works like `git reset --keep GOAL` (each step leaves a reflog entry). **Stamp ref**: only the worktree files change, through a temporary index; HEAD, branches and the real index are never touched. Ignored files are never touched in either mode | V0's two stamp modes, carried over to transitions |
| **`(setf target-state)`** | Writes the worktree files (the materialized-projection rule above). HEAD, the stamp ref and the real index stay as they are, so the target drifts | The protocol's out-of-band write |
| **`target-fidelities`** | `(:exact :shadow)`. `project-plan :exact` = a virtual projection of the goal tree, which is what `execute-plan` leaves on a target with no drift. `:shadow` = a materialized projection: a worktree checked out at `plan-start` (the target's drift is left behind, as after `discard-drift`) where the steps really run. `:model` → `projection-unsupported` with only `use-shadow` and `apply-for-real` offered. A target projection read or committed after the working copy's stamp or state changed → `projection-stale`. `target-transactional-p` stays NIL | Law 6 holds by construction for `:exact` |
| **`capture-revision`** | **Unchanged from V0**: temporary index → `write-tree` → `commit-tree`, then the stamp. The plan's `stash create` row stays rejected, because it skips untracked files and would leave drift. V1 adds the byte-identical acceptance checks around it (including on a linked worktree) | V0 decision stands |
| **Linked worktrees** | `add-worktree store path designator &key branch` → a `git-store` on the new worktree (same `:env` and `:permit-force`). Detached by default; `:branch` creates the branch (an existing one → `ref-conflict`, expected NIL, and nothing is created); a non-empty PATH → `revision-error`. `list-worktrees` → plists `:path :head :branch :detached :bare :locked :prunable`, main worktree first, from `worktree list --porcelain -z` through the pure, fuzzed `parse-worktree-list`. `remove-worktree store path &key force`: local changes without `:force` → `git-command-error`; the main worktree or a non-worktree → `revision-error`. New reader `git-store-common-dir` (= `git-store-git-dir` except on a linked worktree). `(make-git-working-copy linked-store)` is that worktree's own target | Subagents can get a real checkout. Refs are shared, HEAD and the index are per worktree |
| **Rebase → `replay`** | `replay-revisions store revisions onto &key ref expected`: REVISIONS is a chain, parents first (as `revision-range` returns). `git replay --onto` (with the flag that makes it print instead of update refs, `--ref-action=print` where the probed version has it), then the backend moves REF itself with CAS (`ref-conflict` as in V0). Message, author and author date are kept. A merge commit or a non-chain → `revision-error`; a conflict → `replay-conflict` (slots revision, onto), and no ref moves. `diff:rebase-diff` on diff values stays the diff-protocol tree engine's | Git-native rebase of revisions, separate from the pure diff operation |
| **Git minimum (decided)** | `*minimum-git-version*` **stays 2.43.0**: the ci-base container still ships 2.43.0 and [cl-repository#101](https://github.com/egao1980/cl-repository/issues/101) is open with no PR (checked 2026-11-20). Everything in V1 except replay works on 2.43 (`merge-tree --write-tree` ≥ 2.38, `--merge-base` ≥ 2.40, `worktree add --orphan` ≥ 2.42). **`replay-revisions` is the one capability-gated operation**: `*replay-git-version*` = **"2.44.0"**, and `git-replay-p store` says whether the store's git has it. With an older git it signals `vc-tool-version-error` (tool "git", found, required "2.44.0") before any git command runs. The replay tests check the gate on an older git and skip the replay itself. When #101 lands, `*minimum-git-version*` rises to ci-base's git (≥ 2.44) and the gate goes away (follow-up). `git replay` is still marked experimental, so its flags are checked against CI's version whenever the minimum moves | The plan says no fallbacks. A gate is not a fallback, because the operation is simply unavailable, and it keeps V1 off #101's critical path |
| **Threads** | As in V0. A projection is not shared across threads while it is being written. Materialized projections in different directories are independent (git's worktree locks) | — |

### Condition tree (V1 additions)

```
revision-error                                  (revision-protocol)
├── … V0 …
├── merge-conflict (conflicts projection)       commit-projection: take-ours, take-theirs, use-merged, abort
├── target-drift-detected (target drift)        execute-plan: capture-and-continue, discard-drift, abort
├── step-failed (step cause attempt)            execute-plan: retry-step, skip-step, rollback-to-start
├── projection-unsupported (fidelity supported) project-plan :model: use-shadow, apply-for-real
├── projection-stale (projection)               target projections after the working copy changed
├── vc-tool-version-error (tool found required) replay-revisions on git < *replay-git-version*
├── patch-rejected (projection stderr)          apply-patch: git apply refused the patch   [git-specific]
└── replay-conflict (revision onto)             replay-revisions: a commit conflicts       [git-specific]
```

`irreversible-step` is never signalled (git steps always invert). Discarded projections, writes to a read-only projection, non-chains, and merge commits in a replay signal plain `revision-error`. Dirty `remove-worktree` without `:force` → `git-command-error`.

### Protocol surface (V1) mapped to git

| Protocol / backend call | git |
|-------------------------|-----|
| `project-state` (virtual) | the commit's tree, or the working copy's `add -A` tree via a temporary index |
| `project-state :writable t`, `project-plan :shadow` | `worktree add --detach --no-checkout DIR`, then `read-tree -u --reset TREE` (the linked worktree's index); state = `add -A` + `write-tree` through a temporary index |
| `(setf projection-state)`, `(setf target-state)` | `read-tree` into a temporary index, `checkout-index -f -a`, delete paths outside STATE (ignored files kept) |
| `project-merge` | `merge-tree --write-tree -z --allow-unrelated-histories A B` (conflicted file info → `diff-conflict`s; stage-1 entries → base values, written with `mktree`) |
| `apply-patch` | `GIT_INDEX_FILE=tmp git read-tree TREE`, `git apply --cached`, `write-tree` |
| `commit-projection` | `commit-tree` + `update-ref REF NEW OLD` (V0 `commit-revision`) |
| `capture-revision` | V0: temporary index, `add -A`, `write-tree`, `commit-tree`; **not** `stash create` |
| `plan-transition` | `merge-base`, `rev-list --first-parent` paths, `diff-tree -r -z -M --name-status` per step |
| `execute-plan` (HEAD stamp) | per step `read-tree -m -u FROM TO`, then `update-ref HEAD TO` |
| `execute-plan` (stamp ref) | per step: temporary index, `checkout-index` / removals, then `update-ref STAMP-REF TO` |
| `project-plan :exact` | the goal's tree |
| `state-diff` with projections and plans | the projection's tree / the plan goal's tree (V0 `diff-tree` / `git diff`) |
| `add-worktree` / `list-worktrees` / `remove-worktree` | `worktree add [--detach \| -b BRANCH]`, `worktree list --porcelain -z`, `worktree remove [--force]` + `worktree prune` |
| `replay-revisions` | `replay --onto ONTO BASE..TIP` (print mode), then `update-ref` CAS |

```lisp
;;; V1 additions to the package
git-projection git-projection-p (git-projection-tree p) (git-projection-worktree p)
(merge-projection-marker-tree p) *projection-directory*
(make-tree-filesystem store tree) (revision-filesystem-tree fs)
(apply-patch projection patch)  patch-rejected (-projection -stderr)
(git-store-common-dir s) (add-worktree s path designator &key branch)
(list-worktrees s) (remove-worktree s path &key force) (parse-worktree-list string)
*replay-git-version* (git-replay-p s) (replay-revisions s revisions onto &key ref expected)
replay-conflict (-revision -onto)
;; revision-protocol GFs, new on git-store / git-working-copy / git-projection:
;; project-state project-merge project-plan projection-fidelity projection-view
;; projection-state (setf projection-state) projection-parents projection-conflicts
;; projection-writable-p projection-discarded-p commit-projection discard-projection
;; plan-transition execute-plan (setf target-state); target-fidelities → (:exact :shadow)
```

### Contract tests (V1)

Five new files in `revision-backend-git/tests`, plus `v1-support`. That makes **58 new test rows** (parametrized rows counted), and every one fails against the stubs. The **137 V0 rows still pass**. One V0 assertion moved: `working-copy-values` no longer checks `target-fidelities` = NIL, and `transition-test` now expects `(:exact :shadow)`. Expected values come from real git, run in the test (`merge-tree`, `diff --binary`, `worktree list`, `reflog`, `write-tree` through a temporary index, `hash-object` of `.git/index`).

| File | Covers |
|------|--------|
| `v1-support` | `with-checkout-unchanged` (status with `GIT_OPTIONAL_LOCKS=0`, index hash, worktree bytes, HEAD) around every operation the acceptance line names; real `merge-tree`; `build-diverged` (clean and conflicting, with modify/delete) and `build-chain` fixtures |
| `projection-test` | Values and fidelity rows; the read-only view and tree filesystem; projections of a working copy and of a projection; writable worktrees (location, registration, file edits from outside, `setf`, ignored files); `commit-projection` (parents, ref, dates, provenance, refusals, tags); discard (worktree removed, every later call refused); `apply-patch` as text, octets and a diff value, rejections; `state-diff` over projections (law 3); bare stores |
| `merge-test` | Clean merges against git's tree; designators; conflicts as data (paths, base values, marker tree, change kinds, footprints); unrelated and criss-cross; **law 4** (symmetry, clean and conflicting); merge commits; every `merge-conflict` restart; resolving by hand through a writable copy |
| `transition-test` | Fidelities; plan shapes (down, down + up, no steps, unknown TO); `:summary` reversible steps and `describe-plan`; unborn branch; `execute-plan` with the HEAD stamp (**law 5**, a reflog entry per step, index = goal, ignored files kept) and with a stamp ref (HEAD / branch / index untouched); drift restarts; `capture-and-continue`; resume and foreign stamps; `(setf target-state)`; `project-plan` `:exact` (**law 6**), `:shadow`, `:model` restarts, staleness |
| `worktree-test` | Detached and branch worktrees, `git-store-common-dir`, shared refs, existing branch / non-empty directory; a linked worktree as its own target (capture leaves the main index alone); list / lock / remove / force / refusals; bare repositories; `parse-worktree-list` corpus, malformed rows, live output, 3 seeded fuzz rounds |
| `replay-test` | `*replay-git-version*` locked; `git-replay-p`; the gate (bound to "99.0.0": `vc-tool-version-error`, nothing moved); on git ≥ 2.44: replay onto a new base (messages, author dates, chain, ref CAS), conflicts, non-chains, merge commits |

### Non-goals (V1)

- Per-path refinement of conflicted `.lisp` merges through `diff-backend-lisp-source` (git provides the tree level; a follow-up)
- Committing conflicts (that is jj's `:conflicted-revisions`); octopus merges; `merge-tree` strategy options
- `with-target-transaction` on the working copy (`target-transactional-p` stays NIL); multi-head plans (R2)
- Lazy virtual mounts of projections (R4f); copy/clone areas over projections are `cl-stack-pathlib` R4a/R4c on the materialized view, not backend code
- Replaying merge commits; interactive rebase; `rebase-diff` through `replay` (diff values stay with diff-protocol)
- Network, signing, GC, `update-ref --stdin` transactions (as in V0); jj (V2); composite-revision parts (V3)

---

## Implementation tasks

- [x] V0 contract: this brief, `egao1980/revision-backend-git` skeleton, Rove suite, CI git-version probe
- [x] process-protocol / process-backend-uiop fixes above, published
- [x] V0 implementation through team-solve (0.1.0; 0.2.0 on revision-protocol 0.3.0)
- [x] V1 contract: the section above, branch `agent/git-v1-contract-2532` (tests + `%not-implemented` stubs, 0.3.0)
- [ ] V1 implementation through team-solve
- [ ] ci-base git upgrade ([cl-repository#101](https://github.com/egao1980/cl-repository/issues/101)) → raise `*minimum-git-version*` to ≥ 2.44, drop the replay gate

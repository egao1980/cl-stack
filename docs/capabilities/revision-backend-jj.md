# revision-backend-jj (V2) — revision-protocol over the jj CLI

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track V · protocol brief [revision.md](revision.md) · diffs [diff.md](diff.md) · sibling [revision-backend-git.md](revision-backend-git.md)
**Status:** milestone **V2 locked** (contract). Repo [`egao1980/revision-backend-jj`](https://github.com/egao1980/revision-backend-jj) (`stack-rev-jj`), version 0.1.0: exports, conditions, classes, templates, documented behaviour, stub methods and the Rove suite that specifies them. Implementation runs through **team-solve**.

A `revision-store` and a `revision-target` over one jj repository (seen from one workspace), driven through the `jj` program only (no jj-lib). V2 = the surface of git V0: graph, refs, drift, diffs (summary and content), a read-only revision filesystem, plus what jj adds — the working copy is a commit, conflicts can be committed, change ids survive rewrites, the operation log is the recorded-time axis.

---

## Decisions (V2)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Package** | `revision-backend-jj`, nickname `stack-rev-jj`; local nicknames `rev` `diff` `dt` `proc` `pathlib` `json` | Stack naming |
| **Dependencies** | `revision-protocol` 0.2.0, `diff-protocol` 0.2.0 (tree engine, `parse-diff :unified` — it parses `jj diff --git`, hunk headers with section text included), `datetime-protocol` 0.1.3, `process-protocol` 0.2.0 + `process-backend-uiop` 0.1.0, `cl-stack-pathlib` 0.4.0, `encoding-protocol` 0.2.0, `json-protocol` 0.2.1 + `json-backend-jzon` 0.2.0, `bordeaux-threads` 0.9.4 | Own stack first; machine output is JSON lines |
| **Store** | `(make-jj-store path &key jj env permit-force)` → `jj-store`. PATH: the workspace root or any directory below it; outside a jj workspace (a plain git repo included) or missing → `jj-command-error`. Readers `jj-store-path` (workspace root), `jj-store-repo-path` (the `.jj/repo/` jj resolves; a secondary workspace shares its main one's), `jj-store-workspace` (`"default"` …), `jj-store-colocated-p`, `jj-store-env` (copy) | One store per workspace (`@` is per workspace) |
| **Version** | `*minimum-jj-version*` = **"0.47.1"**. `make-jj-store` probes `jj --version` (cached per program) and compares on every call: older → `vc-tool-version-error` (tool "jj", found "0.46.0", required); a program that cannot start → found NIL. `parse-jj-version` reads `jj 0.47.1`, the release binaries' `jj 0.47.1-d16ee1fc…`, `0.48.0-dev` | Plan: minimum = latest stable when V2 starts, pinned in CI, no fallbacks |
| **Locked minimum** | Latest stable on 2026-11-19 = **0.47.1** (2026-11-05; local Homebrew 0.47.1). CI installs the official release binaries of [jj-vcs/jj](https://github.com/jj-vcs/jj/releases/tag/v0.47.1) at exactly that version on every runner (musl Linux in the ci-base container, aarch64 macOS, x86_64 Windows), SHA-256-checked; the first CI run printed `jj 0.47.1-d16ee1fc88a72c54142241b079a34bbf3b033bc0` on all three | "What CI installs"; one pin, bumped by PR |
| **Fixed options** | Before the caller's arguments: `--no-pager --color=never --quiet --config ui.conflict-marker-style=diff --config ui.diff-formatter=:git --config ui.log-word-wrap=false --config working-copy.eol-conversion=none`; `-R` the workspace root. Environment added to the inherited one, winning over `:env`: `NO_COLOR=1`, `JJ_EDITOR=jj-editor-disabled` (a missing program: anything that would open an editor fails at once; the backend always passes `-m`) | Output and stored bytes do not depend on the user's config (checked: `jj config get` through `run-jj` under a hostile user config) |
| **Reads vs writes** | Repository reads: `--ignore-working-copy` (never snapshot, never touch the disk). Ref writes: `--at-op OP` (the operation the CAS check read; implies no snapshot). Working-copy operations snapshot first (`jj util snapshot`). `commit-revision`'s `jj workspace add` snapshots the store's working copy (jj refuses it with `--ignore-working-copy`) but moves nothing. Never `--ignore-immutable` | Plan: "reads use `--ignore-working-copy`; writes don't" |
| **`:env`** | Alist added to every command (HOME, JJ_CONFIG, JJ_TIMESTAMP, JJ_OP_TIMESTAMP …). Note jj's own precedence: `JJ_USER` / `JJ_EMAIL` sit *below* the user config file | Tests isolate the user's config |
| **`run-jj`** | `(run-jj store args &key input (output :string) (ok-exit-codes '(0)) (ignore-working-copy t) at-operation)` → `(values stdout exit-code stderr)`; `:octets` exact bytes; other exits → `jj-command-error` | Escape hatch, and the backend's own plumbing |
| **Templates** | Every parsed command runs an exported `-T` template printing one JSON object per line: `*commit-template*`, `*operation-template*`, `*ref-template*` (local, present refs only), `*file-template*`, `*diff-template*`; parsers `parse-commit-records`, `parse-operation-records`, `parse-ref-records`, `parse-file-records`, `parse-diff-records` → plists (keys in the docstrings). Malformed → `revision-error`, never another condition. Templates were run against 0.47.1 and are re-run in the suite | Plan: "machine output through `-T` templates (JSON where the installed version has it)" — 0.47 has `json()` |
| **Revision ids** | Revisions = visible commits except the root commit. **`revision-id` = full change id** (32 letters k–z); for a **divergent** change each visible commit's id is its **commit id** (unique, resolvable). `revision-content` = commit id; provenance `(:commit-id :author-name :author-email :committer-name :committer-email :conflict :empty)` — commit facts only. `recorded-at` = committer timestamp, `valid-at` = author timestamp (jj keeps author time over rewrites). `revision-parent-ids` without the root commit; message without one final newline | Plan: "change id as the revision id; commit id in provenance" |
| **Rewrites vs immutability** | A change id names the change's *current* commit: a mutable change rewritten by jj (describe, squash, rebase, a snapshot of `@`) resolves to the same id with a new `:commit-id`, message or state. Fixed for ever: a `revision` value; a **commit-id designator** and a **`revision` object as designator** (both name that exact commit, visible or hidden); the change id of an **immutable** revision (`::immutable_heads()`: trunk(), tags, untracked remote bookmarks — jj refuses to rewrite them, and the backend never passes `--ignore-immutable`). The backend rewrites only `@`. `tag-revision` makes its target immutable. Law 1 is tested on those three forms | "Revisions never change" holds where jj guarantees it; mutable change ids are jj's feature |
| **The root commit** | `zzzz…` / `000…` is no revision: designators naming it (`root()` too) → `revision-not-found`; no parent, head or walk entry; a change on `root()` has no parents | Protocol roots have no parent |
| **String designators** | In order: full change id (divergent → `ambiguous-revision` with the commit ids); full commit id (hidden ok); prefix ≥ 4 of change ids (k–z) or commit ids (hex) of visible commits — several → `ambiguous-revision` with every full id (jj only says "ambiguous", so candidates come from listing ids); a **jj revset** evaluated at the current op: one commit → it, several → `ambiguous-revision`, none / root only / rejected → `revision-not-found` | Mirrors git's "revspecs accepted" |
| **Refs** | `:movable` = local bookmarks, `:tag` = local tags; remote refs (`main@git` in colocated repos) are not refs. `ref-target` = revision id (bookmarks follow rewrites). `ref-annotation` NIL (jj tags carry no message). Same name as bookmark and tag: `rev-ref` / `find-ref` pick the tag (jj's own symbol order); `list-refs` lists both, bookmark first | One namespace over two |
| **Conflicted bookmarks** | Concurrent operations can leave a bookmark with several targets. It is not a `revision-ref`: `list-refs` omits it, `conflicted-bookmarks` → `(("main" id1 id2))`, `find-ref` signals `ref-conflict` (ACTUAL = sorted target ids; `use-current` → NIL), `rev-ref` → `ambiguous-revision`. An unconditional `move-ref` (or `force`) resolves it | jj's divergence made visible as the protocol's conflict |
| **CAS (`:ref-cas` NIL)** | `move-ref`, `delete-ref`, `commit-revision :ref`, `tag-revision`: take the store lock, read the current op OP and the ref at OP, compare EXPECTED by **revision id** (a rewrite of the expected change still matches), write with `jj --at-op OP bookmark set NAME -r COMMIT --allow-backwards` / `bookmark delete` / `tag set`, re-read; unless the ref now names exactly the new target → `ref-conflict` (ACTUAL: id, NIL, or the conflicted list). Linearizable within the image (lock); across processes jj reconciles concurrent ops and the re-read detects divergence; jj's reconciled state is kept (in the op log), a concurrent forward move that reconciles to the new target is not detected. Restarts: `use-current`, `retry` (only when ACTUAL is one id or NIL), `force` (gated by `:permit-force`) | Plan: "CAS emulated by checking the operation id, divergence surfaces as `ref-conflict`" |
| **Tags** | `jj tag set` without `--allow-move`: same target → idempotent (no operation written); other target → `tag-immutable` (`create-new-tag`); over a bookmark → `ref-conflict` (expected NIL); `:annotation` → `revision-error`. `move-ref` / `delete-ref` / `commit-revision :ref` on a tag → `tag-immutable` | Protocol R0a rules |
| **Listener** | `(:ref-moved name old new)` with revision ids, for changes made through this store | jj has no notification channel |
| **commit-revision** | CONTENT: tree value · string designator (that revision's state) · `diff-protocol:diff` (applied to the first parent's state) · `revision-payload` · else `revision-error`; `:gitlink` files and (on Windows) symlinks → `revision-error` before anything is written. Written through a **temporary workspace**: `jj workspace add --name <unique> -r P… DIR` (`-r 'root()'` for a root), write the state, `jj file chmod x`, `jj commit -m`, `jj metaedit -r @- --author … --author-timestamp …`, `jj workspace forget`, delete DIR (every exit). Committer time `(dt:now)`, author time `:valid-at` or now, whole seconds UTC (`JJ_TIMESTAMP`) → `dt:with-fixed-clock` fixes both. Provenance overrides identity. MESSAGE gets one final newline (jj's rule; "" stays empty). `:id` → `revision-error`. The new change is **visible** (a head without any ref — unlike git). Atomic: CAS checked before writing; a failing ref write abandons the new change; after any condition the visible heads and refs are unchanged and no temporary workspace remains | jj's CLI has no tree-writing plumbing; a workspace is the CLI-only way |
| **Graph** | Graph set = visible commits minus root (each workspace's `@` included; it is usually a head). Revsets: `children(X)`, `::FROM ~ ::UNTIL`, `first_ancestors(FROM)`, `heads(::A & ::B)`, `A & ::B`, `::INCLUDE ~ ::EXCLUDE`, `heads(all())`, always `~ root()`. `:topo` = `jj log --reversed` order (tests compare exactly); `:time` ascending committer time; `merge-base` ALL NIL = the first base in `jj log` order, NIL when only root is common; `:footprint` via first-parent deltas | Plan: "graph walks via revsets" |
| **as-of** | `:valid`: first parents of ON by author time (protocol rule). `:recorded`: the operation with the largest end time ≤ TIME among the current op and its ancestors; ON resolved **at that op** (`--at-op`) — the commit id it had then, even if hidden now — then first parents by committer time ≤ TIME. No such op / ON absent then → `revision-not-found`. Law 2 holds while ON moves forward | Plan: "`rev-as-of :recorded` → `--at-op <op>` from `jj op log`" |
| **Operation log** | `current-operation` (the single head after jj reconciles), `list-operations &key limit` (`jj op log` order, root included; `:start-ms` / `:end-ms`) | Recorded time and CAS need it; the harness can checkpoint by op id |
| **Content** | `:state`, `tree-diff-engine`, empty = `(diff:make-tree)`. NUL in the first 8000 bytes or invalid UTF-8 → `:binary`, else `:text` (CRLF kept); `#o100644` / `#o100755`; symlink = `:text` target, `#o120000` (jj prints nothing for it in `file show`: read it from the git diff against `root()`); git submodule = `:gitlink` commit id, `#o160000`. `revision-delta` against the first parent (a merge's too, not jj's auto-merged parents) | Same state value as git V0 |
| **Conflicts** (`:conflicted-revisions` T) | A **conflicted file** is a file (`:text`, or `:binary` by the same rule) whose content is jj's **materialized conflict** with `ui.conflict-marker-style=diff` (the fixed option, whatever the user set), mode `#o100644` — the same bytes `jj file show` and `jj diff --git` show, so states, diffs and law 3 agree. Provenance `:conflict` T; `(revision-conflicts store d)` → `(("a.txt" . 2))`. A conflicted parent's child inherits the conflict. Resolving it (e.g. `jj squash`) is a new commit of the same change; the pinned old commit keeps its conflict | Conflicts as data, readable with every pathlib / diff tool |
| **state-diff** | A / B: designators or a `jj-working-copy` (after a snapshot). `:summary` from `jj diff --from A --to B -T *diff-template*` (`renamed` → `:move`, `copied` → `:add`; lazy nodes; `"tree:/path"` footprints). `:changes` (default) = `jj diff --git` → `parse-diff :unified`. `:content` = file-level with hunk children. Binary (jj prints `Binary files … differ`, which parses to an opaque section), submodules and type changes become whole-file changes with both nodes — **never** `opaque-change` — so every diff applies and inverts (law 3) | Plan table |
| **Working copy** | `(make-jj-working-copy store)`. **@ is the target**: `target-state` = @ after a snapshot (jj's rules: .gitignore, `snapshot.auto-track`, `max-new-file-size`); **stamp = @'s parents** (`target-revisions`; NIL when @ is on root); `target-stamp` replaces @ by a new change with those parents and @'s tree / description and abandons the old @ (`jj new --no-edit`, `jj restore --from --into`, `jj edit`, `jj abandon`); several stamps allowed (@ becomes a merge). No file in the workspace is ever written: contents and mtimes byte-identical (tested). `working-copy-revision` = snapshot + @ | Plan: "the working copy is a commit" |
| **Drift** | After the snapshot: several stamps → `revision-error`; NIL iff @'s state equals the stamp's (empty when unstamped); else `state-diff` stamp → working copy at `:changes`. Drift = the working-copy commit's own changes | Plan: "drift = the working-copy commit's changes" |
| **capture-revision** | Snapshot, then: default parents → `jj commit -m MESSAGE` — the captured revision **is the old @ change** (same change id), @ a new empty change on it; other parents → a new change with those parents and @'s tree, @ moved to an empty child of it, the old @ abandoned. MESSAGE default "capture"; afterwards drift NIL, `target-revisions` = (captured id) | Plan: "capture = a snapshot of @" + the protocol's "stamped, no drift" |
| **Revision filesystem** | `make-revision-filesystem store designator` pinned to the **commit id** (rewrites and ref moves do not change what it reads); `revision-filesystem-revision` → the `revision`; `revision-path`. `jj file list -T *file-template*` + `jj file show` (exact bytes); symlinks are files with `fs-symlink-p` / `fs-read-symlink`; `fs-executable-p` = jj's bit; `fs-last-modified` = committer time; `iterdir` sorted by name; conflicted files read as materialized; writes / `fs-make-temp` / `fs-as-uri` → `unsupported-operation`; missing → `path-not-found` | Pathlib tools on any revision |
| **Conditions** | Protocol types for protocol failures. jj-specific: `vc-tool-version-error` (tool found required; same name, slots and readers as git's — moves to revision-protocol with [revision-protocol#4](https://github.com/egao1980/revision-protocol/issues/4), this package then re-exports it) and `jj-command-error` (command exit-code stderr), both `revision-error` | No backend error dialect |
| **Capabilities** | `(jj-capabilities store)` → `(:primary :state :merges t :children-index t :valid-time t :ref-cas nil :atomic-multi-ref nil :gc nil :signed nil :transactional-apply nil :projection nil :conflicted-revisions t)`; revision-protocol has query GFs for only some ([revision-protocol#5](https://github.com/egao1980/revision-protocol/issues/5)) | Plan capability names |
| **Threads** | A store may be shared; ref updates serialized by a per-store lock (CAS linearizable in the image, law 1 with 2×5 / 3×4 threads) | Emulated CAS needs it |

### Condition tree

```
revision-error                       (revision-protocol)
├── revision-not-found / ambiguous-revision / ref-conflict / tag-immutable …   (protocol, signalled by the backend)
├── vc-tool-version-error (tool found required)     make-jj-store   (→ revision-protocol, #4)
└── jj-command-error (command exit-code stderr)     run-jj and any jj failure without a protocol meaning
```

---

## Protocol surface (V2)

```lisp
;;; Store
(make-jj-store path &key jj env permit-force)       ; → jj-store
(jj-store-path s) (jj-store-repo-path s) (jj-store-workspace s) (jj-store-colocated-p s) (jj-store-env s)
*jj-program* *minimum-jj-version* (parse-jj-version string) (jj-version s)
(run-jj s args &key input output ok-exit-codes ignore-working-copy at-operation)  ; → (values stdout code stderr)
(jj-capabilities s) (current-operation s) (list-operations s &key limit)
(conflicted-bookmarks s) (revision-conflicts s designator)
;; revision-protocol GFs on jj-store: resolve-revision commit-revision move-ref tag-revision
;; delete-ref find-ref list-refs revision-parents revision-children walk-revisions merge-base
;; ancestor-p revision-range heads ref-listener permit-force-p content-primary content-engine
;; revision-state revision-delta state-diff (delta-inverse / delta-footprint from the protocol)

;;; Working copy
(make-jj-working-copy store)                         ; → jj-working-copy
(working-copy-store wc) (working-copy-path wc) (working-copy-revision wc)
;; target-revisions target-stamp target-state target-drift capture-revision
;; target-fidelities target-transactional-p

;;; Revision filesystem
(make-revision-filesystem store designator) (revision-path store designator &optional path)
(revision-filesystem-store fs) (revision-filesystem-revision fs)

;;; Templates and parsers
*commit-template* *operation-template* *ref-template* *file-template* *diff-template*
(parse-commit-records s) (parse-operation-records s) (parse-ref-records s)
(parse-file-records s) (parse-diff-records s)

;;; Conditions
vc-tool-version-error (-tool -found -required)  jj-command-error (-command -exit-code -stderr)
```

---

## Contract tests (V2)

`revision-backend-jj/tests`, Rove — **180 tests** (98 deftests + 82 parametrized rows, 784 assertions); against the stubs 178 fail and 2 pass (`minimum-jj-version-is-locked`, `installed-jj-meets-the-minimum`, which only run jj directly). CI run [44586986712](https://github.com/egao1980/revision-backend-jj/actions/runs/44586986712): the suite loads and fails only on stub errors on ubuntu, macos and windows (windows skips the symlink commit test). Each test builds a throwaway repository with the **real jj** (`jj git init`, colocated unless stated) in a fresh temp directory: own `HOME`, `JJ_CONFIG` file with user.name / user.email, inherited `JJ_*` dropped, `JJ_EDITOR` a missing program; every fixture command fixes `JJ_TIMESTAMP` (commit times) and `JJ_OP_TIMESTAMP` (operation times), so both time axes are known. Expected values come from running jj in the test (`jj log -T`, `--at-op`, `op log`, `bookmark list`, `file list` / `show`, `diff -T`) or from the fixture's content; jj runs through UIOP with output redirected to files (byte-exact), independent of the code under test.

| File | Covers |
|------|--------|
| `support`, `fixtures` | Temp repos, jj runner, histories: linear (main follows each commit, backdated author, tags), merge, criss-cross + an unrelated root, content (binary, invalid UTF-8, CRLF, empty, symlink — not on Windows, `jj file chmod`, file → directory), conflict (left / right merged unresolved), working copy with .gitignore, 1024 changes by `jj duplicate` doubling for ambiguous 4-letter prefixes |
| `version-test` | `parse-jj-version` rows, the locked minimum, installed jj ≥ minimum, `vc-tool-version-error` (bound minimum, missing program), store paths (subdir, colocated / not, secondary workspace), outside a repo, `run-jj` output / octets / exit codes / stdin, fixed options win over a hostile user config, `:env` reaches jj, `--ignore-working-copy` / `--at-op`, capabilities, operation log |
| `parse-test` | Hand corpora (escapes, CR LF, blank lines, conflicted refs), every enum row, live output of all five templates, malformed rows, 5 seeded fuzz rounds × 5 parsers (only `revision-error` ever) |
| `resolve-test` | Fields vs `jj log`, merge parent order, every designator form, not-found rows (root commit included), ambiguous revsets and prefixes, tag-first refs, **rewrites keep the change id while commit ids / objects pin**, immutable changes refuse rewrites, divergent changes |
| `ref-test` | `find-ref` / `list-refs`, bookmark + tag sharing a name, remote bookmarks excluded, `move-ref` and CAS (external jj move, change-id match across a rewrite), restarts, gated `force`, tags never move, `tag-revision` rules, `delete-ref`, listener, **conflicted bookmarks** (made by two `--at-op` writes) and `force` resolving one |
| `commit-test` | Tree values (exact tree, binary, CRLF, empty, +x), symlinks, the store's workspace untouched, temp workspace forgotten, parents / refs / merges / root, diffs and payloads, identity and times under `dt:with-fixed-clock`, messages, refusals leave heads and refs unchanged, non-colocated repos |
| `graph-test` | Parents / children / heads vs revsets, walk orders vs `jj log --reversed`, `:time`, `:first-parent`, footprints, merge bases (criss-cross, unrelated), `ancestor-p`, ranges, the graph after a rewrite |
| `as-of-test` | `:recorded` rows vs `jj op log` + `--at-op` (before / after a rewrite: the old commit id), not-found rows, designator ON; `:valid` rows |
| `content-test` | `revision-state` of every file kind (bytes = `jj file show`), reads do not snapshot, deltas (root, merge), `:summary` vs `jj diff -T`, `:changes` / `:content` shapes (hunks, whole-file binary), law 3 rows, footprints, a rewritten change against its pinned snapshot |
| `conflict-test` | Provenance and `revision-conflicts`, the materialized file under a user's different marker style, diffs into a conflicted state at every level, resolution as a new commit of the change |
| `working-copy-test` | Values, stamp = @'s parents (root, merge), `target-state` snapshots (ignored / removed files), `working-copy-revision`, drift rules, unstamped drift, several stamps → error, `target-stamp` keeps files and tree, capture with default parents (= old @ change) and other parents, capture in a fresh repo; every disk-observing call leaves files byte-identical |
| `filesystem-test` | Reads at several revisions (pinned across a bookmark move and a rewrite), listing / predicates / symlinks / modes / sizes / mtime / walk / glob, stat and hashes, read-only and missing paths, conflicted files, `revision-path` |
| `law-test` | **Law 1** (immutable change ids, commit ids and objects never change; lists not shared; CAS linearizable with 2×5 and 3×4 threads, main never conflicted), **law 2** (as-of monotonic rows, both axes), **law 3** (delta composition associative) |

A throwaway prototype (scratchpad, never committed) was run against the suite before sealing; it found the contract's own bugs (operation times printed as `0000` for the root op are no JSON number → times are strings; `jj workspace add` refuses `--ignore-working-copy`; jj reports ambiguous prefixes without candidates; `JJ_USER` sits below the config file) and after the fixes all 180 tests (784 assertions) passed on it, its `:changes` level going through `jj diff --git` → `parse-diff :unified` with binary sections replaced by whole-file changes.

---

## Prerequisites (stack fixes before team-solve)

The backend must run jj through `process-protocol`; `process-backend-uiop` 0.1.0 cannot yet do what jj needs (binary `jj file show`, an environment that extends the inherited one, bounded waits). Design against the fixed semantics — env merges by default, octet capture, timeouts. Fix in the stack, publish, bump the pins:

- [process-backend-uiop#8](https://github.com/egao1980/process-backend-uiop/issues/8) — `backend-run` decodes output as text: binary or non-UTF-8 output errors.
- [process-backend-uiop#9](https://github.com/egao1980/process-backend-uiop/issues/9) / [process-protocol#7](https://github.com/egao1980/process-protocol/issues/7) — `:env` replaces the whole environment on SBCL; semantics undefined.
- [process-backend-uiop#10](https://github.com/egao1980/process-backend-uiop/issues/10) — no octet streams; `:timeout` ignored.
- [revision-protocol#4](https://github.com/egao1980/revision-protocol/issues/4) — host `vc-tool-version-error` (then import + re-export it here and in revision-backend-git).

Related: [revision-protocol#5](https://github.com/egao1980/revision-protocol/issues/5) (query GFs for `:ref-cas` / `:conflicted-revisions`).

---

## Non-goals (V2)

- Projections, `project-merge` (`jj new --no-edit A B`, read, abandon), `commit-projection`, `plan-transition` / `execute-plan` (`jj edit`, `jj new`, `jj rebase -r … -d …`), `(setf target-state)` — the git V1 surface, for jj after it
- Network (`jj git fetch` / `push`), remote bookmarks as refs, signing, GC, multi-ref atomic updates
- A native jj backend (jj-lib); jj versions older than the pin

---

## Implementation tasks

- [x] V2 contract: this brief, `egao1980/revision-backend-jj` skeleton, Rove suite, CI with pinned jj on ubuntu / macos / windows
- [ ] process-protocol / process-backend-uiop fixes above, published; revision-protocol#4
- [ ] V2 implementation through team-solve
- [ ] Projections / plans for jj (after git V1)

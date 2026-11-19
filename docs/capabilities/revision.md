# revision-protocol (P1) — revision DAG, refs, tags, as-of

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track R · MBT [#283](https://github.com/egao1980/cl-stack/issues/283)
**Status:** brief **draft**; milestone **R0a (graph layer) locked**. Repo [`egao1980/revision-protocol`](https://github.com/egao1980/revision-protocol) (`stack-rev`) holds the R0a contract: package, conditions, GFs, designator values, an `in-memory-store` class with stub methods, and the Rove suite that specifies it. Implementation runs through **team-solve**.

A CLOS protocol for versioned things that are not only files. A store holds an immutable revision DAG with movable refs and immutable tags. Designators name revisions by id, ref, tag, time (on a recorded or a valid axis) and graph position. Backends: an in-memory store (in repo), git and jj over their CLIs (`revision-backend-git`, `revision-backend-jj`), `sql-migrate` script directories, agent sessions, Lisp images.

It replaces the ad-hoc version models already in the stack: `steer-protocol`'s `skill-version` / `skill-versions` / `rollback-skill` (`src/store.lisp`) and `sql-migrate`'s `script-directory` / `head-revision` / `history` (`src/directory.lisp`). They move onto it in R5 / S2 as thin wrappers, with their own tests unchanged.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| git | Commit DAG, refs vs tags, `update-ref <new> <old>` CAS, `^n` / `~n`, `merge-base [--all]`, `rev-list A ^B`, `--topo-order` / `--date-order` / `--first-parent`, `rev-list --before` as-of | Revspec mini-language as the core designator (a git backend may accept it), packs, index |
| jj | Change ids stable across rewrites, operation log as the recorded-time axis, committed conflicts | Working copy as a commit (a backend concern) |
| Alembic / `sql-migrate` | Branch + merge revisions, heads, "down to merge-base, up to target" plans | Revision ids as file names |
| Bitemporal databases (XTDB, SQL:2011) | Two axes: recorded (transaction) time and valid time | Full bitemporal queries over content |

---

## Layers (overview — R0b and later)

| Layer | What | Milestone |
|-------|------|-----------|
| **Graph** | Revisions, parents, refs, tags, CAS, designators, walks, merge-base, ranges, heads, ref listener | **R0a (this contract)** |
| **Content** | A revision carries a state, a delta, or both; backends declare `:primary :state \| :delta` and derive the other: `revision-state`, `revision-delta`, `delta-inverse`, `delta-footprint`, `state-diff` (diffs are [`diff-protocol`](https://github.com/egao1980/diff-protocol) values) | R0b |
| **Target** | Where a revision is realized (working copy, DB connection, run, image): `target-revisions`, `target-stamp`, `target-drift`, `capture-revision`, `plan-transition` → plan value, `describe-plan`, `execute-plan` (stamps per step, resumable), `verify-revision`, `with-target-transaction` | R0b |
| **Projection** | State at a revision / after a plan / after a merge without touching the target: `project-state`, `project-plan`, `project-merge`, `projection-fidelity` (`:exact :model :shadow`), `projection-view` (the domain's normal read API: pathlib filesystem, `sql-orm` schema, read-only connection, REPL connection), `commit-projection`, `discard-projection` | R0b |
| **Composite revisions** | Content is a manifest of revisions in other stores (`:conversation :files :db :image`); restore plans one transition per part in dependency order; `skip-part` / `rebuild-from-recipe` | R0b / H5 |

R0b adds the rest of the condition tree: `merge-conflict` (`take-ours`, `take-theirs`, `use-merged`, `abort`), `irreversible-step` (`skip-step`, `stamp-only`, `abort-transition`), `target-drift-detected` (`capture-and-continue`, `discard-drift`, `abort`), `step-failed` (`retry-step`, `skip-step`, `rollback-to-start`), `projection-unsupported` (`use-shadow`, `accept-model-fidelity`, `apply-for-real`), `projection-stale`; and the `force` restart on `ref-conflict`, permission-gated.

**Capabilities** (R0b) are declared through [`capability-protocol`](capability.md), not a flag object: `:merges`, `:children-index`, `:valid-time`, `:atomic-multi-ref`, `:ref-cas`, `:gc`, `:signed`, `:transactional-apply`, `:projection` (fidelity list), `:primary`, `:conflicted-revisions` (jj). R0a does **not** depend on `capability-protocol`: it is colocated with `blackboard-protocol` (KSAR runtime) and is not a light dependency for a graph library. R0b either adds a `revision-protocol/capabilities` secondary system or waits for `capability-protocol` to split out of `blackboard-protocol`.

**Laws** (property tests every backend runs; later the `defspec` invariants, Quint-checked, ITF replay on the in-memory store):

1. The graph is acyclic; revisions never change; tags never move; ref CAS is linearizable. **(R0a)**
2. `as-of` is monotonic along its line. **(R0a)**
3. `apply-diff(state(a), diff(a, b)) = state(b)`; inverses round-trip; `diff(a, a)` is empty; `compose-diffs` is associative. (R0b)
4. `three-way-diff` is symmetric in ours/theirs. (R1)
5. After `execute-plan` without error, `target-revisions` = plan goal; each stamp names the revision reached. (R0b)
6. `:exact` projection equals execution; `:model` equal on the modelled part. (R0b)

---

## R0a — locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Package** | `revision-protocol`, nickname `stack-rev`; local nickname `dt` → `datetime-protocol` | Stack naming |
| **Dependencies** | `datetime-protocol` 0.1.3, `bordeaux-threads` 0.9.4 (bt2). No `diff-protocol`, no `capability-protocol`, no pathlib, git or SQL | Graph only; diffs arrive with content in R0b |
| **Revision** | Immutable CLOS object, readers only: `revision-id`, `revision-parent-ids` (fresh list, first parent first; two or more = merge), `revision-recorded-at`, `revision-valid-at` (or NIL), `revision-provenance` (fresh plist), `revision-message`, `revision-content` (opaque handle, stored as given) | Law 1; callers can't alias store state |
| **Ids** | Strings chosen by the store. In-memory default: 40 lowercase hex characters, unique in the store. `commit-revision :id` lets the caller choose (imports, migration scripts, tests) | git / jj / Alembic ids all fit a string |
| **Bare strings** | A string designator is an **id**, never a ref name: exact match first, then a unique prefix of at least `+minimum-id-prefix+` (4) characters. Several matches → `ambiguous-revision` with the candidate ids; none, or a shorter non-exact string → `revision-not-found` | No ref/id ambiguity in the core; a git backend may also accept revspecs |
| **Recorded time** | `recorded-at` = `(dt:now)` at commit, so `dt:*clock*` / `dt:with-fixed-clock` controls it | Deterministic tests; one clock protocol |
| **Valid time** | Optional `commit-revision :valid-at` instant. `(revision-time rev :valid)` falls back to `recorded-at` when absent | A revision without a claim is valid from when it was recorded |
| **Refs** | One namespace. Kinds `:movable` (branches, `head`, `current`, `candidate`) and `:tag`. `revision-ref` values are snapshots: `ref-name`, `ref-kind`, `ref-target` (id), `ref-annotation` | git-like; a snapshot never changes |
| **CAS** | `:expected` omitted → unconditional; `:expected nil` → ref must be absent; otherwise the ref must point at that designator. Failure → `ref-conflict` (name, expected id, actual id) with restarts `use-current` and `retry` | Linearizable compare-and-swap |
| **commit-revision** | `(commit-revision store content &key parents ref expected message provenance valid-at id)`. `:parents` omitted + existing `:ref` → parent is the ref tip; otherwise a root; explicit `:parents nil` is a root. `:expected` omitted with `:ref` → the tip read at the start. Atomic: any condition → nothing stored, no ref moved | Commit-on-branch is one CAS |
| **Restarts** | `use-current`: `move-ref` returns the current ref unchanged (NIL if absent); `commit-revision` returns the current tip, commits nothing; `delete-ref` returns NIL, ref kept. `retry`: redo with `:expected` = current (and re-read defaulted parents) | Established at the operation (CLHS 9 / ASDF `retry` convention) |
| **Tags** | `tag-revision` creates; same target + annotation is a no-op returning the tag; anything else on an existing tag → `tag-immutable` with restart `create-new-tag` (new name). `move-ref` / `commit-revision :ref` on a tag → `tag-immutable` (`move-ref` offers `create-new-tag`). `delete-ref` on a tag → `tag-immutable`. `tag-revision` over a movable ref → `ref-conflict` | Tags never move or disappear (GC is a later capability) |
| **Cycles** | Fresh ids cannot cycle. A caller `:id` that is an ancestor-or-self of a parent → `cycle-refused`; any other existing `:id` → `revision-error` (revisions never change) | Law 1 for caller-chosen ids |
| **Designators** | Values: `rev-ref`, `rev-tag`, `rev-as-of`, `rev-parent`, `rev-ancestor` (classes `ref-designator`, `tag-designator`, `as-of-designator`, `parent-designator`, `ancestor-designator`; readers `designator-name/-time/-on/-axis/-base/-n`), plus string ids and `revision` objects. Constructors check types (`type-error`) | Composable, printable, backend-dispatchable |
| **rev-ref / rev-tag** | `rev-ref` matches any ref kind; `rev-tag` only tags | `main` vs `v1.0` |
| **rev-as-of** | `(rev-as-of instant &key on (axis :recorded))`; `on` required; a string `on` is a ref name. Walk first parents from `on`, newest first; the first revision whose time on `axis` is ≤ instant. None → `revision-not-found` | git `rev-list -1 --first-parent --before`; monotonic by construction (law 2) |
| **rev-parent / rev-ancestor** | `(rev-parent d &optional (n 1))` = nth parent, 1-based (git `^n`); `(rev-ancestor d n)` = nth first-parent ancestor, `n = 0` is `d` (git `~n`). Out of range → `revision-not-found` | |
| **Walks** | `(walk-revisions store from &key (order :topo) until reverse)`; `from` / `until` are designators or lists. All orders list **parents before children**; `:time` = ascending `recorded-at`, still parents-first under clock skew; `:first-parent` = the first-parent chain, root first. `until` excludes itself and its ancestors. `:reverse t` = children first (git log). Each revision once | Replay / migration order by default |
| **Queries** | `revision-parents` (ordered), `revision-children` (any order), `heads` (every childless revision), `ancestor-p a b` (reflexive), `revision-range include exclude` (topo order; `exclude` may be NIL), `merge-base a b &key all` (best common ancestors; one deterministic revision or NIL; `:all t` → list) | git semantics |
| **Listener** | `(setf (ref-listener store) fn)`; `fn` gets `(:ref-moved name old-id new-id)` after each successful ref change — creation (tags too) has `old-id` NIL, deletion `new-id` NIL. Failed or abandoned (`use-current`) updates are silent. Called outside the store lock | UI / journaling hook |
| **In-memory store** | `make-in-memory-store`; thread-safe with one bt2 lock; CAS linearizable | Reference backend, law suite, later ITF replay |

### Condition tree (R0a)

```
revision-error (message)
├── revision-not-found (designator)
├── ambiguous-revision (designator candidates)
├── ref-conflict (name expected actual)      restarts: use-current, retry
├── tag-immutable (name target)              restart:  create-new-tag (new-name)
└── cycle-refused (id parents)
```

Restart names are exported symbols (`stack-rev:use-current`, `stack-rev:retry`, `stack-rev:create-new-tag`); handlers call `invoke-restart` from `handler-bind`.

---

## Protocol surface (R0a)

```lisp
;;; Values
(defclass revision () …)          ; readers above; no writers
(defclass revision-ref () …)      ; ref-name ref-kind ref-target ref-annotation
(revision-time revision axis)     ; :recorded | :valid (falls back to recorded)
(rev-ref name) (rev-tag name)
(rev-as-of instant :on "main" :axis :recorded)   ; or :valid
(rev-parent d 2) (rev-ancestor d 3)

;;; Store
(defclass revision-store () ())
(defgeneric resolve-revision (store designator))                 ; → revision
(defgeneric commit-revision (store content &key parents ref expected
                                                 message provenance valid-at id))
(defgeneric move-ref (store name designator &key expected))      ; → revision-ref
(defgeneric tag-revision (store name designator &key annotation)); → revision-ref
(defgeneric delete-ref (store name &key expected))               ; → T
(defgeneric find-ref (store name))                               ; → revision-ref | NIL
(defgeneric list-refs (store &key kind prefix))                  ; sorted by name
(defgeneric revision-parents (store designator))
(defgeneric revision-children (store designator))
(defgeneric walk-revisions (store from &key order until reverse))
(defgeneric merge-base (store a b &key all))
(defgeneric ancestor-p (store a b))
(defgeneric revision-range (store include exclude))
(defgeneric heads (store))
(defgeneric ref-listener (store))  (defgeneric (setf ref-listener) (fn store))

(make-in-memory-store)
```

R0b extends `walk-revisions` with `:footprint` and accepts time phrases through `dt:parse-time-range`; the R0a lambda lists stay valid.

---

## Contract tests (R0a)

`revision-protocol/tests` (Rove, `deftest-parametrize` from `egao1980/rove`), all against the in-memory store — 78 tests including parametrized rows:

| File | Covers |
|------|--------|
| `graph-test` | commit + resolve by id / ref / tag, default id format, caller ids, valid time, parents and merges, children, atomic failure on a missing parent, short id prefixes (`ambiguous-revision`, minimum length), heads |
| `walk-test` | `:topo` parents-first on criss-cross and merge graphs, `:reverse`, `:first-parent`, `:time` incl. clock skew, `:until`; `merge-base` simple fork / ancestor / criss-cross (`:all`) / unrelated; `ancestor-p`; `revision-range` |
| `as-of-test` | both axes as parametrized tables (backdated valid times, side branches skipped, valid falling back to recorded), `:on` tags / revisions, not-found; **law 2** monotonicity rows |
| `designator-test` | designator values and type checks, `rev-parent n` on merges, `rev-ancestor n` of a ref, composition |
| `ref-test` | create / move / snapshots / `list-refs` filters; CAS with stale `:expected` → `ref-conflict` slots; `use-current` and `retry` via `handler-bind` for `move-ref`, `commit-revision`, `delete-ref`; tags never move; `create-new-tag` from `tag-revision` and `move-ref`; `cycle-refused`; duplicate ids; listener event sequence |
| `law-test` | **law 1**: revisions unchanged after later commits and ref moves, returned lists not shared, no writers; CAS linearizable under 2 × 50 and 8 × 25 concurrent committers with `retry` |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| [`revision-protocol`](https://github.com/egao1980/revision-protocol) (`stack-rev`) | Protocol, conditions, designators, in-memory store, law suite; later the `defspec` model |
| `diff-protocol` (`stack-diff`) | Diffs as values; `revision-protocol` depends on it from R0b |
| `revision-backend-git`, `revision-backend-jj` | CLI backends (Track V) |

---

## Non-goals (R0a)

- Content, targets, plans, projections, composite revisions (R0b)
- Capability declarations (R0b, see above)
- `defspec` model, Quint checks, ITF replay (R0 after R0b)
- Persistence of the in-memory store, GC, signed revisions, multi-ref atomic updates

---

## Implementation tasks

- [x] R0a contract: brief, `egao1980/revision-protocol` skeleton, Rove suite
- [ ] R0a implementation through team-solve (`.team-solve/task.md` in the repo)
- [ ] R0b: content / target / plan / projection on `diff-protocol`, capabilities, rest of the condition tree
- [ ] `defspec` model → Quint, ITF replay against the in-memory store
- [ ] Cookbook `cookbooks/revision.md`

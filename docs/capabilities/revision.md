# revision-protocol (P1) — revision DAG, refs, tags, as-of

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track R · MBT [#283](https://github.com/egao1980/cl-stack/issues/283)
**Status:** brief **draft**; milestone **R0a (graph layer)** locked and implemented (0.1.0); milestone **R0b (content, targets, plans, projections, composite revisions) locked** — see [R0b — locked](#r0b--locked). Repo [`egao1980/revision-protocol`](https://github.com/egao1980/revision-protocol) (`stack-rev`). Implementation runs through **team-solve**.

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

**Capabilities** (R0b) are declared through [`capability-protocol`](capability.md), not a flag object: `:merges`, `:children-index`, `:valid-time`, `:atomic-multi-ref`, `:ref-cas`, `:gc`, `:signed`, `:transactional-apply`, `:projection` (fidelity list), `:primary`, `:conflicted-revisions` (jj). R0a does **not** depend on `capability-protocol`: it is colocated with `blackboard-protocol` (KSAR runtime) and is not a light dependency for a graph library. R0b keeps it that way: each capability is a query GF (`content-primary`, `target-fidelities`, `target-transactional-p`, `permit-force-p`); a `capability-protocol` adapter maps them once that protocol splits out of `blackboard-protocol`.

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

## R0b — locked

Contract on branch `agent/revision-r0b-7b30` of [`egao1980/revision-protocol`](https://github.com/egao1980/revision-protocol): exports, conditions, classes, GFs with docstrings, stub methods on `in-memory-store` and a new `in-memory-target`, and the Rove suites that specify them. Version 0.2.0. Implementation runs through **team-solve**.

### Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Dependencies** | Adds `diff-protocol` 0.1.0 (local nickname `diff`). Still no `capability-protocol`, pathlib, git or SQL | Diffs are the content values |
| **R0a behaviour** | Unchanged, including the two choices in [revision-protocol#2](https://github.com/egao1980/revision-protocol/issues/2): `:expected` without `:ref` is ignored; re-tagging with another annotation signals `tag-immutable`. R0b adds keys and a restart, changes no R0a lambda list except the new `walk-revisions :footprint` key | The 78 R0a tests are the regression suite |
| **Content classification** | `commit-revision`'s CONTENT: a `diff-protocol:diff` = delta against the first parent's state (a root: against NIL, the empty state); a `revision-payload` (`make-payload :state :delta`) = either or both; anything else = a state. `revision-content` still returns CONTENT as given | One commit GF for state, delta and opaque-migration stores |
| **Primary** | `(content-primary store)` → `:state` \| `:delta`; in-memory `(make-in-memory-store :primary :delta)`. The other form is derived: `revision-state` folds deltas along first parents from NIL; `revision-delta` diffs the first parent's state (merges: first parent). A stored or payload delta is returned as stored (`eq`); a payload state wins over its delta | The plan's `:primary` capability |
| **Engine** | `(content-engine store)`; in-memory `:engine`, default `sexp-diff-engine`. All state equality is the engine's `state-equal` | |
| **delta-inverse / delta-footprint** | `delta-inverse` → diff or NIL (no inverse, e.g. an `opaque-change`); never signals `irreversible-change`. `delta-footprint` = `diff-footprint`; NIL for NIL | Plans ask "reversible?" as data |
| **state-diff** | `(state-diff store a b &key footprint level)`; A / B are revision designators, targets (`target-state`), plans (state of the goal) or projections (`projection-state`). `level` default `:changes`. `:footprint` keeps the top-level changes overlapping one of the strings (`footprint-overlap-p`) | Same resource strings as diffs and permissions |
| **walk :footprint** | `walk-revisions … :footprint list` keeps revisions whose `revision-delta` footprint overlaps; order unchanged | "Which revisions touched `table:widgets`?" |
| **Capabilities** | No `capability-protocol` dependency yet. Each capability R0b needs is a query GF: `content-primary` (`:primary`), `target-fidelities` (`:projection`), `target-transactional-p` (`:transactional-apply`), `permit-force-p` (the `force` gate). A `capability-protocol` adapter maps them once that protocol splits out of `blackboard-protocol` | Keeps the graph library light; plan wording still holds through the adapter |
| **force** | Restart `force` on `ref-conflict` in `move-ref`, `commit-revision`, `delete-ref`, established only when `(permit-force-p store name)` (default NIL; in-memory `:permit-force` NIL / T / predicate of the ref name). Redoes the operation with `:expected` omitted | "Permission-gated": absent restart, not a refusal at invoke time |
| **Targets** | `revision-target`; stamps are revision **ids** (targets know no store). `target-stamp target revs` (revisions or ids, deduped, in order; NIL clears), `target-state` / `(setf target-state)` (an out-of-band write = drift), `target-drift target store` (diff stamped → actual, NIL when equal; unstamped compares with NIL; several stamps → `revision-error`), `capture-revision` (parents default to the stamp; stamps the new revision) | |
| **Transactions** | `(with-target-transaction (target) …)` → `call-with-target-transaction`; a non-local exit restores state and stamp. A target that is not `target-transactional-p` → `revision-error`, body not run | No silent non-atomic fallback |
| **Plans** | `plan-transition store target to` → `transition-plan` value (pure): `plan-store`, `plan-start`, `plan-goal` (one id), `plan-base` (merge-base id, NIL = the empty state for fresh targets and unrelated lines), `plan-steps`. `:down` steps to the base, then `:up` steps to TO, one parent edge each; at a merge the path takes the first parent that is or reaches the base. `plan-step`: `step-direction`, `step-from`, `step-to` (id or NIL), `step-diff` (= `state-diff` of from/to), `step-footprint`, `step-reversible-p` (NIL for a `:down` step undoing a revision whose delta has no inverse). Several stamped revisions → `revision-error` | Alembic "down to merge-base, up to target"; multi-head plans are R2 |
| **describe-plan** | One line per step: `<up\|down> <from\|-> -> <to\|->[ footprint…][ (irreversible)]`, newline-terminated; NIL stream → string, T → `*standard-output*`, else NIL | Dry run / approval text |
| **execute-plan** | `(execute-plan target plan)` → `(values target-revisions skipped-steps)`. Stamps `(step-to)` (or NIL) after each step. Resumes after the step whose TO matches the stamp; a stamp that is neither the start nor any TO → `revision-error`. Drift is checked before the first step | Law 5 |
| **Projections** | `projection`; `project-state` (in-memory: always `:exact`; `:writable` allows `(setf projection-state)`), `project-plan target plan &key fidelity`, `project-merge store a b` → `(values projection conflicts)` (three-way on the merge-base, conflicts as data, base value kept), `projection-fidelity`, `projection-view` (the domain read API; sexp: a fresh copy), `projection-state`, `projection-parents` (commit defaults), `projection-conflicts`, `projection-writable-p`, `projection-discarded-p`, `commit-projection store p &key parents message ref`, `discard-projection` (idempotent; later reads and commits → `revision-error`) | |
| **Fidelity** | Best first `:exact :shadow :model`; `project-plan` default = first of `target-fidelities`. In memory, `:exact` / `:shadow` apply the step diffs to a copy; `:model` is the goal revision's stored state. A target projection read or committed after the target's stamp or state changed → `projection-stale` | Law 6 |
| **Composite revisions** | `make-manifest-part role store designator &key depends-on recipe` (resolved when made; store NIL keeps an id string — a store not available in this image), `make-manifest parts` (duplicate role, unknown dependency, cycle → `revision-error`), `commit-composite store parts &key parents ref expected message` (content and `revision-state` = the manifest), `composite-manifest` (NIL for other revisions), `plan-composite store d targets` → `((role . plan-or-nil) …)` dependencies first, `restore-composite store d targets` → plist role → stamp or `:skipped`. `targets` is a plist role → target. No atomicity across stores | One transition per part |
| **In-memory target** | `make-in-memory-target &key state revisions engine transactional fidelities fail-step stamp-hook`. `fail-step (step attempt)` injects failures; `stamp-hook (target ids)` observes each stamp | Reference target for the law suite |
| **Deferred** | `verify-revision`, multi-head plans, `parse-time-range` phrases, the `capability-protocol` adapter, `defspec` / Quint / ITF | Out of R0b scope |

### Condition tree (R0b additions)

```
revision-error
├── … R0a …                       ref-conflict gains restart: force (gated)
├── merge-conflict (conflicts projection)        commit-projection:  take-ours, take-theirs, use-merged, abort
├── irreversible-step (step)                     execute-plan:       skip-step, stamp-only, abort-transition
├── target-drift-detected (target drift)         execute-plan:       capture-and-continue, discard-drift, abort
├── step-failed (step cause attempt)             execute-plan:       retry-step, skip-step, rollback-to-start
├── projection-unsupported (fidelity supported)  project-plan:       use-shadow, accept-model-fidelity, apply-for-real (applicable only)
├── projection-stale (projection)
└── composite-part-unavailable (part reason)     restore-composite:  skip-part, rebuild-from-recipe (with recipe + target)
```

`abort` is `cl:abort`. Restart semantics:

- `capture-and-continue`: capture the drift as a child of the stamp, re-plan from it to the goal, run. `discard-drift`: reset to the stamped state, run. `abort`: return NIL, nothing changed.
- `skip-step`: no change, no stamp, step returned in the second value, continue. `stamp-only`: stamp TO without changing the state (the target now drifts). `abort-transition`: return NIL, keep the last stamp.
- `retry-step`: apply again with `attempt` + 1. `rollback-to-start`: restore state and stamp from before the call, return NIL. Unhandled `step-failed` propagates; the stamp names the last completed step, and re-running the plan resumes.
- `use-shadow` / `accept-model-fidelity`: a projection at that fidelity. `apply-for-real`: execute the plan, return an `:exact` projection of the result.
- `take-ours` / `take-theirs`: resolve every conflict to that side. `use-merged`: commit with base values at the conflicts. `abort`: commit nothing, return NIL.
- `skip-part`: result `:skipped`. `rebuild-from-recipe`: call `(recipe part target)`, stamp the part's id. Reasons `:no-store`, `:no-target`, `:not-found`.

### Protocol surface (R0b)

```lisp
;;; Content
(make-payload &key state delta)        ; revision-payload: payload-state payload-state-p payload-delta
(content-primary store) (content-engine store) (permit-force-p store name)
(revision-state store d) (revision-delta store d)
(delta-inverse delta) (delta-footprint delta)
(state-diff store a b &key footprint level)
(walk-revisions store from &key order until reverse footprint)

;;; Targets
(target-revisions target) (target-stamp target revisions)
(target-state target) (setf (target-state target) state)
(target-drift target store) (capture-revision target store &key parents message)
(target-fidelities target) (target-transactional-p target)
(with-target-transaction (target) …) (call-with-target-transaction target thunk)

;;; Plans
(plan-transition store target to)      ; transition-plan: plan-store plan-start plan-goal plan-base plan-steps
                                       ; plan-step: step-direction step-from step-to step-diff step-footprint step-reversible-p
(describe-plan plan stream) (execute-plan target plan)

;;; Projections
(project-state store d &key fidelity writable) (project-plan target plan &key fidelity)
(project-merge store a b)
(projection-fidelity p) (projection-view p) (projection-state p) (setf (projection-state p) s)
(projection-parents p) (projection-conflicts p) (projection-writable-p p) (projection-discarded-p p)
(commit-projection store p &key parents message ref) (discard-projection p)

;;; Composite revisions
(make-manifest-part role store d &key depends-on recipe)  ; part-role part-store part-revision-id part-depends-on part-recipe
(make-manifest parts) (manifest-parts m)
(commit-composite store parts &key parents ref expected message)
(composite-manifest store d) (plan-composite store d targets) (restore-composite store d targets)

;;; In memory
(make-in-memory-store &key primary engine permit-force)
(make-in-memory-target &key state revisions engine transactional fidelities fail-step stamp-hook)
```

### Contract tests (R0b)

New files in `revision-protocol/tests`; 239 tests including parametrized rows, all failing against the stubs while the 78 R0a tests pass.

| File | Covers |
|------|--------|
| `r0b-fixtures` | Sexp corpus committed as a DAG (main, feature, a merge with an explicit state, an unrelated line of lists / atoms / strings); transitions with expected step shapes; merge and opaque-payload fixtures; fault-injection hooks |
| `content-test` | primary / engine, `revision-state` and `revision-delta` for both primaries, diffs and payloads as content, `delta-inverse` / `delta-footprint`, `state-diff` levels and `:footprint`, over targets / plans / projections, `walk-revisions :footprint` |
| `target-test` | in-memory target values and copies, stamps, drift, `capture-revision`, `with-target-transaction` rollback and refusal |
| `plan-test` | plan shapes (down to the merge-base, through the empty state, merges), purity, `describe-plan` format, `execute-plan` stamps, foreign stamps, drift / irreversible / step-failed restarts via `handler-bind`, resume after an unhandled failure |
| `projection-test` | `project-state`, writable commits, `project-plan` defaults, fidelity restarts (only applicable ones offered), staleness, `project-merge` clean and conflicting with all `merge-conflict` restarts, discard |
| `composite-test` | parts and manifest validation, `commit-composite`, dependency order, restore, `skip-part`, `rebuild-from-recipe` |
| `force-test` | the gate (NIL / T / predicate), `force` on `move-ref`, `commit-revision`, `delete-ref` |
| `law-r0b-test` | **law 3** (apply / inverse / self-diff / revision deltas / compose associativity, both primaries, three levels), **law 5** (goal reached, one stamp per step naming its TO, state at each stamp), **law 6** (`:exact` and `:shadow` equal execution; `:model` equal on `sexp:/cfg`) |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| [`revision-protocol`](https://github.com/egao1980/revision-protocol) (`stack-rev`) | Protocol, conditions, designators, in-memory store, law suite; later the `defspec` model |
| `diff-protocol` (`stack-diff`) | Diffs as values; `revision-protocol` depends on it from R0b (0.1.0) |
| `revision-backend-git`, `revision-backend-jj` | CLI backends (Track V); git V0 brief: [revision-backend-git.md](revision-backend-git.md) |

---

## Non-goals (R0a, R0b)

- git, jj, SQL and filesystem backends (Tracks V, R2, R4)
- `capability-protocol` declarations (query GFs in R0b; adapter later)
- `verify-revision`, multi-head plans, time phrases through `parse-time-range`
- `defspec` model, Quint checks, ITF replay (R0 after R0b)
- Persistence of the in-memory store, GC, signed revisions, multi-ref atomic updates

---

## Implementation tasks

- [x] R0a contract: brief, `egao1980/revision-protocol` skeleton, Rove suite
- [x] R0a implementation through team-solve (revision-protocol#1, 0.1.0)
- [x] R0b contract: brief section, skeleton and Rove suites on `agent/revision-r0b-7b30`
- [ ] R0b implementation through team-solve (`.team-solve/task.md` in the worktree)
- [ ] R0b follow-ups: `verify-revision`, multi-head plans (R2), `capability-protocol` adapter, `parse-time-range` phrases
- [ ] `defspec` model → Quint, ITF replay against the in-memory store
- [ ] Cookbook `cookbooks/revision.md`

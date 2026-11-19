# diff-protocol (R0, diff half) — diffs as values

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track R · MBT [#283](https://github.com/egao1980/cl-stack/issues/283)
**Status:** brief **locked for R0**. Contract: [`egao1980/diff-protocol`](https://github.com/egao1980/diff-protocol) `diff-protocol/tests` (Rove). Implementation via **team-solve**.

A diff is a **value**: a tree of `change`s computed by an **engine** for one content type. Diffs are applied, inverted, composed, rebased and three-way merged without touching any store. `revision-protocol` (the other R0 half) depends on this repo; this repo depends on nothing in the stack.

R0 ships the core values, the **sexp / plist engine**, and `render-diff` / `parse-diff` for `:summary` and `:sexp`. Text, tree, lisp-form, JSON and schema engines, and `:unified` / `:json` formats, are later milestones (R1, R3, R2).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Package** | `diff-protocol`, nickname `stack-diff`. Test system `diff-protocol/tests` (Rove from OCI). |
| **Dependencies** | None at R0 (no `revision-protocol`, `cl-stack-pathlib`, git, SQL, serdes). |
| **Value** | `diff`: changes + level + engine. `change`: kind, path, footprint, before, after, children. Immutable by contract: no GF mutates a diff or a state. |
| **Kinds** | `:add` `:remove` `:modify` `:move` (type `change-kind`). Anything else → `type-error` from `make-change`. |
| **Footprint** | List of resource strings (`"sexp:/a/b"`, later `"path:src/x.lisp"`, `"table:widgets"`). The same strings permissions and `revision-protocol` use. |
| **Levels** | `:summary` `:changes` `:content` (type `diff-level`). Default `:changes`. |
| **Lazy content** | `before` / `after` are a value or a thunk (`:before-fn` / `:after-fn`), forced once on first read and cached. |
| **Opaque** | `opaque-change`: footprint known, content not (a migration step with arbitrary code). |
| **Engines** | CLOS class per content type, subclass of `diff-engine`. R0: `sexp-diff-engine`, name `:sexp`. |
| **Conflicts** | `rebase-diff` / `three-way-diff` return conflicts as **data** (`diff-conflict`), never signal. `apply-diff` **signals** `apply-conflict`. |
| **Errors** | `diff-error` → `irreversible-change`, `apply-conflict`, `unsupported-content`. CLHS 9 conditions + restarts. |
| **Serialization** | The `:sexp` render is the canonical, complete, plain-data form (keywords, strings, numbers, lists) → serdes-friendly. A `serdes-protocol` adapter system comes later; core does not depend on serdes. |

---

## Values

```lisp
(make-change kind &key path from footprint before after before-fn after-fn children) ; → change
(make-opaque-change kind &key footprint description)                                 ; → opaque-change
(make-diff changes &key engine (level :changes))                                     ; → diff

(change-kind c) (change-path c) (change-from c) (change-footprint c) (change-children c)
(change-before c) (change-after c)                ; force + cache the thunk
(change-before-loaded-p c) (change-after-loaded-p c)
(opaque-change-description c)
(diff-changes d) (diff-level d) (diff-engine d)
(diff-footprint d)                                ; union over all changes and children, deduped, sorted string<
(diff-empty-p d)                                  ; no changes
(footprint-overlap-p f1 f2)                       ; string=, or one is a prefix of the other ending at "/" (the prefix ends in "/" or the next char is "/")
```

- `path` is a list of steps from the state root: a keyword (plist key) or a non-negative integer (list index). Root = `NIL`. `from` is the source path of a `:move`.
- `:add` has no before (reads `NIL`), `:remove` has no after.
- `opaque-change` has kind and footprint; before / after read `NIL`, loaded-p is `NIL`.

## Protocol

```lisp
(compute-diff engine a b &key (level :changes))   ; → diff
(state-equal engine a b)                          ; → boolean; the equality every law uses
(apply-diff state d)                              ; pure → (values new-state skipped)
(invert-diff d)                                   ; → diff | signals irreversible-change
(compose-diffs d1 d2)                             ; → diff: apply d1 then d2
(rebase-diff d onto base)                         ; → (values diff conflicts)
(three-way-diff engine base ours theirs)          ; → (values merged-diff conflicts)
(render-diff d format stream)                     ; :summary | :sexp; stream NIL → string, T → *standard-output*
(parse-diff format input)                         ; :sexp; input string or stream → diff
(engine-name engine)                              ; → keyword
(find-diff-engine name)                           ; → engine instance | NIL
```

All are generic functions except `make-*`, `footprint-overlap-p` and `find-diff-engine`. `diff-changes`, `diff-footprint`, `diff-empty-p` are GFs so other engines and lazy diffs can specialize them.

`three-way-diff` takes the engine first (as `compute-diff` does): states are plain Lisp data and cannot carry dispatch. `rebase-diff` takes `d` and `onto`, both computed against `base`; the result applies to `(apply-diff base onto)`.

## The sexp engine

States are atoms (numbers, strings, characters, symbols), **plists**, and **lists**. Anything else (hash tables, non-string vectors, structures, standard objects) → `unsupported-content`.

- **Plist:** a non-empty proper list of even length, keywords at even positions, no duplicate keys. Compared **by key, order-insensitive**. `NIL` is the empty plist next to a plist and the empty list next to a list.
- **List:** any other proper list, compared **by position**.
- `state-equal`: plists as key sets (recursively), lists by position, atoms by `equal`.

`compute-diff` builds the **content tree** first, then shapes it for the level:

1. Equal (`state-equal`) → no change. Both plists → per key: key only in `a` → `:remove`; only in `b` → `:add`; in both and not equal → `:modify` at path + key. A removed and an added key whose values are `state-equal` pair up as one `:move` (`from` = old path, `path` = new path), matched in `a`'s key order against `b`'s key order, first unused match wins.
2. Both lists → `:modify` per differing common index, then `:remove` of `a`'s extra tail **highest index first**, then `:add` of `b`'s extra tail **lowest index first**. No moves in lists at R0.
3. Otherwise (atom vs anything, plist vs list) → `:modify` of the whole value at that path.
4. A `:modify` whose two sides are both plists or both lists carries `children`: the changes of its sub-values, with **absolute** paths.

Change order within a plist: `a`'s key order for modifies/removes/moves, then `b`'s key order for adds. Order matters: `apply-diff` applies changes in list order.

| Level | `diff-changes` | Content |
|-------|----------------|---------|
| `:summary` | The roots of the content tree, `children` empty | Lazy: `before` / `after` are thunks, **not forced** by `compute-diff` |
| `:changes` | The **leaves** of the content tree, depth-first, flattened | Loaded |
| `:content` | The roots, each with its `children` tree | Loaded |

Footprint of a sexp change: `"sexp:"` + `/` + each step (keyword → lowercased symbol name, integer → decimal). Root → `"sexp:/"`. `(:a 2)` → `"sexp:/a/2"`. A `:move` has two strings, `from` first.

## Apply, invert, compose, merge

- `apply-diff` returns new structure, never mutates `state`. Changes apply in order; a change with children applies its children. Plist adds append the key at the end; existing key order is kept. List adds require index = current length.
- Each change checks the state first: `:modify` / `:remove` need the path present and its value `state-equal` to `before`; `:add` needs the path absent (plist key) or at the tail (list); `:move` needs `from` present with `before` and `path` absent; a missing parent fails. Failure signals **`apply-conflict`** inside `restart-case`:
  - `skip-change` — leave that location, continue. The change is collected into the **second value**.
  - `use-value v` — put `v` at the change's path (for a `:remove` too), continue.
  - `abort` — `apply-diff` returns `(values state :aborted)`, `state` being the original object (`eq`).
- An `opaque-change` cannot be applied by the sexp engine → `unsupported-content`.
- `invert-diff`: `:add` ↔ `:remove`, `:modify` swaps before/after, `:move` swaps `from`/`path`; children inverted; **change order reversed** (keeps list-index order valid). Laziness is kept (swapped thunks are not forced). An `opaque-change` signals **`irreversible-change`** with restarts `skip-change` (omit it from the inverse) and `use-value change` (use that change as its inverse).
- `compose-diffs d1 d2`: applying the result equals applying `d1` then `d2`. Concatenation is a valid implementation; squashing is allowed if the law holds. Composing two empty diffs is empty.
- `three-way-diff` merges at **leaf** granularity (level `:changes`): `ours` = leaves of `diff(base, ours)`, `theirs` likewise. Non-overlapping changes from both go in the merged diff (ours first). Two changes whose footprints overlap (`footprint-overlap-p` on any pair of strings) are a conflict, unless they are the same kind at the same path with `state-equal` after values — then the change is kept once. Conflicting changes stay out of the merged diff (base value kept there).
- `diff-conflict`: `conflict-ours`, `conflict-theirs` (one change each), `conflict-footprint` (union of the two footprints, deduped, sorted `string<`). One conflict per overlapping pair.
- `rebase-diff d onto base`: leaves of `d` that overlap no leaf of `onto` are kept; identical ones (as above) are dropped (already applied); the rest are conflicts (`conflict-ours` = from `d`, `conflict-theirs` = from `onto`).

## Laws (Rove `deftest-parametrize` over a fixed corpus; later the `defspec` invariants)

For every corpus pair `(a b)` and every level:

1. `(state-equal e (apply-diff a (compute-diff e a b :level L)) b)`
2. `(state-equal e (apply-diff b (invert-diff (compute-diff e a b :level L))) a)`
3. `(diff-empty-p (compute-diff e a a :level L))`
4. Compose: for corpus triples `(a b c)`, `(compose-diffs (diff a b) (diff b c))` applied to `a` = `c`; `(compose-diffs (compose-diffs d1 d2) d3)` and `(compose-diffs d1 (compose-diffs d2 d3))` give `state-equal` results on `a`.
5. Three-way symmetry: swapping `ours` / `theirs` gives a `state-equal` merged result on `base` and the same set of conflict footprints.

## Render / parse

- `:summary` — one line per element of `diff-changes`: a letter (`A` add, `D` remove, `M` modify, `R` move), a space, the change's footprint strings joined by spaces, newline. Empty diff → `""`.
- `:sexp` — one form, printed inside `with-standard-io-syntax` with `*package*` = `KEYWORD` and `*print-pretty*` NIL:

  ```lisp
  (:diff :version 1 :engine :sexp :level :changes
   :changes ((:change :kind :modify :path (:a) :footprint ("sexp:/a") :before 1 :after 2)
             (:change :kind :move :path (:y) :from (:x) :footprint ("sexp:/x" "sexp:/y") :before 3 :after 3)
             (:opaque :kind :modify :footprint ("table:widgets") :description "backfill")))
  ```

  Key order is fixed: `:kind :path [:from] :footprint [:before] [:after] [:children]`; opaque: `:kind :footprint :description`. `:before` is omitted for `:add`, `:after` for `:remove`; `:from` only on `:move`; `:children` only when non-empty. Lazy content is forced. `parse-diff :sexp` reads with `*read-eval*` NIL and rebuilds the diff (engine via `find-diff-engine`). Round trip: render → parse → render is `string=`.

## Conditions

| Condition | Parent | Slots (readers) | Restarts |
|-----------|--------|-----------------|----------|
| `diff-error` | `error` | `diff-error-diff`, `diff-error-change` | — |
| `irreversible-change` | `diff-error` | — | `skip-change`, `use-value` (in `invert-diff`) |
| `apply-conflict` | `diff-error` | `apply-conflict-actual` (value found at the path, or `NIL`), `apply-conflict-reason` (`:missing` `:exists` `:before-mismatch`) | `skip-change`, `use-value`, `abort` (in `apply-diff`) |
| `unsupported-content` | `diff-error` | `unsupported-content-engine`, `unsupported-content-content` | — |

`skip-change` is exported as a restart name and as a function `(skip-change &optional condition)`, like `continue`.

---

## Non-goals (R0)

- Text (Myers, histogram, diff3), tree, lisp-form, JSON-patch, schema-op engines; `:unified` / `:json` formats (R1–R3)
- Move detection in lists; similarity-based rename detection
- `revision-protocol` (separate repo, the other R0 half)

## Implementation tasks

- [x] Brief — this doc
- [x] Contract: `egao1980/diff-protocol` skeleton + `diff-protocol/tests`
- [ ] team-solve R0: values, sexp engine, apply / invert / compose / rebase / three-way, render + parse `:summary` / `:sexp`
- [ ] `defspec` model of the laws → Quint (with `revision-protocol` R0)
- [ ] GHCR publish 0.1.0

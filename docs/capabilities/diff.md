# diff-protocol (R0 + R1) — diffs as values

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track R · MBT [#283](https://github.com/egao1980/cl-stack/issues/283)
**Status:** brief **locked for R0** (shipped, diff-protocol 0.1.0) and **locked for R1** (text engine, tree engine, `:unified`, the diff-protocol#2 fix — see [R1 — locked](#r1--locked)). Contract: [`egao1980/diff-protocol`](https://github.com/egao1980/diff-protocol) `diff-protocol/tests` (Rove). Implementation via **team-solve**.

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

## R1 — locked

R1 adds the **text engine** (Myers, histogram, diff3), the **tree engine** (named nodes, leaf dispatch by type, rename detection), the **`:unified`** format (render and parse, including real `git diff` output), and fixes [diff-protocol#2](https://github.com/egao1980/diff-protocol/issues/2) in the sexp engine. Still no dependencies: no pathlib, git or `revision-protocol`. Everything in R0 stays as locked above unless this section says otherwise.

### R1 decisions

| Decision | Choice |
|----------|--------|
| **Text state** | A CL string. Lines split after each `#\Newline`; a last line without one is kept as is. `#\Return` is part of the line, so `"a\r\n"` ≠ `"a\n"` (CRLF is lossless). `state-equal` = `string=`. Non-strings → `unsupported-content`. |
| **Hunk** | A plain `change`. `path` = `(p)`, `p` = 0-based line index **in the state the change is applied to** (sequential, like R0 list indices). `before` / `after` = lists of line strings with terminators. Kind `:add` (before empty), `:remove` (after empty), `:modify` otherwise. |
| **Hunk order** | `compute-diff` emits hunks **descending** by `p`, so every `p` is a base coordinate. `invert-diff` (R0 rule: reverse order) makes them ascending; positions stay valid in both orders. |
| **Text footprint** | `"text:/<p>-<p+len(before)>"`: the half-open 0-based line range the change replaces in the state it applies to. Pure insert: `"text:/3-3"`. Whole text: `"text:/"`. `invert-diff` **recomputes** a hunk footprint from the inverse's path and before (`text:…/<s>-<e>` strings only), so a double inverse restores it; nothing lazy is forced. |
| **Histogram** | `(make-instance 'text-diff-engine :algorithm :histogram)`; default `:myers`; anything else → `type-error`. Histogram (git's): anchor on the lowest-occurrence common line, extend the match both ways, recurse; fall back to Myers in a region with no unique-enough line. Myers is minimal. |
| **Tree value** | Plain data (so `:sexp` renders it unchanged): directory `(:dir (name node) …)` sorted `string<`; file `(:file :type t :content c :mode m)`. Built by `make-tree` / `make-tree-file`. Empty subdirectories are not represented. Mode `NIL` reads as `#o100644`. |
| **Tree paths** | File-level changes: a list of names (`("src" "x.lisp")`). Leaf changes append the leaf engine's steps (text: line index; sexp: keywords / indices); a mode change appends the symbol `tree-mode`. The tree part of a path is its leading strings. |
| **Tree footprints** | File-level: `"tree:/src/x.lisp"`. Leaf change: `"tree:/<file>"` followed by the leaf engine's strings with the file path spliced in after the scheme: `"text:/3-5"` → `"text:/src/x.lisp/3-5"`, `"sexp:/a/b"` → `"sexp:/cfg/a/b"`, `"sexp:/"` → `"sexp:/cfg"`. A `:move` has `(from to)` tree strings (R0 order). |
| **Rename detection** | Exact first (same type, `state-equal` content), then line similarity for text files `2·LCS / (lines(a) + lines(b))` ≥ `rename-threshold` (default 0.5). Empty files are never rename candidates. |
| **Unified** | Text diffs render bare `@@` hunks; tree diffs render `diff --git` sections. `parse-diff :unified` returns a text diff for bare hunks, a tree diff when file headers are present. No `index` lines on render. |
| **#2 fix** | Merges **transform indices** (not wider footprints): adds re-indexed past the other side's removes; list tail runs are atomic in conflicts. |

### Exports (new in R1)

```lisp
;; conditions
diff-parse-error diff-parse-error-line          ; subclass of diff-error; LINE 1-based
;; text
text-diff-engine text-engine-algorithm          ; class; :myers | :histogram
(split-lines string)                            ; → fresh list of lines (terminators kept); "" → NIL
(merge-texts base ours theirs &key engine (style :merge)
             (ours-label "ours") (base-label "base") (theirs-label "theirs"))
                                                ; → (values merged-string conflicts)
;; tree values
(make-tree &rest name node …) (make-tree-file content &key type mode)
(tree-dir-p x) (tree-file-p x) (tree-entries dir) (tree-get tree path)   ; tree-get → (values node found-p)
(tree-file-type f) (tree-file-content f) (tree-file-mode f)
tree-mode                                        ; the path step of a mode change
;; tree engine
tree-diff-engine tree-engine-rename-threshold tree-engine-detect-renames tree-engine-leaf-engines
```

`(find-diff-engine :text)` → a `text-diff-engine` (Myers); `(find-diff-engine :tree)` → a `tree-diff-engine` with defaults. Both are what `parse-diff` uses.

### Text engine

`(compute-diff text-engine a b &key (level :changes) (context 0))`

- **`:changes`** — the hunks, descending. With `:context 0` hunks are minimal: a maximal run of changed lines, separated by at least one unchanged line.
- **`:context n`** — each hunk also covers up to `n` unchanged lines before and after (clipped at the text's edges); two hunks merge when the unchanged gap between their changes is ≤ `2n` (git's rule). Context lines are part of `before` and `after` (and of the footprint range).
- **`:summary`** — one root `:modify`, path `NIL`, footprint `("text:/")`, before / after = the whole strings as **thunks, not forced**, no children.
- **`:content`** — the same root, loaded, with `children` = the hunks.
- Equal texts → empty diff at every level.
- **Apply** (`%apply-change`): a hunk at `(p)` checks that the state's lines `[p, p+len(before))` exist (else `apply-conflict :missing`) and are `string=` to `before` (else `:before-mismatch`, `actual` = the lines found), then replaces them with `after`. A root change (path `NIL`) checks the whole string. `use-value v` (a list of lines) replaces the hunk's range, clipped to the text. Non-string state → `unsupported-content`.
- **`render-diff … :sexp` / `parse-diff :sexp`** work unchanged (engine `:text`).

### diff3 (`three-way-diff` on the text engine)

- Hunks `base→ours` and `base→theirs` (context 0). Two hunks with base ranges `[s1,e1)` and `[s2,e2)` **interact** when no unchanged base line separates them: `s1 ≤ e2` and `s2 ≤ e1` (so two inserts at the same point, or an insert touching an edit, interact). Interacting hunks are grouped transitively into **regions** (the union of their base ranges).
- A region changed by one side only → that side's change. Both sides with the same resulting lines → kept once. Otherwise → a **conflict**; the region keeps base in the merged diff.
- Merged diff: level `:changes`, one hunk per merged region, descending, base coordinates (so the R1 hunk invariants hold against `base`).
- `diff-conflict` per conflicting region: `conflict-ours` = a change at `(s)` with `before` = base lines of the region and `after` = ours's lines for it (kind by emptiness); `conflict-theirs` likewise; `conflict-footprint` = `("text:/s-e")`.
- Symmetric in ours / theirs (law 4). One side unchanged, or both equal → no conflicts.

`merge-texts` → `(values merged-string conflicts)`: the merged text with each conflict region written as

```
<<<<<<< ours
…ours lines…
||||||| base          ← only with :style :diff3
…base lines…
=======
…theirs lines…
>>>>>>> theirs
```

Labels follow the marker after one space. Marker lines always end in `#\Newline`; a side whose last line has none gets one before the next marker. No conflicts → the merged text and `NIL`.

**`rebase-diff d onto base`** for text and tree diffs: `(three-way-diff e base (apply-diff base d) (apply-diff base onto))`, conflicts with `conflict-ours` from `d` and `conflict-theirs` from `onto` (R0 sides), conflict regions resolved to `onto`'s version; the result is `(compute-diff e onto-state merged-state)` and applies to `(apply-diff base onto)`.

### Tree values

- `make-tree`: alternating name / node arguments. A name is a non-empty string without `/`, and a node is a directory or a file node; anything else → `type-error`. Odd argument count or duplicate names → `error`. Entries sorted `string<`; subdirectories with no files are dropped. `(make-tree)` = `(:dir)`, the empty tree.
- `make-tree-file content &key type mode`: `type` defaults to `:text` (string), `:binary` (`(unsigned-byte 8)` vector), `:sexp` (anything else). `mode`: `NIL` or an integer (`#o100644`, `#o100755`, `#o120000`).
- `tree-get tree path` → `(values node found-p)`; `NIL` path → the tree; through a file → `(values nil nil)`.
- Values print and read back `equal` (when no octet vectors are inside) and construction is deterministic.

### Tree engine

`(make-instance 'tree-diff-engine &key (rename-threshold 0.5) (detect-renames t) (leaf-engines '((:text . :text) (:sexp . :sexp))))` — `leaf-engines` maps a file type to an engine name (`find-diff-engine`) or instance. Types without an engine (`:binary`, …) are diffed as whole values (`equalp`).

`(compute-diff tree-engine a b &key (level :changes) (context 0))` — both sides must be directory nodes, else `unsupported-content`. `context` is passed to text leaves.

- **File-level changes:** `:add` (after = file node), `:remove` (before = file node), `:move` (from / path, before = old node, after = new node — content may differ for a similarity rename; no children), `:modify` (before / after = file nodes).
- **Leaves of a `:modify`** (its `children` at `:content`; the change list at `:changes`): when both sides have the same type and that type has a leaf engine, the leaf engine's `:changes` (nested paths, spliced footprints), plus a mode change `(… tree-mode)` with before / after modes (`NIL` normalized to `#o100644`) when modes differ. A mode-only change is a `:modify` whose only child is the mode change. Different types, or no leaf engine → a `:modify` with no children (the whole node).
- **Levels:** `:summary` = file-level changes, lazy, no children; `:content` = file-level changes with children; `:changes` = leaves (file-level changes without children + nested leaf changes).
- **Canonical order:** `:remove`, then `:move`, then modifies (files in path order; per file the mode change first, then its leaves in the leaf engine's order — text hunks descending), then `:add`; each group by path (names joined with `/`, `string<`; a move by its destination). Inverse = reversed (R0).
- **Rename detection** (when `detect-renames`): candidates are files only in `a` (removed) and only in `b` (added), non-empty. (1) Exact: removed files in path order each take the first unused added file (path order) of the same type with `state-equal` content (modes may differ; the move's `after` carries the new one). (2) Similarity, text files only: every pair with similarity ≥ threshold, taken highest first, ties by removed path then added path.
- **Apply:** `:add` creates missing parent directories; a file in the way of a parent or the path itself → `apply-conflict :exists` (`actual` = that node). `:remove` / `:modify` need the file (else `:missing`) and a `state-equal` before (else `:before-mismatch`). `:remove` prunes directories left empty. `:move` needs `from` (checked against `before` only when `before` is loaded) and an absent `path`; a move with unloaded sides (from `parse-diff`) moves the node unchanged. Leaf changes are applied by the file's leaf engine to its content; a mode change sets the mode. An `opaque-change` → `unsupported-content` with `use-value` (a file node, put at the change's path) and `skip-change` available.
- **`state-equal`:** same set of file paths; per file same type, modes equal after `NIL` → `#o100644`, contents equal under the leaf engine's `state-equal` (`equalp` without one).
- **Three-way:** per file, from the leaves of both sides. One side touches a path → taken. Identical changes → once. Both sides change the content of a file present in base with the same type and a leaf engine → the leaf engine's `three-way-diff` on the three contents; merged and conflicting leaf changes come back nested (paths, footprints). Mode vs content changes merge independently; two different mode changes conflict. Anything else whose tree footprints overlap (`footprint-overlap-p`: same file, or a file vs a path under it) → one `diff-conflict` per overlapping pair; in particular modify / delete, add / add with different content, rename vs any change of its source or target, file vs directory. Conflicting paths keep base. Merged diff at `:changes`, canonical order. Symmetric.

### Unified format

**Hunks** (text diffs, and the hunks inside tree sections):

- Header `@@ -os[,oc] +ns[,nc] @@`: starts 1-based; for a count of 0 the start is the line before (git); a count of 1 is omitted. Old starts and new starts come from the hunk sequence: descending → paths are old 0-based starts; ascending (an inverted diff) → paths are new starts; a single hunk is both. Any other order (e.g. a composed diff) → `unsupported-content`.
- Body: the hunk's lines from the engine's own line diff of `before` against `after`: common lines `" "`, each change block `-` lines then `+` lines. A minimal hunk is all `-` then all `+`. Lines are written raw (a CRLF line keeps its `\r`). A line without a terminator is followed by `\n\ No newline at end of file\n`.
- Hunks in ascending order. Empty diff → `""`. A text root change without children (`:summary`) is rendered from a context-0 diff of its before / after. Diffs of other engines → `unsupported-content`.

**Tree sections** (`diff --git a/P b/P`), sorted by path (a move by its destination), one per file:

| Change | Lines after `diff --git` |
|--------|--------------------------|
| modify (text) | `--- a/P`, `+++ b/P`, hunks |
| add | `new file mode 100644` (or the file's mode), then `--- /dev/null`, `+++ b/P`, one hunk of the whole file — none for an empty file |
| remove | `deleted file mode …`, `--- a/P`, `+++ /dev/null`, one hunk — none for an empty file |
| move | `diff --git a/OLD b/NEW`, `similarity index N%` (N = ⌊100 × similarity⌋, only when both sides are loaded), `rename from OLD`, `rename to NEW`, then `--- a/OLD`, `+++ b/NEW` and hunks when the content differs |
| mode | `old mode 100644`, `new mode 100755` (before any `---` lines of the same file) |
| non-text content (binary, sexp, any type change) | `Binary files a/P and b/P differ` (`/dev/null` for an add / remove side) |

A file `:modify` without children is rendered from a context-0 diff of its contents. The same text at every level of the same diff.

**Parse** (`parse-diff :unified input`, string or stream):

- No file headers → a text diff (engine `:text`, level `:changes`, hunks descending). `""` → an empty text diff.
- File headers → a tree diff (engine `:tree`, level `:changes`, canonical order). A section starts at `diff --git` or at a `---` / `+++` pair. `---` / `+++` paths: text after a TAB is dropped (timestamps of `diff -u`), `/dev/null` means absent, one leading component is stripped (`a/`, `b/`, `before/` — like `patch -p1`). `rename from` / `rename to`, `new file mode`, `deleted file mode`, `old mode` / `new mode` are used; `index`, `similarity index`, `dissimilarity index` and any other line outside a hunk (mail preamble, `diff -r` command lines) are ignored. Quoted paths (`core.quotePath`) and copies are out of scope at R1. **0.2.1** ([diff-protocol#4](https://github.com/egao1980/diff-protocol/issues/4)): C-quoted paths are unquoted in `diff --git` (either side quoted alone), `---` / `+++`, `rename from` / `to` and `copy from` / `to` — escapes `\a \b \t \n \v \f \r \" \\` and `\ooo` octets decoded as UTF-8 (Latin-1 when not valid UTF-8); a malformed quoted path → `diff-parse-error` at its line. Render quotes as git with `core.quotePath=off` (control characters, DEL, `"`, `\`). A copy section is an opaque `:add` of the destination (`change-from` = source, footprint both; `use-value` supplies the node) that renders back as `copy from` / `copy to`.
- A parsed hunk keeps its context lines in `before` and `after`; `p` = old start − 1 (old start when the old count is 0). In a tree, hunks get the file path and spliced footprints.
- New file → `:add` with a file node built from the `+` lines (mode from the header); deleted → `:remove` with a node from the `-` lines; empty new / deleted file (header only) → content `""`. Rename → `:move` with **unloaded** before / after, followed by its hunks at the new path. Mode change → `(… tree-mode)` `:modify` from / to the integer modes. `Binary files … differ` → an `opaque-change` (kind `:add` / `:remove` / `:modify`) with `change-path` = the file path, footprint `("tree:/P")`, description = that line.
- Errors → `diff-parse-error` with the 1-based `line`: a malformed `@@` header, a body line not starting with `" "`, `-`, `+` or `\` while the counts are unfinished, a `\ No newline` line with no line before it, a hunk cut short (line = the one after the last line read).
- Round trip: render → parse → render is `string=` for text diffs and for tree diffs without renames; `render ∘ parse` is idempotent for all tree diffs (a parsed rename loses its similarity line). A parsed diff applies to the old state and gives the new one (fixtures from real `git diff`).

### Sexp lists in merges (diff-protocol#2)

R0 list edits are tail edits: `:remove`s of the tail (highest index first) and `:add`s at the tail. Their footprints are unchanged; R1 fixes merges instead:

- **Re-index:** in a merged (or rebased) diff, an `:add` at index `i` of a list `L` whose list has `k` `:remove`s earlier in the merged diff, coming from the other side, is re-indexed to `i − k`; footprints follow the new path.
- **Atomic tail runs:** for one side and one list, the tail removes form one run and the tail adds another. When any member of a run is in a conflict, every member of the run stays out of the merged diff; members with no conflict of their own are reported as a `diff-conflict` paired with the opposite change of the run's first (in diff order) conflict.
- **`use-value`** in `apply-diff` that cannot place its value (an unreachable list path) signals `apply-conflict` again **with `skip-change`, `use-value` and `abort` available**, not only `abort`.

### Laws (R1)

Laws 3–4 of the plan for the text engine (both algorithms, all levels) over every ordered pair of a fixed corpus (empty, no trailing newline, CRLF and mixed line ends, identical, all-different, blank and repeated lines) plus 40 deterministic random pairs and 45 triples; for the tree engine over a tree corpus (renames, similarity renames, mode, sexp / binary leaves, file ↔ directory) plus 25 random pairs and triples. Extra properties: hunk invariants (descending, separated, `before` = the base lines, footprint), Myers minimality (`removed + added = |a| + |b| − 2·LCS`), three-way with one side unchanged or both equal has no conflicts.

---

## Non-goals (R0)

- Text (Myers, histogram, diff3), tree, lisp-form, JSON-patch, schema-op engines; `:unified` / `:json` formats (R1–R3)
- Move detection in lists; similarity-based rename detection
- `revision-protocol` (separate repo, the other R0 half)

## Non-goals (R1)

- Rename-aware merges (a rename on one side and an edit of its source on the other is a conflict at R1); copy detection (a parsed copy is opaque, 0.2.1)
- `git apply`-style fuzz or offset search when context does not match
- Binary patches (`GIT binary patch`); git blob hashes on `index` lines
- `:json` format, serdes adapter, lisp-form / JSON-patch / schema engines (R2, R3)

## Implementation tasks

- [x] Brief — this doc
- [x] Contract: `egao1980/diff-protocol` skeleton + `diff-protocol/tests`
- [x] team-solve R0: values, sexp engine, apply / invert / compose / rebase / three-way, render + parse `:summary` / `:sexp`
- [x] R1 contract: text / tree engine stubs, `:unified` tests, `git diff` fixtures, diff-protocol#2 regressions (branch `agent/diff-r1-f7bb`)
- [ ] team-solve R1: text engine, diff3, `merge-texts`, tree values + engine, `:unified` render / parse, #2 fix
- [ ] `defspec` model of the laws → Quint (with `revision-protocol` R0)
- [ ] GHCR publish 0.1.0

# diff-backend-lisp-source (R3): form-level diffs of Common Lisp source

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track R, milestone **R3** ("Round-trip on the workspace's own `.lisp` history; comments preserved") · protocol brief [diff.md](diff.md) · source tooling [`lisp-source-protocol`](https://github.com/egao1980/lisp-source-protocol)
**Status:** **locked for R3** (contract). Repo [`egao1980/diff-backend-lisp-source`](https://github.com/egao1980/diff-backend-lisp-source) (`stack-diff-lisp`), version 0.1.0: exports, conditions, the engine class, stubs and the Rove suite `diff-backend-lisp-source/tests` that specifies them. Implementation runs through **team-solve**.

A `diff-protocol` engine whose states are Common Lisp source **strings**. It diffs at the level of top-level forms (`defun foo`, `defmethod m :around (c t)`, `defclass …`), goes inside a form for structural edits, and merges three ways form by form: edits to different forms merge cleanly, two different edits to one form conflict. Text is never normalised: comments, blank lines, indentation, `#+`/`#-` and `#.` stay byte for byte, and nothing is evaluated.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Package** | `diff-backend-lisp-source`, nickname `stack-diff-lisp`. Test system `diff-backend-lisp-source/tests` (Rove from OCI). | Stack naming (`diff-backend-*` beside `revision-backend-*`) |
| **Dependencies** | `(:version "diff-protocol" "0.2.0")`, `lisp-source-protocol` (0.2.4 on GHCR). Nothing else. | The engine sits on the stack's own reader; no second Lisp parser |
| **Engine** | Class `lisp-source-diff-engine` (subclass of `diff-protocol:diff-engine`), `engine-name` → **`:lisp`**, registered so `(find-diff-engine :lisp)` returns the shared instance. Initarg `:detect-renames` (default T), reader `lisp-engine-detect-renames`. | Same shape as `:text` / `:tree`; `parse-diff :sexp` finds the engine by name |
| **State** | A CL string. `state-equal` = `string=` (CRLF ≠ LF). Anything else → `unsupported-content`. | Lossless: the engine never rewrites text it did not change |
| **Reader** | `lisp-source-protocol:read-source` with **`:features '()`** (the empty feature list), never the host `*features*`. `#.` reads as a placeholder (never evaluated), symbols are tokens (never interned, unknown packages fine). | Same result on SBCL / Windows / any host; nothing runs |
| **CST reuse** | Yes. Units, keys and nested paths come from the lisp-source-protocol CST: top-level `parsed-source-nodes`, `node-forms` child indices (the `path:` locator of lisp-mcp), `node-head-name`, `node-text`. The method key format is lisp-mcp's locator (`defmethod m (c t)`). | The lisp-mcp server is built on the same tree, so a footprint names what `source-read` / `edit-replace` would address |
| **Clean input only** | A side that does not read clean (`parsed-source-clean-p` false: reader errors or paren imbalances) → `lisp-source-unreadable` with restarts `use-text-diff` and `use-value`. No form diff over recovered nodes. | Recovery is a guess; a guessed structure must not drive a merge |
| **Paths** | `(:form KEY . INDICES)`: the keyword `:form`, the unit's key string, then `node-forms` indices inside the form. A `:move`'s `from` is `(:form OLD-KEY)`. | A non-string second step keeps the tree engine's rule "leading strings = file path" intact, so the engine nests under `:tree` unchanged |
| **Footprints** | `"lisp:/" + escaped key [+ "/" i …]`. Escape: `\` → `\\`, `/` → `\/`. A `:move` with a new key has `(from to)`; a pure reorder has one string. | `footprint-overlap-p` prefix rule: `defun foo` never overlaps `defun foo/bar`, a leaf overlaps its form |
| **Form-level content** | `before` / `after` of a form-level change are plists **`(:key K :anchor A :text T)`**: the key, the key of the unit it follows (NIL = file start), the unit text. Nested leaves carry node texts (strings). | Plain data → `:sexp` render round trips; the anchor is what makes `:add` / `:move` positional without line numbers |
| **Merge granularity** | The form. Two different changes to the same form (or a form and something inside it) conflict; no merge inside a form at R3. | The R3 row of the plan; text-level merge inside one form is the `:text` engine's job |
| **Engine hooks** | Public behaviour only through exported `diff-protocol` GFs. The implementation specializes diff-protocol's engine hooks `%apply-change`, `%put-value`, `%three-way`, `%rebase` and registers through `%register-engine` — the same internal SPI the in-repo text / tree engines use, so `apply-diff` restarts, `invert-diff`, `compose-diffs`, `rebase-diff` and tree nesting work unchanged. Exporting that SPI: [diff-protocol#6](https://github.com/egao1980/diff-protocol/issues/6). | There is no exported engine SPI in 0.2.0; reimplementing apply / invert / rebase would fork the restart contract |

---

## Surface

```lisp
(make-instance 'lisp-source-diff-engine &key (detect-renames t))
(find-diff-engine :lisp)                        ; the shared instance
(lisp-engine-detect-renames engine)

(source-units text)            ; → ((:key k :anchor prev-or-nil :text unit-text) …) in order
(unified-patch base diff &key path (context 3))  ; → string; "" when nothing changes

;; conditions / restarts
lisp-source-unreadable                          ; subclass of diff-protocol:unsupported-content
(lisp-source-unreadable-diagnostics c)          ; lisp-source-protocol DIAGNOSTIC (:error) + IMBALANCE objects
(use-text-diff &optional condition)             ; restart name and function, like CL:CONTINUE
```

Everything else is `diff-protocol`: `compute-diff` (`&key level context`; `context` is accepted and ignored so the tree engine can pass it), `state-equal`, `apply-diff`, `invert-diff`, `compose-diffs`, `three-way-diff`, `rebase-diff`, `render-diff :summary | :sexp`, `parse-diff :sexp`.

## Units

The file is cut into **units**; their texts concatenate to the file exactly.

- **Heads** are the top-level nodes of the CST that are forms: every top-level expression node, and every top-level `:feature-skipped` node (a `#+x` form whose feature is absent, i.e. every `#+` form under the empty feature list). Comments, block comments and whitespace are not heads.
- **A unit ends** after its head's last line: after the head, the spaces and tabs that follow, any comments that start on that line (a `;` comment runs to and includes its newline; after a `#|…|#` comment, more trailing material may follow), and the newline (`LF` or `CR LF`) that ends that line. If the next head starts on the same line, the unit ends where that head starts (`(a) (b)` → `"(a) "`, `"(b)\n"`).
- **The next unit starts** where the previous one ended: blank lines, comments and whitespace before a form belong to that form. The first unit starts at offset 0 (a `#!` line and file header comments go with the first form).
- **Trailer:** text after the last unit, if any (`;; end` comments, blank lines), is one more unit with key **`"eof"`**. A file with no forms but some text is a single `"eof"` unit; `""` has no units.

## Form keys

Each unit has a key string, unique in its file.

| Head | Key |
|------|-----|
| `(defmethod NAME QUAL* LAMBDA-LIST …)` | `defmethod NAME QUAL… (S1 S2 …)`: qualifiers as normalised text; one specializer per required parameter (until the first `&` keyword): a `(var spec)` parameter → normalised text of `spec`, a plain symbol → `t`. `(defmethod m :around ((a pkg:cls) (b (eql :k)) c))` → `defmethod m :around (pkg:cls (eql :k) t)` |
| `(in-package X)` | `in-package NAME` |
| `(OP NAME …)` where OP starts with `DEF` or contains `DEFINE-` (lisp-source-protocol's `definition-operator-p`) and a second form exists | `OP NAME`, e.g. `defun foo`, `define-condition oops`, `defsystem my-sys/tests` (`(defun)` alone → `defun`) |
| any other list with a symbol head | the operator: `eval-when`, `setf` |
| anything else | the node kind, downcased: `list` (non-symbol head), `symbol`, `dispatch` (`#.(…)`), `string`, … |
| `#+F FORM` / `#-F FORM` | `#+F KEY` / `#-F KEY`: the guard (`#+` or `#-` and the normalised feature expression) and the key of FORM, read on its own. `#+(or sbcl ccl) (defvar *h* 1)` → `#+(or sbcl ccl) defvar *h*`; guards nest (`#+a #-b defun k`) |

- **OP** is the head symbol's name, package prefix dropped, downcased (`cl:defmacro` → `defmacro`).
- **NAME**: a symbol → its name without package marker, downcased (`#:my-pkg`, `:my-pkg`, `My-Pkg` → `my-pkg`); a string → its characters as written (`"my-sys/tests"` → `my-sys/tests`); anything else → normalised text (`(setf foo)`).
- **Normalised text** = lisp-source-protocol's locator normalisation: trimmed, runs of whitespace → one space, downcased.
- **Duplicates:** the second unit with the same key gets `" #2"`, the third `" #3"`, in file order (`setf`, `setf #2`). `"eof"` is reserved for the trailer: a top-level `(eof …)` form counts from `#2` (`eof #2`, `eof #3`), with or without a trailer (0.2.0, diff-backend-lisp-source#2).

## Changes

`compute-diff engine a b` reads both sides (clean, or `lisp-source-unreadable`) and compares their units by key.

**Anonymous units** (0.2.0) — a head with no name node (not `in-package`, not the trailer: `setf`, `eval-when`, `progn`, …) has no identity beyond operator + ordinal, so before comparing, b's anonymous units are keyed in a's namespace by content: per base key, a b unit takes the key of the first unused a unit with the same text; the rest pair up in order between the same matched neighbours (an edit stays a `:modify`); the others get fresh ordinals after a's. Inserting a `setf` before others is one `:add`. The changes are then renamed to **operational keys**: applying them in order is simulated, and each key, `from` and anchor is the ordinal key that unit has in the state the change reads (before key, `from`, before anchor) or makes (key, after anchor). Only keys of duplicated bases differ. A merge keys ours and theirs in base's namespace the same way; new anonymous units of both sides share one numbering by text (sorted), so the same new form is a twin and different new forms never collide.

- **`:add`** — key only in b. `after` = b's unit plist, anchor = its predecessor in b.
- **`:remove`** — key only in a. `before` = a's unit plist, anchor = its predecessor in a.
- **`:modify`** — key in both, not moved, unit texts differ. Sides = the unit plists; both anchors = the unit's predecessor (0.2.0: only `use-value` on a vanished unit uses them).
- **`:move` (reorder)** — key in both, but out of order: the **moved** keys are the common keys that the diff-protocol `:text` engine (Myers) marks removed when it diffs the common keys of a (in a's order) against those of b (in b's order), one key per line. A moved unit whose text also changed is still one `:move` (`before` text ≠ `after` text). `path` = `from` = `(:form K)`.
- **`:move` (rename)** — with `detect-renames`: a removed and an added unit, both with a **name node** (a `DEF…` / `DEFINE-…` / `defmethod` head, also under a `#-` guard; not `in-package`, anonymous forms or `#+` units), whose texts are `string=` once the **name node's text** is cut out of each (so: the same definition operator, the same body and comments, a different name). Removed units in a's order each take the first unused match in b's order. `from` = `(:form OLD)`, `path` = `(:form NEW)`, footprint `("lisp:/OLD" "lisp:/NEW")`. A rename that also changes the body is a remove and an add.
- **Anchors** (what makes apply and invert exact):
  - `after.anchor` of an `:add` / `:move` = the unit's predecessor in b.
  - `before.anchor` of a `:remove` = its predecessor in a.
  - `before.anchor` of a `:move` = the unit right before it in the state it moves from (the apply order simulated); NIL if none. The inverse puts it back exactly there, so every later inverse change sees the state the forward one left. (0.1.0 used the nearest predecessor in a that is stable or moved later in b's order, which skips an added unit in between and shifts ordinals for later inverse changes.)
- **Order** (`apply-diff` applies in list order): removes in **descending** a order; then adds and moves in **b's order**; then modifies in b's order. Inverse = reversed (diff-protocol rule), which keeps every anchor valid.

### Nested changes

A `:modify` of a unit has **children** when the unit's text before its head and after its head are identical on both sides and the two head nodes have the **same shape**. Two expression nodes have the same shape when they have the same node kind, the same number of children (trivia included), trivia children at the same positions, and identical **gaps** (all text of the node not covered by an expression child: delimiters, whitespace, comments). Then for each expression child pair, by index `i`: equal text → nothing; same shape → recurse; otherwise a leaf. A **leaf** is a `:modify` with path `(:form KEY i1 i2 …)`, footprint `"lisp:/KEY/i1/i2"`, `before` / `after` the node texts. Leaves are listed in node order (depth first).

So an edit of a literal, a call, a docstring or an argument list is a leaf; adding or removing a body form, re-indenting, or editing a comment changes the gaps or the child count and the leaf is the smallest list that contains it (the whole unit when that is the head). A `#+x` unit is skipped input under the empty feature list (no expression children), so its changes are always form level; a `#-x` unit has children (`1` = the guarded form).

### Levels

| Level | `diff-changes` |
|-------|----------------|
| `:summary` | form-level changes, before / after as **thunks** not forced by `compute-diff`, no children |
| `:content` | form-level changes; a `:modify` with nested leaves carries them as `children` |
| `:changes` | the leaves: each form-level change without children, and the nested leaves in place of their `:modify` |

Equal sources → an empty diff at every level.

## Apply

States are strings; each change re-reads the current state (unclean → `lisp-source-unreadable`, non-string → `unsupported-content`) and finds its unit **by key**, so a change applies to any state where its unit still looks as it did — other forms may have moved, changed or appeared.

| Change | Needs | Does |
|--------|-------|------|
| `:modify` / `:remove` (form) | unit present (`:missing`), text `string=` before's text (`:before-mismatch`, actual = the unit text found) | replace its text / drop it |
| `:add` | key absent (`:exists`, actual = that unit's text); anchor present unless NIL (`:missing`) | insert right after the anchor (NIL → at the start) |
| `:move` | `from` present with before's text; new key absent unless it equals `from` (`:exists`); anchor present | take the unit out, insert after's text after the anchor |
| leaf | unit present and `node-forms` path reachable (`:missing`); node text `string=` before (`:before-mismatch`, actual = node text) | replace that node's text |

- 0.2.0: a state the engine itself just returned (found by identity, `EQ`) keeps the units that change placed instead of being re-cut. Re-cutting an intermediate state can move a comment onto a unit with no final newline and break a later change's before check.
- 0.2.0, anonymous units: a unit found by key whose text differs (or a key not found) is looked up by text among the anonymous units of the same base; an `:add` / `:move` onto a key held by an anonymous unit of the same base is not `:exists` (the new one shifts the ordinals of those after it).
- Restarts are diff-protocol's: `skip-change`, `use-value`, `abort` around every change (including `lisp-source-unreadable` from an unclean state). `use-value V`: for a leaf, V is node text put at its path; for a form-level change, V is a unit text put at its key — replacing the unit when present, else inserted after the change's anchor (after's, then before's) when that is present, else at the end of the file before the `"eof"` unit.
- `invert-diff` (diff-protocol default): kinds swap, plists swap, order reversed, `:summary` laziness kept. `compose-diffs` = concatenation.

## Three-way merge

`three-way-diff engine base ours theirs` → `(values merged-diff conflicts)`; `merged-diff` is `(compute-diff engine base merged-text :level :changes)`, so it applies to `base`.

1. Form-level changes (`:content`) of `base→ours` and `base→theirs`. A change **touches** its key and, for a move, its `from` key.
2. Every pair (ours change, theirs change) touching a common key:
   - **identical** — same kind, path, from, after text, and for an add / move the same after-anchor → kept once (a **twin**);
   - a **pure reorder** (a `:move` with `from` = `path` and before text = after text) against a **`:modify`** → both apply (the form moves and gets the new text);
   - anything else → a **conflict**: modify / modify with different texts (also a comment edit against a body edit, nested or not), modify / remove, add / add with different text, rename / anything on its old or new key, two different moves of one form.
3. Conflicting changes leave the merge: the key keeps its **base** unit (or stays absent for add / add).
4. The merged text, from the non-conflicting changes of both sides: removed keys (removes, renames' old keys) drop out; a unit's text is the modifying side's (a twin's), else the positioning side's, else base's.
   - **Skeleton** = base units, in base order, that are neither removed nor positioned (added / moved) by a kept change.
   - Each side's positioned units form **runs**: walking the side's own file, a positioned unit joins the run of the last skeleton key seen before it (NIL = file start). A twin is positioned by both sides.
   - Output: the run at NIL, then each skeleton unit followed by its runs. When both sides have a run at the same place, the run whose key list sorts first (element by element with `string<`, a proper prefix first) goes first; a key that appears twice (a twin) keeps its first occurrence. The `"eof"` unit always ends the file.
5. **Conflicts** (`diff-conflict`, data): one per conflicting pair, `conflict-ours` / `conflict-theirs` = the form-level changes (`:content` level, with children), `conflict-footprint` = their footprints, deduped, `string<`.

Properties (suite): symmetric in ours / theirs (same merged text, same conflict footprints); one side equal to base, or both sides equal → the other side, no conflicts; two sides appending different forms at the same place → no conflict.

**Rebase:** `rebase-diff d onto base` = the merge above with every conflict resolved to **onto** (its change kept, `d`'s dropped); result = `(compute-diff engine onto-state merged)` — applies to `(apply-diff base onto)`. Conflicts as data, `conflict-ours` from `d`.

## Render

- `:summary` / `:sexp` — diff-protocol's renders, unchanged (`A lisp:/defun c`, `M lisp:/defun a/3/2`). `parse-diff :sexp` rebuilds an applicable diff (engine via `find-diff-engine :lisp`).
- `unified-patch base diff &key path (context 3)` — the unified diff of `base` → `(apply-diff base diff)`, rendered by diff-protocol (`:text` engine hunks with `:context`, `render-diff :unified`). Without `path`: bare `@@` hunks (`parse-diff :unified` → a text diff that applies to `base`). With `path`: `--- a/PATH` and `+++ b/PATH` first (`parse-diff :unified` → a tree diff; also what `patch -p1` / `git apply` take). Every level of the same diff gives the same patch. `render-diff … :unified` on a `:lisp` diff stays diff-protocol's `unsupported-content` (it has no base text).

## Under the tree engine

`(make-instance 'tree-diff-engine :leaf-engines '((:text . :text) (:lisp . :lisp)))` with `(make-tree-file content :type :lisp)`: leaf paths nest as `("src" "r.lisp" :form "defun a" 3 2)`, footprints splice to `"lisp:/src/r.lisp/defun a/3/2"`, apply / invert / three-way per file go through this engine (tree conflicts on one file carry the form-level footprint plus `"tree:/src/r.lisp"`). The tree's `:unified` render shows `:lisp` files as hunks since 0.2.1 (diff-protocol 0.3.0 `render-unified-content`, [diff-protocol#7](https://github.com/egao1980/diff-protocol/issues/7) closed, diff-backend-lisp-source#3). When the tree diff carries the file contents (`:summary`, `:content`), it renders the `:text` engine's line hunks, the same ones `unified-patch` gives. At `:changes` level it carries neither side, so it renders one section per change, `@@ lisp:/… @@` with the unit or node texts. That form is for reading; for `patch` / `git apply`, use `unified-patch` with the base text. The engine registers with `register-diff-engine` and specializes the exported hooks (`apply-change`, `put-value`, `merge-states`, `rebase-states`).

## Conditions and restarts

| Condition | Parent | Slots (readers) | Signalled by | Restarts |
|-----------|--------|-----------------|--------------|----------|
| `lisp-source-unreadable` | `diff-protocol:unsupported-content` (engine, content) | `lisp-source-unreadable-diagnostics`: lisp-source-protocol `:error` diagnostics and imbalances | `compute-diff`, `three-way-diff`, `rebase-diff`, `source-units`; `apply-diff` on an unclean state | `compute-diff`: **`use-text-diff`** (→ the `:text` engine's diff of the same strings at the same level), `use-value` (→ that value). `three-way-diff`: `use-text-diff` (→ the `:text` engine's diff3 result), `use-value`. In `apply-diff`: diff-protocol's `skip-change` / `use-value` / `abort` |
| `diff-protocol:unsupported-content` | — | — | a non-string state; an `opaque-change` in `apply-diff` | apply-diff's restarts |
| `diff-protocol:apply-conflict` | — | reason `:missing` `:exists` `:before-mismatch`, actual | `apply-diff` | `skip-change`, `use-value`, `abort` |

`use-text-diff` is exported as a restart name and a function `(use-text-diff &optional condition)` that returns NIL when no such restart is active, like `continue` and diff-protocol's `skip-change`. `read-time-eval-refused` (a non-error signal of lisp-source-protocol for each `#.`) is declined: it never reaches the caller as an error.

## Laws and acceptance

- diff-protocol laws for every level over a deterministic random corpus (a pool of units with variants: edits inside forms, comment edits, renames, `#+` / `#-`, `#.`, an unknown package, block comments; shuffled; optional header and trailer): apply, invert, empty, compose (and associativity on the result), three-way symmetry, one side unchanged, both equal, rebase applies.
- **The workspace's own history** (fixtures committed byte for byte from git): lisp-source-protocol `src/indent.lisp` (3 revisions), `src/edit.lisp` (3), `src/reader.lisp`, `src/package.lisp`, diff-protocol `src/ops.lisp` (R0 → R1). Per pair: units concatenate to the file, apply / invert at every level, `:sexp` round trip, `unified-patch` applies, every unit of the new side (comments included) is in the result, exact `:summary` renders. Real concurrent edits: lisp-source-protocol PR #6 and PR #7, both from `indent.lisp`@caf719c, merge with no conflicts into the real `indent.lisp`@3b71bca, and rebase to the same file.
- CRLF sources, `#!` headers, unknown packages, `#.(error …)` (never runs), host `*features*` with and without `:sbcl` / `:win32` (same result).

## Out of scope (R3)

- Merging two edits **inside** one form (nested three-way); a textual fallback inside a conflicting form (callers can run the `:text` engine on the two unit texts).
- Conflict markers in a merged file (`merge-sources` / a git merge driver) — V-track, on top of `conflict-ours` / `conflict-theirs`.
- Descending into top-level `progn` / `eval-when` / `locally` for identity (they are one unit keyed by the operator). (Anonymous forms are matched by content since 0.2.0.)
- Move detection for nested forms; similarity-based renames; renames of a body that also references the old name.
- Recovery-based diffs of files that do not read clean (use `use-text-diff`).
- `render-diff :unified` on a `:lisp` diff without a base; `:lisp` leaves in the tree engine's `:unified` render.
- A `serdes-protocol` adapter, `defspec` model.

## Follow-ups

- [diff-protocol#6](https://github.com/egao1980/diff-protocol/issues/6): export the engine SPI (`%apply-change`, `%put-value`, `%three-way`, `%rebase`, `%register-engine`) for engines that live in other repos.
- [diff-protocol#7](https://github.com/egao1980/diff-protocol/issues/7) (done in diff-protocol 0.3.0; used from 0.2.1): render non-`:text` leaves with a text form (`:lisp`) in the tree engine's `:unified` output.

## Implementation tasks

- [x] Brief — this doc
- [x] Contract: `egao1980/diff-backend-lisp-source` skeleton, stubs, `diff-backend-lisp-source/tests`, real history fixtures (prototype-checked: the suite passes against a throwaway implementation)
- [ ] team-solve R3
- [ ] GHCR publish 0.1.0; QUICKSTART pin

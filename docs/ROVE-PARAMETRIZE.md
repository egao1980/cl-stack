# Rove `deftest-parametrize` design

**Upstream PR:** [fukamachi/rove#76](https://github.com/fukamachi/rove/pull/76)  
**Fork:** [egao1980/rove](https://github.com/egao1980/rove) (`cursor/parametrize-3a7a`)  
**Issues:** cl-stack #7 / #27 / #28

## Goal

One test body × many input rows (pytest/JUnit parametrize shape), without forking Rove's runner model.

## Contribution constraints (kept for upstream)

- Expands to plain `deftest` only — no private Rove APIs.
- Package-inferred file `rove/core/parametrize` + reexport from `rove/main` (matches existing layout).
- No version bump in the PR (maintainer chooses).
- README documents the API without coupling to cl-stack.

## API

```lisp
(deftest-parametrize name
    ((var*) [:ids ids] [:rows form] row*)
  body…)
```

| Piece | Meaning |
|-------|---------|
| `var*` | symbols bound in `body` |
| `row` | value list (or bare atom for a single var) |
| `:ids` | per-row name suffixes → `NAME/ID` (else `NAME/0`…) |
| `:rows` | load-time form → list of rows (still registers via `deftest`) |

Hooks, reporters, and `run-test` see normal per-row tests.

## Non-goals (later gaps)

Nested parametrize, fixture injection, markers — see [ROVE-GAPS.md](ROVE-GAPS.md).

## Pin

Until upstream merges: pin `github egao1980/rove` (branch or post-merge master).
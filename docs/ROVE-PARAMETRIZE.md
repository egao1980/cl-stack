# Rove `deftest-parametrize` design

**Upstream:** [fukamachi/rove](https://github.com/fukamachi/rove)  
**Fork:** [egao1980/rove](https://github.com/egao1980/rove)  
**Issues:** cl-stack #7 / #27 / #28

## Goal

pytest `mark.parametrize` / JUnit parameterized tests — one body, many input rows — so corpus ports can be tables of vectors without copy-paste `deftest`s.

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
| `:rows` | load-time form → list of rows (dynamic tables) |

Expands to N independent `deftest` registrations (hooks / reporters / `run-test` work unchanged).

## Non-goals (later gaps)

Nested parametrize, fixture injection, markers — see [ROVE-GAPS.md](ROVE-GAPS.md).

## Pin

Until upstream merges: qlfile / cl-repo pin `github egao1980/rove` (or OCI republish once packaged).

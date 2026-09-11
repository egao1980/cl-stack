# Rove gaps (dogfood)

Stack runner is [fukamachi/rove](https://github.com/fukamachi/rove). Gaps vs pytest / JUnit → fork [`egao1980/rove`](https://github.com/egao1980/rove) → upstream PR. No framework hop.

Design note: [ROVE-PARAMETRIZE.md](ROVE-PARAMETRIZE.md). Module backlog: [STDLIB-MODULES.md](STDLIB-MODULES.md).

| Gap (vs Py/Java) | Status | Issue / PR |
|------------------|--------|------------|
| Parametrize / data-driven | **upstream PR** (`deftest-parametrize`) | #7 · #27 · #28 · [fukamachi/rove#76](https://github.com/fukamachi/rove/pull/76) · [fork#1](https://github.com/egao1980/rove/pull/1) |
| Fixtures / scoped setup | **shipped** (`deffixture` / `with-fixture`; `:test` / `:suite` / `:session`) | fork 0.10.2 |
| Markers / subset select | **shipped** (`deftest` `:marks` + `run` `:marks`) | fork 0.10.2 |
| JUnit XML / structured report | **shipped** (`:style :junit` + `:junit-file`) | fork 0.10.2 |
| Per-test timeout | **shipped** (`:timeout` / `*default-test-timeout*`) | fork 0.10.2 |
| Pretty failure diffs | **shipped** (`equal` / `equalp` / `string=` / `=` / `eql`) | fork 0.10.2 |
| Parallel (or CI sharding first) | **shard shipped** (`:shard` / `:shards`); process-parallel still later | fork 0.10.2 |

Update this table when filing Rove-gap issues.

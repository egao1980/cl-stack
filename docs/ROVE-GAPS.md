# Rove gaps (dogfood)

Stack runner is [fukamachi/rove](https://github.com/fukamachi/rove). Gaps vs pytest / JUnit → fork [`egao1980/rove`](https://github.com/egao1980/rove) → upstream PR. No framework hop.

Design note: [ROVE-PARAMETRIZE.md](ROVE-PARAMETRIZE.md). Module backlog: [STDLIB-MODULES.md](STDLIB-MODULES.md).

| Gap (vs Py/Java) | Status | Issue / PR |
|------------------|--------|------------|
| Parametrize / data-driven | **upstream PR** (`deftest-parametrize`) | #7 · #27 · #28 · [fukamachi/rove#76](https://github.com/fukamachi/rove/pull/76) · [fork#1](https://github.com/egao1980/rove/pull/1) |
| Markers / subset select | **upstream PR** (`deftest` `:marks` + `run` `:marks`) | [fukamachi/rove#77](https://github.com/fukamachi/rove/pull/77) · fork 0.10.2 |
| Per-test timeout | **upstream PR** (`:timeout` / `*default-test-timeout*`) | [fukamachi/rove#77](https://github.com/fukamachi/rove/pull/77) · fork 0.10.2 |
| Parallel (or CI sharding first) | **upstream PR** (`:shard` / `:shards`); process-parallel still later | [fukamachi/rove#77](https://github.com/fukamachi/rove/pull/77) · fork 0.10.2 |
| JUnit XML / structured report | **upstream PR** (`:style :junit` + `:junit-file`) | [fukamachi/rove#78](https://github.com/fukamachi/rove/pull/78) · fork 0.10.2 |
| Pretty failure diffs | **upstream PR** (`equal` / `equalp` / `string=` / `=` / `eql`) | [fukamachi/rove#78](https://github.com/fukamachi/rove/pull/78) · fork 0.10.2 |
| Fixtures / scoped setup | **upstream PR** (`deffixture` / `with-fixture`; `:test` / `:suite` / `:session`) | [fukamachi/rove#79](https://github.com/fukamachi/rove/pull/79) · fork 0.10.2 |

Update this table when filing Rove-gap issues.

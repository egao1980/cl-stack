# Rove gaps (dogfood)

Stack runner is [fukamachi/rove](https://github.com/fukamachi/rove). Gaps vs pytest / JUnit → fork [`egao1980/rove`](https://github.com/egao1980/rove) → upstream PR. No framework hop.

Design note: [ROVE-PARAMETRIZE.md](ROVE-PARAMETRIZE.md).

| Gap (vs Py/Java) | Status | Issue / PR |
|------------------|--------|------------|
| Parametrize / data-driven | **implemented on fork** (`deftest-parametrize`, 0.11.0) | #7 · #27 · #28 · [egao1980/rove#1](https://github.com/egao1980/rove/pull/1) · [upstream#76](https://github.com/fukamachi/rove/pull/76) |
| Fixtures / scoped setup | backlog | |
| Markers / subset select | backlog | |
| JUnit XML / structured report | backlog | |
| Per-test timeout | backlog | |
| Pretty failure diffs | backlog | |
| Parallel (or CI sharding first) | backlog | |

Update this table when filing Rove-gap issues.

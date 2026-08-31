# Conditions / restarts (P2)

**Issues:** [#107](https://github.com/egao1980/cl-stack/issues/107)  
**Status:** cookbook **shipped** — teach CLHS 9; do **not** wrap it away. Cookbook: [conditions.md](../cookbooks/conditions.md)

The language **is** the library. First-party stack code signals conditions and offers restarts. Status-code returns and Java-style wrap-and-rethrow are not the failure path.

Conventions: [API.md](../API.md). Gap: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Signal** | `error` / `cerror` / `signal` / `warn`. Protocol owns the types; backends signal them. |
| **Names** | CLHS first: `use-value`, `store-value`, `continue`, `abort`, `muffle-warning`. ASDF `retry` at the **operation** boundary. |
| **Policy** | `handler-bind` above the primitive. `handler-case` only to unwind / translate. |
| **Wire codes** | Slots on the condition. Bind on **type**, not integers. |
| **Sugar** | `invoke-*` / `with-auto-*` (pathlib, …) are optional `find-restart` wrappers — not a second protocol. |
| **No library** | No stack conditions utility. CLHS + Alexandria + UIOP are enough. |

Prior art to match when adding: pathlib (domain restarts at the signal site + `retry` at the op site); HTTP (taxonomy + urllib3 retry **policy object**, not a restart); process (timeout condition); schema (per-field `use-value`).

---

## Non-goals

- A `cl-stack-conditions` ASDF system
- Replacing CLHS restart functions with private `invoke-use-value` as the advertised API
- Catch-all `error` in backends to “keep the server up”

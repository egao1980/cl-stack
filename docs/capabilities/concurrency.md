# Concurrency (bordeaux-threads / bt2)

**Issues:** [#95](https://github.com/egao1980/cl-stack/issues/95)  
**Status:** pin **locked** — Bordeaux-Threads **v0.9.4** (bt2 API)

Portable threads default for the stack. Actor frameworks / lparallel = later optional.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Default | **[bordeaux-threads](https://github.com/sionescu/bordeaux-threads)** `v0.9.4` → OCI `0.9.4` |
| API | **bt2** (`bordeaux-threads:make-thread`, locks, condition variables, atomics where provided) |
| Transitives | `global-vars`, `trivial-garbage`, `alexandria`, `trivial-features` (all on GHCR) |
| Non-goal | lparallel bakeoff, actor runtime |

---

## DX

```lisp
(cl-repo:load-system "bordeaux-threads" :version "0.9.4")
(bt2:make-thread (lambda () …) :name "worker")
```

Package nick / API is the upstream **bt2** surface shipped by 0.9.x.

Import: `cl-stack-systems/imports/bordeaux-threads` (+ `global-vars`, `trivial-garbage`).

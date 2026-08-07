# event-protocol (wave-1)

**Issues:** [#2](https://github.com/egao1980/cl-stack/issues/2) · [#13](https://github.com/egao1980/cl-stack/issues/13) · [#14](https://github.com/egao1980/cl-stack/issues/14)  
**Status:** brief locked; `#15`–`#17` done (libuv/libev backends + OCI overlays + clean-container smoke); `#18` conformance lives in this repo + backend CI

Pluggable event loops (asyncio policies / NIO `SelectorProvider` shape). One app-level async DX; multiple native backends behind `event-protocol`.

Conventions: [API.md](../API.md). Overlay shipping: [overlays.md](../overlays.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **App-level async DX** | **Promises** (Blackbird-shaped) | Compose HTTP/WS like httpx; `attach`/`catcher`/`finally` map to conditions; await-macros = P2 sugar later |
| **Protocol primitive** | Callbacks + cancel tokens | Backends stay thin; promises wrap protocol ops in the facade |
| **Default backend (A)** | **libuv** | **Windows is primary** (IOCP, same as Node); also linux/darwin; matches OpenSSL overlay story |
| **Second backend (B)** | **libev** | Woo/Clack server stack; **Unix-only** (libev has no Windows) |
| **ABCL backend (C)** | **NIO `Selector`** | JVM-native; no JNA/libuv. Repo: `event-backend-nio`. Pair with `http-backend-java` |
| **Not wave-1 second** | iolib | Unix/epoll-strong, weaker Windows + less Woo reuse; revisit P2 |
| **CFFI grovel** | Overlay build time | Grovel on CI/builder per os/arch; ship `cffi-grovel-output` → `grovel-cache/`. Consumers need no C toolchain (incl. Windows). |
| **Loop affinity** | One loop per thread; ops on “current” loop | Cross-thread schedule via notifier/wake (backend-specific) |
| **Selection DX** | ASDF system + pin / `*event-backend*` | Default pin loads A; apps swap with `asdf:load-system` + bind special (no plugin DSL) |

---

## Backend scorecard (#14)

Scores: **1** (poor) … **5** (excellent) for wave-1 cl-stack needs.

| Criterion | libuv (+ cl-async lineage) | libev (+ Woo) | iolib |
|-----------|----------------------------|---------------|-------|
| Platform coverage (win+linux+darwin) | **5** (IOCP) | **3** (POSIX-only) | **2** (Unix-centric) |
| Overlay pain (ship `.so`/`.dylib`/`.dll` + grovel) | **4** | **4** (no win row) | **5** |
| Existing CL stack fit | **4** (cl-async, drivers, blackbird) | **5** (Woo = de-facto fast server) | **3** (Conserv/teepeedee2 niche) |
| Maintenance / liveliness | **3** (mature, slower churn) | **4** (Fukamachi ecosystem active) | **3** |
| Windows (primary) | **5** | **1** (unsupported) | **1** |
| Conformance surface (timers/IO/wake) | **5** | **4** | **3** |
| **Wave-1 role** | **Default (A)** | **Second (B)** | Stretch / not B |

**Woo coupling:** Backend B does **not** require running Woo. We use libev (and optionally patterns from Woo’s ev bindings) so a future Clack/Woo deploy shares the same native overlay. HTTP client async (#31) targets `event-protocol`, not Woo’s accept loop.

**Implementation note:** Prefer thin `event-backend-libuv` / `event-backend-libev` that CFFI the C APIs (or wrap the minimal subset of cl-async / lev). Do **not** force the entire cl-async driver zoo into the protocol system.

**Repo layout (locked):** one GitHub project per layer — not colocated under `event-protocol`.

| Layer | Repo |
|-------|------|
| Protocol + shared conformance suite | [`egao1980/event-protocol`](https://github.com/egao1980/event-protocol) |
| Default backend A | [`egao1980/event-backend-libuv`](https://github.com/egao1980/event-backend-libuv) |
| Second backend B (Unix) | [`egao1980/event-backend-libev`](https://github.com/egao1980/event-backend-libev) |
| ABCL / JVM (C) | [`egao1980/event-backend-nio`](https://github.com/egao1980/event-backend-nio) |

---

## Async DX (#13)

### Chosen: promises

Facade returns **promises** (resolve / reject). Rejected promises signal or carry `event-error` conditions (see below).

```lisp
;; illustrative — final names in event-protocol / cl-stack/event
(event:run
  (lambda ()
    (bb:attach (event:sleep 0.1)
      (lambda (_)
        (bb:attach (http:get-async "https://example.com")
          (lambda (res) (print (http:status res))))))))
```

Blackbird (or a protocol-local promise type with the same shape) is the wave-1 pin for composition macros (`alet*`, `catcher`, `finally`). Protocol code must not hard-depend on Blackbird internals — only the facade.

### Rejected alternatives

| Option | Why not for wave-1 app DX |
|--------|---------------------------|
| Raw callbacks only | Hostile for HTTP/WS composition; still OK *inside* backends |
| await-macro / delimited continuations | Powerful but impl-fragile; add as P2 sugar over promises |
| Green threads only (Bordeaux + block) | Wrong concurrency model for 10k sockets; can coexist later |

---

## Protocol surface

Tiny ASDF system `event-protocol`: generics, conditions, value types. Almost no deps.

### Types

| Type | Role |
|------|------|
| `event-loop` | Opaque loop handle bound to a backend |
| `event-handle` | Cancelable registration (timer, IO, idle, signal) |
| `event-backend` | Class; specialize methods |

### Dynamics

| Symbol | Role |
|--------|------|
| `*event-backend*` | Current backend object (required when running) |
| `*event-loop*` | Current loop (bound inside `run`) |

### Generics (minimum)

```lisp
(defgeneric backend-name (backend))           ; "libuv" | "libev" | …
(defgeneric make-event-loop (backend &key))
(defgeneric run (backend loop &key stop-when-idle))
(defgeneric stop (backend loop))

(defgeneric defer (backend loop function &key))           ; next tick
(defgeneric call-soon (backend loop function &key))       ; alias / alias policy
(defgeneric sleep* (backend loop seconds &key))           ; → promise in facade; handle at protocol
(defgeneric cancel (backend handle))

;; IO interest — gray-stream / fd based; exact FD type backend-defined
(defgeneric register-io (backend loop fd direction callback &key))
;; direction: :read | :write | :read-write

(defgeneric wake (backend loop))              ; cross-thread: schedule on loop thread
```

Facade (`cl-stack/event` later) wraps these with keywords + promises:

```lisp
(event:with-loop () …)           ; make + run + unwind
(event:sleep 1.0)                ; → promise
(event:defer #'fn)
(event:cancel handle)
```

### Conditions

| Condition | When |
|-----------|------|
| `event-error` | Base |
| `event-loop-error` | Loop crashed / already running |
| `event-canceled` | Handle canceled before fire (optional restart: `ignore`) |
| `event-io-error` | Registration / fd failure |
| `unsupported-operation` | Backend missing a method |

Restarts (where useful): `retry`, `abort-loop`, `use-value` (for sleep/defer results in tests).

### Threading rules

1. **Affinity:** callbacks run on the loop thread.
2. **Foreign threads** must use `wake` / `defer` to enter the loop (never touch libuv/libev handles off-thread).
3. Protocol tests may use a single-threaded model only for wave-1 conformance (#18).

---

## Backend selection DX

```lisp
;; default pin (cl-stack / qlfile / cl-repository lock)
;;   event-backend-libuv

(asdf:load-system "event-backend-libuv")
(let ((*event-backend* (make-instance 'libuv-backend)))
  (event:with-loop () …))

;; swap for conformance / Woo-adjacent deploy
(asdf:load-system "event-backend-libev")
(let ((*event-backend* (make-instance 'libev-backend)))
  (event:with-loop () …))
```

No central plugin registry. Metapackage (#21) may depend on the default backend only.

---

## Overlay plan (feeds #16 / #17)

| Backend | Native | GHCR (planned) | Matrix |
|---------|--------|----------------|--------|
| A libuv | `libuv` + grovel | `ghcr.io/egao1980/cl-systems/event-backend-libuv:<ver>` | linux/amd64+arm64, darwin/arm64, **windows/amd64** |
| B libev | `libev` + grovel | `ghcr.io/egao1980/cl-systems/event-backend-libev:<ver>` | linux/amd64+arm64, darwin/arm64 (**no Windows**) |

Same overlay policy as OpenSSL ([overlays.md](../overlays.md)): `native-library` + `cffi-grovel-output` per os/arch. Grovel runs on the builder only.

---

## Implementation order

1. `#15` — `event-protocol` generics + conditions (no natives) — **Done** (PR merged)
2. `#16` — libuv backend + overlay + smoke → repo `event-backend-libuv`
3. `#17` — libev backend + overlay + smoke → repo `event-backend-libev`
4. `#18` — shared Rove suite in `event-protocol/conformance`; backends set `*test-backend-maker*`

HTTP async (#31) and WSS (#35) **depend on** `#15`+`#16` at minimum.

---

## Out of scope (wave-1)

- Full cl-async driver set (DNS/HTTP/redis/…) inside protocol
- await-macro / delimited continuations
- iolib as a shipped backend
- Multi-loop-per-process orchestration

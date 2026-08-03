# cl-stack pins + channels

**Issues:** [#5](https://github.com/egao1980/cl-stack/issues/5) · [#19](https://github.com/egao1980/cl-stack/issues/19) · [#20](https://github.com/egao1980/cl-stack/issues/20) · [#21](https://github.com/egao1980/cl-stack/issues/21)  
**Status:** pin format + channel policy **locked** (#19/#20); metapackage `#21` open

Anaconda-style **curated set** of systems on `ghcr.io/egao1980/cl-systems`, installed via [`cl-repository`](https://github.com/egao1980/cl-repository). This hub documents the pin file; runtime resolution is `cl-repository-client`.

Related: [overlays.md](overlays.md), [LICENSE-POLICY.md](LICENSE-POLICY.md).

---

## Pin file format (`cl-stack.pins`)

**Format:** S-expression (same family as `cl-repo.lock`). One file per channel/profile.

```lisp
;;; cl-stack.pins — curated stack pin (hand-edited or released)
((:pin-format 1)
 (:channel :stable)                         ; or :edge — see Channels
 (:registry "https://ghcr.io" :namespace "egao1980/cl-systems")
 (:defaults
  :event-backend "event-backend-libuv"      ; Windows-primary default
  :http-backend "http-backend-dexador"      ; sync default
  :http-async-backend "http-backend-async"
  :ws-backend "ws-backend-websocket-driver") ; when #34 lands
 (:systems
  ;; name version &optional :digest "sha256:…"
  ("alexandria" "1.0.1")
  ("cffi" "677cabae64b181330a3bbbda9c11891a2a8edcdc")
  ("cl-idna" "0.1.0")
  ("quri" "0.7.1")
  ("http-protocol" "0.1.0")
  ("http-encoding-chipz" "0.1.0")
  ("http-backend-dexador" "0.1.0")
  ("http-backend-async" "0.1.0")
  ("event-protocol" "0.1.0")
  ("event-backend-libuv" "0.1.0")
  ("cl-stack-ssl" "3.4.1")
  ;; Unix-only second event backend — omit on Windows consumers
  ("event-backend-libev" "0.1.0" :platforms (:unix))))
```

### Rules

1. **Versions** are OCI tags under `ghcr.io/egao1980/cl-systems/<name>:<version>`.
2. Optional **`:digest`** pins the index/manifest digest (reproducible CI). Prefer digests on `:stable`.
3. **`:platforms`** filters install (`:unix` = linux+darwin; `:windows`; or explicit os/arch lists). Default = all wave-1 platforms for that artifact.
4. **`:defaults`** are advisory for facades / metapackage — apps still bind `*http-backend*` / `*event-backend*`.
5. Pins **do not** replace native overlay selection — overlays resolve via cl-repository platform match ([overlays.md](overlays.md)).

### Minimal / empty example

```lisp
;;; tests/fixtures/minimal.pins — smoke only
((:pin-format 1)
 (:channel :edge)
 (:registry "https://ghcr.io" :namespace "egao1980/cl-systems")
 (:defaults :event-backend "event-backend-libuv")
 (:systems
  ("alexandria" "1.0.1")
  ("event-protocol" "0.1.0")
  ("event-backend-libuv" "0.1.0")))
```

Ship real release pins under `pins/stable.pins` / `pins/edge.pins` when `#21` metapackage lands.

---

## Relationship to `cl-repo.lock`

| Artifact | Owner | Role |
|----------|-------|------|
| **`cl-stack.pins`** | cl-stack (this repo) | Curated **intent**: which systems+channels the stack endorses |
| **`cl-repo.lock`** | app / CI (cl-repository-client) | **Resolved** install: digests, overlay digests, registry URLs |

Workflow:

1. Start from a published `cl-stack.pins` (stable or edge).
2. `cl-repo:add-registry` + install each pin entry (or future `cl-repo:restore-pins`).
3. Client writes / updates **`cl-repo.lock`** with concrete digests ([spec § Lockfile](https://github.com/egao1980/cl-repository/blob/main/docs/spec.md)).
4. Apps commit `cl-repo.lock` for bit-for-bit CI; bump pins when moving channels.

Pins may list only roots; the lock expands the full graph. Digests in pins, when present, must match the lock after resolve.

---

## Channels: `stable` vs `edge`

Anaconda analogy: **stable** = defaults users should get; **edge** = newest stack commits still expected to install.

| | `:stable` | `:edge` |
|---|-----------|---------|
| **Tag policy** | Semver / known-good OCI tags + digests | May track `latest` or moving minor tags |
| **When pins move** | Milestone / release PR on cl-stack; changelog blurb | Anytime a sibling lib publishes; hub pin PR may lag by hours |
| **Breakage** | Treat as regression | Allowed if CI on the publishing lib is green |
| **Default for metapackage (#21)** | **stable** | Opt-in profile |

### Versioning

- Library repos keep their own semver / git tags → OCI `:version`.
- Hub **pin revision** = git commit of `pins/*.pins` (or a dated `pins/stable-YYYY-MM-DD.pins`).
- Moving stable: open PR updating versions/digests; require green OCI consumer smoke (`cl-stack/oci-corpus` or successor).

### What qlot / ocicl are for

| Tool | Use in cl-stack world |
|------|------------------------|
| **cl-repository** | **Default** for apps/CI: GHCR systems + overlays |
| **qlot** | **Import / bootstrap only** — vendor QL graphs into `cl-stack-systems/imports/*` for republish; local lib development |
| **ocicl** | Optional alternate client; not the stack’s primary pin story |
| **`ros install`** | Not for project deps (MEMORY: cl-repository only) |

Never both fork **and** `cl-stack-systems` import for the same lib.

---

## Install sketch

```lisp
(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)
;; future: (cl-stack:apply-pins #p"pins/stable.pins")
;; today: install each (:systems) entry via install-system / load-system
(asdf:load-system "http-backend-dexador")
```

Clean-container E2E = `#22`.

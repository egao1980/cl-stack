# Multi-implementation CI matrix

Track: [cl-stack#42](https://github.com/egao1980/cl-stack/issues/42).

README markets **SBCL / ECL / ABCL**. Wave-1 CI remains **SBCL-required**; this doc is the matrix policy + local smoke notes as secondary impls land. **CCL** is strongly recommended and now locally proven.

## Tiers

| Tier | Impl | Role | OS (first) |
|------|------|------|------------|
| **Required gate** | **SBCL** | Full suite; merge blocker | linux + darwin + windows (per package claim) |
| **Required smoke** (README) | **ECL** | Load + Rove core; catch `#+` / FFI / pathname gaps | linux/amd64 first |
| **Required smoke** (README) | **ABCL** | Same; JVM pathname / classpath edges | linux/amd64 first |
| **Strongly recommended** | **CCL** | Cheap binary via Roswell `ccl-bin` on linux/amd64 | linux/amd64 |
| **Stretch (blocked)** | **CLISP** | Distro CLISP = no `:mt`; MT source bootstrap broken on clean Ubuntu 24.04 | — |
| **Stretch** | Clasp, … | Optional / `continue-on-error` until promoted | opportunistic |

Overlay natives stay **OS/arch** keyed. Use `lisp` / `dev.common-lisp.implementation` only for impl-specific compiled artifacts ([overlays.md](overlays.md)).

## Local smoke order (maintainer machine)

Prefer **Homebrew bottles** for a fast local probe when native; use **Roswell** for CI-shaped installs.

| Impl | Local (darwin/arm64, 2026-08) | Notes |
|------|-------------------------------|--------|
| **ECL** | `brew install ecl` → **26.5.5** | Ships ASDF **3.1.8.11**; `require :asdf` before any `asdf:…` at read time. Non-interactive: `ecl --norc --nodebug -q --load script.lisp`. |
| **CCL** | **No native arm64.** Official 1.13 = x86_64 only. | Local: download `ccl-1.13-darwinx86.tar.gz`, run `arch -x86_64 ./dx86cl64 --no-init --batch -l script.lisp`. Roswell `ccl-bin` **refuses arm64**. Homebrew `clozure-cl` deprecated (disable 2026-09-25). CI: `ros install ccl-bin` on **linux/amd64**. |
| **CLISP** | Brew + clean Ubuntu both fail Ironclad path | See **CLISP blocker** below (linux container results). |
| **ABCL** | `brew install abcl` (needs OpenJDK) | Not probed yet here (no JRE on this host). Next. |

### ECL pitfalls (agents / CI)

1. **Read-time packages:** `(asdf:…)` in the same `-eval` as `(require :asdf)` fails — split evals or use `--load` scripts.
2. **Debugger hang:** always `--nodebug` + `*debugger-hook*` → `si:quit 1` (same idea as SBCL `--disable-debugger`).
3. **Compile cost:** Ironclad on ECL is slow (C backend). First smoke ~minutes; cache FASLs help locally. Budget long GHA timeouts for ECL jobs.
4. **Comma in quoted lists:** `'(("x" :ql), ("y" :ql))` is a reader error (`Comma not inside a backquote`). Never paste JSON-style commas into `:sources`.

### CCL pitfalls (agents / CI)

1. **Roswell name is `ccl-bin`**, not `ccl`. `ros install ccl` fails; `ros install ccl-bin` works on **linux/amd64** and **darwin/x86_64** only — install script hard-errors on `arm64`.
2. **No Apple Silicon port** (upstream 1.13 release notes). Darwin local smoke = **Rosetta** (`arch -x86_64`) with Clozure’s `darwinx86` tarball (`dx86cl64`).
3. **Non-interactive:** `dx86cl64 --no-init --batch -l script.lisp`; quit with `(quit n)`. Use `*debugger-hook*` → `(quit 1)`.
4. **Rosetta cost:** PBKDF2 verify ~2 min each under Rosetta on M-series; native linux/amd64 CI should be far cheaper. Keep a generous `timeout-minutes` anyway.
5. ASDF on CCL 1.13 via QL path was **3.3.7** (healthier than brew ECL’s bundled 3.1.8).

### CLISP blocker (clean Linux + Darwin) — 2026-08-07

**Why Ironclad stacks care:** `ironclad` → `bordeaux-threads` → BT `.asd` errors `"This implementation is unsupported."` unless CLISP has feature **`:mt`** (`#+ (and clisp mt)`).

Configure flag is **`--with-threads=POSIX_THREADS`** (not `POSIX`). Upstream marks this **“highly experimental”**.

| Environment | Result |
|-------------|--------|
| Homebrew CLISP 2.49.92 (darwin/arm64) | Runs; **`MT=NIL`** → BT refuses |
| **Clean `ubuntu:24.04` container, linux/arm64** | Distro `clisp` **`PACKAGED_MT=NIL`**. Source `POSIX_THREADS` + `-DNO_GENERATIONAL_GC` (aarch64 has no fast spinlocks): **`lisp.run` links**, then **`interpreted.mem` bootstrap hangs** (0% CPU; killed after 180s). |
| **Clean `ubuntu:24.04` container, linux/amd64** | Distro **`PACKAGED_MT=NIL`**. Source `POSIX_THREADS` (x86 fast spinlocks): **`lisp.run` links**, bootstrap prints banner then **`SIGSEGV`** in GC (`handle_fault … Fault address = 0xa8`) while saving `interpreted.mem`. |

**Decision:** no `test-clisp` CI row. Not a `continue-on-error` red job — known upstream/bootstrap failure, not our code. Revisit only if a maintained MT-capable CLISP binary appears (or Ironclad drops the hard BT dep).

## Proven green (local)

### ECL 26.5.5 (Homebrew, native arm64) — 2026-08-07

| System | Result |
|--------|--------|
| `crypto-protocol` (protocol-only tests) | pass |
| `crypto-backend-ironclad` (full recipe/hazmat suite) | pass |
| `secrets-protocol` / `secrets-backend-os` | pass |

Method: Homebrew ECL + `~/quicklisp/setup.lisp` + `asdf:load-asd`.

### CCL 1.13 DarwinX8664 (Rosetta on arm64 host) — 2026-08-07

| System | Result |
|--------|--------|
| `crypto-protocol` | pass |
| `crypto-backend-ironclad` (incl. dual-backend / KDF) | pass |
| `secrets-protocol` | pass |

Method: Clozure release tarball + `arch -x86_64 ./dx86cl64 --no-init --batch`. Same QL + `load-asd` path. Duplicate-definition compile warnings seen on re-load; tests still green.

## CI recipe (sibling libs)

Keep the existing **SBCL × OS** job. Add **separate** linux/amd64 smoke jobs:

| Job | Install | Notes |
|-----|---------|--------|
| `test-ecl` | `ros install ecl` | Needs C toolchain (`build-essential`, libffi/gc/gmp). |
| `test-ccl` | `ros install ccl-bin` && `ros use ccl-bin` | Prebuilt; **ubuntu-latest (amd64) only**. |

Both reuse the same oras client pull + `scripts/ci-install.lisp` + `scripts/ci-test.lisp`.

Do **not** fold ECL/CCL into the Windows/macOS SBCL matrix until those runners are known-good for that impl.

Policy while ramping: ECL + CCL smoke are merge signals for crypto/secrets once green; other libs copy the fragment after their SBCL gate is solid. **ABCL next.** Track upstream-red separately (fail closed on *our* code only).

## Copyable workflow fragments

```yaml
  test-ecl:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
    timeout-minutes: 90
    steps:
      - uses: actions/checkout@v5
      - uses: oras-project/setup-oras@v2
        with:
          version: 1.2.3
      - name: Install Roswell
        shell: bash
        run: |
          curl -sL https://raw.githubusercontent.com/roswell/roswell/master/scripts/install-for-ci.sh | bash
          echo "$HOME/.roswell/bin" >> "$GITHUB_PATH"
      - name: Install ECL
        shell: bash
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends build-essential libffi-dev libgc-dev libgmp-dev
          ros install ecl
          ros use ecl
      # … same oras pull / QL client bootstrap / ci-install / ci-test as SBCL job …

  test-ccl:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5
      - uses: oras-project/setup-oras@v2
        with:
          version: 1.2.3
      - name: Install Roswell
        shell: bash
        run: |
          curl -sL https://raw.githubusercontent.com/roswell/roswell/master/scripts/install-for-ci.sh | bash
          echo "$HOME/.roswell/bin" >> "$GITHUB_PATH"
      - name: Install CCL
        shell: bash
        run: |
          ros install ccl-bin
          ros use ccl-bin
      # … same oras pull / QL client bootstrap / ci-install / ci-test as SBCL job …
```

## Done-when (from #42)

- [x] Documented impl matrix (this file) + link from overlays / README
- [ ] Hub or sibling CI runs Rove on **SBCL + ECL** (ABCL TBD) on linux/amd64 — ECL: crypto-protocol#4 merged; secrets/CCL PRs in flight
- [x] CCL job present (strongly recommended; linux/`ccl-bin`) — local Rosetta green; GHA fragment above
- [x] Known impl-specific failures tracked — **CLISP**: clean Ubuntu MT bootstrap hang (arm64) / SIGSEGV (amd64); packaged `MT=NIL`
- [x] Sibling-lib guidance copyable (fragments above)
- [ ] README claim matches CI reality

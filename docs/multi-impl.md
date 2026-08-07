# Multi-implementation CI matrix

Track: [cl-stack#42](https://github.com/egao1980/cl-stack/issues/42).

README markets **SBCL / ECL / ABCL**. Wave-1 CI remains **SBCL-required**; this doc is the matrix policy + local smoke notes as secondary impls land.

## Tiers

| Tier | Impl | Role | OS (first) |
|------|------|------|------------|
| **Required gate** | **SBCL** | Full suite; merge blocker | linux + darwin + windows (per package claim) |
| **Required smoke** (README) | **ECL** | Load + Rove core; catch `#+` / FFI / pathname gaps | linux/amd64 first |
| **Required smoke** (README) | **ABCL** | Same; JVM pathname / classpath edges | linux/amd64 first |
| **Strongly recommended** | **CCL** | Cheap once Roswell matrix exists | linux/amd64 |
| **Stretch** | CLISP, Clasp, … | Optional / `continue-on-error` until promoted | opportunistic |

Overlay natives stay **OS/arch** keyed. Use `lisp` / `dev.common-lisp.implementation` only for impl-specific compiled artifacts ([overlays.md](overlays.md)).

## Local smoke order (maintainer machine)

Prefer **Homebrew bottles** for a fast local probe; use **Roswell** for CI-shaped installs.

| Impl | Local (darwin/arm64, 2026-08) | Notes |
|------|-------------------------------|--------|
| **ECL** | `brew install ecl` → **26.5.5** | Ships ASDF **3.1.8.11**; `require :asdf` before any `asdf:…` at read time. Non-interactive: `ecl --norc --nodebug -q --load script.lisp`. |
| **ABCL** | `brew install abcl` (needs OpenJDK) | Not probed yet here (no JRE on this host). Next after ECL. |
| **CCL** | Homebrew `clozure-cl` **deprecated** (disable 2026-09-25) | Prefer `ros install ccl` when adding CCL row. |

### ECL pitfalls (agents / CI)

1. **Read-time packages:** `(asdf:…)` in the same `-eval` as `(require :asdf)` fails — split evals or use `--load` scripts.
2. **Debugger hang:** always `--nodebug` + `*debugger-hook*` → `si:quit 1` (same idea as SBCL `--disable-debugger`).
3. **Compile cost:** Ironclad on ECL is slow (C backend). First smoke ~minutes; cache FASLs help locally. Budget long GHA timeouts for ECL jobs.
4. **Comma in quoted lists:** `'(("x" :ql), ("y" :ql))` is a reader error (`Comma not inside a backquote`). Never paste JSON-style commas into `:sources`.

## Proven green (local ECL 26.5.5, 2026-08-07)

| System | Result |
|--------|--------|
| `crypto-protocol` (protocol-only tests) | pass |
| `crypto-backend-ironclad` (full recipe/hazmat suite) | pass |
| `secrets-protocol` / `secrets-backend-os` | pass |

Method: Homebrew ECL + `~/quicklisp/setup.lisp` + `asdf:load-asd` on checkout(s). Not yet the full cl-repository-client OCI path on ECL (follow-up: Roswell `ros install ecl` + same `ci-install`/`ci-test` scripts).

## CI recipe (sibling libs)

Keep the existing **SBCL × OS** job. Add a **separate** `test-ecl` job (linux/amd64 only) that:

1. Installs Roswell (Unix CI script).
2. `ros install ecl` && `ros use ecl` (needs C toolchain — present on `ubuntu-latest`).
3. Reuses the same oras client pull + `scripts/ci-install.lisp` + `scripts/ci-test.lisp`.

Do **not** fold ECL into the Windows/macOS SBCL matrix until those runners are known-good for ECL.

Policy while ramping: ECL smoke is a **merge signal** for crypto/secrets once the job is green; other libs copy the fragment after their SBCL gate is solid. ABCL next; track upstream-red separately (fail closed on *our* code only).

## Copyable workflow fragment

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
          ros install ecl
          ros use ecl
      # … same oras pull / QL client bootstrap / ci-install / ci-test as SBCL job …
```

## Done-when (from #42)

- [x] Documented impl matrix (this file) + link from overlays / README
- [ ] Hub or sibling CI runs Rove on **SBCL + ECL** (ABCL TBD) on linux/amd64
- [ ] CCL job present or explicitly deferred in this doc
- [ ] Known impl-specific failures tracked with issue links
- [ ] Sibling-lib guidance copyable (fragment above)
- [ ] README claim matches CI reality

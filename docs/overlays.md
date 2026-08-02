# Platform overlays (wave-1)

Ship native deps (OpenSSL, event-loop libs, CFFI grovel output) as **OCI platform overlays** via [`egao1980/cl-repository`](https://github.com/egao1980/cl-repository) — consumers install without a local C toolchain.

Normative packager/client behavior: [cl-repository `docs/spec.md`](https://github.com/egao1980/cl-repository/blob/main/docs/spec.md) (Platform Selection, media types, naming). This doc is the **cl-stack policy** layer: which platforms we ship, how we name GHCR artifacts, and when to pin ABI.

## Wave-1 platform matrix

| Status | OS | Arch | Builder notes |
|--------|----|------|----------------|
| **Required** | `linux` | `amd64` | GitHub-hosted Ubuntu runner |
| **Required** | `linux` | `arm64` | GitHub-hosted ARM Ubuntu runner |
| **Required** | `darwin` | `arm64` | Apple Silicon (e.g. `macos-14`); M4 self-hosted OK |
| **Required** | `windows` | `amd64` | Self-hosted Windows builder (maintainer machine / runner) |
| Stretch | `darwin` | `amd64` | Intel Mac runner if available |

CL implementation for wave-1 CI: **SBCL**. Overlays that are grovel/native-ABI only do **not** need a `:lisp` / `dev.common-lisp.implementation` pin (one overlay serves all impls on that OS/arch). Use `--lisp` only for impl-specific compiled artifacts.

## Overlay keys (`os` / `arch` / `os-version`)

cl-repository authoring keys (`.asd` `:platform`, `overlay-spec`, `cl-repo add-overlay`):

| Key | OCI field | Required | Examples |
|-----|-----------|----------|----------|
| `os` | `platform.os` | yes (overlays) | `linux`, `darwin`, `windows` |
| `arch` | `platform.architecture` | yes (overlays) | `amd64`, `arm64` |
| `os-version` | `platform.os.version` | optional | `ubuntu-22.04`, `ubuntu-24.04`, `macos-14`, `windows-11` |
| `lisp` | annotation `dev.common-lisp.implementation` | optional | `sbcl` |

> Workspace notes sometimes say `release` for the third dimension — the **wire/API name is `os-version`** (OCI `os.version`). Prefer that name in pins, docs, and CLI.

### When to set `os-version`

| Case | Policy |
|------|--------|
| Shared libs built on oldest supported glibc / macOS SDK, forward-compatible | Omit `os-version` — publish bare `os`+`arch` |
| Grovel output or natives tied to a specific distro/SDK ABI | Set `os-version` (e.g. `ubuntu-22.04`) |
| Both generic and versioned overlays exist | Spec: prefer exact `os.version` match, then fall back to generic `os`+`arch` |

**Wave-1 default:** build Linux natives on the **oldest LTS we support** and publish **without** `os-version`, unless a package proves ABI-sensitive (then add a versioned overlay and keep a generic fallback if possible).

### Consumer selection (summary)

1. Always install the **universal** manifest (no `platform`).
2. Match overlays by local `os` + `arch`.
3. Prefer `os.version` match when present; else generic overlay.
4. Optionally filter by CL implementation annotation.
5. Standard OCI clients: `oras pull --platform linux/amd64 <ref>` (omit `--platform` → first/universal manifest).

Clean-container proof: already demonstrated with **`grpc` / `cl-protobufs`** on GHCR (see [overlay-ci.md](overlay-ci.md) § Prior art). New natives should reuse that consume path — Linux first (no `gcc`/headers), then Windows when the overlay exists.

## GHCR namespace + artifact naming

### Canonical namespace (wave-1)

```
ghcr.io/egao1980/cl-systems/<system-name>:<version>
```

| Piece | Value | Rationale |
|-------|-------|-----------|
| Registry | `ghcr.io` | cl-repository default |
| Namespace | `egao1980/cl-systems` | Matches existing publish/consume practice; shared catalog-friendly |
| Repository | ASDF **system name** (canonical) | One OCI repo per system; multi-provide systems mount secondaries |
| Tag | Semver / upstream version string | Pin digests in `cl-repo.lock` / future cl-stack pins |

**Not** `ghcr.io/egao1980/cl-stack/<lib>` for natives — cl-stack is the docs/pins hub. Sibling libs publish into **`cl-systems`**. A future metapackage may use `ghcr.io/egao1980/cl-stack/cl-stack:<version>` (#21); that does not replace per-system overlay repos.

Lowercase all path segments (GHCR requirement). CLI: `--registry ghcr.io --namespace egao1980/cl-systems`.

### Staging paths (source tree / CI)

```
lib/<os>-<arch>/<soname>                 # generic overlay
lib/<os>-<arch>-<shortver>/<soname>      # when os-version pinned (e.g. u2204)
```

Examples: `lib/linux-amd64/libfoo.so`, `lib/darwin-arm64/libfoo.dylib`, `lib/linux-amd64-u2204/libfoo.so`.

Keep overlay file lists **relative** to the packager source dir (absolute paths → empty layers). Prefer staging natives outside the published source tree when using `build-package` so they are not swept into the universal tarball.

### Media types (reference)

| Role | Media type |
|------|------------|
| Index | `application/vnd.oci.image.index.v1+json` |
| Manifest | `application/vnd.oci.image.manifest.v1+json` |
| Layer | `application/vnd.oci.image.layer.v1.tar+gzip` |
| CL config | `application/vnd.common-lisp.system.config.v1+json` |
| Artifact type | `application/vnd.common-lisp.system.v1` |

Overlay layers use roles such as `native-library`, `cffi-grovel-output`, `cffi-wrapper`, `headers` (see cl-repository spec).

### Example publish commands

Source-only first, then incremental overlays (distinct platforms; serialize index updates if parallel CI):

```sh
# Universal (pure Lisp or source + later overlays)
cl-repo publish my-cffi-lib \
  --registry ghcr.io --namespace egao1980/cl-systems

# linux/amd64 overlay (generic ABI)
cl-repo add-overlay my-cffi-lib \
  --os linux --arch amd64 \
  --native-paths lib/linux-amd64/libfoo.so \
  --tag 1.0.0 \
  --registry ghcr.io --namespace egao1980/cl-systems

# linux/amd64 + ubuntu-22.04 (ABI-sensitive)
cl-repo add-overlay my-cffi-lib \
  --os linux --arch amd64 --os-version ubuntu-22.04 \
  --native-paths lib/linux-amd64-u2204/libfoo.so \
  --tag 1.0.0 \
  --registry ghcr.io --namespace egao1980/cl-systems

# darwin/arm64
cl-repo add-overlay my-cffi-lib \
  --os darwin --arch arm64 \
  --native-paths lib/darwin-arm64/libfoo.dylib \
  --tag 1.0.0 \
  --registry ghcr.io --namespace egao1980/cl-systems

# windows/amd64 (self-hosted builder)
cl-repo add-overlay my-cffi-lib \
  --os windows --arch amd64 \
  --native-paths lib/windows-amd64/foo.dll \
  --tag 1.0.0 \
  --registry ghcr.io --namespace egao1980/cl-systems
```

Consumer (conceptual):

```lisp
(cl-repository-client/quickload:add-registry "https://ghcr.io"
                                             :namespace "egao1980/cl-systems")
(cl-repository-client/quickload:load-system "my-cffi-lib" :version "1.0.0")
```

External pull:

```sh
oras pull --platform linux/amd64 \
  ghcr.io/egao1980/cl-systems/my-cffi-lib:1.0.0
```

## Wave-1 deliverables (tracking)

| Task | Issue | Status |
|------|-------|--------|
| This matrix + naming | #8 #9 | done |
| Spike: one native → GHCR → clean container | #10 | done — prior art: grpc / cl-protobufs ([overlay-ci.md](overlay-ci.md)) |
| Multi-arch CI pattern | #11 | done pattern in grpc; Windows via `windows-latest` or self-hosted ([overlay-ci.md](overlay-ci.md)) |
| OpenSSL overlay | #12 | done — [`egao1980/cl-stack-ssl`](https://github.com/egao1980/cl-stack-ssl) `ghcr.io/egao1980/cl-systems/cl-stack-ssl:3.4.1` (linux/amd64+arm64, darwin/arm64, windows/amd64); clean-container smoke OK |
| libuv overlay (event A) | #16 | done — [`egao1980/event-backend-libuv`](https://github.com/egao1980/event-backend-libuv) `ghcr.io/egao1980/cl-systems/event-backend-libuv:0.1.0` (linux/amd64+arm64, darwin/arm64, windows/amd64); clean-container smoke OK — [event-protocol.md](capabilities/event-protocol.md) |
| libev overlay (event B) | #17 | done — [`egao1980/event-backend-libev`](https://github.com/egao1980/event-backend-libev) `ghcr.io/egao1980/cl-systems/event-backend-libev:0.1.0` (linux/amd64+arm64, darwin/arm64; Unix-only); clean-container smoke OK — [event-protocol.md](capabilities/event-protocol.md) |
| Brotli (`br`) overlay | #45 | publishing — [`egao1980/cl-stack-brotli`](https://github.com/egao1980/cl-stack-brotli) `ghcr.io/egao1980/cl-systems/cl-stack-brotli:1.2.0` (linux/amd64+arm64, darwin/arm64, windows/amd64) — [http-protocol.md](capabilities/http-protocol.md) |
| Zstd overlay | #46 | publishing — [`egao1980/cl-stack-zstd`](https://github.com/egao1980/cl-stack-zstd) `ghcr.io/egao1980/cl-systems/cl-stack-zstd:1.5.7` (same matrix) — [http-protocol.md](capabilities/http-protocol.md) |

## Pitfalls (short)

- Namespace case: lowercase; workflows often `echo "${GITHUB_REPOSITORY,,}"`.
- Catalog package under a namespace may be writable only by the creating repo — use `:skip-catalog t` / packager warn path when cross-repo publish hits 403.
- Local registry from act/devcontainer: use `host.docker.internal` + `--add-host=host.docker.internal:host-gateway` as needed.
- Homebrew-linked binaries are not portable overlays — bundle self-contained natives or official static releases.
- Windows overlays: ship the DLL set the consumer needs (CRT/UCRT linkage); don't assume MSVC Build Tools on the install machine. Prefer GHA `windows-latest`; optional self-hosted runner — [overlay-ci.md](overlay-ci.md).

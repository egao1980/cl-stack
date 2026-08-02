# Multi-arch overlay CI (wave-1)

Policy companion to [overlays.md](overlays.md). **Canonical live pipelines** already exist — do not reinvent a toy `libcalc` spike.

## Prior art (#10 done)

| Package | GHCR | Workflow | Platforms published |
|---------|------|----------|---------------------|
| [`egao1980/grpc`](https://github.com/egao1980/grpc) | `ghcr.io/egao1980/cl-systems/grpc` | [`.github/workflows/publish-oci.yml`](https://github.com/egao1980/grpc/blob/main/.github/workflows/publish-oci.yml) | `linux/amd64`, `linux/arm64`, `darwin/arm64` |
| [`egao1980/cl-protobufs`](https://github.com/egao1980/cl-protobufs) | `ghcr.io/egao1980/cl-systems/cl-protobufs` | same pattern | same trio |

Pattern: **parallel matrix build** → upload `native-<os>-<arch>` artifacts → single `publish` job arranges `lib/<os>-<arch>/` → atomic `build-package` / `publish-package` into `egao1980/cl-systems`.

Local / clean-container consume: each repo’s `scripts/test-oci-local.sh` + workspace notes in [lisp-workspace `LESSONS_LEARNED.md`](https://github.com/egao1980/lisp-workspace/blob/main/LESSONS_LEARNED.md) (relative overlay `:files`, empty layers from `(directory #p"*")`, catalog 403 / `:skip-catalog`, `host.docker.internal` for act → local registry).

**Spike criteria for #10 are satisfied by the above.** New stack natives (OpenSSL, event loops) should copy this workflow shape, not invent a second demo package.

## Recommended GHA matrix (#11)

GitHub-hosted runners cover all **required** wave-1 platforms except you may prefer self-hosted for Windows toolchain control:

| `os` | `arch` | `runs-on` | Notes |
|------|--------|-----------|-------|
| `linux` | `amd64` | `ubuntu-latest` | default |
| `linux` | `arm64` | `ubuntu-24.04-arm` / `ubuntu-24.04-arm64` | match current grpc label |
| `darwin` | `arm64` | `macos-latest` (Apple Silicon) | M4 self-hosted optional |
| `windows` | `amd64` | **`windows-latest`** | **hosted — available**; use this by default |
| `darwin` | `amd64` | `macos-13` (Intel) | stretch only |

Example matrix fragment (parallel batch, same shape as grpc):

```yaml
strategy:
  fail-fast: true
  matrix:
    include:
      - os: linux
        arch: amd64
        runner: ubuntu-latest
      - os: linux
        arch: arm64
        runner: ubuntu-24.04-arm64
      - os: darwin
        arch: arm64
        runner: macos-latest
      - os: windows
        arch: amd64
        runner: windows-latest   # or: [self-hosted, windows, x64]
```

`publish` job stays on `ubuntu-latest` (oras + SBCL packager); only **native compile** steps need Windows/macOS.

### Windows on hosted vs self-hosted

| | `windows-latest` (hosted) | Self-hosted (your PC) |
|--|---------------------------|------------------------|
| Availability | Yes — no special allowlist | You register the machine |
| Minutes | Billed (Windows hosted is pricier than Linux) | Free of GHA minutes |
| Toolchain | Image has MSVC Build Tools / common SDKs; still pin versions | Full control (vcpkg, custom OpenSSL, GPU, etc.) |
| When to use | Default for OpenSSL / simple CFFI overlays | Heavy deps, private caches, or hosted image missing libs |

**grpc today:** matrix is linux×2 + darwin/arm64 only. Adding `windows-latest` is allowed by Actions, but **grpc’s workflow is Homebrew-centric** — a Windows row needs a real MSVC/vcpkg (or similar) build + DLL bundle path first. Prefer bringing Windows online on the next simpler native (**OpenSSL #12**), then back-port to grpc.

## Expose your Windows machine as a build node

Use a **GitHub Actions self-hosted runner**. The runner polls GitHub over HTTPS outbound — no inbound port forward required.

### 1. Create runner registration

1. Repo (or user/org) → **Settings → Actions → Runners → New self-hosted runner**
2. OS: **Windows** / Architecture: **x64**
3. Copy the one-time token (≈1h lifetime)

Prefer **user/org-level** runners if several `egao1980/*` repos will publish overlays; otherwise repo-scoped is fine (e.g. register on `egao1980/cl-stack` or the lib being built).

### 2. Install on the Windows box (PowerShell, elevated)

Pin the runner version from [actions/runner releases](https://github.com/actions/runner/releases) (example `2.336.0` — check latest):

```powershell
mkdir C:\actions-runner; cd C:\actions-runner
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.336.0/actions-runner-win-x64-2.336.0.zip `
  -OutFile actions-runner-win-x64-2.336.0.zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD\actions-runner-win-x64-2.336.0.zip", "$PWD")

.\config.cmd --url https://github.com/egao1980/<repo-or-leave-for-org-ui> `
  --token <TOKEN_FROM_UI> `
  --name "windows-amd64-overlay" `
  --labels "self-hosted,windows,x64,overlay" `
  --work "_work" `
  --unattended

.\svc.cmd install
.\svc.cmd start
```

GitHub UI also prints the download URL for the current release — prefer that over a stale version pin.

### 3. Target it from a workflow

```yaml
- os: windows
  arch: amd64
  runner: [self-hosted, windows, x64, overlay]
```

or simply `runs-on: [self-hosted, windows, x64]` if labels are enough.

### 4. Hardening (short)

- Treat the machine as a **CI node**: only trusted workflows (private repos / require approval for forks — **never** let public PRs run unconstrained on your desktop).
- Install build deps on the host (MSVC Build Tools, `pkg-config`/vcpkg as needed); the runner does not bring a full VS image unless you install it.
- Keep the service account able to write `C:\actions-runner\_work` and your package caches.
- Outbound **443** to `github.com` / `*.actions.githubusercontent.com` is enough; no router port mapping.

## Pitfalls (CI-specific)

- Serialize incremental `publish-overlay` updates (`max-parallel: 1`) if not using atomic batch publish.
- Stage natives under `$RUNNER_TEMP` / outside `:source-dir` so `build-package` does not sweep `.so`/`.dll` into the universal source layer.
- Overlay `:files` must be **relative**; absolute paths → empty layers.
- GHCR namespace: `egao1980/cl-systems` (lowercase); `packages: write` on the publish job.
- Windows artifacts: upload DLLs + dependent CRT/UCRT policy as in [overlays.md](overlays.md).

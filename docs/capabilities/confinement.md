# Confinement (R4d, with H8a-1) — who may touch an area

**Repos:** [`egao1980/compute-protocol`](https://github.com/egao1980/compute-protocol) (nick `stack-compute`) · [`egao1980/supervisor-protocol`](https://github.com/egao1980/supervisor-protocol) · new [`egao1980/compute-backend-seatbelt`](https://github.com/egao1980/compute-backend-seatbelt) · new [`egao1980/compute-backend-landlock`](https://github.com/egao1980/compute-backend-landlock) · [`egao1980/process-protocol`](https://github.com/egao1980/process-protocol) / [`process-backend-uiop`](https://github.com/egao1980/process-backend-uiop) (R4d-3)
**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) "R4 detail" (the *who* concern, confinement backends table), row R4d, H8a ("OS-enforced death"), decisions 2026-11-20 #4 (plan-mode bash unconfined until R4d) and 2026-11-21 #1 (R4d confines spawns through the supervisor)
**Status:** **R4d split locked** (five team-solve runs, landed in order, below). **R4d-0a** (compute-protocol 0.3.0) and **R4d-0b** (supervisor-protocol 0.4.0) contracts on branches `agent/r4d0-contract-7c02` in each repo (stubs `%r4d0-pending`). R4d-1 … R4d-4: decisions locked here; contracts written when the run starts. Windows confinement (AppContainer / restricted token) stays **R4e**. Implementation via **team-solve**.

R4a–R4c give a plan its own **area** (a copy or clone of the project). Until now only the agent's own Lisp tools were jailed to it; the shell, the spawned Lisp image and anything they start could still write outside the area, read `~/.ssh` and reach the network ([cl-stack-code.md § H5a](cl-stack-code.md#h5a--locked), "The shell is not confined"). R4d closes that gap with **lightweight, kernel-enforced confinement of one command and its children**: the area read-write, a policy for everything else, network off, a scrubbed environment. The kernel mechanism is a `compute-protocol` backend per OS; the supervisor runs a confined command as an ordinary unit, so plan-mode `bash` and the area's image become confined units.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| **Codex CLI** sandbox | macOS: a generated Seatbelt (SBPL) profile run through `/usr/bin/sandbox-exec`, `(deny default)` plus explicit allows; Linux: Landlock for the filesystem + a seccomp filter for the network, applied by a helper just before `exec`; **network off by default** in its workspace-write mode; writable roots = the workspace (+ temp); everything readable | Sandbox modes as a user-facing setting (our policy is a value the caller builds); `.git` read-only carve-outs inside writable roots (plan areas are copies, so not needed yet) |
| **Claude Code** sandboxing / [`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime) | Seatbelt on macOS, **bubblewrap** on Linux; write = the working directory, read = everywhere except a deny list; network only through a proxy outside the sandbox that enforces an allowed-domain list (the sandbox may only reach the proxy's port on loopback); children inherit | The domain-filtering proxy itself (R4d ships `:none` / `:allow` / port rules; host allowlists are a later rung, see "Not in R4d") |
| bubblewrap / Flatpak | `--ro-bind / /`, `--bind area area`, `--tmpfs` over denied dirs, `--unshare-net`, `--unshare-pid --die-with-parent` (kernel kills the whole pid namespace with its init) | setuid bwrap |
| Landlock docs (kernel ≥ 5.13) | ABI ladder: v1 fs, v2 `REFER` (cross-dir rename/link), v3 `TRUNCATE`, v4 TCP bind/connect, v5 ioctl, v6 scoped signals / abstract sockets; best effort = use what the running ABI has, report the rest | — |
| cl-stack | `compute-protocol` 0.2 `sandbox-spec` (`:network` `:none`/`:allow`/policy, limits, `sandbox-denied`), trusted-only native backend; `supervisor-protocol` 0.3 executor GFs; `process-protocol` 0.4 `:env-mode :replace`, `:process-group t` | — |

**Locally verified (macOS 26, 2026-11-21):** `sandbox-exec -p` with `(deny file-write* (require-not (subpath AREA)))`, `(deny file-read* (subpath SECRETS))`, `(deny network*)` denies: a write outside, a read of the secrets dir, a write through a symlink out of the area, `ln` of an outside file into the area, `mv` out of and into the area, a child's write outside, and a loopback connect — while writes in the area succeed. Seatbelt sees physical paths: `/tmp` must be written `/private/tmp`.

---

## The split (locked; each its own team-solve run, landed in this order)

| Run | Repo · version | Delivers | Verdict |
|-----|----------------|----------|---------|
| **R4d-0a** | compute-protocol **0.3.0** | `confinement` value, capability query, `check-confinement`, `confine-command` → `confined-launch`, `run-confined`, the reference model `confinement-decide`, `model-confinement-backend`, and the reusable **`compute-protocol/confinement-suite`** with its probe program | its tests (below) |
| **R4d-0b** | supervisor-protocol **0.4.0** (needs compute-protocol 0.3.0 **published** first) | `compute-executor`: a unit launched through a confining backend; `start-unit :confinement`; unit files record it | its tests |
| **R4d-1** | **new** compute-backend-seatbelt 0.1.0 | macOS: generated SBPL profile, `sandbox-exec` through process-protocol | `run-confinement-suite` → no failures on `macos-latest` |
| **R4d-2** | **new** compute-backend-landlock 0.1.0 | Linux: Landlock via `syscall`, seccomp network fallback, user + mount (+ net, pid) namespaces, bubblewrap when installed | the suite on ubuntu-24.04 in three CI jobs (below) |
| **R4d-3** (= H8a-1 death) | process-protocol 0.5.0, process-backend-uiop 0.4.0, supervisor-protocol 0.5.0 | kernel-enforced child death: Linux `PR_SET_PDEATHSIG` + `PR_SET_CHILD_SUBREAPER`, Windows `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, macOS kqueue `NOTE_EXIT` exit notices; a capability query; the sweep stays the fallback | SIGKILL of the harness leaves no unit process alive where the capability is T |
| **R4d-4** | agent-tools minor, cl-stack-code minor | plan mode confines `bash` / `job_input` and the area image; decision 2026-11-20 #4 ends | the R4d row: a write outside the area and network access are denied; the image spawned in the area loads only its files |

R4d-1, R4d-2 and R4d-3 are independent of each other once R4d-0a is published; R4d-4 needs R4d-0b and at least one backend.

---

## Decisions (locked, all runs)

| Decision | Choice |
|----------|--------|
| **Unit of confinement** | One command and **everything it starts** (children inherit; no escape by `fork`, `exec`, `setsid`, double fork). Not a container: same uid, same kernel, same host filesystem view minus the policy. Untrusted Lisp images and full isolation stay `compute-backend-podman` (R4e) |
| **Shape: a value + a launch** | A `confinement` is an immutable policy value. A backend never runs anything itself: `confine-command backend confinement argv` → a `confined-launch` (argv, **complete** environment, start directory, private temp dir) that **any launcher** runs — `run-confined` (process-protocol `run`), the supervisor's `compute-executor` (`launch`), agent-tools' pty. So pipes, ptys, unit logs, stop/kill trees and the H8 machinery are reused unchanged, and a mechanism that is "a prefix argv" (`sandbox-exec -p …`, `bwrap …`, a Landlock trampoline) fits without special cases |
| **Policy defaults** | **Network off** (`:none`). **Writes only** under `:writable` (the area), the launch's private temp dir and `/dev/null`-like devices (`+device-paths+`). **Reads**: `:read :all` minus `:deny-read`, which defaults to the credential locations `+default-deny-read+` under `$HOME` (`.ssh/ .aws/ .gnupg/ .netrc .config/gh/ .docker/ .kube/ .azure/ .config/gcloud/ .npmrc .pypirc .git-credentials`) — the Codex / Claude Code default. `:read :system` (only the writable/readable paths, `system-read-paths` and the running Lisp's runtime) is the strict option. **Environment scrubbed** to `+default-env-allow+` (`HOME LANG LC_* LOGNAME PATH SHELL TERM TZ USER`, plus the names a Windows process needs to start); `:env` adds back. **Private `TMPDIR`** (`:tmp :private`, a fresh `stack-compute-<16 hex>/`, removed on release) |
| **Fail closed** | Every feature a confinement needs (`confinement-requirements`) must be in the backend's `confinement-features`, else `confinement-unsupported` (a `sandbox-denied`; slot `missing`; restart `use-value` with another confinement, checked again). A backend that cannot confine on this machine → `confinement-unavailable` (reason string). Never a silent unconfined run. The native backend has no features |
| **Features** | `+confinement-features+` = `:filesystem :read-system :deny-read :network-none :network-allow :network-ports :network-hosts :cpu-limit :memory-limit :file-size-limit :process-limit`. `:deny-read` = subtracting from read-all (needs Seatbelt or a mount namespace; plain Landlock cannot subtract). `:network-ports` = a policy whose rules all have host `"*"` (Landlock ABI ≥ 4, Seatbelt `remote ip "*:PORT"`); `:network-hosts` = host rules (needs the proxy, not in R4d). Wall-clock is the launcher's job (`run-confined`, supervisor stop), never a backend feature |
| **Paths are physical** | `resolve-confinement` / `physical-path` resolve every symlink of the longest existing prefix, then `..` (macOS `/tmp` → `/private/tmp`). Kernel mechanisms see physical paths; so does the model. A writable entry must be an existing directory (`invalid-confinement :writable`) |
| **Deny wins** | Under `:deny-read` → no read and no write, even inside `:writable` |
| **The model is the oracle** | `confinement-decide` is the reference decision (`:read`/`:write` a path, `:connect` host+port). `model-confinement-backend` runs argv unchanged (it is **not a sandbox**) and its in-process suite probe decides with the model. Real backends must give the same effects as the model on the suite |
| **The suite** | `compute-protocol/confinement-suite` (SBCL; package `stack-compute-suite`): `run-confinement-suite backend &key cases root` → `(values failures ran skipped)`. 21 cases, each on a fresh fixture (`area/` writable, `ro/` readable, `outside/victim`, `secrets/token` deny-read, a loopback listener): area writes and tree ops allowed; create / modify / delete outside denied; read-only file not writable but readable; secrets unreadable; read-all vs read-system; network denied (`:none`) and allowed (`:allow`); **children inherit**; escapes by **symlink**, **`..`**, **hardlink**, **rename out**, **rename in** denied; environment scrubbed; private `TMPDIR` writable and gone after release; start directory = the area. Laws are about **effects** (the victim file is unchanged, nothing appeared outside), not error codes. A case needing a feature the backend lacks is **skipped**, never failed; a backend without `:network-none`, or with neither `:deny-read` nor `:read-system`, signals `confinement-unsupported`. The probe is this SBCL with `--script` (`sb-posix`, `sb-bsd-sockets` only): ops in on stdin, results out on stdout. `suite-confinement` lists the probe program's own file (not its directory) as readable, so it runs under `:read :system` (runtime, core and contribs come from `system-read-paths`; compute-protocol 0.3.1, #4). An unconfined backend that lies about its features fails exactly the 13 deny cases — that is the suite's own test |
| **Supervisor integration** | `compute-executor` is a `process-executor` subclass: `confine-command` of the unit's command (`:directory` = `unit-cwd`, `:env` = `unit-env` added after the scrub), then `pp:launch` of the launch argv with `:env-mode :replace`, `:process-group t`, octet pipes; stop / wait / input / pumps / logs unchanged; `executor-release` releases the launch after the tree is gone; every (re)launch is a new launch. `start-unit … :confinement c` routes to it (`make-supervisor :compute-executor`); refusals are `unit-start-error` whose cause is the compute condition, nothing registered, no id used. Unit files gain `:confinement` (`confinement-summary`) and `:compute-backend`; format stays 1. Kind for plan-mode bash: `:shell-job` |
| **Native access** | CFFI or `sb-alien` into libc / system libraries, loaded at ASDF load (absolute paths). **No custom C library.** `sandbox-exec`, `bwrap`, `setpriv` run through process-protocol |
| **Packaging** | One repo per mechanism, CI per OS. compute-protocol stays pure Lisp (it gains a `process-protocol` dependency for `run-confined`; still tested on ABCL / ECL / CCL; the suite system is SBCL-only) |

---

## R4d-0a — compute-protocol 0.3.0 (contract)

Branch `agent/r4d0-contract-7c02`, draft PR. Stubs: `%r4d0-pending` (`src/confinement.lisp`, `src/suite/*.lisp`).

**Given:** conditions (`invalid-confinement` field/value, `confinement-unsupported` backend/missing, `confinement-unavailable` backend/reason), constants, the `confinement` class + readers + `make-confinement` with its validation + `default-deny-read`, `sandbox-spec :confinement`, `confining-backend`, `confinement-features` / `confinement-supports-p` / `confinement-available-p` / `backend-confine-argv` GFs, `model-confinement-backend` (features, availability, argv + `STACK_COMPUTE_CONFINEMENT=model`), the `confined-launch` class + readers, `with-confined-launch`; in the suite: the case table, `case-requirements`, the probe vocabulary, the fixture class + readers, `with-suite-fixture`, `probe-program-pathname`, `probe-command`.
**Stubbed:** `confinement-requirements`, `check-confinement`, `physical-path`, `resolve-confinement`, `system-read-paths`, `confinement-decide`, `image-environment`, `confinement-environment`, `confinement-summary`, `confine-command`, `release-confined-launch`, `run-confined`, `run-sandboxed` on `confining-backend`; `make-suite-fixture`, `release-suite-fixture`, `suite-confinement`, `run-confinement-suite`, both `confinement-probe` methods, the body of `probe-program.lisp`.

```lisp
;; value
(make-confinement &key writable readable (read :all) (deny-read :default) (network :none)
                       (env-mode :scrub) (env-allow +default-env-allow+) env (tmp :private)
                       cpu-limit memory-limit file-size-limit process-limit wall-clock)
confinement-p confinement-{writable readable read deny-read network env-mode env-allow env tmp
                           cpu-limit memory-limit file-size-limit process-limit wall-clock}
(default-deny-read &optional home)  +confinement-features+ +default-env-allow+ +default-deny-read+ +device-paths+
;; backends
confining-backend  (confinement-features b) (confinement-supports-p b f) (confinement-available-p b) → (values ok reason)
(backend-confine-argv b resolved-confinement argv directory tmp) → (values argv extra-env cleanups)
model-confinement-backend (make-model-confinement-backend &key features) model-backend-features
;; policy
(confinement-requirements c) (check-confinement b c) → c | signals
(physical-path p) (resolve-confinement c) (system-read-paths)
(confinement-decide c op target &key tmp) → :allow | :deny      ; op :read :write :connect
(image-environment) (confinement-environment c &key base extra tmp) → sorted alist
(confinement-summary c) → printable plist
;; launches
(confine-command b c argv &key directory env) → confined-launch
confined-launch-{backend confinement argv env directory tmp released-p}
(release-confined-launch l) → T once, then NIL   (with-confined-launch (l b c argv &rest keys) &body)
(run-confined b c argv &key directory env input wall-clock) → sandbox-result | NIL (abort-execution)
;; suite (compute-protocol/confinement-suite, SBCL)
(run-confinement-suite b &key cases root) → (values failures ran skipped)
(confinement-probe b c ops &key directory)  +suite-cases+ +probe-operations+ (suite-case-names) (case-requirements name)
(make-suite-fixture &key root) (release-suite-fixture f) (with-suite-fixture (f) …) fixture-{root area readonly outside secrets port}
(suite-confinement f b &key read network) (probe-program-pathname) (probe-command)
```

**Contract (tests)** — `compute-protocol/tests` (Rove), 121 cases (18 existing + 103 new):

| File | Covers |
|------|--------|
| `confinement-test` | defaults (network off, scrub, private tmp, default deny-read), constants, 15 parametrized rejections naming the field, policies and limits, `sandbox-spec :confinement`, capabilities (model all, native none), **requirements** (8 rows), **check** (accept, `missing` in order, `use-value` replaces and re-checks, unavailable ×2), **physical paths** (symlinked dir, `..` after the symlink, missing tail, macOS `/private/tmp`), resolve (idempotent, missing / file writable refused), `system-read-paths` (includes `/usr/`, `/System/`, the SBCL runtime dir), **decide** (15 path rows: symlink, `..`, deny-inside-writable, read-system sibling …; tmp and devices; 6 connect rows), **environment** (6 rows: scrub, inherit, overrides / unset, extra last, `TMPDIR`, prefix pattern), `image-environment`, summary round-trips |
| `launch-test` | launch from the model (argv, backend env, default directory, private tmp physical under the system temp dir, resolved confinement), scrub, backend env added last, `:tmp :shared`/`:none`, start directory rules (`invalid-confinement :directory`), no writable → start in tmp, **refusal before anything is created**, release once / cleanups in order / a failing cleanup does not stop the next, `with-confined-launch` on a non-local exit; `run-confined` (exit code, stdout, stderr, env, pwd; the image's variables scrubbed; stdin; **wall-clock** → `sandbox-timeout` + `abort-execution`, killed in time, released; unavailable backend); `run-sandboxed` on a confining backend |
| `suite-test` (SBCL) | case table, fixture layout and release, `suite-confinement` (deny-read vs read-system base; no read policy → refused), **the probe program through an unconfined backend** (all 12 op kinds), the model's in-process probe, **the model keeps every law**, unsupported features skip the right cases (2 rows), no `:network-none` → refused, **an unconfined backend fails exactly the 13 deny laws**, subsets, environment restored, unavailable backend |

Locally (macOS, stubs, SBCL 2.4.11): 39 pass (18 existing + 21 on given code), 82 fail, every failure on `%r4d0-pending`; the systems load with no warnings of their own (the only warnings are trivial-garbage's `.asd` and ASDF's recursive-operate notice, as on main).

## R4d-0b — supervisor-protocol 0.4.0 (contract)

Branch `agent/r4d0-contract-7c02`, draft PR. Depends on `(:version "compute-protocol" "0.3.0")`: CI goes green only after R4d-0a is merged and published. Stubs: `%r4d0-pending` (`src/confine.lisp`).

**Given:** `compute-executor` + `make-compute-executor &key compute-backend confinement backend` (a non-confining backend → `supervisor-error`), readers, `executor-supports-p … :confined`, `make-supervisor :compute-executor` / `supervisor-compute-executor`, `start-unit :confinement` (stored as `unit-confinement`), `unit-confined-p`, the unit-file hook. **Stubbed:** `%confined-executor` (routing + refusals), `executor-launch` / `executor-release` on `compute-executor`, `unit-confined-launch`, `%unit-file-confinement`. Non-confined units never reach a stub.

**Contract (tests):** `tests/confine-test.lisp`, 17 new cases (311 in all): construction, the supervisor slot, unconfined units unchanged, **a confined unit's child sees the backend env, the confinement env, the unit env, not the image's other variables, a private `TMPDIR` and the area as cwd**, `unit-cwd` honoured, **the private dir lives exactly as long as the launch**, the launch argv is what runs (a wrapping backend), the executor's default confinement, **a restart is a new launch with a new tmp, both released**, 5 parametrized start errors (nothing registered), a backend refusal is a `unit-start-error` caused by `confinement-unsupported` with no id consumed, the unit file's `:confinement` / `:compute-backend` (format 1), stdin / stdout through a confined unit. Locally (macOS, stubs, compute-protocol worktree on the registry): 294 pass, 2 skip, 15 fail (all new, all on `%r4d0-pending`).

---

## R4d-1 — compute-backend-seatbelt (macOS), locked

| Decision | Choice |
|----------|--------|
| **Mechanism** | `sandbox-exec -p <profile> -- argv` (profile passed inline; a temp file only if argv length limits bite, removed by the launch cleanup). `/usr/bin/sandbox-exec` absolute; missing → `confinement-unavailable`. Deprecated by Apple but still what Codex and Claude Code ship; the `sandbox_init` API is the same engine and needs no extra process — rejected for 0.1.0 because it would confine the harness itself |
| **Profile** | `(version 1) (deny default)` + an explicit allow list (Codex-derived base: `process-exec`, `process-fork`, `signal (target same-sandbox)`, `sysctl-read`, `mach-lookup` for the services a shell and SBCL need, `file-ioctl` on ttys, `pseudo-tty`). Files: `:read :all` → `(allow file-read*)` then `(deny file-read* file-write* (subpath D))` per deny-read entry; `:read :system` → `(allow file-read* (subpath P))` per system/readable/writable path + `(allow file-read-metadata)` on ancestors (path lookups). Writes: `(allow file-write* (subpath W))` per writable + tmp + `(literal "/dev/null")`…. Network: `:none` → nothing allowed (default deny); `:allow` → `(allow network*)`; ports → `(allow network-outbound (remote ip "*:PORT"))` + DNS via `mach-lookup` for mDNSResponder only if a policy has `dns`. All paths physical, strings escaped for SBPL |
| **Limits** | `:cpu-limit :file-size-limit :process-limit` via `ulimit` in a `/bin/sh -c 'ulimit …; exec "$@"'` prefix inside the sandbox; `:memory-limit` is **not** offered (macOS ignores `RLIMIT_AS`) |
| **Features** | `:filesystem :read-system :deny-read :network-none :network-allow :network-ports :cpu-limit :file-size-limit :process-limit` on macOS; none elsewhere (`confinement-available-p` → NIL "not macOS") |
| **Tests / CI** | `run-confinement-suite` → no failures and `:network-hosts`/`:memory-limit` cases absent from `ran`; profile golden tests (pure function `seatbelt-profile resolved-confinement tmp` → string); an SBCL image spawned confined in the area loads a system from the area and **cannot read the real project** (`:read :system`). Canned `test-system.yml`; the suite runs on `macos-latest`; Linux / Windows load and skip |

## R4d-2 — compute-backend-landlock (Linux), locked

| Decision | Choice |
|----------|--------|
| **Mechanisms, best first** | (1) **bubblewrap** when `bwrap` is on PATH and user namespaces work: `--ro-bind / /` (read-all) or binds of the read set (read-system), `--bind W W` per writable + tmp, `--tmpfs D` / `--ro-bind /dev/null F` over deny-read entries, `--dev /dev`, `--proc /proc`, `--unshare-net` for `:none`, `--unshare-pid --die-with-parent`, `--new-session`; (2) **Landlock trampoline** otherwise: the argv is prefixed with this SBCL running `--script landlock-exec.lisp` (shipped in the repo, `sb-alien` only), which sets `PR_SET_NO_NEW_PRIVS`, builds a ruleset for the running ABI (`landlock_create_ruleset` 444 / `add_rule` 445 / `restrict_self` 446, same numbers on x86-64 and arm64), `setrlimit`s, the network rule, then `execv`s the command. Codex's helper does the same in Rust; ours is Lisp so no custom native library |
| **Network** | `:none`: a network namespace (bwrap, or `unshare(CLONE_NEWUSER\|CLONE_NEWNET)` in the trampoline when user namespaces work), else a **seccomp** filter denying `socket(AF_INET/AF_INET6/AF_PACKET)` (Codex's approach; works without namespaces). `:network-ports`: Landlock ABI ≥ 4 TCP connect rules + the seccomp filter for UDP. `:allow`: nothing |
| **Read policy** | `:read-system` always (Landlock allow-list). `:deny-read` (subtract from read-all) only with a mount namespace (bwrap or the trampoline's `unshare(CLONE_NEWNS)` + tmpfs over the entries) — else the feature is absent and `check-confinement` refuses: never "read-all and hope" |
| **ABI** | Probed once (`landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION)`); `landlock-abi` exported; ABI < 2 → no cross-directory rename/link at all (safe: the hardlink/rename laws hold by refusal); ABI 0 / ENOSYS / EOPNOTSUPP and no bwrap → `confinement-unavailable` |
| **Trampoline hazards (must be tested)** | `unshare(CLONE_NEWUSER)` needs a single-threaded process: the trampoline checks `/proc/self/task` and refuses with a clear error instead of half-applying. The trampoline's own reads (runtime, core, script) are inside the read set |
| **Shared temp vs deny-read (amended 2026-11-21)** | `:tmp :shared` makes the system temp directory a granted write path (a Landlock rule with every right; a bwrap `--bind`). A `:deny-read` entry inside it overlaps that grant, so **deny wins** (locked decision above) applies: the entry is masked (`--tmpfs` / `--ro-bind /dev/null`, or the trampoline's mount-namespace masks). Without user namespaces the trampoline plan signals `confinement-unsupported` with `:missing (:deny-read)`: fail closed, never planned with the entry readable or writable |
| **Merged /usr under `:read :system` (bwrap, amended 2026-11-21)** | `system-read-paths` yields physical directories, so on merged-/usr hosts (ubuntu-24.04: `/bin` `/sbin` `/lib` `/lib64` → `usr/…`) bwrap's new root would lack `/lib*/ld-linux-*.so` and every exec fails. `host-facts` gains `root-symlinks` (`make-host-facts :root-symlinks`, exported reader `host-root-symlinks`, default NIL): an alist `(PATH . TARGET)`, one entry for each of `/bin /sbin /lib /lib64` (that order) that is a symlink on the host, TARGET as `readlink(2)` returns it; `probe-host` measures it; a PATH that is not `"/NAME"` (absolute, top-level, no trailing `/`), a TARGET that is not a non-empty string, or an element that is not a cons → `landlock-error`. `bwrap-argv` under `:read :system` emits `--symlink TARGET PATH` for each entry in host order, right after the read set's last `--ro-bind` (system paths, readable, the chained trampoline script) and before `--dev`; an entry whose PATH is itself a `--ro-bind` destination is skipped. `:read :all` (`--ro-bind / /`) emits none; the Landlock trampoline ignores them (it runs in the real root). Linux tests assert the command actually ran under `:read :system` |
| **Overlay areas** | Optional here: if R4c's author moves overlayfs-in-a-user-namespace out of `fs-backend-linux`, it lands as `compute-backend-landlock/overlay`; otherwise not in R4d-2. Coordinate in the R4c brief |
| **CI (honest)** | GitHub's **ubuntu-24.04** runners ship AppArmor with `kernel.apparmor_restrict_unprivileged_userns=1`: unprivileged `unshare(CLONE_NEWUSER)` succeeds but the namespace gets no capabilities, so bwrap and mount namespaces fail. The canned workflow runs Linux in the `ci-base` **container**, whose default seccomp profile blocks namespaces too. So the repo's `test.yml` adds a custom job on the **VM** (`ci-image: ''` path: `setup-lisp` action + `cl-repo test`, no container), matrix of three: **`bwrap`** (`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`, `apt-get install bubblewrap`), **`landlock`** (same sysctl, no bwrap: the trampoline with namespaces), **`restricted`** (sysctl left at 1, no bwrap: Landlock + seccomp only; asserts `:deny-read` absent and the deny-read case skipped, not failed). Each job prints the Landlock ABI and fails if it is 0 (the runner kernel 6.8+ has Landlock in its LSM list; if a runner image ever drops it the job fails loudly rather than skipping). macOS / Windows: canned job, load + skip |

## R4d-3 (= H8a-1 death) — kernel-enforced child death, locked

| Decision | Choice |
|----------|--------|
| **Home** | The mechanisms belong to **launching**, not to filesystems: `process-protocol` 0.5.0 adds the launch key `:die-with-parent t` and capabilities `:die-with-parent :subreaper :exit-notify` (`supports-p`); `process-backend-uiop` 0.4.0 implements them (it already holds the Windows job object through `sb-alien`); `supervisor-protocol` 0.5.0 passes `:die-with-parent t` when supported and answers `supervisor-supports-p :die-with-parent / :subreaper / :exit-notify`. No new repo; `fs-backend-*` stay filesystem-only (the H8a row's "fs-backend-*-style overlays" is superseded) |
| **Windows** | The job object process-backend-uiop creates per `:process-group t` launch gets `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` (`SetInformationJobObject`); the harness holds the only handle, so when the harness dies the kernel kills the whole job. Gap: a grandchild spawned before `AssignProcessToJobObject` escapes → launch suspended (`CREATE_SUSPENDED`, assign, resume) where the backend controls `CreateProcess`, else documented |
| **Linux** | `PR_SET_PDEATHSIG SIGKILL` on the direct child via the `setpriv --pdeathsig KILL --` prefix (util-linux ≥ 2.33; absent → capability NIL), plus `PR_SET_CHILD_SUBREAPER` on the harness (`prctl` via `sb-alien`) so `setsid` / double-fork escapees reparent to the harness while it lives and the stop wave finds them. **Hazard (locked):** pdeathsig fires when the *thread* that forked exits, so the supervisor launches `:die-with-parent` units from **one long-lived launcher thread** per supervisor, never from a restart or caller thread. **Hazard (locked):** a subreaper must reap adopted orphans without stealing exit statuses from process-backend-uiop's own children — the reaper reaps only pids that are not live handles of the backend (the backend exposes its live pid set). With confinement the tree dies wholesale anyway: bwrap's `--unshare-pid --die-with-parent` |
| **macOS** | No kernel die-with-parent → capability NIL; the durable unit-file sweep stays the mechanism. kqueue `EVFILT_PROC NOTE_EXIT` gives `:exit-notify` (waits without polling) |
| **Fallback** | The orphan sweep stays on every OS and remains the only path on macOS |
| **Verdict** | Child-image crash fixture (H8a's): SIGKILL / TerminateProcess the harness → within 2 s no unit process (incl. grandchildren under `:process-group`) is alive on Windows and Linux, without a sweep; macOS still needs the sweep |
| **pty / tmux executors** | The rest of H8a-1 (pty, tmux executors; consumer migration) stays in supervisor.md "Later", not in R4d |

## R4d-4 — plan mode confined, locked

| Decision | Choice |
|----------|--------|
| **agent-tools** | `make-shell-tools … :confinement c :compute-backend b`: each command line goes through `confine-command` (`:directory` = the resolved `workdir`), then the pty or process executor runs the launch argv with exactly its env; released when the job ends. No confinement → unchanged behaviour |
| **cl-stack-code** | Plan mode builds the area confinement: writable = the area (+ the plan's scratch dir), `:read :all` + default deny-read, network **off**, scrub with the user's settings `env` added back; backend = `compute-backend-seatbelt` on macOS, `compute-backend-landlock` on Linux (`(:feature …)` deps). The area's Lisp image (H5d) is a confined `:image` unit with `XDG_CACHE_HOME` and ASDF output translations inside the area, `:read :system` plus the runtime, so it loads only the area's files. Unavailable or refused confinement → plan mode asks before each `bash` again (0.4.0 behaviour), never silently unconfined; `--allow-network` (or a settings key) opts into `:allow` |
| **Ends** | Decision 2026-11-20 #4 ("unconfined until R4d") and the H5a "known gap" note |

---

## Not in R4d

- **Host allowlists** (`:network-hosts`): needs a filtering HTTP/SOCKS proxy outside the sandbox (Claude Code's design) on `http-backend-async`; the sandbox then allows only the proxy's loopback port. A later rung (R4d-5) once a consumer needs `pip install` / `npm install` inside a plan.
- **Windows confinement**: AppContainer or restricted token + job object (`compute-backend-appcontainer`) — **R4e**, with `compute-backend-podman` areas as bind mounts.
- `.git` read-only carve-outs inside writable roots; per-command profiles; GPU / device policies; a violation log (Seatbelt `(trace)`, Landlock audit on ≥ 6.15) — later, when a consumer needs them.

# supervisor-protocol (H8a) — process supervisor core

**Repo:** [`egao1980/supervisor-protocol`](https://github.com/egao1980/supervisor-protocol) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) rows H8a–H8d, "Backlog note: why H8", "Decisions (2026-11-21)"
**Status:** **H8a locked**, version **0.1.0**. Contract on branch `agent/h8a-contract-a68e` (`supervisor-protocol/tests`, Rove): given code, stubs (`%h8a-pending`) and the failing tests. Implementation via **team-solve**. Later rungs: [H8a-1](#later-h8a-1-and-after).

One in-image registry for every child the harness owns: shell jobs, rpc / MCP and language servers, spawned Lisp images, subagent threads. A **unit** has an id, a kind tag, an owner scope, labels, a command or a thread function, pid / pgid, start times, a state and an exit status. The supervisor starts units under caps with LRU eviction, restarts servers on failure with backoff, stops them graceful → grace → force (tree-wide), stops everything a scope owns when the scope closes, shuts down on image exit, publishes every state change on an ordered, replayable event stream, and records each process unit in a durable file so the next supervisor reaps what a crash left behind.

Layering stays pure: `ai-agent-protocol` (the agent core) never depends on it. `agent-tools`, `cl-stack-code`, `rpc-backend-stdio` consumers and `lisp-mcp` opt in; each keeps working without it.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Codex `unified_exec` | A cap on retained processes; at the cap prune exited ones first, then least recently used; head + tail output buffers | Token-based output caps; sandbox policy (confinement is `compute-backend-*`) |
| Claude Code background tasks | One model for shells and agents; its bugs as named regression tests: stale "running" after exit, interrupt leaving subagents/shells alive, background shells surviving session end, Windows kill leaving children, tasks lost after compaction | Per-tool lifecycles |
| OpenCode V2 `/api/pty`, opencode-pty | Session-scoped cleanup (scope close), one registry a viewer can list | — (pty executor is H8a-1) |
| Pi | No process management in the agent core: the supervisor is a separate layer | tmux as the only executor (an optional executor in H8a-1) |
| cl-stack | `process-protocol` 0.4 `:process-group t` + `kill :tree t` + `process-pid` + `supports-p`; `process-backend-uiop` 0.3.1 job objects on Windows; agent-tools job ids / caps / `close-shell-tools` (first consumer, migrates later) | — |

---

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| **Package / systems** | `supervisor-protocol` (local nickname `pp` = `process-protocol`), one system plus `supervisor-protocol/tests`. Pure Lisp |
| **Dependencies** | `process-protocol` ≥ 0.4.1, `process-backend-uiop` ≥ 0.3.1 (loading the system sets `*process-backend*`; no consumer setup call), `bordeaux-threads` (bt2 API), `uiop`. Nothing else |
| **Unit** | `unit-id` `"<kind>-<n>"` (n counted per kind per supervisor, a refused or failed start takes no number) · `unit-kind` keyword, open set (`:shell-job :lsp :rpc :image :pty :subagent …`) · `unit-owner` scope · `unit-labels` plist · `unit-command` argv / `unit-function` · `unit-cwd`, `unit-env` · `unit-pid`, `unit-pgid` (Unix = pid; Windows NIL) · `unit-start-time` (universal time of the last launch) · `unit-os-start-time` (the OS start string, pid-reuse guard) · `unit-state` · `unit-exit-code` · `unit-signal` · `unit-condition` / `unit-result` (threads) · restart policy, max restarts, backoff, `unit-restart-count` · `unit-last-used` (LRU tick) · `unit-interacting-p` · `unit-stop-requested-p` · `unit-output-sink` · `unit-file-path` |
| **States** | `:starting :running :exited :killed :failed`. `:exited` = ended by itself with success (exit 0, thread returned); `:failed` = ended by itself otherwise (non-zero exit, thread error, a relaunch that could not start); `:killed` = ended after a stop request (any outcome after a stop request is `:killed`). Transitions: nil → `:starting` → `:running` → final; a restart goes `:failed` → `:starting` (after `:restart-scheduled`); a relaunch failure goes `:starting` → `:failed`. `unit-live-p` = `:starting`/`:running`; `unit-finished-p` = final and no restart pending |
| **Signal** | `unit-signal` is `:term` / `:kill` when the supervisor stopped the unit (the last stop it sent; Windows stops are always forced → `:kill`), else NIL. process-protocol reports a signal death as an exit code only, so an external kill shows as a non-zero `unit-exit-code` and `:failed` |
| **Scopes** | `make-scope sup kind name &key parent` (default parent `*current-scope*` when it belongs to the supervisor, else the root; root kind `:supervisor`). Kinds `:session :agent :tool-source`, any other keyword accepted. `scope-path` = names below the root. `with-scope` binds `*current-scope*` and closes on any exit (normal, non-local, interrupt that unwinds). `close-scope` closes the scope and its descendants and stops their live units in **one stop wave**; idempotent (second call → NIL); the root → `supervisor-error` (use `shutdown-supervisor`). A closed scope refuses units and child scopes (`scope-closed`) |
| **Start** | `start-unit sup kind &key command function owner labels cwd env executor restart max-restarts backoff interacting` → the unit in `:running`. `:command` → process executor, `:function` → thread executor; exactly one unless `:executor` is given, else `unit-start-error`. Default owner = `*current-scope*` if it belongs to `sup`, else the root; an owner of another supervisor → `supervisor-error`. Launch failure → `unit-start-error`, nothing registered. Shut-down supervisor → `supervisor-closed` |
| **Caps + LRU** | `make-supervisor :kind-caps '(:shell-job 8 …) :owner-cap n`. Caps count **retained** units (any state) of the kind / owned **directly** by the scope. At a cap: evict the least recently used **finished** unit silently (event `:evicted`); with none, `error 'unit-limit-reached` (kind, owner, limit, victim = LRU live unit) with restarts **`evict-lru`** (only when a victim exists: stop it, evict it, retry) and **`abort`** (`start-unit` → NIL). Units with `unit-interacting-p` are **never** evicted, finished or not (`with-unit-interaction`). LRU tick: start, `touch-unit`, `send-unit-input`, `unit-output` |
| **Restart policy** | `:never` (default) or `:on-failure` (default for `:rpc` and `:lsp`, `kind-default-restart`). Only `:failed` restarts; `:exited` and `:killed` never. `restart-delay (initial factor max) attempt` = min(max, initial × factor^(attempt−1)); default backoff `(0.5 2 30)`, max restarts 3. Same unit, same id, new pid, new unit file content. A stop cancels a pending restart |
| **Stop** | `stop-unit u &key grace force-grace` blocks → final state. Graceful stop (sets `unit-stop-requested-p`), wait GRACE (default 5 s) → still running: **`signal 'stop-timeout`** (phase `:graceful`, `waited`) with restarts **`force`** and **`keep-waiting`** (another GRACE, then signal again); **unhandled → force**. Forced stop, wait FORCE-GRACE (default 2 s) → still running: **`error 'stop-failed`** with restart **`abandon`** (mark `:killed`, detail `:abandoned t`, keep the unit file for the next sweep). `stop-units` / `close-scope` / shutdown send the graceful stop to all selected units, wait one grace, then escalate the rest — never one grace per unit. A finished unit: no-op, its state |
| **Process executor** | `pp:launch … :process-group t`, stdin/stdout/stderr UTF-8 pipes, `:directory` cwd, `:env` env. Graceful = `pp:kill :tree t` (Unix SIGTERM to the group; Windows: the job object, always forced); force = `:tree t :force t`. When the direct child ends (by itself or not), what is left of its tree is killed too: nothing a unit started outlives it. stdout and stderr are pumped into the unit's sink |
| **Thread executor** | `unit-function` called with the unit on a new bt2 thread; `*current-unit*` = the unit, `*current-scope*` = its owner (units a subagent starts belong to its scope). Normal return → `:exited` (value in `unit-result`); an unhandled ERROR → `:failed` (`unit-condition`), never the debugger. **Graceful = cooperative**: `unit-stop-requested-p` becomes T and the body polls it. **Force = `bt2:interrupt-thread`** that unwinds to the unit's top (UNWIND-PROTECT cleanups run; not a failure, no condition). A thread that cannot be unwound (foreign call, without-interrupts) ends in `stop-failed` → `abandon` |
| **Executor protocol** | `executor-launch` → handle · `executor-pid` / `executor-pgid` · `executor-stop … &key force` (returns at once) · `executor-wait … &key timeout` → `(values ended-p exit-code condition result)` · `executor-alive-p` · `executor-send-input` (default: `executor-unsupported`) · `executor-release` (after the end) · `executor-supports-p` (`:pid :tree :input :graceful-stop`). The supervisor waits on one thread per launch and publishes the final state from there, so **a state never stays `:running` after the work ended** and nobody needs to poll. H8a-1 executors (pty, tmux, compute) implement the same GFs |
| **Output** | `output-sink` GFs `sink-write sink stream text` (`:stdout`/`:stderr`), `sink-text`, `sink-stats` → `(values total dropped)`, `sink-close` (later writes ignored). Default `head-tail-buffer` (16 384 head + 65 536 tail characters); when anything was dropped, `sink-text` = head + `(format nil "~%[~D characters dropped]~%" n)` + tail. `make-supervisor :output-sink-factory` (function of the unit) is the **H8b attach point** for rotated log files. `unit-output` = `sink-text` (touches the unit) |
| **Events** | `unit-event`: `event-seq` (1, 2, … per supervisor, no gaps), `event-time` (universal), `event-monotonic` (seconds), `event-unit-id`, `event-unit-kind`, `event-type` (`:state :restart-scheduled :evicted`), `event-from`, `event-to`, `event-detail` (final `:state` events: `:exit-code`, `:signal`, `:abandoned`; `:restart-scheduled`: `:attempt`, `:delay`). Appended under the supervisor lock in transition order. The last `:event-capacity` (default 4096) are retained: `events-since sup seq` → `(values events complete-p)`. `subscribe sup fn &key since` replays the retained events after SINCE, then continues live — no gap, no duplicate; callbacks run serially on **one dispatcher thread per supervisor**, in seq order, never under the lock; a callback that signals an ERROR is unsubscribed (`subscription-error`), others carry on. `unsubscribe` idempotent. Shutdown delivers the final events, then ends the subscriptions |
| **Queries** | `find-units sup &key kind owner (recursive t) labels state` (kind/state a keyword or a list; owner with its descendants unless `:recursive nil`; every label pair EQUAL), start order. `find-unit sup id`. `supervisor-units`. `scope-units`. Evicted units are gone from all of them |
| **Supervisor** | `make-supervisor &key state-directory (sweep t) (exit-hook t) kind-caps owner-cap grace force-grace event-capacity output-sink-factory process-executor thread-executor`. `supervisor-id` = `"<pid>-<8 hex>"`. `live-supervisors`. `shutdown-supervisor` stops all (one wave), deletes the unit files, ends event delivery, removes the exit hook, closes the scopes; queries still answer; later starts → `supervisor-closed`; idempotent |
| **Exit hook** | `:exit-hook t` pushes a function on `sb-ext:*exit-hooks*` (other Lisps: `uiop:register-image-exit-hook`), `supervisor-exit-hook` returns it; it shuts the supervisor down with an unhandled `stop-timeout` forcing and `stop-failed` abandoning. A SIGKILL runs no hook: that is the sweep's job |
| **Unit files** | `<state-directory>/units/<supervisor-id>--<unit-id>.unit`, one per **process** unit (threads die with the image), written atomically (temp + rename) after every launch, deleted when the unit is finished, evicted or shut down. One plist printed `with-standard-io-syntax` in the keyword package, read with `*read-eval*` NIL: `(:format 1 :supervisor-id :supervisor-pid :supervisor-os-start :unit-id :kind :pid :pgid :os-start :command :cwd :inspector)`. `read-unit-file` → plist, or NIL after **warning** `unit-file-unreadable` (bad syntax, `#.`, odd plist, unknown format) |
| **Orphan sweep (the fallback path, every OS)** | `make-supervisor :state-directory` runs `sweep-orphans` first (`supervisor-sweep-report`). Per file: unreadable → warn, delete, `:unreadable`. Owner alive (its pid runs with `:supervisor-os-start`; in this image, its id is in `live-supervisors`) → `:live-owner`, kept. **Unix** (pgid recorded): members = processes in the group; a leader (pid = pgid) with another start time → `:reused` (a pid is not reused while its group has members, so the old group is gone); members → TERM the group, wait `:grace` (0.5 s), KILL the rest → `:killed`; none → `:gone`. **Windows** (no groups): the root pid running with another start time → `:reused`; else the root (if running) plus its descendants by ParentProcessId, each started no earlier than its parent, `taskkill /F /PID` each → `:killed`; none → `:gone`. Every action but `:live-owner` deletes the file. Returns `sweep-record`s (unit id, pid, pgid, action, killed pids, path) |
| **OS inspection** | `os-inspector` GF `inspector-list-processes` → `os-process` (pid, ppid, pgid, start). **`ps-inspector`** (Unix): `ps -A -o pid= -o ppid= -o pgid= -o lstart=` with `LC_ALL=C TZ=UTC`, whitespace in lstart collapsed; kills with `kill(1)` (`kill-os-processes`, `kill-os-process-group` = `kill -SIG -- -PGID`). **`cim-inspector`** (Windows): `powershell.exe -NoProfile -NonInteractive -Command` `Get-CimInstance Win32_Process` → ProcessId, ParentProcessId, CreationDate as UTC `yyyyMMddHHmmss.ffffff` (sorts as a string); kills with `taskkill /F /PID` per pid (no `/T`); `kill-os-process-group` → `supervisor-error`. `default-os-inspector` picks per OS; `os-process-start-time`, `os-process-alive-p … :start-time`. All through `pp:run`: no native code |
| **Why `ps` and CIM** | One code path for macOS and Linux (`/proc` is Linux-only; `ps -o pgid,lstart` exists on both), testable in CI on all three runners. `wmic` is deprecated and missing from current Windows images; PowerShell 5.1 + CIM is on every supported Windows and GitHub runner. The sweep runs once per start, so a ~0.5–1 s PowerShell call is acceptable. Toolhelp32 through `sb-alien` was rejected for 0.1.0 (SBCL-only, struct definitions); OS-enforced death replaces most of the sweep's work in H8a-1 |
| **Conditions** | `supervisor-condition` (root, slot supervisor) › `supervisor-error` (ERROR) › `supervisor-closed`, `scope-closed`, `unit-start-error` (kind, command, cause), `unit-limit-reached` (kind, owner, limit, victim), `executor-unsupported` (executor, operation), `unit-error` (unit) › `stop-failed`, `unit-not-running`. `stop-timeout` (unit, phase, waited) is **not** an error. `unit-file-unreadable` is a WARNING. Restarts: `evict-lru`, `cl:abort`, `force`, `keep-waiting`, `abandon` |
| **Threads** | Every API function is thread-safe (one lock per supervisor). No user code (callbacks, sink methods, thread bodies) runs under the lock |
| **Stubs** | `%h8a-pending` (internal, `src/model.lisp`). Given: package and exports, constants, conditions, the class definitions and readers, `scope-path`, `unit-live-p` / `unit-finished-p`, `kind-default-restart`, `make-head-tail-buffer`, `default-output-sink`, the executor classes, constructors and `executor-supports-p`, `current-pid`, the inspector classes and `default-os-inspector`, `unit-file-directory`, `with-scope`, `with-unit-interaction`. The implementation removes `%h8a-pending` and every call; it may add slots |

## Surface

```lisp
;;; supervisor
(make-supervisor &key state-directory (sweep t) (exit-hook t) kind-caps owner-cap grace force-grace
                      event-capacity output-sink-factory process-executor thread-executor) → supervisor
supervisor-id supervisor-state-directory supervisor-root-scope supervisor-kind-caps supervisor-owner-cap
supervisor-grace supervisor-force-grace supervisor-event-capacity supervisor-output-sink-factory
supervisor-sweep-report supervisor-closed-p supervisor-exit-hook
(supervisor-units sup) (live-supervisors) (shutdown-supervisor sup &key grace force-grace)

;;; scopes
(make-scope sup kind name &key parent) scope-supervisor scope-kind scope-name scope-parent
scope-children scope-closed-p (scope-path s) (scope-units s &key recursive)
(close-scope s &key grace force-grace) (with-scope (var sup kind name &key parent) &body) *current-scope*

;;; units
(start-unit sup kind &key command function owner labels cwd env executor restart max-restarts
                          backoff interacting) → unit | NIL
(stop-unit u &key grace force-grace) (stop-units sup &key kind owner recursive labels state grace force-grace)
(wait-unit u &key timeout) → (values state exit-code) | NIL
(touch-unit u) (send-unit-input u text) (unit-output u) (with-unit-interaction (u) &body) *current-unit*
(find-unit sup id) (find-units sup &key kind owner (recursive t) labels state)
(kind-default-restart kind) (restart-delay backoff attempt)
unit-… readers (see Decisions) · unit-live-p unit-finished-p · (setf unit-interacting-p)

;;; executors
executor process-executor thread-executor make-process-executor make-thread-executor
executor-launch executor-pid executor-pgid executor-stop executor-wait executor-alive-p
executor-send-input executor-release executor-supports-p

;;; output
output-sink sink-write sink-text sink-stats sink-close
head-tail-buffer make-head-tail-buffer head-tail-buffer-head-size head-tail-buffer-tail-size default-output-sink

;;; events
unit-event event-seq event-time event-monotonic event-unit-id event-unit-kind event-type event-from
event-to event-detail (events-since sup seq) (supervisor-last-seq sup)
(subscribe sup fn &key since) → subscription · (unsubscribe sub) subscription-active-p subscription-error

;;; unit files, sweep, OS
(unit-file-directory dir) (write-unit-file u) (read-unit-file path) (sweep-orphans dir &key grace inspector)
sweep-record sweep-record-unit-id sweep-record-pid sweep-record-pgid sweep-record-action
sweep-record-killed-pids sweep-record-path
(current-pid) os-process os-process-pid os-process-ppid os-process-pgid os-process-start
os-inspector ps-inspector cim-inspector make-ps-inspector make-cim-inspector (default-os-inspector)
inspector-list-processes (list-os-processes &key inspector) (os-process-start-time pid &key inspector)
(os-process-alive-p pid &key start-time inspector) (kill-os-processes pids &key force inspector)
(kill-os-process-group pgid &key force)

;;; constants
+unit-states+ +live-states+ +final-states+ +event-types+ +scope-kinds+ +unit-file-format+
+default-grace+ +default-force-grace+ +default-backoff+ +default-max-restarts+
+default-event-capacity+ +default-head-size+ +default-tail-size+ +default-sweep-grace+
```

## Contract (tests)

`supervisor-protocol/tests` (Rove; 107 forms, 114 cases with the parametrized ones). CI: the canned `test-system.yml` on macOS, Linux and Windows. Child programs are this SBCL itself (runtime + core, no init files: sleepers writing their pid, an echo server, a tree with grandchildren, a TERM-ignoring child), so the same fixtures run on every OS; liveness and external kills use `ps`/`kill` and `tasklist`/`taskkill` directly, never the code under test. Per-OS skips with a note: on Windows the `ps` inspector, process-group kill, the POSIX `sh` tree and the real TERM-ignoring escalation (4 cases); on macOS and Linux the CIM inspector and the group-kill refusal (2 cases).

| File | Covers |
|------|--------|
| `model-test` | constants, condition classes, default restart policies, `current-pid`, the default inspector, `restart-delay` (8 parametrized cases), head-tail construction; **the test programs themselves** (tree pgids, echo, exit codes, TERM-ignoring) |
| `output-test` | whole text below the caps, head + marker + tail, many small writes, zero head, close, 8 concurrent writers, a custom sink factory |
| `unit-test` | supervisor basics, every process-unit reader, ids per kind, exit codes 0 / 3, stdout + stderr captured, cwd + env, thread outcomes (`*current-unit*`, `*current-scope*`, own thread, result, error), start errors (no program, neither/both, executor refusal, foreign owner, no id consumed), after shutdown, a custom executor, capabilities, input errors |
| `query-test` | **the H8a fixture** (session › agent › tool source + subagent scope; 2 shell jobs, a fake stdio echo server, a subagent thread that starts its own job): exact queries by kind / owner (recursive and not) / labels / state, echo round trip, **closing the subagent scope stops only its units** |
| `scope-test` | tree and paths, `*current-scope*` defaults, `with-scope` closes on return and on non-local exit, closed scopes refuse, descendants close, one stop wave |
| `restart-test` | **a killed server restarts exactly once with backoff** (exact event sequence, delay ≥ backoff, same id, new pid, rewired I/O), `:never`, success and stops do not restart, thread restarts up to max, stop cancels a pending restart, relaunch failure counts as an attempt |
| `events-test` | one unit's events, killed detail, `events-since`, **`subscribe :since` replays then continues (no gap, no duplicate)**, unsubscribe, a failing subscriber is dropped, one dispatcher thread in seq order under 10 concurrent units, capacity, shutdown delivers then ends |
| `caps-test` | LRU finished eviction (silent, event), other kinds unaffected, all-live → `unit-limit-reached` (victim), `evict-lru`, `abort` (no id consumed), interacting never evicted (no `evict-lru` without a victim), owner cap counts direct ownership, LRU touches, process eviction kills the process |
| `stop-test` | graceful process stop, **real escalation on a TERM-ignoring child** (Unix), `keep-waiting` ×2 then `force`, `waited`, `stop-failed` + `abandon` (+ event detail), cooperative and forced thread stops (cleanups run), POSIX `sh` tree, Lisp tree on every OS, **exit reaps the rest of the tree**, `stop-units` selection |
| `unit-file-test` | directory, lifecycle and exact content, none for threads / without a state directory, rewritten on restart, gone after stop and eviction, atomic rewrite, unreadable files (`#.` never evaluated) |
| `sweep-test` | `ps` / CIM inspectors, liveness with start time, OS kills, sweep: missing directory, **orphans of a dead supervisor (root + grandchildren)**, **pid-reuse guard**, gone, live owner kept, same-image dead supervisor, unreadable deleted, `make-supervisor` sweeps first / `:sweep nil`; **crash simulation**: a child SBCL with a tree job, an rpc server and a thread is SIGKILLed / TerminateProcess'd, a new supervisor's sweep reaps every orphan including grandchildren |
| `shutdown-test` | shutdown stops everything (tree, thread, files, scopes, queries still answer), exit-hook registration and removal, **a child image that exits normally stops its units through the exit hook** |
| `regression-test` | Claude Code: status never stale after exit / external kill / thread return; **scope close on interrupt** (`bt2:interrupt-thread` unwinding a `with-scope`); units stay tracked after "compaction" (no references held, GC); Windows tree kill (every OS) |

Locally (macOS, stubs): 9 cases pass (given code + the test programs), 2 skip, 103 fail on `%h8a-pending`; the systems load with no warnings. Expected on Linux the same, on Windows 9 pass, 4 skip, 101 fail.

## Later: H8a-1 and after

- **H8a-1 — OS-enforced death** as backends with a capability query (`supervisor-supports-p :pdeathsig` …): Linux `PR_SET_PDEATHSIG` + `PR_SET_CHILD_SUBREAPER` (also catches `setsid` escapees), Windows job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, macOS kqueue `EVFILT_PROC NOTE_EXIT` for exit notices. Natives through `fs-backend-*`-style overlays; the sweep stays as the fallback.
- **H8a-1 — executors**: `pty-protocol` (pty-backend-native), optional **tmux** (attachable, Pi-style), later `compute-backend-*` confinement (R4d confines spawns through the supervisor).
- **H8a-1 — consumer migration**: agent-tools `shell-tools` jobs, `rpc-backend-stdio` child servers, `lisp-mcp` `repl-spawn` become units.
- **H8b** rotated, capped log files behind `:output-sink-factory`; **H8c** search/read/tail tools; **H8d** TUI / `--rpc` / web views over the event stream.
- Not in 0.1.0: Windows graceful stop (CTRL_BREAK), a per-session total cap, persisting finished units across restarts, narrowing the sweep to processes a `setsid` moved out of the group.

# supervisor-protocol (H8a, H8b, H8c) — process supervisor core, unit logs, log search

**Repo:** [`egao1980/supervisor-protocol`](https://github.com/egao1980/supervisor-protocol) · **Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) rows H8a–H8d, "Backlog note: why H8", "Decisions (2026-11-21)"
**Status:** **H8a shipped** (0.1.0). **H8b shipped** (0.2.0, rotated capped unit logs): [section below](#h8b-locked--rotated-capped-unit-logs-020). **H8c locked** (0.3.0, log search index, `restart-unit`, `close-unit-input`): [section below](#h8c-locked--log-search-index-manual-restart-stdin-close-030); its agent tools are [agent-tools-units.md](agent-tools-units.md). Implementation via **team-solve**. Later rungs: [H8a-1](#later-h8a-1-and-after).

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

## H8b locked — rotated, capped unit logs (0.2.0)

**Status:** **H8b shipped**, version **0.2.0** (same repo, published). Contract on branch `agent/h8b-contract-b2b9` ([PR #2](https://github.com/egao1980/supervisor-protocol/pull/2)): given code, stubs (`%h8b-pending`) and the failing tests. Implementation via **team-solve**. Plan: [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) row H8b, "Decisions (2026-11-21)" item 2. H8c (search / read / tail tools) and H8d (views) build on the reader API below.

Every unit's stdout and stderr go to rotated, size-capped segment files by default. Memory keeps only the H8a head + tail buffer, fed from the same pump. Nothing is unbounded, and nothing is lost without a trace: a dropped segment leaves a marker with exact counts, and reads that cross it report a gap. Logs stay readable after the unit finishes, after the supervisor shuts down, and after a SIGKILL, by this image or the next.

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| logrotate / journald / Docker `json-file` (`max-size` × `max-file`) | Size × count rotation per unit; a global cap; a stamped record per line | `copytruncate` (racy, double I/O); binary journal formats; compression |
| Codex `unified_exec`, H8a | The head + tail in memory | — |
| Kafka log segments | Numbered append-only segments with a sparse offset index, rebuilt from the segment | Time indexes, compaction |
| SQLite WAL / LevelDB log | A checksum per record: a torn tail is detected and ignored, never trusted | Block framing |

### Decisions (locked)

| Decision | Choice |
|----------|--------|
| **Where** | `(unit-log-pathname state-directory supervisor-id unit-id)` = `<state-directory>/units/<supervisor-id>--<unit-id>/`, next to the H8a `.unit` file. The supervisor id keeps two supervisors on one state directory apart, and makes previous supervisors' logs findable (`find-unit-logs`). Files `NNNNNNNN.seg` (8 digits, from `00000001`) and `NNNNNNNN.idx`. The sweep ignores these directories; shutdown keeps them |
| **When** | `default-output-sink` makes a `log-sink` when `(getf (unit-log-settings unit) :enabled)`: the supervisor has a state directory, `make-supervisor :log` (default T), and `start-unit :log` (default T). Otherwise a `head-tail-buffer`, as in 0.1.0. `:output-sink-factory` still replaces the default |
| **Caps** | Per unit: `:log-segment-size` (default **1 MiB**) × `:log-segments` (default **5**), set on `make-supervisor` and overridable per `start-unit` (`unit-log-settings` = `(:enabled b :segment-size n :segments k)`). No segment file exceeds its size. Opening segment N+1 when more than K would be retained drops the oldest. Per supervisor: `:log-total-cap` (default **256 MiB**) over segment and index files of every log it wrote, including units evicted from the registry (`supervisor-log-usage`). After each rotation and each finished unit, while usage is over the cap: first the **finished** unit that finished earliest loses its oldest segment, and its newest is replaced by a stub (header + drop marker + end record, written as segment N+1 atomically, then N deleted). A unit already reduced to a stub is skipped. Then a **live** unit's oldest segment that is not its newest. A live unit's newest segment is **never** evicted, so usage can exceed the cap by at most those segments plus stubs. Other supervisors' logs are not counted |
| **Record format** (`+log-format+` 1) | One line per record, all ASCII except UTF-8 text payloads: `<line> <wall-ms> <mono-ms> <tag> <payload> <crc>\n`. `line` is the record number, 1-based and contiguous across the unit's segments; every record takes one, including headers and markers. `wall-ms` = Unix epoch ms, `mono-ms` = the writer's monotonic clock in ms. `tag` = type (`o` stdout, `e` stderr, `h` header, `d` drop, `x` end) + encoding (`t`/`b`) + continuation (`.` = an LF ended these octets in the output (not stored), `+` = no LF: the line continues in the next record of that stream, or the output stopped). `crc` = CRC-32 (IEEE, as zlib) of every byte before ` <crc>`, 8 lowercase hex digits. Meta records (`h d x`) carry a plist printed `with-standard-io-syntax` in the keyword package (as unit files), read with `*read-eval*` NIL. Golden lines are in the tests |
| **Why this format** | Line-oriented, so `grep`, `tail -f` and H8c's chunker work on it, and so a torn tail is simply "no LF or bad CRC". Append-only: a crash can only tear the last line. The CRC also rejects zero-filled or garbage tails (power loss) and in-place damage, which becomes a `:corrupt` gap of only the damaged line. The rejected alternatives were length-prefixed binary frames (not greppable; one bad length desynchronises the rest of the file), JSON lines (an escaping cost on every byte, and no checksum), and Lisp-printed records (`read` is slow and unsafe on damaged input) |
| **Binary / non-UTF-8** | Per record: **escaped text** when the octets are valid UTF-8 and the escaped form is no longer than base64. Escaping is `\` → `\\`, C0 controls except TAB and DEL → `\xHH`, everything else raw. Otherwise **base64** (RFC 4648, padded). Escaping keeps normal output readable and greppable at about 1.0×. Base64 bounds the worst case at 4/3 and round-trips any bytes exactly, where a pure `\xHH` scheme costs 4× on binary. Readers get `log-record-octets` (exact) and `log-record-text` (UTF-8, invalid bytes → U+FFFD) |
| **Splitting** | `sink-write-octets` splits each stream at LF. Each call flushes: a remainder without an LF becomes a `+` record at once, so nothing waits in memory, and prompts and progress bars are visible. The exception is an incomplete UTF-8 sequence at the end (at most 3 octets), which is carried to that stream's next call (flushed by `sink-close`). Lines longer than `:log-max-record` (default **8192** octets) split into `+` records, moved back to a character boundary when the bytes are UTF-8. Constraint: segment size ≥ 512 + 2 × max-record (else `supervisor-error`). Concatenating a stream's record octets, with an LF after each `.` record, gives back exactly the bytes the unit wrote |
| **Header / markers / end** | Every segment starts with `h`: `(:format 1 :supervisor-id :unit-id :kind :segment :first-line :dropped-through :dropped-records :dropped-bytes)` (cumulative drops before it). Each dropped segment leaves a `d` record in the unit's newest segment: `(:segment :first-line :last-line :records :bytes :reason :rotated\|:total-cap)`, where RECORDS = lines it held and BYTES = output octets it carried (payload + 1 per `.`). `sink-close` writes `x`: `(:last-line :bytes)` (all output octets ever accepted). Dropped segments are always a numeric prefix, so readers ignore any segment at or below the highest `:dropped-through` / `d :segment` they see |
| **Index** | `NNNNNNNN.idx`, little-endian: `"SPLX"`, u32 stride (`+log-index-stride+` 64, `make-log-sink :index-stride`), u64 first line, then u64 byte offsets of lines first + k·stride. A line lookup is one seek plus a scan of at most stride − 1 records. It is appended and flushed with the segment. Readers treat it as untrusted. If it is missing, has a bad header, or has an entry that does not point at its line, they scan instead and rewrite the index atomically (`cl-stack-pathlib` `fs-write-atomic`), except for the newest segment of an open log (no end record), whose writer may be alive in another image. `rebuild-log-index` does any segment on request. A partial last entry is ignored |
| **Durability** | Each `sink-write-octets` ends with `finish-output` on the segment, so readers in this or another image see the records at once. Everything a unit wrote is in its records before its final state is published (pumps joined, thread streams flushed). The end record follows right after, from `sink-close` in the finish path, so code that needs it waits on `log-closed-p` or on `log-follow`'s ENDED-P. A SIGKILL loses at most the torn last line (plus ≤ 3 carried octets of a split character). No fsync: a power loss may lose the tail, and the CRC rejects whatever garbage it leaves |
| **Windows rotation** | SBCL opens files with `FILE_SHARE_READ \| FILE_SHARE_WRITE` only (no `FILE_SHARE_DELETE`, `src/code/win32.lisp`), so a segment a reader holds open cannot be deleted or renamed. **Chosen: logical drop + deferred delete.** The marker is written at once and the segment is no longer listed or read. The physical delete is retried at every rotation, at `sink-close` and at `shutdown-supervisor`. Readers hold a segment open only for one call. Rejected: a native `CreateFileW` with `FILE_SHARE_DELETE` (SBCL-only native code that cannot fix foreign readers such as editors or `type`), and copy-on-rotate (twice the I/O, and a crash window between copy and truncate). Unix unlinks at once, and an open reader keeps its inode |
| **Write errors** | Any ERROR while opening, writing or flushing a segment or index signals `log-write-error` (sink, unit, path, cause), a `supervisor-condition` that is **not** an error (like `stop-timeout`: `signal`, never `error`, so handlers on ERROR — `handler-case error` wrappers, test runners — never see it), inside `restart-case` with **`retry`** (reopen via `log-open-segment-stream`, write the record again), **`drop-to-memory-only`** (permanent for the sink: no more files, the head + tail keeps going, `log-sink-memory-only-p`), and, when the sink has a unit, **`abort-unit`** (request a forced stop without waiting; the unit ends `:killed`). The order is: the writing thread's dynamic handlers first (a pump, or a thread unit's own thread, so the body's `handler-bind` wins), then `make-supervisor :log-error-handler`, then the default **`drop-to-memory-only`**. Every outcome publishes one **`:log-error`** event (`+event-types+` gains it): `from` = `to` = the unit's state, detail `(:action :memory-only\|:retry\|:abort-unit :path "…" :message "…")`. The default never stops the unit and never enters the debugger |
| **Process pumps** | `pp:launch … :element-type :octets` (all three pipes). Pumps hand the bytes to `sink-write-octets` unchanged: what one read returned, at once (a prompt without an LF is visible), except that a read that fills the 16 KiB buffer while more output is waiting is cut back to its last LF and the rest completed by the next read, so a read size limit never splits a line into two records (0.3.1, [supervisor-protocol#5](https://github.com/egao1980/supervisor-protocol/issues/5); a full buffer without an LF goes on whole). `send-unit-input` encodes UTF-8. The default `sink-write-octets` on any `output-sink` decodes UTF-8 incrementally per stream and calls `sink-write`, so 0.1.0 sinks keep working |
| **Thread units** | The thread executor binds `*standard-output*` / `*error-output*` to `sink-output-stream`s (trivial-gray-streams; `:stdout` / `:stderr`). Characters are buffered until a newline, 4096 characters, `finish-output` / `force-output` or close; each flush is one `sink-write`. Both streams are flushed however the body ends. `sink-write` on a `log-sink` encodes UTF-8 and records it like a pump |
| **Readers** | Each takes a log designator: `unit-log`, `unit`, `log-sink`, or a directory pathname / namestring. Readers parse the files, so a running unit, a finished one and a previous supervisor's log read the same way. They are thread-safe and safe while writing. `log-read (&key start end streams types limit)` → `(values records gaps next-line)`. `streams` defaults to `(:stdout :stderr)`, `types` to `(:output)` (T = all), and `next-line` continues paging. `log-tail n &key streams` → `(values records gaps)`. `log-follow (&key from wait streams limit)` → `(values records gaps next-line ended-p)`: it waits up to WAIT s, woken by the sink when it lives in this image, else polling every ≤ 100 ms. ENDED-P = end record present and nothing selected at or after FROM. Also `map-log-records`, `log-segments` → `log-segment-info` (number, path, index path, first/last line, records, bytes, output bytes, first/last wall time, `torn-p`), `log-last-line`, `log-closed-p`, `rebuild-log-index`, `find-unit-logs state-dir &key supervisor-id unit-id` (sorted by directory name), and `delete-unit-log`. A unit without a log, or a directory that is not one → `log-not-found` |
| **Gaps** | `log-gap`: first/last line, records, bytes (NIL when unknown), reasons ⊂ `(:rotated :total-cap :corrupt :missing)`. A gap is a maximal range of missing line numbers. Its counts come from the markers and the newest header's cumulative fields, so they are exact for drops. `:corrupt` = invalid bytes between valid records (skipped up to the next LF). `:missing` = lines absent with no marker (deleted from outside). A read that touches a gap returns the whole gap. Records filtered out by STREAMS / TYPES are not gaps |
| **File I/O** | **cl-stack-pathlib 0.9.0** for directory creation and listing, unlink, `fs-rename` (MoveFileExW replace semantics on Windows), `fs-write-atomic` (indexes, stubs), `fs-read-range` and `fs-file-size`. The append writer is a plain `cl:open … :element-type (unsigned-byte 8) :if-exists :append` stream, because pathlib's `fs-open` is input-only ([cl-stack-pathlib#45](https://github.com/egao1980/cl-stack-pathlib/issues/45)) and `fs-write-bytes :append` opens and closes per call, which is too slow for a pump. It is behind the GF `log-open-segment-stream` (tests inject failing streams through it). **encoding-protocol 0.2.0** for base64 and UTF-8. **trivial-gray-streams** for the thread streams (the stack has no Gray-stream layer). No other new dependency |
| **Threads** | One lock per `log-sink`. Writes from both pumps and a reader in any thread are safe. No user code runs under the supervisor lock: the sink publishes `:log-error` events and calls the handler outside it |
| **Stubs** | `%h8b-pending` (internal, `src/model.lisp`). Given: constants, exports, conditions, the classes and their readers (`log-sink`, `log-record`, `unit-log`, `log-gap`, `log-segment-info`, `sink-output-stream`), `make-log-record`, `unit-log-pathname`, the default `log-open-segment-stream` method, `make-supervisor` `:log*` keys and `start-unit` `:log*` keys (stored; `unit-log-settings` computed), and the docstrings of everything stubbed. The implementation removes `%h8b-pending` and every call, changes `default-output-sink`, the process pumps and the thread executor as described, and may add slots |

### Surface (added in 0.2.0)

```lisp
;;; constants
+log-format+ +default-log-segment-size+ +default-log-segments+ +default-log-total-cap+
+default-log-max-record+ +log-index-stride+ +log-record-types+ +log-gap-reasons+
;; +event-types+ = (:state :restart-scheduled :evicted :log-error)

;;; supervisor / units
(make-supervisor … &key (log t) log-segment-size log-segments log-total-cap log-max-record log-error-handler)
supervisor-log-p supervisor-log-segment-size supervisor-log-segments supervisor-log-total-cap
supervisor-log-max-record supervisor-log-error-handler (supervisor-log-usage sup)
(start-unit … &key (log t) log-segment-size log-segments)  unit-log-settings

;;; sinks
(sink-write-octets sink stream octets &key start end)                 ; GF, default decodes → sink-write
log-sink (make-log-sink dir &key class unit supervisor-id unit-id kind segment-size segments
                                  max-record index-stride head-size tail-size)
log-sink-directory log-sink-unit log-sink-supervisor-id log-sink-unit-id log-sink-kind
log-sink-segment-size log-sink-segments log-sink-max-record log-sink-index-stride
log-sink-memory-only-p log-sink-last-line (log-open-segment-stream sink path)
(unit-log-pathname state-dir supervisor-id unit-id)
sink-output-stream (make-sink-output-stream sink :stdout|:stderr) sink-output-stream-sink sink-output-stream-name

;;; records
log-record (make-log-record &key line wall-time monotonic type stream octets continued-p detail)
log-record-line -wall-time -monotonic -type -stream -octets -text -continued-p -detail -segment -offset
(format-log-record r) → octets   (parse-log-record octets &key start end) → record | NIL, next

;;; readers
unit-log (unit-log designator) unit-log-directory unit-log-supervisor-id unit-log-unit-id
(find-unit-logs state-dir &key supervisor-id unit-id) (delete-unit-log log)
(log-read log &key start end streams types limit) (log-tail log n &key streams)
(log-follow log &key from wait streams limit) (map-log-records fn log &key start end streams types)
(log-segments log) (log-last-line log) (log-closed-p log) (rebuild-log-index log &key segment)
log-gap log-gap-first-line -last-line -records -bytes -reasons
log-segment-info log-segment-number -path -index-path -first-line -last-line -records -bytes
                 -output-bytes -first-time -last-time -torn-p

;;; conditions and restarts
log-write-error (log-write-error-sink -unit -path -cause)  log-not-found (log-not-found-path)
retry drop-to-memory-only abort-unit
```

### Contract (tests)

`supervisor-protocol/tests` grows by **49 forms / 55 cases**, all on macOS, Linux and Windows. There are no skips; the open-reader rotation case asserts per-OS expectations. Small caps (1–2 KiB segments) exercise rotation fast. The 100 MiB case uses the defaults. The 0.1.0 suite is unchanged except `+event-types+` gaining `:log-error`.

| File | Covers |
|------|--------|
| `log-format-test` | constants and condition classes; **golden lines** (text, escapes, base64 for invalid UTF-8 and for control-heavy text, empty line, header plist), 7 parametrized round trips, rejection of torn / cut / CRC-mismatch / zero-filled / garbage / bad-escape lines |
| `log-sink-test` | construction and the size constraint; header and end records with exact detail; empty close; `+` continuation per call and per stream; `:start`/`:end`; **long-line splitting** on character boundaries; UTF-8 carried across writes; **binary round trip** (20 000 random bytes in random chunks; no control byte in the files); the head + tail view; **rotation caps** (≤ K files, each ≤ its size); **drop markers exact** (gap = prefix, records and bytes = what was written) |
| `log-reader-test` | **reads across rotation boundaries seamless**; paging with `next-line`; the whole gap reported; `log-tail`; **`log-follow` returns within its wait** (live sink and polled directory, timeout, end record); `map-log-records`; segment stats; index layout (entries point at their lines); **index rebuild** (missing / corrupt, byte-identical, explicit); torn tail skipped; corrupt bytes = one `:corrupt` gap; **open-reader rotation** (Windows deferred delete, Unix unlink); designators, `find-unit-logs`, `delete-unit-log`, `log-not-found` |
| `log-supervisor-test` | default sinks and settings (`:log nil`, per-start overrides, no state dir → 0.1.0); process stdout/stderr in arrival order; **binary process output round-trips**; **a chatty unit (100 MiB) stays under 1 MiB × 5**, drop + retained bytes = everything written, memory = head + tail; thread-unit `*standard-output*` / `*error-output*`; stream flush rules; **total-cap eviction order** (finished-earliest first, then live units' old segments, never a live unit's newest; stubs; usage = file bytes); a restarted unit continues one log; logs outlive registry eviction and shutdown; follow a live echo server |
| `log-error-test` | **disk-error restarts** through a sink subclass whose segment streams are closed: default memory-only + one `:log-error` event and the unit still `:exited`; `retry` via `:log-error-handler` (nothing lost); `abort-unit` (`:killed`); a thread body's `handler-bind` wins over the supervisor's; standalone sinks (no `abort-unit`; unhandled → memory-only, no error) |
| `log-crash-test` | **a SIGKILLed / TerminateProcess'd child supervisor** with a chatty thread unit: the next image finds the log, reads ≥ 2000 contiguous lines across segments with no gap, skips an appended torn tail, reads without indexes and rebuilds them; a new supervisor on the same directory leaves the old log untouched |

Locally (macOS, stubs): the 114 H8a cases still pass or skip as before (112 pass, 2 skip). Of the new cases, 1 passes (constants and conditions) and 54 fail on `%h8b-pending`. The systems load with no warnings. Expected the same on Linux. On Windows the H8a skips are 4, and the new cases match macOS.

### Not in 0.2.0

Retention across supervisors (old sessions' logs stay until `delete-unit-log`; H8c decides a policy), compression of old segments, fsync per record, a time index, and persisting the head + tail.

## H8c locked — log search index, manual restart, stdin close (0.3.0)

**Status:** **H8c locked**, version **0.3.0** (same repo). Contract on branch `agent/h8c-contract-238f` ([PR #3](https://github.com/egao1980/supervisor-protocol/pull/3)): given code, stubs (`%h8c-pending`) and the failing tests. Implementation via **team-solve, run 1 of 2**; run 2 is the agent tool source in agent-tools ([agent-tools-units.md](agent-tools-units.md)), which needs this one published first. Plan: [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) row H8c, "Decisions (2026-11-21)" item 2.

Agents reach unit output through search, read and tail, not raw dumps. This rung builds the engine: an incremental lexical index over the H8b segments, with structured hits for the lines an agent usually looks for first. It also adds the two controls the tool source needs and 0.2.0 lacks: a manual restart and closing a unit's stdin.

### Home (decided)

| Piece | Home | Why |
|-------|------|-----|
| Index, tokenizer, kind rules, BM25 search | **`supervisor-protocol/search`**, a secondary system in this repo (`src/search/`, package `supervisor-protocol/search`, version 0.3.0) | It reads the H8b record format and segment lifecycle directly (index files live and die with segments), so it belongs with the log writer. Pure Lisp on the stack, no agent, JSON or LLM dependency. A secondary system keeps the supervisor core free of the index for consumers that only supervise (rpc-backend-stdio, lisp-mcp) |
| `restart-unit`, `close-unit-input` | primary `supervisor-protocol` 0.3.0 | Supervisor state transitions; the tool source must not reach into internals |
| Agent tools (`unit_list` … `unit_control`), shell jobs as units | **agent-tools 0.3.0**, a new `unit-tools` source | The agent core (`ai-agent-protocol`) stays free of process management (the Pi lesson). Tool JSON, permissions and output caps already live in agent-tools |

Considered and rejected: a separate `egao1980/unit-search` repo (one more publish hop for a module that is meaningless without the H8b format; the format version and the index version would drift apart), and putting the index in agent-tools (the TUI panel and `--rpc` of H8d need the same search without agent tools).

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Lucene / Elasticsearch BM25 | k1 1.2, b 0.75, IDF ln(1 + (N − df + 0.5)/(df + 0.5)) (never negative) | Positional indexes, analyzers per field, segment merging |
| Code search tokenizers (GitHub code search, Sourcegraph, Zoekt) | Identifiers kept whole and split at camel / snake boundaries; paths kept whole plus components | Trigram indexes (no regex search here) |
| Log tools (Loki labels, `grep -C`, journalctl) | Line refs and context lines; filters by unit, stream, time | A query language |
| CI log parsers (GitHub problem matchers, Jenkins warnings-ng) | Rule-based detection of compiler errors, warnings and test failures | Per-tool regex catalogues; we keep a small, tested rule set |
| Claude Code / Codex | Agents get bounded, ref-bearing excerpts instead of the whole buffer | — |

### Decisions (locked)

| Decision | Choice |
|----------|--------|
| **Systems** | `supervisor-protocol/search` depends on `supervisor-protocol` 0.3.0, `cl-stack-pathlib` 0.9.0 (atomic writes, unlink), `encoding-protocol` 0.2.0 (UTF-8), `bordeaux-threads`, `uiop`. Tests stay in `supervisor-protocol/tests` (it now also loads the search system) |
| **Documents** | A **block** = lines 16B+1 … 16B+16 of one log (`+default-block-lines+`, line numbers as H8b assigns them, headers included). Fixed boundaries, so a rebuild, an incremental build and a different refresh rhythm give the same blocks. Blocks are scored; a hit is one line of a block |
| **What is indexed** | Output records only (`o`/`e`), each record its own line (a `+` continuation is a line of its own). Record text = `log-record-text` (UTF-8, U+FFFD for invalid bytes). Header, drop and end records are not tokenized; end records are `:exit` hits |
| **Tokenizer** (`+tokenizer-version+` 1) | (1) strip ANSI escapes; `\` → `/`. (2) Spans: runs of word characters (`alphanumericp` or `_`) and the separators `- . / : @ #`. (3) Trim separators off both ends. (4) A span still holding a separator is a **compound**: emit it; if it ends in `:<digits>` groups also emit the prefix before them (`src/foo.lisp:12:5` → `src/foo.lisp`); split that prefix at `/` and `:` and emit each component that still has a separator (`foo.lisp`, `my-package`, `some-function`). (5) Words: runs of word characters. (6) Sub-words: split a word at `_`, at lower/digit → upper, and before the last capital of a capital run followed by a lowercase letter (`parseHTTPResponse_v2` → `parse http response v2`), when that gives ≥ 2 parts; letters and digits are not split (`sha256`, `utf8`). (7) Lowercase; drop one-character terms unless a digit; drop terms over 64 characters (`+max-term-length+`). Per span: compound-level terms first (distinct), then each word and its distinct sub-words; otherwise one term per occurrence. No stemming, no stop words. Queries use the same function; `"double quotes"` add a case-insensitive phrase filter |
| **Why this tokenizer** | Log and code queries are identifiers, paths, file:line refs and error words. Keeping compounds whole makes `src/parser.c` and `my-package::fn` precise; their parts keep recall (`parser`, `fn`). Camel / snake splitting finds `TypeError` from `error` and `test_total_counts_all_items` from `total`. Stemming and stop words hurt code tokens (`errors.c` is not an error; `in` and `at` matter in stack frames) |
| **Kinds** | `+hit-kinds+` = `(:error :warning :stack-trace :test-failure :exit)`. One-line rules over a **word set** (words + sub-words; a path-like span — one with `/`, or a `.` between a word character and a letter — contributes only its last component's words, so `error.log` and `errors.c` are not errors): **:error** ⇔ `error err fatal panic panicked exception critical`; **:warning** ⇔ `warning warn deprecated deprecation`; either not right after `no`, `0`, `zero`, `without` (`0 Error(s)`, `no error`). Plurals do not match (`0 errors, 2 warnings`). **:test-failure** on the left-trimmed line: Rove `× <n>)`; pytest `FAILED …::…` and `…::… FAILED`; jest `✕ ` and `● … › …`; cargo `test … ... FAILED`; go `--- FAIL: `; generic `FAIL` + space/tab. **:stack-trace** (kind on the first line, `hit-extent` = first..last): Python `Traceback (most recent call last):` + indented lines + the exception line; frame runs `<n>: …` numbered from 0 (≥ 2 frames; a preceding `Backtrace for:` / `stack backtrace:` header starts it; indented `at ` lines continue it — SBCL, Rove, Rust); at-line runs (≥ 2 lines `<ws>at <x>`, continued by `Caused by: ` and `... N more`; the non-indented line before starts it — JS, Java). Each stream of a log is classified separately, in line order across segments; a trace completed by a later refresh updates the earlier line |
| **Ranking** | Candidates: output lines of the selected logs and streams, in the time range, with a selected kind (when KINDS), containing every phrase, and (when there are terms) at least one **clause term**: per query span its first term, i.e. the whole compound for a compound span (`zzzz-not-there`), else the word. A query compound must occur whole; its parts (`not`) only add to the score of a line that already matched; every term scores. **With terms**: BM25 per block, tf and dl over the block's lines in the selected streams and time range, N / df / avgdl over all blocks of the selected logs; `+ kind-boost` (0.5) when the hit line has :error, :stack-trace or :test-failure. Hit line = most distinct query terms, then a boosted kind, then earliest. One hit per block. Order: score ↓, time ↓, key, line ↑. **Without terms** (kinds only): every candidate line is a hit, score NIL. Order: **severity**, then time ↓, key, line ↓ (newest first within a severity). Severity = the hit's most severe kind among KINDS, in the order :test-failure, :stack-trace, :error, :warning, :exit (a failed test names what is broken, a trace locates a fault, an error line reports one, a warning is not a failure, an end record is lifecycle). With one kind the result is just newest first. `search-logs` → `(values hits total)` where TOTAL counts hits before the cut to K, so callers can say "showing 5 of 23" honestly |
| **Keys and refs** | Key = unit id for the index's supervisor (evicted units included), else the log directory name `<supervisor-id>--<unit-id>` (previous supervisors), or `index-add-log`'s key. Ref = `"<key>:<segment>:<line>"` (`format-log-ref`, `parse-log-ref`, `hit-ref`): the line number is what resolves; the segment says where it was found and shows a drop at a glance |
| **Incremental** | `refresh-index` (called by every search) discovers new logs, forgets dropped segments, loads valid index files, and tokenizes only records it has not indexed (a running unit's new lines). Cheap when nothing changed (segment sizes compared). `index-stats :tokenized` proves nothing is tokenized twice |
| **Persistence** | `NNNNNNNN.six` next to `NNNNNNNN.seg`, written atomically for every **sealed** segment (not the newest, or the newest of a closed log); the open newest segment is indexed in memory only (≤ 1 MiB to re-tokenize after a restart). Header: `"SPSI"`, u32 `+search-index-format+`, u32 `+tokenizer-version+`, u64 segment number, u64 segment byte size; body the implementation's; trailing CRC-32. Deterministic bytes: a rebuild is byte-identical. Untrusted: missing, other version, other size, bad CRC or unparsable → rebuilt from the segment. `:persist nil` writes nothing. A write failure is the WARNING `index-file-error` (the segment stays in memory) |
| **Drops and gaps** | A segment the reader no longer lists is forgotten and its `.six` deleted. **0.3.0 sink change:** dropping segment N deletes `NNNNNNNN.*` (seg, idx, six; Windows deferred delete covers all three) and `supervisor-log-usage` counts `.six` bytes, so the total cap stays honest. Nothing in a gap is searchable; `hit-excerpt` reports gaps the context touches |
| **Embeddings** | Hook only: GF `embed-texts (embedder texts)`, no method in this repo, no LLM dependency. With `:embedder`, each refresh calls it once per log with the texts of the blocks it completed (in order; every block once); vectors via `index-block-embedding`. Ranking ignores them in 0.3.0; hybrid ranking through `llm-protocol` embeddings is a later rung (H8c-1) |
| **`restart-unit`** | `(restart-unit u &key grace force-grace)`: stop if live (as `stop-unit`), cancel a pending policy restart, relaunch the same unit (same id, new run). Events `:state` FINAL → `:starting` detail `(:restart :manual)`, then → `:running`. `unit-restart-count` unchanged. The log continues in one line sequence; a new segment with a header follows an end record, and `log-closed-p` / ENDED-P look at the last end record only. Evicted → `supervisor-error`; shut down → `supervisor-closed`; launch failure → `unit-start-error`, unit `:failed` |
| **`close-unit-input`** | `(close-unit-input u)` → T when it closed stdin, NIL when already closed or finished; GF `executor-close-input` (process executor closes the pipe; default → `executor-unsupported`, so thread units refuse). `send-unit-input` afterwards → `unit-input-closed` (a `unit-error`). Lets the shell tools give foreground commands end of file |
| **Threads** | One lock per index; searches from several tool threads are safe; no user code (embedder) runs under it |
| **Stubs** | `%h8c-pending` (`src/model.lisp`, `src/search/model.lisp`). Given: exports, constants, conditions, `log-index` / `search-hit` classes and readers, `make-log-index`, refs, `embed-texts` GF. The implementation may add slots |

### Surface (added in 0.3.0)

```lisp
;;; supervisor-protocol
(restart-unit unit &key grace force-grace) → unit
(close-unit-input unit) → T | NIL        executor-close-input        unit-input-closed

;;; supervisor-protocol/search
+search-index-format+ +tokenizer-version+ +hit-kinds+ +default-block-lines+ +default-bm25-k1+
+default-bm25-b+ +default-kind-boost+ +max-term-length+ +default-search-k+
(strip-ansi string) (tokenize text) (query-terms query) → (values terms phrases)
(line-kinds text) (classify-lines texts) → ((index kinds end) …)
(format-log-ref key segment line) (parse-log-ref string) → (values key segment line)
(make-log-index &key supervisor state-directory (previous t) (persist t) block-lines k1 b kind-boost embedder)
log-index index-supervisor index-state-directory index-previous-p index-persist-p index-block-lines
index-k1 index-b index-kind-boost index-embedder index-closed-p
(index-add-log index designator &key key) (index-remove-log index key) (index-log-keys index)
(index-unit-log index key) (index-log-key index designator)
(refresh-index index &key keys) → records tokenized    (index-stats index) → plist
(close-log-index index)
(search-logs index query &key units since until streams kinds k) → (values hits total)
search-hit hit-key hit-log hit-segment hit-line hit-ref hit-kinds hit-score hit-stream hit-time
hit-text hit-extent    (hit-excerpt index hit &key context) → (values records gaps)
(embed-texts embedder texts)  (index-block-embedding index key block)
search-condition search-error index-closed index-file-error (path, cause)
```

### Contract (tests)

`supervisor-protocol/tests` grows by **51 forms / 121 cases**, all on macOS, Linux and Windows, no skips. The recorded corpus is `tests/fixtures/corpus/` (captured from real runs, local paths replaced by `/home/dev/…`; `.gitattributes` keeps the bytes): `build.log` (make + cc, 30 objects, an undeclared-identifier error and an unused-variable warning), `rove.log` (cl-repo test of a small system: 2 failures, a TYPE-ERROR, an SBCL backtrace, ANSI colours), `devserver.log` (a Node HTTP server: request lines on stdout; two TypeErrors with JS stacks and a DeprecationWarning on stderr), `pytest.log` (5 tests, 2 failed, an AssertionError and a KeyError). The tokenizer table, the kind rules and the golden rankings were checked against a throwaway prototype before sealing.

| File | Covers |
|------|--------|
| `control-test` | `close-unit-input` ends a stdin reader (exit 0), already closed, `unit-input-closed`, thread refusal; `restart-unit` of a live process (new pid, old one dead, exact events, count unchanged), of a finished thread (one log, both runs, contiguous lines, closed only after the second end), evicted / shut down, launch failure → `:failed` |
| `search-tokenizer-test` | constants and conditions; **18-row tokenizer table** (paths with line:col, Lisp symbols, camel / snake, URLs, emails, Windows paths, CJK, hex, long terms); ANSI; occurrence order and counts; `strip-ansi` (CSI, OSC + BEL / ST, ESC + intermediate); `query-terms` phrases |
| `search-kinds-test` | **36-row one-line kinds table** (compiler, SBCL, npm, Rust, Java, Python, MSBuild-style counts, Rove, pytest, jest, cargo, go, false positives); Python / SBCL debugger / Rust / Java / JS traces and non-traces; **every line of the four corpus logs classified** |
| `search-index-test` | keys and logs; **incremental refresh** (only new records tokenized); a stack trace completed by a later refresh; **`.six` written for sealed segments, loaded by a fresh index (nothing tokenized), rebuilt byte-identical when missing or corrupt**; the open newest segment in memory only; `:persist nil`; **drop forgets the segment and its file, gap respected**; excerpts report gaps; close; the embeddings hook (once per completed block) |
| `search-rank-test` | **BM25 by hand** (scores to 1e-4, index parameters), the kind boost (and none for warnings), hit-line choice and ties, one hit per block and TOTAL, kinds-only newest first, compound clause matching, extents, `:exit` hits, streams, time range (inclusive), unit globs, phrases, argument errors |
| `search-golden-test` | **15 golden queries over the corpus → the expected ref in the top k** (k 1–3), the kinds-only order (severity groups, newest first in a log), stack traces across the corpus newest first with extents, errors across the corpus, the units filter |
| `search-unit-test` | a **running unit indexed while it writes** (keys = unit ids, no record tokenized twice), **search across rotation after a drop**, **previous supervisors' logs** (and `:previous nil`), `.six` counted in `supervisor-log-usage`, a supervisor without a state directory |

Locally (macOS, stubs): the H8a / H8b cases pass and skip as before; of the new cases 1 passes (constants and conditions) and 120 fail on `%h8c-pending`. No new load warnings (the ASDF "deprecated recursive use" warning is the canned test-op's, as before).

### Not in 0.3.0

Semantic / hybrid ranking (H8c-1, through `llm-protocol` embeddings), regex search, a query language, retention of previous sessions' logs (they stay until `delete-unit-log`; a policy waits for H6's session daemon), and indexing logs of other harness processes.

---

## Later: H8a-1 and after

- **H8a-1 — OS-enforced death** as backends with a capability query (`supervisor-supports-p :pdeathsig` …): Linux `PR_SET_PDEATHSIG` + `PR_SET_CHILD_SUBREAPER` (also catches `setsid` escapees), Windows job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, macOS kqueue `EVFILT_PROC NOTE_EXIT` for exit notices. Natives through `fs-backend-*`-style overlays; the sweep stays as the fallback.
- **H8a-1 — executors**: `pty-protocol` (pty-backend-native), optional **tmux** (attachable, Pi-style), later `compute-backend-*` confinement (R4d confines spawns through the supervisor).
- **H8a-1 — consumer migration**: agent-tools `shell-tools` jobs, `rpc-backend-stdio` child servers, `lisp-mcp` `repl-spawn` become units.
- **H8b** rotated, capped log files (0.2.0, shipped); **H8c** search engine (0.3.0, shipped) and the agent tools ([agent-tools-units.md](agent-tools-units.md)); **H8c-1** hybrid ranking through `llm-protocol` embeddings (`embed-texts`); **H8d** TUI panel and `--rpc` `units/*` views over the event stream and the same search: locked in [cl-stack-code.md § H8d](cl-stack-code.md#h8d--locked) (cl-stack-code 0.8.0; the web page is a later H8d-1).
- Not in 0.1.0: Windows graceful stop (CTRL_BREAK), a per-session total cap, persisting finished units across restarts, narrowing the sweep to processes a `setsid` moved out of the group.

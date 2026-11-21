# agent-tools (H8c): tools over supervised units and their logs

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) row H8c, "Decisions (2026-11-21)" item 2 ("agents reach it through search/read/tail tools, not raw dumps")
**Status:** milestone **H8c locked**, version target **agent-tools 0.3.0**. Contract on branch `agent/h8c-contract-238f` of [`egao1980/agent-tools`](https://github.com/egao1980/agent-tools) ([PR #5](https://github.com/egao1980/agent-tools/pull/5)); new functions call `%h8c-pending`. Implementation via **team-solve, run 2 of 2**: it needs **supervisor-protocol 0.3.0** (run 1, the search engine, [supervisor.md § H8c](supervisor.md#h8c-locked--log-search-index-manual-restart-stdin-close-030)) merged and published first. File tools: [agent-tools.md](agent-tools.md). Shell tools: [agent-tools-shell.md](agent-tools-shell.md).

`unit-tools` is a third tool source in `agent-tools`, next to `file-tools` and `shell-tools`. It gives an `ai-agent-protocol` agent five tools over a `supervisor-protocol` supervisor:

- `unit_list`: what is running or ran (shell jobs, servers, subagents …).
- `unit_search`: ranked excerpts from the unit logs, with refs to drill down.
- `unit_read`: lines of a log by ref or range.
- `unit_tail`: the end of a log, or follow it.
- `unit_control`: stop, restart, or send input (asks for approval by default).

With a supervisor, `shell-tools` runs every `bash` command as a unit, and `job_list` / `job_output` become views over the unit logs with their H2c text unchanged.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code BashOutput / background tasks | Incremental reads of a running task; one model for shells and agents | Reading a task means its whole buffer |
| Codex `unified_exec` | Bounded output per call; `write_stdin` + read back | Token caps |
| `grep -C` / `journalctl -u … -f` / `kubectl logs --since` | Context lines, per-unit follow, since / until | Query languages |
| Sourcegraph / GitHub code search results | Ref-first result blocks, "showing N of M" | Ranking signals beyond BM25 |
| H2b / H2c (this repo) | JSON Schema conventions, `tool-input-error`, `read`'s numbered lines and continue notices, approval defaults, glob permission resources | — |

---

## Decisions (locked)

| Decision | Choice | Reason |
|----------|--------|--------|
| **Home** | The tool source lives in **agent-tools 0.3.0** (new `unit-tools`); the index and search engine live in **`supervisor-protocol/search`** (0.3.0). | The engine is pure Lisp next to the log format it reads, and H8d (TUI, `--rpc`) reuses it without agent tools. The agent core gains no dependency (Pi lesson); agent-tools already owns tool JSON, permissions and caps. |
| **Dependencies (new)** | `supervisor-protocol` ≥ 0.3.0 and `supervisor-protocol/search` ≥ 0.3.0 (local nicknames `sup`, `ss`). `cl-stack-pathlib` resolves to 0.9.0 through them. | Loading `agent-tools` is enough. |
| **Source shape** | `unit-tools` class; specializes `list-agent-tools`, `tool-executable-p`, `tool-needs-approval-p`, `invoke-tool-async` (worker thread, as H2b/H2c), `tool-permission-resources`. An agent lists it in `:tools` next to the other sources. | Same shape as `file-tools` / `shell-tools`. |
| **Visibility** | `:scope` (default the supervisor's root): units it owns directly or below. Previous supervisors' logs in the same state directory with `:previous t` (default), read and search only, keyed `<supervisor-id>--<unit-id>`. Anything else → `unit-not-found`. | A subagent's tools see only its own children; a resumed session can still read what the last one left. |
| **Index** | `:index` (a `log-index`), default a new one over the supervisor (closed by `close-unit-tools`). Every `unit_search` refreshes it, so a running unit's new lines are found at once. | One index per source; a product can share one. |
| **Caps** | `max-output` 30 000 characters per result, **everything included** (H2c's shell cap); `max-results` 100 rows (`unit_list`); `k` default 10, max 50; context default 2, max 10; `max-read-lines` 2000; `max-wait` 600 000 ms; one log line shows at most `+max-excerpt-line+` 500 characters, then `… [+N chars]`. | Same order as the shell and file tools; a result never surprises the context window. |
| **Refs** | Every hit, read and tail names `<unit>:<segment>:<line>` refs or the `start_line` / `after_line` to continue with. | Drill-down without re-searching. |
| **Approval** | `:needs-approval t` (default): `tool-needs-approval-p` is T for `unit_control` only. Reading never asks. | Control acts on processes; reading is harmless. |
| **Permission resources** | `unit_control` → `("<action>:<unit>")` (`stop:shell-job-3`); `unit_read` / `unit_tail` → `("unit:<unit>")` (a ref's unit); `unit_search` → `("unit:<pattern>")` per `units` entry, else `("unit:*")`; `unit_list` → `("*")`. Unparsable arguments → `("*")`; never signals. | One resource per call, so a single rule decides: `("unit_control" "stop:shell-job-*" :allow)` lets the agent stop shell jobs without asking while restarts still ask; `("unit_control" "*:subagent-*" :deny)` protects subagents. Deny-by-unit for `unit_search` only works with an explicit `units` list (an unrestricted search is `unit:*`). |
| **Shell under a supervisor** | `make-shell-tools :supervisor sup [:scope parent]`: the source makes a `:tool-source` scope `"shell"` under PARENT (default root). Every `bash` command is a `:shell-job` unit (labels `(:tool "bash")`, cwd = workdir, env as H2c), on the supervisor's process executor: `:executor :auto` → `:process`; `:pty` → ERROR until H8a-1 brings a pty executor. Foreground commands get EOF (`close-unit-input`) and are not jobs; `run_in_background` and the `run-in-background` restart make jobs. Job ids are the **unit ids** (`shell-job-2`). | One registry, one log, one kill path. The text of every tool stays H2c's, so models and tests that read it keep working. |
| **Stubs** | `%h8c-pending` (`src/unit-tools.lisp`). Given: exports, constants, classes and readers, `make-unit-tools`, `call-unit-tool` / `close-unit-tools` frames, descriptors and schemas, approval, invocation, the `make-shell-tools` keys. Stubbed: every tool body, `parse-time-argument`, the permission resources, the supervised shell path. | — |

---

## Surface (added in 0.3.0)

```lisp
(make-unit-tools &key supervisor index scope (previous t) (needs-approval t)
                      (max-output 30000) (max-results 100) (default-k 10) (max-k 50)
                      (context 2) (max-context 10) (max-read-lines 2000) (max-wait 600000)
                      (tools +unit-tool-names+))
  ;; SUPERVISOR required; a scope of another supervisor, an unknown tool name,
  ;; DEFAULT-K > MAX-K or CONTEXT > MAX-CONTEXT → ERROR.
unit-tools unit-tools-p unit-tools-supervisor unit-tools-index unit-tools-scope unit-tools-previous
unit-tools-needs-approval unit-tools-max-output unit-tools-max-results unit-tools-default-k
unit-tools-max-k unit-tools-context unit-tools-max-context unit-tools-max-read-lines
unit-tools-max-wait unit-tools-names unit-tools-closed-p
+unit-tool-names+        ; ("unit_list" "unit_search" "unit_read" "unit_tail" "unit_control")
+unit-search-kinds+      ; ("error" "warning" "stack-trace" "test-failure" "exit")
+unit-control-actions+   ; ("stop" "restart" "input")
+max-excerpt-line+       ; 500
(call-unit-tool tools name arguments) → string   ; not enabled → AGENT-UNKNOWN-TOOL; closed → TOOL-UNAVAILABLE
(close-unit-tools tools) → NIL                    ; idempotent; closes the index it made
(parse-time-argument string &key now) → Unix ms   ; RFC 3339 or "90s" "10m" "2h" "1d" ago
unit-not-found (TOOL-INPUT-ERROR)  unit-not-found-unit

;; shell-tools (H2c) additions
(make-shell-tools … &key supervisor scope)  shell-tools-supervisor  shell-tools-scope  shell-job-unit
```

---

## Tools

Results are plain strings, LF-separated, no trailing LF, never longer than `max-output`. Shared formats:

- **Log line:** `(format nil "~a~6d~c~a" mark line #\Tab text)`; MARK `>` for the hit / ref line, else a space; TEXT the record text with ANSI escapes and control characters (except TAB) removed, cut at 500 characters + `… [+N chars]`.
- **Gap:** `[gap: lines A-B not in the log (rotated)]` (reasons from `log-gap-reasons`, joined by `, `), in line order among the lines.
- **Status word** (`unit_list`, `unit_read`): `running`, `starting`, `exited <code>` / `failed <code>` (processes), `exited` / `failed` (threads), `killed`, `previous` (an earlier session's log). **Status phrase** (`unit_tail`): `running`, `starting`, `exited with code N`, `failed with code N`, `exited`, `failed`, `killed`, `from a previous session`.
- **Times:** RFC 3339 UTC, seconds in `unit_list` (`2026-11-21T12:00:01Z`), milliseconds in `unit_search` (`2026-11-21T12:00:01.250Z`).
- **Arguments:** decoded as H2b (`%decode-arguments`); unknown keys ignored; wrong types, out-of-range numbers, unknown enum values → `tool-input-error` naming the key or value. A unit the source cannot see → `unit-not-found` (message names the argument and `unit_list`).

### unit_list — `kind`, `state`, `owner`, `label`, `include_previous`

```
id	kind	state	owner	started	lines	labels	command
subagent-1	subagent	exited	s/a	2026-11-21T12:00:00Z	5	tool=demo	<thread>
shell-job-1	shell-job	running	s	2026-11-21T12:00:01Z	1	tool=bash	/usr/bin/sbcl --core … --eval (sleep 60)
```

- One TAB-separated row per visible unit, in start order (`find-units`), after the header row. kind = lowercase keyword name; owner = `scope-path` joined with `/`, `-` for the root; started = `unit-start-time`; lines = `log-last-line` (`-` without a log); labels = `key=value` (lowercase key) joined with `,`, `-` when none; command = argv joined with spaces, `<thread>` for thread units.
- `kind` exact; `state` one of `live` (starting, running), `finished` (exited, failed, killed) or a state; `owner` a glob (`*` any run) over the owner column; `label` an object of string pairs, all equal (`princ-to-string` of the label value).
- `include_previous: true` appends previous sessions' logs sorted by key: `<key> <kind from the header> previous - <first record time> <last line> - -`. A `state` filter leaves them out.
- None → `[no units]`. More than `max-results` rows, or over `max-output` → the rows that fit, then `[truncated: showing M of N units; filter by kind, state, owner or label]`.

### unit_search — `query`\*, `units`, `kinds`, `streams`, `since`, `until`, `k`, `context`

```
[1] shell-job-3:1:5 stdout 2026-11-21T12:00:01.250Z error
       3	cc -Wall -Wextra -O2 -c -o src/list.o src/list.c
       4	cc -Wall -Wextra -O2 -c -o src/parser.o src/parser.c
>      5	src/parser.c:7:12: error: use of undeclared identifier 'tokn'; did you mean 'tok'?
       6	    7 |     return tokn->kind + depth;
       7	      |            ^~~~

[2] shell-job-4:1:3 stderr 2026-11-21T12:00:02.000Z error,stack-trace (stack trace: lines 3-6)
…

[showing 2 of 9 results; raise k (max 50), narrow the query, units, kinds or since, or unit_read a ref]
```

- `search-logs` over the visible logs (`units`: ids / keys or globs over them), `streams` (default both), `kinds` (`+unit-search-kinds+`), `since` / `until` (`parse-time-argument`), `k`; each hit block = header `[i] <ref> <stream|-> <time> <kinds|->` (kinds joined with `,`; a stack trace adds ` (stack trace: lines A-B)`), then `hit-excerpt` with `context` lines. Blocks are separated by an empty line; after the last, an empty line and the summary: `[N result(s)]` when all are shown, else the `[showing …]` line above.
- `query` is required and may be empty only with `kinds` (else `tool-input-error` naming `kinds`).
- No hits → `No results for "<query>"[ with kinds a, b] in <m> unit(s)` (m = logs searched).
- The cap: hits are added while the result fits; the first hit is cut down to its header and hit line if it alone does not.

### unit_read — `ref` | `unit`, `start_line`, `limit`, `streams`

```
unit shell-job-3 (exited 2): lines 41-80 of 102
    41	text line 040
…
>   51	text line 050
…
[more: unit_read unit "shell-job-3" start_line 81]
```

- Exactly one of `ref` / `unit`. With a ref: start = line − 10, limit 40; with a unit: start 1, limit 200; `start_line` / `limit` (1 … `max-read-lines`) override. Lines counted are output records; gaps are shown where they fall.
- Header `unit <key> (<status>): lines A-B of <last line>`; `[more: …]` when output exists after B (also when the cap cut the lines).
- Nothing from START: `unit <key> (<status>): no output from line S; the log ends at line L`.
- A unit without a log file (supervisor without a state directory): `unit <key> (<status>): no log file; in-memory head and tail:` then `unit-output`, cleaned, trailing newlines dropped, truncated as H2c (`truncate-shell-output`).

### unit_tail — `unit`\*, `lines`, `after_line`, `wait_ms`, `streams`

```
    29	text line 028
    30	text line 029
[unit shell-job-3 running; continue with after_line 30]
```

- No `after_line`: the last `lines` (default 50) output lines (`log-tail`), at once. With `after_line`: the lines after it (`log-follow`), waiting up to `wait_ms` for the first one or the end; at most `lines`.
- Footer `[unit <key> <status phrase>; continue with after_line L]` while the log may grow (L = the last line shown, else `after_line`, else the log's last line), or `[unit <key> <status phrase>; end of output]` once the log has its end record and nothing follows. A unit without a log: the head + tail as `unit_read`, then `[unit <key> <status phrase>; no log file]`.

### unit_control — `unit`\*, `action`\* (`stop` `restart` `input`), `input`, `eof`

| Action | Result |
|--------|--------|
| stop | `Stopped <id>: <status>` (`stop-unit`, tree-wide). Already finished → `<id> had already finished: <status>` |
| restart | `Restarted <id>: running; its output continues after line L (unit_tail after_line L)` (`restart-unit`; L = last line before) |
| input | `Sent N characters to <id>[, then closed its stdin]; read the reply with unit_tail after_line L` (`send-unit-input`, `close-unit-input` with `eof: true`; L = last line before sending) |

Errors: unknown or out-of-scope unit → `unit-not-found`; a previous session's key → `tool-input-error` ("from a previous session; it cannot be controlled"); `input` missing for input; input to a finished unit (`not running`), after stdin closed (`stdin`), or to a thread unit (`does not take input`) → `tool-input-error`; a restart that cannot launch → `tool-unavailable` with the report.

### Shell tools under a supervisor

- `bash` foreground: start the unit, close its stdin, wait up to `timeout_ms`; result = its stdout and stderr records in line order, cleaned (`clean-shell-output`), trailing newlines dropped, `truncate-shell-output` — except that the omitted-characters line reads `[truncated: <n> characters omitted; the full output is in unit <id>: use unit_read or unit_search]` — then `[exit code N]`. Timeout: `shell-timeout` with `continue` / `run-in-background` as H2c; unhandled → `stop-unit` and the H2c timeout text.
- `run_in_background` → `Started job <id>: <command>` … (H2c text, unit id). `job_output` / `job_input` / `job_kill` / `job_list`: H2c texts; output since the last read comes from the log (a per-job line cursor; the oldest unread characters beyond `max-job-buffer`, and gap bytes, count as dropped); `job_list` status `running` / `exited N` (`:exited` or `:failed` with a code) / `killed`. `max-jobs` counts running job units. H2c `job-<n>` ids do not exist under a supervisor (`job-not-found`).
- `shell-tools-jobs` / `find-shell-job` return `shell-job`s whose `shell-job-unit` is the unit. `close-shell-tools` closes the source's scope: its units stop, their logs stay; later calls → `tool-unavailable`.

---

## Contract (tests)

`agent-tools/tests` grows by **51 forms / 59 cases** in new `unit-*` files (Rove), on macOS, Linux and Windows; one case skips on Windows (a line-by-line `/bin/sh` stdin echo). Every test makes a fresh supervisor over a temp state directory; child processes are this SBCL (sleepers, exit codes, a stdin echo) as in supervisor-protocol. Expected rows, refs and line numbers come from the supervisor and the log reader, never from the tools.

| File | Covers |
|------|--------|
| `unit-support` | `with-units`, `ucall`, thread units printing lines (stdout / stderr), gated units, SBCL child argv, independent formatters (`expected-row`, `rfc3339`, `log-line`, `ref-of`) |
| `unit-construct-test` | defaults and constants, construction errors, descriptors and every schema (required keys, enums, bounds from the caps), approval only for `unit_control`, unknown names, close (own index closed, a passed index not) |
| `unit-time-test` | 9-row `parse-time-argument` table (durations, RFC 3339 with fraction, offsets, space), errors naming the value, default now |
| `unit-list-test` | exact rows (scope paths, labels, thread / process commands, exit codes), every filter, argument errors, previous sessions, truncation by rows and by `max-output`, a narrower scope |
| `unit-search-test` | exact hit header and context block, stack-trace header with extent, `[N results]` / `[showing …]` / `No results …`, unit / stream / since / until filters, the output cap, 500-character lines, argument errors |
| `unit-read-test` | by ref (window, mark, `[more]`), by range, end of output, gaps first, the cap, a unit without a log file, errors (`unit-not-found` for units and refs) |
| `unit-tail-test` | last lines + end footer; **follow returns when the line arrives** (gated unit, far inside a 20 s wait); a wait that expires; failed / killed phrases; errors |
| `unit-control-test` | **permission resources** of every tool (never signals); **rules over them** (`stop:shell-job-*` allow, restart still asks, `*:subagent-*` deny); stop, restart (one log, two runs), input + eof to a stdin echo (it exits 0); errors; out-of-scope and previous-session units |
| `unit-shell-test` | under a supervisor: `:auto` → `:process`, `:pty` refused, scopes; **foreground bash keeps the H2c text** and is a unit with its log; stdin EOF; **jobs keep their text** (ids = unit ids), `job_output` since the last read, `job_list`, `job_kill`, `job_input`; timeout → `run-in-background`; truncation names the unit; close stops the scope; foreground units visible to `unit-tools` |
| `unit-agent-run-test` | a mock-LLM run on libuv using `unit_list` / `unit_search` / `unit_tail` without approval; **`unit_control` under rules**: a deny rule's feedback as the tool result, an allow rule stops a shell job without asking |

Also in the contract commit: `tests/support.lisp`'s racing filesystem accepts `&allow-other-keys` on `fs-write-atomic` (cl-stack-pathlib 0.9.0 added `:mode`, which made the H2b suite fail to load with the newer pathlib that supervisor-protocol brings).

Locally (macOS, stubs, supervisor-protocol from the run-1 contract branch): the H2b / H2c suites pass as before; of the new cases 4 pass (defaults, construction errors, descriptors and schemas, approval) and 55 fail on `%h8c-pending`; no new load warnings. Expected the same on Linux; on Windows 4 pass, 1 skips, 54 fail. CI on the contract PR fails until supervisor-protocol 0.3.0 is published.

---

## Out of scope (H8c)

- Semantic search (H8c-1: an `embed-texts` method over `llm-protocol` embeddings, hybrid ranking).
- Attaching to a pty or tmux unit (H8a-1 executors, H8d panel).
- The TUI panel, `--rpc` views and web dashboard (H8d), which reuse the same search engine and permission layer.
- Migrating `rpc-backend-stdio`, `lisp-mcp` and pty jobs onto the supervisor (H8a-1).
- A `cd` / env session across bash calls (unchanged from H2c).

# agent-tools (H2c): the coding agent's shell tools

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H2 ("shell on `pty-protocol` with timeouts, output caps and background jobs; shell command scanner feeding permission resources")
**Status:** milestone **H2c locked**. The contract is in [`egao1980/agent-tools`](https://github.com/egao1980/agent-tools) (`agent-tools/tests`, Rove), and every new function calls `%not-implemented`. It will be implemented through **team-solve**. Version target **agent-tools 0.2.0**. The file tools are H2b ([agent-tools.md](agent-tools.md)).

`shell-tools` is a second tool source in `agent-tools`, next to `file-tools`. It runs shell commands for an `ai-agent-protocol` agent through five tools:

- `bash`: a foreground command with a timeout, or a background job.
- `job_output`, `job_input`, `job_kill` and `job_list`: the background jobs.

On Unix, commands run on a pseudo-terminal ([pty.md](pty.md): `pty-protocol` + `pty-backend-native`). On Windows, and with `:executor :process` anywhere, they run over `process-protocol` 0.3.0 pipes ([process.md](process.md)). A pure command scanner turns a command line into permission resources (`bash:git status`, `program:git`, `write:out.txt`, `cd:src`, `*`), and ai-agent-protocol rules match those.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code Bash / BashOutput / KillShell | `command` + `timeout` (ms, default 2 min, max 10 min); `run_in_background` returning an id; incremental output reads; ~30 000 character output cap; optional `description` | A persistent shell session (`cd` that carries across calls); the separate read-only allowlist |
| Codex `exec_command` / `write_stdin` (unified exec) | Interactive jobs on a pty; sending input and reading what comes back in one call; head + tail truncation; `workdir` argument | Token-based caps; `yield_time_ms` as the only wait; sandbox policy (confinement stays in `compute-backend-*`) |
| pi `bash` | Process-tree kill on timeout; a timeout error that carries the output so far | Tail-only truncation with a temp file; no background jobs |
| opencode v2 `bash` | Per-command permission patterns from a parsed command (tree-sitter there, our own scanner here); `cd` targets as resources | `external_directory` prompts |
| cl-stack | `pty-protocol` sessions; `process-protocol` 0.3.0 env + octet streams; ai-agent-protocol whole-value globs ("last match wins, deny beats ask") | — |

---

## Decisions (locked)

| Decision | Choice | Reason |
|----------|--------|--------|
| **Repo / system** | Same repo and system as H2b: `egao1980/agent-tools`, system `agent-tools`, tests `agent-tools/tests`. **Version 0.2.0.** | One tool package per harness. The agent core gains no dependency. |
| **Dependencies (new)** | `process-protocol` ≥ 0.3.0, `process-backend-uiop` ≥ 0.2.0, `pty-protocol` ≥ 0.1.0, `pty-backend-native` ≥ 0.2.1. Loading `agent-tools` loads all four, and each backend sets its `*…-backend*`. | Consumers write `(asdf:load-system "agent-tools")` and nothing else (workspace rule). pty-backend-native ships overlays for linux amd64/arm64, darwin arm64 and windows amd64. |
| **Source shape** | A new `shell-tools` class, separate from `file-tools`. An agent lists both in `:tools`. It specializes `list-agent-tools`, `tool-executable-p`, `tool-needs-approval-p`, `invoke-tool-async`, `tool-permission-resources` and `tool-instruction-paths`. | The file tools work on any pathlib filesystem. The shell needs the local one. Separate objects keep `make-file-tools` unchanged. |
| **Root** | A local directory: a string, a pathname or a `PATH` on `cl-stack-pathlib`'s local filesystem. Any other filesystem is an ERROR. `workdir` resolves under the root the way H2b `resolve-tool-path` does (lexical; `path-outside-root` outside; it must exist and be a directory). | Processes run in OS directories. Reusing H2b's resolution gives one confinement story for the start directory. |
| **Confinement** | None for the command itself. The command runs unconfined. Permission rules and approvals are the control here; OS confinement is `compute-backend-*`. | The H2b brief said the same. A scanner can't confine. |
| **Executor** | `:executor :auto` resolves to **`:pty` on Unix** and **`:process` on Windows**. `:process` also works on Unix. `:pty` on Windows is an ERROR in 0.2.0. | On a pty the shell leads its own session. When it dies or the pty closes, the hangup reaches its whole foreground process group, so timeouts and `job_kill` stop the tree. With `:executor :process`, agent-tools 0.2.0 launches with `:process-group t` and kills with `:tree t` (process-protocol 0.4.0, [process-protocol#9](https://github.com/egao1980/process-protocol/issues/9), done). A pty also lets `job_input` drive programs that want a terminal. ConPTY output is a screen-repaint stream (cursor moves, redraws), not a byte log, so Windows uses pipes. |
| **Shell** | `:shell` is an argv prefix, and the command line is appended as one last argument. `(default-shell)` is `("/bin/sh" "-c")` on Unix and `("cmd.exe" "/d" "/s" "/c")` on Windows. | `/bin/sh` is everywhere and is what models write for. |
| **Windows: cmd, not PowerShell** | The default is `cmd.exe /d /s /c` (no AutoRun, verbatim command line). PowerShell is opt-in, e.g. `:shell '("powershell.exe" "-NoProfile" "-NonInteractive" "-Command")`, and it scans with the `:opaque` dialect. | cmd is always present, starts in tens of milliseconds (PowerShell takes 0.3–1 s), has no profile or execution policy, and its syntax is small enough to scan conservatively. Git Bash is not on every machine. A product that finds it can pass `:shell '("C:\\…\\bash.exe" "-c")`, which gets the `:posix` dialect. |
| **Dialect** | `:posix`, `:cmd` or `:opaque`, derived by `shell-dialect` from the shell's basename (case-insensitive, without `.exe`): sh / bash / dash / zsh / ksh / mksh / ash → `:posix`; cmd → `:cmd`; anything else → `:opaque`. `:dialect` overrides it. | The scanner has to know which grammar it is reading. |
| **Tool name** | `bash` on every OS. Its description names the actual shell (`/bin/sh -c` or `cmd.exe /d /s /c`). | Rules stay the same everywhere (`("bash" "program:rm" :deny)`), and models know the name. |
| **No session state** | Each call is a fresh shell in `workdir` (default: the root). Neither `cd` nor `export` carries over to the next call. | The result is deterministic, and the scanner knows the start directory. The model passes `workdir` instead. |
| **Environment** | Parent environment, then `+shell-environment+` (`TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `NO_COLOR=1`, `GIT_TERMINAL_PROMPT=0`), then `:env` (alist; a NIL value unsets). | This keeps pagers, colours and credential prompts out of an unattended run. |
| **stdin** | Foreground commands see end of file (a pty implementation may redirect `</dev/null` or send EOF). Background jobs keep stdin open for `job_input`. | `cat`, `read` or a prompt must not hang until the timeout. |
| **Output** | stdout and stderr in one stream, in order (pty: inherent; process: `:error-output :output`). It is cleaned (`clean-shell-output`), capped at `max-output` characters (`truncate-shell-output`, head + tail), and trailing newlines are dropped. | Errors usually sit at the end and the first compiler error at the start, so head + tail keeps both. Models need no ANSI escapes. |
| **Exit status** | A non-zero exit is a normal result (`[exit code 1]`), not a tool failure. | `grep`, `diff` and `test` exit non-zero by design. The model reads the status. |
| **Timeout** | `timeout_ms` (default `default-timeout` 120 000, maximum `max-timeout` 600 000; out of range → `tool-input-error`). Expiry **signals `shell-timeout` while the command is still running**. `continue` waits another `timeout_ms`; `run-in-background` turns it into a job. Unhandled, the process tree is killed (pty) and the call fails with `tool-timeout` text. | This is the CLHS 9 shape: the caller (a harness, a human at the REPL, a policy) decides, and the default is safe. The H4 debugger bridge can offer both restarts. |
| **Background jobs** | Ids `job-1`, `job-2`, … per source; a refused start takes no id. At most `max-jobs` (8) **running**. Unread output is capped at `max-job-buffer` (1 000 000) characters by dropping the oldest. Jobs stay listed after they finish. `close-shell-tools` kills the running ones. | Matches Claude Code's background shells. The id counter makes results deterministic for tests. The caps bound memory for a chatty dev server. |
| **Approval** | `:needs-approval t` (default) makes `tool-needs-approval-p` true for `bash` and `job_input`. With no rule deciding, they **ask**. `job_output`, `job_kill` and `job_list` never need approval. | A shell is the most dangerous tool. Reading and stopping your own jobs is harmless. |
| **Threads** | Handlers run in worker threads (the H2b function-tool path). Each job has its own reader/pump. The protocol-level owner rule for a pty ("one owner thread at a time") is the implementation's to respect. | Same as H2b. |
| **Stubs** | `%not-implemented` (internal, `src/shell-tools.lisp`). The implementation removes it and every call. Classes, readers, `+shell-tool-names+`, `+shell-environment+` and `default-shell` are given. | — |

---

## Surface

```lisp
(make-shell-tools &key root (executor :auto) shell dialect env (needs-approval t)
                       (default-timeout 120000) (max-timeout 600000)
                       (max-output 30000) (max-jobs 8) (max-job-buffer 1000000)
                       (tools +shell-tool-names+))
  ;; ROOT missing → PATH-NOT-FOUND; not a directory → PATH-ERROR; a PATH on a non-local
  ;; filesystem, an unknown tool name / executor / dialect, DEFAULT-TIMEOUT > MAX-TIMEOUT,
  ;; :PTY on Windows → ERROR. TOOLS kept in +SHELL-TOOL-NAMES+ order.
shell-tools  shell-tools-p
shell-tools-root  shell-tools-executor  shell-tools-shell  shell-tools-dialect
shell-tools-env  shell-tools-needs-approval  shell-tools-default-timeout
shell-tools-max-timeout  shell-tools-max-output  shell-tools-max-jobs
shell-tools-max-job-buffer  shell-tools-names  shell-tools-closed-p
+shell-tool-names+        ; ("bash" "job_output" "job_input" "job_kill" "job_list")
+shell-environment+       ; see Decisions
(default-shell)           ; → argv prefix for this OS
(shell-dialect shell)     ; → :posix | :cmd | :opaque

(call-shell-tool tools name arguments)  ; → result string; synchronous. A name not enabled
                                        ;   → AGENT-UNKNOWN-TOOL; after close → TOOL-UNAVAILABLE.
(close-shell-tools tools)               ; kill running jobs, refuse later calls; idempotent; → NIL

;; jobs
shell-job  shell-job-id  shell-job-command  shell-job-status   ; :running :exited :killed
shell-job-exit-code  shell-job-signal                          ; signal: :term … (pty) or NIL
(shell-tools-jobs tools)   ; oldest first, finished ones included
(find-shell-job tools id)  ; → job or NIL

;; pure helpers
(shell-command-resources command &key (dialect :posix) (workdir ".") root)
(clean-shell-output octets-or-string)
(truncate-shell-output string max)

;; conditions and restarts
shell-timeout (AI-AGENT-PROTOCOL:TOOL-TIMEOUT)
  shell-timeout-command  shell-timeout-timeout (ms)  shell-timeout-output
  restarts: CONTINUE, RUN-IN-BACKGROUND (exported symbol)
job-not-found (TOOL-INPUT-ERROR)    job-not-found-id
job-not-running (TOOL-INPUT-ERROR)  job-not-running-id  job-not-running-status
;; reused: PATH-OUTSIDE-ROOT (workdir), TOOL-INPUT-ERROR, TOOL-UNAVAILABLE
```

---

## Tools

Results are plain strings with LF line ends and no trailing LF. `<out>` is the cleaned, truncated output with its trailing newlines removed. When `<out>` is empty, the result is the status line alone.

### bash: `command`\*, `timeout_ms`, `workdir`, `run_in_background`, `description`

- Foreground: `<out>` LF `[exit code N]`. On the pty executor, a shell killed by a signal gives `[killed by signal TERM]` (the keyword's name).
- The call returns when the shell has exited **and** its output has reached EOF or gone quiet. A background child that keeps the terminal or pipe open (`sleep 30 & echo done`) must not hold up the result. A short drain (≈ 200 ms of silence) after the exit is enough.
- `run_in_background: true` returns at once:
  ```
  Started job job-1: <command>
  Read its output with job_output (job_id "job-1"); stop it with job_kill.
  ```
  `timeout_ms` is ignored for a background job. Too many running jobs → `tool-input-error` mentioning `job_kill`.
- Timeout → `shell-timeout`, message `Command timed out after <ms> ms and was killed; output so far:` LF `<out>` LF `Run long commands with run_in_background: true and read them with job_output.` (with `(no output)` when there is none). The `run-in-background` restart makes the call return the `Started job …` text for the still-running command. The output from before the timeout stays unread in the job.
- Errors: a missing, empty or blank `command`, a wrong type, `timeout_ms` outside 1…`max-timeout`, a non-boolean `run_in_background`, bad JSON or a non-object → `tool-input-error` naming the key. A `workdir` outside the root → `path-outside-root`; missing → `not found`; a file → `not a directory`. The shell cannot start (`pty-spawn-error`, `process-error`) → `tool-unavailable` naming the shell program, and no job is recorded. `description` is accepted and unused (UI text).

### job_output: `job_id`\*, `wait_ms` (0…`max-timeout`, default 0)

Waits until the job finishes or `wait_ms` passes, then returns the output **since the last read** and the status:

```
<new output>
[job job-1 running]                 | [job job-1 exited with code 0]
[job job-1 killed]                  | [job job-1 terminated by signal TERM]
```

When more than `max-job-buffer` characters arrived unread, the oldest are dropped and the chunk starts with `[truncated: <n> characters dropped; …]`. The chunk is then capped like a foreground result. An unknown id → `job-not-found` (the message names the id and `job_list`).

### job_input: `job_id`\*, `input`\*, `wait_ms`

Writes `input` (UTF-8, verbatim; `\n` is Enter) to the job's stdin, then returns what `job_output` would with the same `wait_ms`. On a pty the terminal echoes the input into the output. A finished job → `job-not-running` (status `:exited` / `:killed`).

### job_kill: `job_id`\*

Kills the job's process tree (pty) or its shell (process), waits for it, and returns the unread output and `[job <id> killed]`. A job that has already finished is not an error: you get its unread output and final status.

### job_list

One `<id>` TAB `<status>` TAB `<command>` line per job, oldest first. The status is `running`, `exited <code>`, `signal <NAME>` or `killed`. With no jobs: `[no jobs]`.

### Output cleaning and truncation (pure)

`clean-shell-output`:
1. Octets are decoded as UTF-8, with U+FFFD for each invalid byte.
2. CR LF becomes LF.
3. ANSI escape sequences are removed: CSI `ESC [` … final byte 0x40–0x7E; OSC `ESC ]` … BEL or `ESC \`; otherwise `ESC`, its intermediates 0x20–0x2F, and one final byte.
4. In each line, only the text after its last remaining CR is kept (progress bars).
5. Other control characters except TAB and LF are removed.

`truncate-shell-output string max`: a string of at most `max` characters is returned unchanged. A longer one keeps a head of at most ⌊max/2⌋ characters, cut back to its last LF, and a tail of at most the rest, starting after the first LF in it (cut mid-line when there is none). Between them goes the line `[truncated: <n> characters omitted; redirect the output to a file and use read or grep on it]`, where `n` is exactly what was left out.

---

## Permission resources: `shell-command-resources`

The scanner is pure and never signals. Its result is in order of appearance, without duplicates, with `"*"` last when anything was not modelled. It returns NIL for a blank or comment-only command (the tool method then returns `("*")`).

| Resource | Emitted for |
|----------|-------------|
| `bash:<words>` | each simple command: its words joined by one space, quotes removed. Leading `NAME=value` assignments are kept. A word with an expansion keeps its source text (`bash:echo "$(date)"`). Redirections are not words. |
| `program:<argv0>` | the first non-assignment word as written (`program:git`, `program:./build.sh`). No program resource when argv0 is dynamic. |
| `cd:<path>` | `cd` with exactly one static operand (after `-L`/`-P`); also `workdir` when it is not `.` (first, always). |
| `read:<path>` | `<`, `<&file`, `<>` targets |
| `write:<path>` | `>`, `>>`, `>|`, `&>`, `&>>`, `N>`, `<>` targets; every operand of `rm rmdir unlink touch mkdir tee truncate mv shred`; the last operand of `cp ln install` (options before `--` are skipped; a detached option argument such as `-s 0` counts as an operand, which over-reports) |
| `*` | something the scanner does not model (see below) |

**Paths** are lexical, like H2b. Relative ones join the current directory (`workdir`, then `cd` targets) and normalize `.` and `..`. With `:root` (the tool passes the root's POSIX string), a path under the root is root-relative (`.` for the root itself), and one outside it is absolute and normalized. Without a root, a relative path that climbs out keeps its `../`. `/dev/null` and fd duplications (`2>&1`, `>&-`) produce nothing. A path with an expansion, an unquoted glob (`* ? [`) or a leading `~` adds `*` instead.

**cd tracking.** A `cd` changes the directory for later commands only when it is followed by `&&`. After `;`, newline, `||` or the end of the line, the directory becomes unknown, because the `cd` may have failed. Later relative paths then add `*`; absolute paths stay exact. A `cd` that is part of a pipeline or ends with `&` changes nothing. A subshell `( … )` restores the directory; a brace group `{ …; }` does not.

**Dynamic constructs.** These add `*`, and the scan continues where it still can:
- parameter, command and arithmetic expansion (`$x`, `${x}`, `$(…)`, `` `…` ``, `$((…))`, `$'…'`, `$"…"`);
- process substitution;
- an unquoted here-doc body with `$` or a backtick (a quoted delimiter is literal), or a missing terminator;
- unterminated quotes or parentheses;
- reserved words and compound commands (`if for while until case select function [[ ((`, `name()`). The scan stops at these.
- argv0 in `eval exec source . command builtin env sudo doas su nohup nice timeout time xargs sh bash dash zsh ksh fish`;
- `find` with `-exec`, `-execdir`, `-ok`, `-okdir` or `-delete`.

Not modelled, and not marked: `sed -i`, `git -C`, interpreters running a script (`python x.py`; deny `program:python` if that matters), and option arguments.

**cmd dialect.** A blank command gives NIL. A command with `%`, `!` or a line break anywhere, or `& | < > ^ ( )` outside double quotes, or an unterminated quote, gives `("bash:<trimmed command>" "*")`. Otherwise it is one simple command: `bash:<words>` (double quotes removed) and `program:<argv0>`. argv0 is lowercased and loses a `.exe`, `.com`, `.bat` or `.cmd` suffix. A `*` is added for `cd chdir pushd popd del erase rd rmdir md mkdir ren rename move copy xcopy robocopy call start cmd powershell pwsh`. cmd paths are not modelled.

**opaque dialect.** `("bash:<trimmed command>" "*")`.

### On the tool

- `bash` → `shell-command-resources` of `command` with the tools' dialect, the resolved `workdir` and the root. Any of these gives `("*")`: unparsable arguments, a missing, blank or non-string command, or a `workdir` that does not resolve under the root.
- `job_output`, `job_input`, `job_kill` → `("job:<id>")`; `job_list`, or a missing id → `("*")`.
- `tool-instruction-paths`: `bash` → `("<workdir>")` (`(".")` when absent), so `AGENTS.md` discovery covers where the command runs; NIL for job tools and for a workdir outside the root.

**How rules read it.** ai-agent-protocol matches each resource on its own. Across resources, a deny on any of them wins, then an ask. If any resource is undecided while the rest are allowed, the result is the tool default, which for `bash` is ask. So:

- `("bash" "bash:git *" :allow)` allows `git status && git diff`.
- The same rule leaves `git status && rm -rf x` and `git log $(…)` to an ask, because `"*"` matches only a catch-all rule.
- `("bash" "program:rm" :deny)` or `("bash" "write:secret/*" :deny)` refuses wherever the scanner sees the program or the write.
- A catch-all `("bash" "*" :allow)` also allows what the scanner cannot see. That is the user's choice.

---

## Conditions and restarts

| Condition | Parent | When | Restarts |
|-----------|--------|------|----------|
| `shell-timeout` | `tool-timeout` | the foreground `timeout_ms` passed and the command is still running | `continue` (wait another `timeout_ms`), `run-in-background` (become a job; the call returns the start text). Unhandled → tree killed, the run gets the `Tool bash timed out: …` text |
| `job-not-found` | `tool-input-error` | an unknown `job_id` | — |
| `job-not-running` | `tool-input-error` | `job_input` on a finished job | — |
| `path-outside-root` (H2b) | `tool-input-error` | a `workdir` outside the root | — |
| `tool-unavailable` | — | the shell cannot start; any call after `close-shell-tools` | — |

Restarts are established around the signal inside the call, so a `handler-bind` around `call-shell-tool` sees them (`find-restart` by name). Nothing between the signal and the caller unwinds first. The process is killed only when control leaves the call without `run-in-background`.

---

## Windows

- Executor `:process` (pipes, stderr merged), shell `cmd.exe /d /s /c`, dialect `:cmd`. `:executor :pty` is an ERROR in 0.2.0.
- The command line reaches cmd as one argument. Under `/s`, cmd strips the outer quotes that argv quoting adds. Command lines with inner double quotes depend on `process-backend-uiop` quoting, and the contract does not test them.
- Killing a job or a timed-out command kills `cmd.exe` and its children: a tree kill through a job object (process-protocol 0.4.0 `:tree`, process-backend-uiop 0.3.1; [process-protocol#9](https://github.com/egao1980/process-protocol/issues/9) done). A grandchild started before the job assignment can still escape. The call still returns promptly: the implementation must not wait for EOF on a pipe a grandchild holds.
- No signal statuses: an exit is always `[exit code N]`.
- Output is decoded as UTF-8. Programs writing in the OEM code page show U+FFFD for non-ASCII; `chcp 65001` is the user's choice.

---

## Out of scope (H2c)

- A persistent shell session (`cd` and `export` across calls).
- Spilling full output to a file.
- Output filtering in `job_output` (no regex engine).
- Recursive scanning of `sh -c '…'` / `eval`.
- PowerShell grammar.
- ConPTY jobs.
- Process confinement or sandboxing (`compute-backend-*`).
- Resource limits (CPU, memory).
- Persisting jobs across a harness restart.
- The H4 debugger → inbox bridge for `shell-timeout`.

---

## Contract (tests)

These are 80 new tests in new files of `agent-tools/tests` (Rove). Executor tests are `deftest-parametrize` over `+executors+`: `(:pty :process)` on Unix, `(:process)` on Windows. Each uses a fresh temp directory and closes its source. Commands that differ by OS go through `pick` (`/bin/sh` syntax / cmd syntax), and sleeps use `sleep N` / `ping -n N+1 127.0.0.1 >nul`.

On the stubs, everything new fails except the two constant checks (`default-shell`, `+shell-environment+`). A throwaway prototype (scratchpad, not committed) passed the whole suite three times in a row on SBCL / macOS (H2b + H2c, 39 s per run). That prototype pass also caught one test bug: a helper name clashing with an H2b test helper.

| File | Covers |
|------|--------|
| `shell-support` | `with-shell`, `deftest-executors`, `pick`, `sleep-command`, result builders (`exit-text`, `job-text`, `started-text`), `real-failure` (an ERROR that is not the stub's) |
| `shell-construct-test` | defaults per OS, root designators, options, bad arguments, `shell-dialect`, `default-shell`, close, unknown tool, descriptors and schemas (`additionalProperties`, required, bounds from `max-timeout`) |
| `shell-scan-test` | about 160 scanner checks: simple commands, lists, pipelines, subshells, groups, redirections, here-docs, written operands, `cd` tracking, `workdir` / `:root`, dynamic words, indirection, unmodelled syntax, cmd and opaque dialects, a 900-case "never signals" sweep |
| `shell-output-test` | UTF-8 decoding, CR LF / lone CR, CSI / OSC / ESC removal, control characters, head + tail truncation |
| `shell-test` | every OS × executor: echo, exit codes, merged stderr, `workdir` and its errors, environment, empty stdin, argument errors, unhandled timeout (bounded time), `continue` and `run-in-background` restarts (handlers inside `ok`), truncation, background start / read / exit code / kill / list / ids, job errors, `job_input` after exit, `max-jobs`, `max-job-buffer`, close, spawn failure |
| `shell-posix-test` | (not on Windows) quoting, ANSI and progress cleaning, UTF-8 and invalid bytes, tty vs pipe, a background child does not block, scripts in `workdir`, `job_input` round trips, incremental `job_output` |
| `shell-pty-test` | (not on Windows) `job_kill`, timeout and `close-shell-tools` kill a grandchild that would write a marker after 2 s (with a control test where it does); signal statuses |
| `shell-permissions-test` | resources for each tool, workdir `cd:`, absolute paths under the root, never signals, approval defaults, executable names, instruction paths, rule effects over scanner output |
| `shell-agent-run-test` | mock-LLM runs on libuv: both sources listed and found, bash → job → job_output, a `program:rm` deny rule, a timeout as a tool result (no job left), failures as tool results |

Checklist applied (team-solve STAGED):
- Restart lookups sit inside the `shell-timeout` handler, inside `ok`.
- `find-restart` is called without the condition argument.
- `failure` catches `agent-condition` for `agent-unknown-tool`.
- Windows-only and Unix-only code is under `(:or :windows :win32)`, with Unix-only files `:if-feature`.
- No `~<newline>` in FORMAT strings.
- The random sweep uses a fixed LCG, not `random`.

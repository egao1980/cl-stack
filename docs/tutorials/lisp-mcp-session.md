# Tutorial: a token-thrifty lisp-mcp session

**You will** fix a failing test in a Common Lisp project through [`lisp-mcp`](https://github.com/egao1980/lisp-mcp) **0.5.0**, keeping the agent's context small:
- terse output by default;
- long logs stored and read back in slices;
- edits that compile as they land;
- long test runs that become background jobs.

The full tool reference is the [lisp-mcp cookbook](../cookbooks/lisp-mcp.md). Tool calls are written `tool {arguments}`, and results are shortened where marked `…`.

## 0. Setup

```bash
ros install egao1980/lisp-mcp
claude mcp add lisp-mcp -- lisp-mcp --root "$PWD" --spawn swank
```

Inside the workspace, `scripts/lisp-mcp.sh` (lisp-workspace) builds and caches `~/.cache/lisp-mcp/lisp-mcp-0.5.0`. After an upgrade, reconnect the server: `/mcp` in Claude Code.

Server flags that matter for token use:

| Flag / env | Default | Effect |
|------------|---------|--------|
| `--tools` / `LISP_MCP_TOOLS` | `all` | tool groups offered: `code` (source, edit, output) or `image` (repl, debug, inspect, jobs, output); run one server per preset and the agent pays only for what it loads |
| `--verbose` / `LISP_MCP_VERBOSE=1` | off | every call verbose (diffs, hints, 12 frames) |
| `--max-output-lines` / `LISP_MCP_MAX_OUTPUT_LINES` | 120 | cut point; ×4 with `verbose` |
| `--max-output-chars` / `LISP_MCP_MAX_OUTPUT_CHARS` | 10000 | cut point; ×4 with `verbose` |
| `LISP_MCP_OUTPUT_STORE_SIZE` | 64 | stored long outputs |

The catalog itself is small: 56 tools in about 17 KB of `tools/list` (0.4.1: 35 KB for 63). Common arguments carry no per-tool description: the server instructions explain them, and the workflow, once.

---

## 1. Run the tests: a job, not a timeout

```text
repl-load-system {"system": "stats"}
→ loaded stats (2.1 s)

repl-run-tests {"system": "stats", "timeout": 30}
→ Still running as job j1; do not start another copy while it is running;
  the result is reported when done (or call job-status / job-wait).
```

The suite is still running in the image. Do something else, or wait at most 300 s per call:

```text
job-wait {"id": "j1"}
→ j1 repl-run-tests done (41.3 s)
  stats/tests
    × average-of-empty-list
      (= 0 (average nil)) — got division-by-zero
  3 tests, 1 failed
```

Notes:
- **Only failures come back.** Terse mode drops Rove's passing assertions: you get the failures, the test names and the summary.
- **No duplicate runs.** Calling `repl-run-tests` again with the same arguments while j1 runs returns j1. Nothing is started twice.
- **Completion.** The server also logs completion (logger `lisp-mcp/jobs`). `job-list` shows every job and `job-cancel` interrupts one; the job then reports the debugger state.
- **Timeouts.** Default timeouts are 60 s, or 300 s for `repl-load-system` and 600 s for `repl-run-tests`.

## 2. Long output: read only the slice you need

A big build log is cut to its head and tail, with a stored id:

```text
repl-load-system {"system": "big-project"}
→ ; compiling file … (first lines)
  [… lines 41-2210 of 2290 cut (182311 chars). Stored as o3: output-read id=o3 offset=41 or grep=…]
  ; caught WARNING: undefined variable *CACHE*   (last lines)

output-read {"id": "o3", "grep": "WARNING|ERROR", "context": 2}
→ 3 matches …
```

The same text is at the resources `lisp-output://o3`, `…/lines/{start}-{end}` and `…/grep/{pattern}`.

## 3. Read the form, then edit it with compile

```text
source-read {"path": "src/stats.lisp", "locator": "defun average"}
→ (defun average (xs)
    (/ (reduce #'+ xs) (length xs)))
  hash 609d73583a2b33f1 · path:1

edit-replace {"path": "src/stats.lisp", "locator": "defun average",
              "expected_hash": "609d73583a2b33f1", "compile": true,
              "code": "(defun average (xs)\n  (if (null xs) 0 (/ (reduce #'+ xs) (length xs))))"}
→ wrote src/stats.lisp (+1 -1 lines) · hash 1be0…
  compiled 1 form: no notes
```

- **Terse edits.** A written edit reports `(+a -b lines)` instead of the diff. Pass `"dry_run": true` to see the diff first, or `"verbose": true` to get it after writing.
- **Compile on write.** `compile: true` compiles the changed top-level forms in the live image and appends the compiler notes, mapped to file positions.
- **Misses say what to do.** A locator that misses lists the closest definitions. A stale hash shows the current form and the hash to retry with. Every write is re-read and refused if it would unbalance the file.

## 4. When it breaks: the debugger is a value

```text
repl-eval {"code": "(stats:average '(1 \"2\"))"}
→ Debugger level 1: The value "2" is not of type NUMBER
  Restarts: 0 [RETRY] … 1 [USE-VALUE] … 2 [ABORT] …
  Backtrace (top 4; debug-backtrace for more)
   0 (SB-KERNEL:TWO-ARG-+ 1 "2")
   1 (REDUCE #<FUNCTION +> (1 "2"))
   …

debug-invoke-restart {"restart": 2}
→ returned to top level
```

Terse mode shows 4 frames and leaves out the next-step hints. Use `debug-backtrace`, `debug-frame-locals` and `inspect-condition` when you need more, or `"verbose": true` once.

## 5. Re-run, confirm

```text
repl-run-tests {"system": "stats"}
→ 3 tests, 0 failed
```

---

## What it cost

The output in this session is what an agent reads:
- one failure block instead of the whole Rove log;
- a one-line edit report instead of a diff;
- 4 backtrace frames instead of 12;
- a grep of the build log instead of 2,000 lines.

Turn on `verbose` for a single call when you need the full picture.

## Driving lisp-mcp from a cl-stack agent

`ai-agent-protocol/mcp` makes an MCP server a tool source (`make-mcp-tool-source`), so the [agent harness tutorial](agent-harness.md) applies directly:
- **Permissions.** `("edit-*" "*" :ask)` with `("source-*" "*" :allow)` keeps reads free and edits gated.
- **Instruction discovery.** Path arguments of `source-*` and `edit-*` calls trigger `AGENTS.md` discovery.
- **Jobs and the step budget.** A job id result keeps the agent from re-running a long suite inside its step budget.

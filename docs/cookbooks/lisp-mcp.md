# Cookbook: lisp-mcp (static analysis, structural edits, live images)

**Audience:** an agent (or its operator) working on Common Lisp code through MCP. For writing your own MCP server or client, see [mcp.md](mcp.md).

| Piece | Package | OCI |
|-------|---------|-----|
| Server | [`lisp-mcp`](https://github.com/egao1980/lisp-mcp) | **0.2.0** |
| Source CST, lint, edits, indentation | [`lisp-source-protocol`](https://github.com/egao1980/lisp-source-protocol) | **0.2.0** |
| Live image protocol | [`repl-protocol`](https://github.com/egao1980/repl-protocol) | **0.2.2** |
| SLIME Swank wire | [`repl-backend-swank`](https://github.com/egao1980/repl-backend-swank) | **0.2.0** |
| Sly Slynk wire | [`repl-backend-slynk`](https://github.com/egao1980/repl-backend-slynk) | **0.2.0** |
| MCP | [`mcp-protocol`](https://github.com/egao1980/mcp-protocol) / [`mcp-backend-stdio`](https://github.com/egao1980/mcp-backend-stdio) / [`mcp-backend-streamable-http`](https://github.com/egao1980/mcp-backend-streamable-http) | **0.3.0** / **0.2.0** / **0.3.0** |

| If you know | Here |
|-------------|------|
| Jedi / rope / a language server (outline, references, rename) | `source-*` tools, `edit-rename-symbol` — static, never loads the code |
| paredit / parinfer | `edit-*` tools — every write is re-read and refused if unbalanced |
| `pdb` / a debugger attached to a process | `repl-*`, `debug-*`, `inspect-*` against a Swank/Slynk image |
| IPython kernels | Slynk channels (`repl-channel-open`) with `#v` value history |

Three rules hold throughout:

- **The server never evaluates project code.** Source tools read with an Eclector client that refuses `#.` and never interns. Evaluation happens in a separate image over Swank or Slynk.
- **There is no raw text write for `.lisp` files.** Edits are operations on forms. The result is re-read before it is written, and refused if it adds a reader error or paren imbalance, or if the file changed since you read it.
- **The debugger is an answer, not a hang.** An error in the image returns its condition, restarts and backtrace; you decide what to do next.

---

## 1. Install and register

```bash
ros install egao1980/lisp-mcp                  # or: cl-repo sync in a checkout
claude mcp add lisp-mcp -- lisp-mcp --root "$PWD"
```

`.mcp.json` for other hosts:

```json
{ "mcpServers": { "lisp-mcp": { "command": "lisp-mcp", "args": ["--root", "."] } } }
```

| Flag | Effect |
|------|--------|
| `--root DIR` (or `MCP_PROJECT_ROOT`) | every path is resolved inside DIR; `..` and symlinks out are refused |
| `--spawn swank` / `--spawn slynk` | start with a fresh SBCL image attached |
| `--attach 127.0.0.1:4005 [--backend slynk]` | attach to your running SLIME / Sly |
| `--transport http --port 3000` | Streamable HTTP instead of stdio |

stdout carries JSON-RPC only: the launcher sends load output to stderr.

---

## 2. Read before you edit

Tool calls below are written `tool {arguments}`.

```text
source-outline {"path": "src/stats.lisp"}
→ src/stats.lisp (hash 609d73583a2b33f1, 3 forms)
     L1  defpackage stats  [path:0]
     L4  defun average (list)  [path:2] "Mean of LIST."

source-read {"path": "src/stats.lisp", "locator": "defun average"}
→ src/stats.lisp path:2 lines 4-6 (file hash 609d73583a2b33f1)
  (defun average (list) …)
```

Locators: `defun average`, `defmethod print-object (point t)`, `defclass point`, `path:2.3.1` (top-level index, then child indices), `line:12` or `line:12:4`, `offset:120`, `hash:<form hash>`. An ambiguous locator lists the candidates as `path:` locators.

`source-check` reads the whole file without evaluating it. It reports reader errors, paren imbalances with a suggested fix position, and lint: unused variables, missing `in-package`, exports never defined, public definitions without a docstring, missing ASDF components, and `#.` forms. `rules` narrows the lint (`"unused-variable,undefined-export"`, or `"none"`).

Project-wide, still static: `source-find-definitions`, `source-find-references` (through `:use`, `:import-from`, nicknames and `:local-nicknames`) and `source-packages`.

---

## 3. A file that does not read

One missing `)` would usually swallow every form after it. Here the damage stays in one form, and the fix comes with a position:

```text
source-check {"path": "src/broken.lisp", "rules": "none"}
→ imbalance missing-close: 1 closing parenthesis missing — suggested fix at 3:13 (confidence high)

edit-repair {"path": "src/broken.lisp"}            ; applies the fix; refused unless problems drop
source-check {"path": "src/broken.lisp", "rules": "none"}
→ … clean
```

Outside MCP, the same reader backs the workspace script: `ros scripts/static-eclector.lisp src/` prints `path:line:column: message; 1 closing parenthesis missing (fix at 3:13)`.

---

## 4. Structural edits

```text
edit-replace {"path": "src/stats.lisp", "locator": "defun average",
              "code": "(defun average (list)\n\"Mean of LIST; 0 when empty.\"\n(if (null list)\n0\n(/ (reduce #'+ list) (length list))))",
              "expected_hash": "609d73583a2b33f1", "dry_run": true}
→ Dry run …
  +(defun average (list)
  +  "Mean of LIST; 0 when empty."
  +  (if (null list)
  +      0
  +      (/ (reduce #'+ list) (length list))))
```

- The input must read as balanced Lisp, or it is refused before the file is touched: `Edit input does not read as balanced Lisp: While reading list, expected the character )…`.
- Inserted code is re-indented in Emacs/SLIME style. The rules come from the standard table, from the indentation hints a connected image sends, and from the `&body` of each `defmacro` in the project. So `(define-widget w (:size 1) …)` indents its body like the macro says.
- `expected_hash` (from `source-read` / `source-outline`) refuses the edit if the file changed since you read it. Re-read and try again.
- `dry_run` shows the unified diff without writing.

| Tool | Does |
|------|------|
| `edit-insert` (`where` before/after), `edit-delete` | siblings, with the separating whitespace |
| `edit-wrap` (`head` e.g. `"when (ready-p)"`), `edit-splice`, `edit-raise` | paredit wrap / splice / raise |
| `edit-slurp`, `edit-barf` (`direction`) | grow or shrink a list |
| `edit-transpose`, `edit-move` (`target_locator`, optional `target_path`, `where`) | reorder; move across files (both files verified before either is written) |
| `edit-rename-symbol` (`symbol` `pkg:name`, `new_name`, optional `path`) | every reference that resolves to the symbol, keeping prefixes and case; verifies all files first |
| `edit-add-export` | appends to the `defpackage` `:export` in its designator style |
| `edit-new-file` | a new file whose content reads clean; never overwrites |

Refused with a reason: sibling edits under `#+`/`#-`, quote or backquote prefixes, the consing dot, dotted lists, and forms rebuilt by recovery (repair the file first).

---

## 5. The live loop

```text
repl-spawn {}                                       ; or {"backend": "slynk"}, or repl-connect {"port": 4005}
→ swank-1: SBCL 2.6.7, pid 7645, package COMMON-LISP-USER (spawned)

repl-compile {"path": "src/stats.lisp"}            ; whole file: compile-file + load
→ src/stats.lisp ok (0 notes), loaded
repl-compile {"path": "src/stats.lisp", "locator": "defun average"}
→ notes point at file positions: "warning at src/stats.lisp:5:7: undefined variable: LIZT"

repl-eval {"code": "(stats:average '(1 2 3 4))"}
→ => 5/2
  (result id 1; inspect it with inspect {"result": 1})

repl-eval {"code": "(stats:average '(1 :x))"}
→ DEBUGGER level 1 (thread 9747): The value :X is not of type NUMBER
  Restarts:
    0: [*ABORT] Return to SLIME's top level.
  Backtrace: …
```

In the debugger:

```text
debug-backtrace {"end": 10}
debug-frame-locals {"frame": 1}
debug-eval-in-frame {"frame": 1, "code": "(length list)"}
inspect-condition {}                 ; then inspect-part {"index": n}, inspect-back {}
debug-invoke-restart {"restart": 0}  ; returns how the evaluation ended: values, abort, or a new level
```

An index the debugger does not have is refused immediately: `No restart 2: the debugger has 2 restarts (0..1)`.

**Stepping.** Compile the code with `(declare (optimize (debug 3)))`, enter with `(step …)`, then `debug-step {"mode": "into" | "next" | "out"}`. Each call returns the next stop or the final values.

Also: `repl-load-system`, `repl-run-tests` (ASDF `test-op`), `repl-interrupt` (a running evaluation enters the debugger), `repl-describe`, `repl-arglist`, `repl-apropos`, `repl-complete`, `repl-macroexpand`, `repl-xref` (`calls`, `references`, `binds`, `sets`, `macroexpands`, `specializes`), `repl-find-definitions`, `repl-threads`.

---

## 6. Static and live together

```text
source-outline {"path": "src/stats.lisp", "live": true}
→  L4  defun average (list)  [path:2] [image: defined]
   L9  defun median (list)   [path:3] [image: not loaded]      ; edited but not compiled yet

source-find-references {"symbol": "stats:average", "live": true}
→ 3 references to STATS::AVERAGE  (static, with file positions)
  [image] who-calls: …                                       ; includes calls made by macro expansions
```

The image is only asked through `find-symbol`, `fboundp` and Swank xref. Nothing is interned or loaded for the check.

---

## 7. Several REPLs (Slynk)

```text
repl-spawn {"backend": "slynk"}
repl-channel-open {"package": "stats"}
→ Channel channel-1 open (package STATS)
repl-eval {"channel": "channel-1", "code": "(list 1 2 3)"}
→ => (1 2 3)   #v0:0
repl-eval {"channel": "channel-1", "code": "(length #v0:0)"}
→ => 3   #v1:0
inspect-history {"channel": "channel-1", "entry": 0}
repl-channel-close {"channel": "channel-1"}
```

Each channel has its own thread, package and history. A long evaluation in one does not block another. Swank connections have no channels and say so.

---

## 8. Resources and notifications

| URI | |
|-----|--|
| `lisp-source:///{+path}` | file outline (path completion) |
| `repl://{connection}/output` | image output outside eval results, subscribable |
| `repl://{connection}/debugger` | innermost debugger level, subscribable |
| `repl://connections` | live connections |

The client also receives:

- a `warning` log message (logger `repl/<connection>`) when an image enters the debugger;
- `notifications/resources/updated` for subscribed URIs;
- progress for project scans, `repl-load-system`, `repl-run-tests` and whole-file compiles, when the request carries a `progressToken`.

On stdio these arrive at any time. Over HTTP they arrive in the SSE response of the request that caused them.

---

## 9. The libraries without MCP

```lisp
(asdf:load-system "lisp-source-protocol")
(let* ((ps (stack-lisp-source:read-source-file "src/stats.lisp"))
       (node (stack-lisp-source:locate ps '(:definition "defun" "average"))))
  (stack-lisp-source:commit-plan
   (stack-lisp-source:wrap-node ps node "eval-when (:compile-toplevel :load-toplevel :execute)")
   :expected-hash (stack-lisp-source:parsed-source-hash ps)
   :dry-run t))                                  ; → EDIT-RESULT with a unified diff

(asdf:load-system "repl-backend-slynk")
(asdf:load-system "process-backend-uiop")
(process-backend-uiop:use-uiop-process-backend)
(let ((conn (stack-repl:repl-spawn (repl-backend-slynk:make-slynk-backend))))
  (unwind-protect
       (let ((r (stack-repl:repl-eval conn "(error \"boom\")")))
         (when (typep r 'stack-repl:debugger-state)
           (stack-repl:repl-invoke-restart conn 0)))
    (stack-repl:repl-disconnect conn :kill t)))
```

Conditions to handle: `edit-input-unreadable`, `edit-would-unbalance`, `stale-source` (`continue` restart), `edit-not-applicable`, `ambiguous-locator` (`use-value`). On the live side: `repl-timeout` (`keep-waiting`, `interrupt`), `repl-connection-error`, `repl-spawn-error` (with the image's output), `repl-invalid-restart` and `repl-not-supported`.

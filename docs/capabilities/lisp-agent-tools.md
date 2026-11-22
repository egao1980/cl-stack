# lisp-mcp/agent (H4a, H4b): Lisp image tools for a native agent, and the debugger → inbox bridge

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H4 ("`lisp-mcp/agent` native tool source (no MCP hop); … form scanner (pure / defines / mutates / io / read-eval) as permission resources; … read-only observe mode")
**Status:** milestone **H4a** shipped as lisp-mcp **0.6.0** (0.6.1 is current), with systems `lisp-mcp/agent` and `lisp-mcp/agent/tests` (Rove) in [`egao1980/lisp-mcp`](https://github.com/egao1980/lisp-mcp), implemented through **team-solve**. Milestone **H4b locked** (the debugger → agent inbox bridge, version target **lisp-mcp 0.7.0**, then cl-stack-code 0.6.0): [H4b — locked](#h4b--locked). H4c–H4h are listed under [Roadmap](#roadmap-h4bh4h), with the H4 goal (image-first development, 2026-11-22).

H4a has three parts:

1. **`lisp-tools`** is an `ai-agent-protocol` tool source over lisp-mcp's tools: source, edit, output, repl, debug, inspect and jobs. A call runs the handler the MCP server registers, inside the agent's own image, with lisp-mcp's state bound. There is no JSON-RPC and no second process. The live image is still a separate SBCL reached over Swank or Slynk, as it is over MCP.
2. **`lisp-mcp:form-resources`** is a pure scanner from Lisp code to permission resources: `lisp:pure`, `lisp:reads`, `lisp:defines`, `lisp:mutates`, `lisp:package`, `lisp:io`, `lisp:read-eval`, `lisp:calls` and `lisp:*`. ai-agent-protocol rules match them, the same way they match `agent-tools`' shell scanner ([agent-tools-shell.md](agent-tools-shell.md)).
3. **Observe mode** (`:mode :observe`) offers only the read tools and code tools. A code tool refuses any form whose scan goes beyond `lisp:pure` / `lisp:reads …`.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| lisp-mcp 0.5.0 (`egao1980/lisp-mcp`) | All tools, names, schemas, result texts, output bounding (`oN` + `output-read`), background jobs (`jN`), per-state connections | The MCP transport, resources and notifications. Natively there is no `repl://` resource and no job-done log message: the model calls `job-wait` |
| SLIME / Sly (`slime-eval`, sldb restarts, `slime-inspect`) | The restart is chosen by index from the debugger state; the inspector walks values; separate Slynk channels | Interactive restarts that prompt (`use-value` reading from the minibuffer): Swank's `invoke-nth-restart` would hang, so tests use restarts with no arguments |
| Agent integrations over Swank (Lem's / Emacs gptel-style "eval in my image" tools, cl-mcp's `repl-eval`) | Eval in a live image as a tool, compiler notes mapped to files, errors as the debugger's value instead of a hang | Unrestricted eval with an on/off switch as the only control |
| Claude Code Bash permission model | Rules on a parsed command (`Bash(git status:*)`), a read-only class that runs without asking, a deny that the model sees as a tool result | Prefix matching on text: Lisp code is matched on **resources** from a reader walk, not on its spelling |
| agent-tools H2c `shell-command-resources` | A pure, total scanner; `*` for anything not modelled; per-resource rule matching, where an undecided resource falls back to the tool's ask | Its token grammar. Lisp needs a reader and a walker |
| lisp-source-protocol 0.2.4 | Eclector CST that never evaluates (`#.` → `read-eval-placeholder`, `#S` → `structure-placeholder`) and never interns (`symbol-token`) | — |

---

## Decisions (locked)

| Decision | Choice | Reason |
|----------|--------|--------|
| **Repo / system** | `egao1980/lisp-mcp`, a new system `lisp-mcp/agent` (`src/agent/`, package `lisp-mcp/agent`) and tests `lisp-mcp/agent/tests` (`tests/agent/`). The scanner is in core `lisp-mcp` (`src/scan-forms.lisp`, exported `form-resources`). **Version 0.6.0** for both systems. CI gets a second job, `test-system.yml` with `system: lisp-mcp/agent`. | The tool source reuses about 2 300 lines of lisp-mcp internals: the tool registry, locators, renderers, output store, jobs and state. A separate repo would either copy them or turn them into a public API in lockstep with lisp-mcp. A subsystem is the mirror image of `ai-agent-protocol/mcp`: the MCP server core gains no `ai-agent-protocol` dependency, and `lisp-mcp/agent` pulls in `mcp-protocol` only through `lisp-mcp`. The scanner depends only on lisp-source-protocol, which the core already loads, so a later MCP `--observe` flag can use it (H4d). |
| **Dependencies (new, agent system only)** | `ai-agent-protocol` ≥ 0.12.0, `llm-protocol` ≥ 0.5.0, `json-protocol` ≥ 0.2.0, `json-backend-jzon` ≥ 0.2.0. `:ci :with ("swank" "slynk")`, as in core. | JSON arguments are decoded with the stack's JSON protocol, the same way agent-tools does it. Swank and Slynk are install roots for spawned images, never dependencies. |
| **No MCP hop** | `call-lisp-tool` finds the handler in `lisp-mcp::*tools*`, wraps it exactly as `make-lisp-mcp-server` does (`bounded-handler`, plus `job-handler` for job tools), and calls it with `lisp-mcp:*state*` bound to the source's own state and `lisp-mcp::*server*` bound to NIL. | Same texts, same bounding, same jobs. NIL `*server*` makes progress and log notifications no-ops, which they already are without a client. |
| **State** | One `lisp-mcp-state` per `lisp-tools`, made by `lisp-mcp::make-state` with the root and groups. Calls may run in parallel worker threads (the protocol's function-tool path); the state's lock already serializes what needs it. | Two sources (an observer and a full one) never share connections or jobs. |
| **Tool names** | **lisp-mcp's names, unchanged** (`repl-eval`, `debug-invoke-restart`, `source-read`, …). Rules read `("repl-eval" "lisp:io" :ask)`. | One vocabulary across MCP, native, docs and the `lisp-mcp-tooling` skill. Server instructions name tools, and renaming would make them wrong. Hyphens are valid in Anthropic and OpenAI tool names. |
| **Catalog** | `:groups` takes what lisp-mcp's `--tools` takes (NIL = all, keywords, or `"code"` / `"image"` / `"all"` / comma lists), via `lisp-mcp::parse-tool-groups`. `:tools` (a name list) narrows it further. Names always stay in lisp-mcp registration order (`(reverse lisp-mcp::*tools*)`). Descriptors use lisp-mcp's description and `tool-schema`. A tool outside the catalog is `agent-unknown-tool`. | The same selection logic as the MCP server, and the descriptor bytes stay inside lisp-mcp's catalog budget. |
| **Instructions** | `lisp-tools-instructions` returns lisp-mcp's `server-instructions` for the source's groups without the `Resources:` line. In observe mode it adds one line that starts with `OBSERVE MODE`. The product appends it to the agent's instructions. | Common arguments (path, locator, connection, …) carry no schema description; the instructions explain them once. ai-agent-protocol has no hook for tool sources to add instructions, and H4b keeps it that way: the product appends the text. |
| **Arguments** | A JSON object string or a string-keyed hash table. NIL or blank means `{}`. Bad JSON, or JSON that is not an object → `tool-input-error`. | The same rule as agent-tools. |
| **Error mapping** | lisp-mcp's `bad-argument`, `path-outside-root`, `unknown-job` (all `lisp-mcp-error`), `no-connection`, `unknown-connection` and lisp-source-protocol's `lisp-source-error` (locator, edit, stale hash) → `agent:tool-input-error` with the same message. A call after `close-lisp-tools` → `agent:tool-unavailable`. Other conditions (wire errors) pass through. | "No live image: call repl-spawn …" is advice to fix the next call. `tool-unavailable` tells the model "do not call it again", which is wrong for it. |
| **Permission resources** | See [Resources](#permission-resources). The method never signals: arguments that do not parse → `("*")`. | Rules must not crash a run. |
| **Approval** | With `:needs-approval t` (the default) and no rule deciding: the code tools `repl-eval`, `debug-eval-in-frame` and `inspect` (with `code`) ask unless the scan is **observe-safe**. An edit with `compile: true` asks the same way, on its `code`. `+approval-tools+` always ask. Everything else never asks: read tools, edits without `compile`, `repl-disconnect`, `repl-interrupt`, channels, jobs, `output-read`. `:needs-approval nil` asks for nothing; rules still apply. | `(+ 1 2)` and `(length *features*)` should not prompt. A pure scan is the analogue of Claude Code's read-only commands. Edits match agent-tools' file tools, which never ask. A restart, a spawn or a load runs arbitrary code. |
| **Observe-safe** | Every resource is `lisp:pure` or matches `lisp:reads *`, or matches one of `:observe-allow`'s globs (ai-agent-protocol glob syntax). Exported as `observe-safe-resources-p`. | One predicate for both the approval default and observe mode. |
| **Observe mode** | Offers every read-kind tool (lisp-mcp's `readOnlyHint`) plus `+observe-tools+` (`repl-eval`, `debug-eval-in-frame`, `inspect`, `repl-connect`, `repl-disconnect`). Before the handler runs, a code tool whose scan is not observe-safe signals `observe-mode-refused` with only the offending resources. A tool from the full catalog that observe mode leaves out also signals `observe-mode-refused` (not `agent-unknown-tool`), with the tool's resources, so the model learns why. Spawning is refused because observe attaches. | It holds even under a catch-all allow rule: this is a mode, not a rule. |
| **Threat model** | The scanner guards against a model's mistakes in an image the user trusts. It is not a sandbox against hostile code. It assumes user methods on standard generic functions (`print-object`, …) do not have side effects, and that unqualified names that are external in `CL` mean the `CL` symbols. Confinement is H4d (remote / Podman images). | A static walk without macroexpansion cannot be sound against adversarial code. Saying so keeps the boundary honest. |
| **Stubs** | `lisp-mcp::%not-implemented` (in `src/scan-forms.lisp`). The class, readers, `lisp-tools-p`, the three constants and the condition are given. The implementation removes the stub and every call. | — |

---

## Surface

```lisp
;; package lisp-mcp (core)
(form-resources code &key (package "cl-user") features)   ; → resource strings; see grammar

;; package lisp-mcp/agent
(make-lisp-tools &key (root (uiop:getcwd)) groups tools (mode :full) observe-allow
                      (needs-approval t) (package "cl-user"))
  ;; ROOT must exist (its truename is kept). Unknown group, tool name or mode → ERROR.
lisp-tools  lisp-tools-p
lisp-tools-root  lisp-tools-groups  lisp-tools-names  lisp-tools-mode
lisp-tools-observe-allow  lisp-tools-needs-approval  lisp-tools-package  lisp-tools-closed-p
(call-lisp-tool tools name arguments)   ; → result string, synchronous
(close-lisp-tools tools)                ; disconnect all (spawned images killed), cancel jobs,
                                        ;   refuse later calls; idempotent; → NIL
(lisp-tools-instructions tools)         ; → string
(observe-safe-resources-p resources &optional allow)
+code-tools+      ; ("repl-eval" "debug-eval-in-frame" "inspect")
+approval-tools+  ; ("repl-spawn" "repl-connect" "repl-compile" "repl-load-system" "repl-run-tests"
                  ;  "debug-invoke-restart" "debug-step" "debug-restart-frame"
                  ;  "debug-return-from-frame" "inspect-action")
+observe-tools+   ; ("repl-eval" "debug-eval-in-frame" "inspect" "repl-connect" "repl-disconnect")
observe-mode-refused   ; (AI-AGENT-PROTOCOL:TOOL-PERMISSION-DENIED)

;; ai-agent-protocol methods on LISP-TOOLS
list-agent-tools  tool-executable-p  tool-needs-approval-p  invoke-tool-async
tool-permission-resources
```

`invoke-tool-async` runs `call-lisp-tool` on the protocol's sync function-tool path, in a worker thread with the value or error delivered on the loop (the same as agent-tools). It establishes its own bindings in the worker.

---

## Permission resources

| Tool | Resources |
|------|-----------|
| `repl-eval`, `debug-eval-in-frame`, `debug-return-from-frame` | `form-resources` of `code`, in the call's `package`, else the source's `:package` |
| `inspect` | with `code`: as above. With `result` N: `("inspect:N")` |
| `repl-compile` | `path:<rel>`, then `form-resources` of the located form's text in the package in effect at it (`src:package-at`), or of the whole file. A path that does not resolve, or a locator that misses → `("path:<arg>" "lisp:*")` |
| `edit-*` | `path:<rel>` for `path` (and `target_path`). With `compile: true`, the `form-resources` of `code` follow |
| `source-*` | `path:<rel>` when there is a `path`, else `("*")` |
| `repl-load-system`, `repl-run-tests` | `("system:<name>")`, downcased |
| `debug-invoke-restart` | `("restart:<name>")`: the restart at that index in the connection's current debugger state (`repl:repl-debugger-state`, `restart-info-name`), downcased, with a leading `*` and any package prefix dropped (`*ABORT` → `restart:abort`). Not in the debugger, or the index is out of range → `("*")` |
| `repl-spawn` | `("image:spawn")` |
| `repl-connect` | `("image:<host>:<port>")`, host `127.0.0.1` by default |
| any other tool, or arguments that do not parse | `("*")` |

`path:<rel>` is agent-tools' convention: lexical, relative to the root, or kept as given when it climbs out. So `("*" "path:src/*" :allow)` covers both sources.

Blank or missing `code` → `("*")`.

---

## Scanner grammar: `form-resources`

The result is a list of strings. It is in order of appearance, without duplicates, with `lisp:*` last when present. `lisp:pure` appears only alone. NIL for blank or comment-only code. The scanner never signals.

| Resource | Emitted for |
|----------|-------------|
| `lisp:pure` | at least one form, and nothing else below was emitted |
| `lisp:reads <sym>` | a free reference to an earmuffed variable (`*x*`), or `(symbol-value '<sym>)` |
| `lisp:defines <sym>` | `defun defmacro defvar defparameter defconstant defgeneric defmethod defclass defstruct deftype define-condition`, `(setf (fdefinition 'f) …)`, `(setf (symbol-function 'f) …)`, `fmakunbound`. `(defun (setf f) …)` → `lisp:defines (setf <sym>)`. Only the defined name; accessors, constructors and slots are not listed |
| `lisp:mutates <sym>` | `setq setf psetq psetf incf decf push pop pushnew shiftf rotatef multiple-value-setq remf` on a **free** variable, or on a place rooted in one (`(setf (gethash k *h*) v)` → `*h*`); destructive functions (`sort stable-sort nreverse nconc delete delete-if delete-duplicates nsubst fill replace map-into rplaca rplacd remhash clrhash vector-push vector-push-extend adjust-array …`) whose mutated argument is a free variable; `set`, `makunbound`, `(setf (symbol-value 's) …)`; `in-package` → `lisp:mutates cl:*package*` |
| `lisp:package <name>` | `defpackage make-package delete-package rename-package use-package unuse-package export unexport import shadow shadowing-import intern unintern`, `uiop:define-package`. The name is the literal designator's, downcased; no package argument → the scan's package |
| `lisp:io` | streams, files, processes and printing: `print prin1 princ pprint write terpri fresh-line write-string write-line write-char finish-output force-output`, `format` with a destination other than NIL, `read-line read-char peek-char` on a stream that is not fresh, `open with-open-file with-open-stream probe-file directory delete-file rename-file ensure-directories-exist load compile-file describe`, `uiop:run-program uiop:launch-program uiop:read-file-string uiop:read-file-lines uiop:delete-file-if-exists uiop:delete-directory-tree` |
| `lisp:read-eval` | a `#.` or `#S(…)` in the code; `read read-preserving-whitespace read-from-string read-delimited-list` (with `*read-eval*` at its default they can run `#.`) |
| `lisp:calls <sym>` | an operator the scanner does not model, whether it is a function or a macro (`(my-app:start)`, `(asdf:load-system …)`), and `#'<sym>` / `'<sym>` given to `funcall`, `apply` or a mapping function. Its arguments are still walked as forms. If it is a macro this over-reports, which is safe |
| `lisp:*` | something not attributable to a name: code that does not read cleanly (then the whole result is `("lisp:*")`); `funcall` / `apply` of a computed function; `eval`, `compile`, `coerce … 'function`; `macrolet`, `symbol-macrolet`, `progv`; an operator that is not a symbol or lambda form (`(1 2)`); an unknown setf place's root; mutating an object that is not provably fresh; nesting deeper than 200 forms |

**`<sym>`** is `package:name`, always with one colon. The package is `cl` for `CL` / `COMMON-LISP`, and for an unqualified name that is external in `CL`. It is `cl-user` for `CL-USER` / `COMMON-LISP-USER`, and `keyword` for keywords. Any other package is downcased as written. An unqualified name that is not a `CL` external takes the scan's `:package` (canonicalized the same way). The name is downcased when it has no lowercase characters; otherwise it is written `|Name|`. Uninterned names are `#:name`. Rules are case-sensitive globs, so they are written in lowercase: `lisp:calls my-app:*`.

**Reading.** `lisp-source-protocol:read-source` reads the code with `:features` (NIL → host `*features*`). A reader diagnostic or imbalance (`parsed-source-clean-p` false) → `("lisp:*")`.

**Walking.** The scanner does not macroexpand. It models the special forms and these standard macros: `quote function progn if let let* flet labels block return-from return tagbody go catch throw unwind-protect the locally multiple-value-call multiple-value-prog1 eval-when load-time-value setq declare` (ignored), `when unless cond and or case ecase typecase etypecase prog1 prog2 lambda dolist dotimes do do* loop multiple-value-bind multiple-value-list nth-value destructuring-bind handler-case handler-bind ignore-errors restart-case with-output-to-string with-input-from-string with-slots with-accessors`, the definition forms, the mutation forms, `format`, and quasiquote: only the unquoted parts are walked. `loop`: keywords are not forms, and the list after `for` / `as` / `with` is a binding pattern. Bodies of `defun`, `defmacro`, `defmethod`, `lambda`, `flet` and `labels` are walked like any code. Their effects are reported even though they run later, because that is what a person approving the definition needs to see. Calls to `flet` / `labels` functions are local. The known pure set is the CL data functions: arithmetic, comparison, conses and lists, sequences, strings, characters, hash-table reads, type tests, `values identity constantly`, printing to strings (`princ-to-string`, `format nil`), symbol and package lookups that do not intern (`find-symbol find-package find-class symbol-name`), and constructors. Any other CL operator is `lisp:calls cl:<name>` unless a table above claims it. The tests pin the cases they list. Beyond those, the solver keeps the tables conservative: when in doubt, name the operator.

**Lexical scope.** Variables bound by `let let* lambda` lists (all of `&optional &key &rest &aux`, with init forms walked), `flet` / `labels` parameters, `dolist dotimes do`, `multiple-value-bind destructuring-bind`, `loop` and `with-…-string` are lexical. Assigning a lexical variable emits nothing. A `let` of an earmuffed name is a dynamic binding. It emits nothing, and the name is not free inside. A lexical variable is **fresh** when its `let` / `let*` init is a constructor call (`list list* cons vector make-list make-array make-string make-hash-table copy-list copy-seq copy-tree copy-alist mapcar subseq reverse concatenate make-string-output-stream make-string-input-stream`), or when it is the stream of `with-output-to-string` / `with-input-from-string`, and nothing assigns it in its scope. Mutating a fresh object, or the direct result of a constructor call, emits nothing. Mutating a place rooted in a non-fresh lexical, a parameter or another call's result → `lisp:*`. Output to a fresh string stream is pure. An unknown setf accessor `(setf (acc x …) v)` → `lisp:calls (setf <acc>)` plus the root rule applied to `x`.

---

## Conditions

| Condition | Parent | When |
|-----------|--------|------|
| `observe-mode-refused` | `agent:tool-permission-denied` (`:decision :deny`) | Observe mode: a refused tool, or code that is not observe-safe. `action` = tool name, `resources` = the offending ones, `feedback` mentions observe mode and what is allowed |
| `agent:tool-input-error` | — | lisp-mcp argument / path / locator / edit / no-connection errors, bad JSON (message kept) |
| `agent:tool-unavailable` | — | any call after `close-lisp-tools` |
| `agent:agent-unknown-tool` | — | a name outside this source's catalog |
| (passes through) `repl-protocol` wire errors, `repl-timeout` | — | handled by the job layer as over MCP |

The refusal is signalled before the handler runs, so the form never reaches the image (a live test checks `boundp` afterwards). In an agent run it becomes a tool result through `tool-failure-text` (`Tool repl-eval was not run: …`).

---

## Contract (tests)

44 deftests in 8 new files of `lisp-mcp/agent/tests` (one is parametrized over swank and slynk, so 45 cases). On the stubs all of them fail (244 failing assertions, none pass), and the existing `lisp-mcp/tests` still pass. Live tests spawn `ros +Q run` images through `repl-spawn`, as lisp-mcp's own tests do. lisp-mcp's CI runs those on ubuntu, macos and windows (all green on 0.5.0). Agent tests use `llm:make-mock-llm-backend` with a scripted handler (the agent-tools pattern) on a libuv loop.

| File | Covers |
|------|--------|
| `support` | `with-tools`, `tool`, `resources`, `approval-p`, `failure` (catches `agent-condition` too), `real-failure`, the scan checks (`well-formed-p`: no duplicates, `lisp:*` last, `lisp:pure` alone; sets compared otherwise), scripted backend, `with-agent-loop` |
| `scan-test` | about 180 golden cases: blank, pure (special forms, standard macros, `loop` patterns, `flet` / `labels`, `#+(or)`, quasiquote), lexical and fresh-object mutation, non-fresh mutation → `lisp:*`, reads, defines (incl. `(setf f)` names, bodies walked, `:package`), mutates (places, destructive functions, `set`, `in-package`, unknown accessors), io, read-eval, calls (case, `|Foo|`, `#:`, `funcall #'x`), package, not modelled, unreadable code → `("lisp:*")` alone, a 300-deep form, a 600-string fixed-LCG sweep plus every prefix of five forms that never signals |
| `construct-test` | defaults, `:groups` / `:tools` / `:package` / `:needs-approval`, errors, the observe catalog (read kind + `+observe-tools+`), descriptors equal to lisp-mcp's (description, `timeout` / `verbose` arguments, no `live` without an image group), `tool-executable-p`, `source-outline` text equal to the MCP server's, hash-table and JSON-string arguments, an edit that writes, error mapping, a long result stored as `o1` and read with `output-read`, instructions, close |
| `permissions-test` | resources of code, path, compile (form, whole file, `in-package` context, misses) and image tools; approval defaults over every `+approval-tools+` entry and the never-ask tools; `agent-permission` effects for rules over scanner output (`lisp:calls my-app:*` allow, undecided io → ask, `lisp:*` only by a catch-all, deny on defines / read-eval, `system:` and `path:` rules) |
| `observe-test` | `observe-safe-resources-p`; refusals with only the offending resources and an "observe" feedback; safe code passes the gate (then "No live image"); `:observe-allow` globs; refused tools leave files untouched; read tools run |
| `live-test` | swank × slynk: spawn, eval, compile a located form, a seeded `restart-case` bug → debugger, `restart:return-default` / `restart:abort` / out of range, invoke restart → `=> 42`; a background job (`timeout` 1 → `j1`, `job-wait`); `close-lisp-tools` disconnects spawned images; observe source attached over `swank:create-server` refuses `defparameter`, the image never sees it, and closing the observer leaves the image running |
| `agent-run-test` | descriptors through `collect-run-tools` / `find-agent-tool`; **an agent fixes a seeded bug with a restart** while a `restart:abort` deny rule refuses the wrong one with its feedback; a pure eval runs and a mutating one pauses the run (`:approval`); a `lisp:io` deny rule; an observe refusal is a tool result and the run goes on |

Checklist applied (team-solve STAGED): every assertion sits inside `ok`; `failure` catches `agent-condition`; there are no `handler-bind` / `find-restart` assertions; there are no `~<newline>` FORMAT directives; the sweep uses a fixed LCG. **No prototype was run over the stubs** (STAGED's cheapest guard), so a proven test bug found during the solve should be fixed by the coordinator in its own commit and re-sealed, and the PR should say so.

---

## Out of scope (H4a)

The debugger → inbox bridge, drift and promote-to-source, image checkpoints, remote images, trace / profile, an MCP `--observe` flag, a tool-source instructions hook in ai-agent-protocol, macroexpansion in the scanner (it would need the image), and recursive scanning of `eval` with a literal form.

## H4b — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, H4 ("debugger → agent inbox bridge (restarts gated by permissions)"), acceptance "Agent fixes a seeded bug by choosing a restart in a spawned image". H4a shipped as lisp-mcp **0.6.0** (0.6.1: edits compile in the file's package, kills wait for the image).

H4b is split over two repos, **in this order**:

1. **`egao1980/lisp-mcp` (this section), version 0.7.0.** The bridge itself: which debugger entries are events, the event object and its text, the queue on the source, and posting into an agent run's inbox. Contract: branch `agent/h4b-contract-e2a7`, systems `lisp-mcp/agent` and `lisp-mcp/agent/tests`. The exact rules are in the header of `src/agent/events.lisp`.
2. **`egao1980/cl-stack-code`, version 0.6.0.** The product wiring: `--lisp-image spawn|attach:[HOST:]PORT`, the lisp tools beside the file and shell tools, the system prompt section, the status line marker, the banner, and what an event does when no turn runs. See [cl-stack-code.md, H4b — locked](cl-stack-code.md#h4b--locked). Contract: branch `agent/h4b-contract-e2a7` of cl-stack-code. It depends on `lisp-mcp/agent` 0.7.0, so lisp-mcp is implemented, merged and published first.

Both go through **team-solve**.

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| SLIME / Sly | A debugger entry in any thread pops an sldb buffer naming the thread and level, with the restarts and the top frames. `:debug-return` closes it. | The buffer itself, and the "which sldb is current" UI. The debug tools act on the newest level of the connection (repl-protocol), as before. |
| repl-protocol 0.2.7 | `(:debug thread level condition restarts frames conts)` events through `repl-event-listener`, the `continuations` list (pending request ids in that thread), `debugger-state-request-id`. | No protocol change: the events and the data were already there. |
| lisp-mcp 0.5 MCP notifications | "X entered the debugger (level N): … Use debug-state, debug-backtrace, debug-invoke-restart" as a log message, and job-done log messages | MCP resource updates. Natively the message is an inbox turn, which the model actually reads |
| ai-agent-protocol inbox (0.5–0.14) | `agent-run-post` (injected before the next generate), a post during the final answer takes one more step, subagent reports as tagged user turns (`<subagent id=… name=…>`) | No protocol change. The tool-source instructions hook moves out (the product appends `lisp-tools-instructions` itself, as H4a planned) |
| Claude Code background tasks | A background job's end is reported to the agent without a poll | Its UI |

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Repo split** | The bridge is in `lisp-mcp/agent`. The product decides what an event does when no turn runs, and how it looks, in cl-stack-code. Two contract branches, lisp-mcp first. | The bridge needs lisp-mcp's state, jobs and connection listeners, which are internals. Every host of `lisp-tools` (cl-stack-code, demos, a future SDK) gets events the same way. The idle policy, the banner and the status line are product UI. |
| **Which entries are events** | A `:debug` whose `continuations` is NIL or `:unknown`: a thread no request is pending in (a background thread, a timer, an attached image's own threads). A `:debug` whose continuations name a pending request belongs to that request. A synchronous tool call returns it as its result (H4a's "DEBUGGER level N …", **not a hang**), and a detached job reports it as a `:job` event. So nothing is reported twice. | Swank and Slynk send the continuations with every `:debug`. They tell exactly whether a caller is waiting. Timing heuristics would race. |
| **Jobs** | A job the caller was told is "Still running as job jN" (detached) produces a `:job` event when it finishes, fails or ends in the debugger. A job that finishes within its call's wait is that call's result. | Natively there was no job-done notification (H4a: "the model calls job-wait"). A long load that lands in the debugger is the most common asynchronous debugger entry. |
| **Event object** | `image-event`: kind (`:debugger` `:job` `:debugger-return`), connection, thread, level, condition, restarts (`(index name description)` with NAME in the `restart:` resource form, e.g. `retry-later`), frames (top `+image-event-frames+` = 8), job, job-state, text. | A product can show the rule that would allow a restart without parsing text. |
| **Text** | `<lisp-image-event kind="debugger" connection="C" thread="T" level="L">` LF, `C entered the debugger outside a tool call (thread T, level L).` LF, lisp-mcp's terse debugger rendering with 8 frames, then `The thread waits in the debugger until a restart is chosen: call debug-invoke-restart with connection "C" (debug-backtrace, debug-frame-locals and inspect-condition look first).` LF, `</lisp-image-event>` LF. Observe mode replaces the advice line with `This source is in observe mode: it cannot choose a restart. Tell the user which restart you would choose and why.` Job events: `<lisp-image-event kind="job" connection="C" job="jN" state="done\|failed">`, `Job jN (<summary>) finished\|failed after S s:`, the result, the closing tag. `debugger-event-text` is pure and exported. | The subagent-report idiom (`<subagent …>`). The body is the same text a tool call shows, so the model reads one format. |
| **Queue and callback** | Events are queued on the source, oldest first. A new `:debugger` event for the same connection, thread and level replaces the old one. `lisp-tools-pending-events` copies the queue, `take-image-events` empties it, and `post-image-events tools run` takes the events and `agent-run-post`s each one's turn (`image-event-turn`). `:on-image-event` (a function of `tools event`) is called on the producing thread (the reader thread, or the job worker) after queuing. It must not block or call the source's image tools. Its errors become warnings. `:debugger-return` events are not queued: they go only to the callback, and they drop queued `:debugger` events of that thread at that level or deeper, which are stale. `close-lisp-tools` empties the queue. `:image-events nil` turns all of this off. | The queue keeps events that arrive while no turn runs, so a product can decide later. The callback lets a product wake its UI or its loop without polling. Posting from any thread is safe, because `agent-run-post` locks. |
| **Restarts** | Unchanged H4a gate: `debug-invoke-restart` gives `("restart:<name>")` from the connection's newest debugger level (the background one when it is the newest), it is in `+approval-tools+`, rules decide, interactive approval dialogs, headless deny unless a rule allows it. On a level no request waits for, the tool returns `Invoked restart N [NAME] in thread T; no tool call was waiting on that thread, so its values are not shown.` instead of `; No values`. | The permission story stays one story. The new text tells the model the restart worked, and why no value comes back. |
| **Observe mode** | A hard gate, unchanged. An observer still gets debugger events (watching a production image's errors is a use case), with the observe footer. It never runs a restart: `debug-invoke-restart` is not offered and is refused with `observe-mode-refused`. | A rule cannot lift it, and neither can `bypassPermissions` in the product. |
| **Instructions** | With image events on and an image group offered, `lisp-tools-instructions` adds a line starting `IMAGE EVENTS:` that names `<lisp-image-event>`, after lisp-mcp's lines and before the `OBSERVE MODE` line. | The model should know what the tagged turns are before the first one arrives. |
| **Wiring** | A per-state hook in lisp-mcp core, called by `connection-listener` for every connection event, and one called by `finish-job` for detached jobs. Both are set by `make-lisp-tools`. The MCP server's notifications are unchanged. | No repl-protocol change. |
| **Moved out of H4b** | The MCP server's `--observe` goes to H4d (remote images, where observe is the default). The tool-source instructions hook in ai-agent-protocol is dropped: products append `lisp-tools-instructions`. `shell-timeout` restarts are an agent-tools slice, not the image layer. | The slice stays about the image debugger. None of the three is needed for the plan's H4 acceptance. |
| **Stubs** | `lisp-mcp/agent::%not-implemented` in `src/agent/events.lisp`. Given: the `image-event` class and readers, the constants, the `make-lisp-tools` keys and slots. Stubbed: `debugger-event-text`, `lisp-tools-pending-events`, `take-image-events`, `image-event-turn`, `image-event-turn-p`, `post-image-events`. Left to the implementation: the core hooks, classification, the restart text, the instructions line. | — |

### Surface (new in 0.7.0)

```lisp
;; package lisp-mcp/agent
(make-lisp-tools … &key (image-events t) on-image-event)
lisp-tools-image-events-p  lisp-tools-on-image-event (accessor)
image-event  image-event-p  image-event-kind  image-event-connection  image-event-thread
image-event-level  image-event-condition  image-event-restarts  image-event-frames
image-event-job  image-event-job-state  image-event-text
+image-event-frames+ 8   +image-event-tag+ "lisp-image-event"
(debugger-event-text connection debugger-state &key observe) → string   ; pure
(lisp-tools-pending-events tools) → events   (take-image-events tools) → events
(image-event-turn event) → llm user turn      (image-event-turn-p turn)
(post-image-events tools run) → events posted (agent-run-post, oldest first)
```

### Contract (tests)

15 new deftests (17 cases with the swank × slynk rows) in three new files of `lisp-mcp/agent/tests`. On the stubs all 17 fail (33 failing assertions, measured), and the 46 H4a cases pass, as do `lisp-mcp/tests`. The asynchronous debugger entry is a `sb-thread:make-thread` in a spawned `ros +Q run` image whose `restart-case` offers `retry-later`.

| File | Covers |
|------|--------|
| `bridge-test` | defaults and constants, the callback accessor, the exact debugger text (8 of 12 frames) against lisp-mcp's renderer, the observe footer, event turns and `image-event-turn-p` (user turns only, the tag leads), the `IMAGE EVENTS:` line and its place, closed sources |
| `bridge-live-test` | swank × slynk: a background debugger is one queued event with every slot, the callback sees it once, the restart gate sees it (`restart:retry-later`, asks), take, the new restart text, the `:debugger-return` event, not queued; a restart without a take drops the stale event; swank × slynk: a tool call's own debugger is its result and no event, `=> 42` after the restart; detached jobs as `:job` events (done, and ended in the debugger, reported once), a call that finishes in time is no event; `:image-events nil`; close drops events |
| `bridge-agent-test` | **an agent answers a background debugger**: the event reaches the run's inbox before the next generate (after the eval's result, once), a `restart:abort` deny rule refuses the wrong restart with its feedback, `retry-later` runs; an unattended run denies the restart (no rule) and the thread stays in the debugger; an event while no turn runs waits in the queue and becomes the next turn with `continue-ai-agent` |

No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, re-sealed, as in H4a.

---

## Roadmap (H4b–H4h)

**Goal of the H4 track (2026-11-22): image-first development.** Other harnesses are file / edit / compile / restart oriented. Here the live image is where the agent works: it evaluates, inspects, fixes in the frame and keeps state, and files are where finished definitions land. The harness image already runs everything; agent code runs in **session images** the harness controls (confined, supervised `:image` units). Self-modification of the harness itself comes later (after H6).

**Order:** H4f → H4e (versioned) → ACP ([acp.md](acp.md)) → H5d → H4g → self-modification later. H4h runs after H4f, in parallel with H4e.

| Slice | Content | Depends on |
|-------|---------|------------|
| **H4b** | **Locked**: [H4b — locked](#h4b--locked). Debugger → agent inbox bridge in lisp-mcp/agent 0.7.0, product wiring in cl-stack-code 0.6.0. The MCP `--observe` flag moves to H4d, the tool-source instructions hook is dropped, and `shell-timeout` restarts go to agent-tools | H3 (inbox), repl-protocol events |
| **H4c** | **Image ↔ source drift + promote to source.** Compare definitions in the image (xref / `find-definitions`, function source forms) with the files (`source-outline` + hashes). **Three-way drift** (2026-11-22): each image definition records the source-form hash it shadows, so drift reads as changed in the image, moved in the source, or both. Drift blocks a commit (an H6 revision hook). "Promote" writes the image's version of a form to its file with `edit-replace` | revision-protocol, H4a |
| **H4d** | **Remote and confined images.** SSH port forward, Swank secret, Podman via `agent-runtime-backend-podman`, observe mode as the default for production attaches, the MCP server's `--observe` flag (from H4b), `image:` resources with host names | agent-runtime-protocol |
| **H4e** | **Suspend / resume and versioned session images**, plus trace and profile (below) | H4f, revision-protocol, object-store-protocol, diff-protocol, repl-protocol 0.3 |
| **H4f** | **Named live sessions and the workbench** (below). First in the H4 order | supervisor-protocol, R4d confinement |
| **H4g** | **Code mode and `deftool`** (below) | H4f, H4e, H5d |
| **H4h** | **Canvases**: plain CL functions in the session image served as HTML pages, live or frozen to a file (below) | H8d-1, H4f |

### H4f — named live sessions and the workbench

| Topic | Decision |
|-------|----------|
| **Tools** | `lisp_session_open` / `lisp_session_list` / `lisp_session_describe` / `lisp_session_close`, and `lisp_eval` in a named session. Every session is a supervisor `:image` unit, confined (R4d) |
| **Workbench** | A session that replaces shell and Python for scratch work: the stack preloaded (pathlib, json / yaml / csv / sql, http-backend-async, process-protocol, diff / lisp-source, the revision backends), shipped as a **saved core** for a fast start, with a cheat sheet in the system prompt. `bash` stays for external programs |
| **Inspection and restarts** | inspect, describe, xref, apropos and restarts are first-class. Fix in the frame: redefine, then `restart-frame`. Tools the agent builds define their own restarts |
| **Human attach** | A shared session a person can attach to from SLIME / Sly / Lem |

### H4e — suspend / resume and versioned session images

| Topic | Decision |
|-------|----------|
| **Suspend** | Unix: fork + `save-lisp-and-die` in the child (the session keeps running). Windows: stop + save. Everywhere: a **reload recipe** (systems + an evaluated-forms journal) as the fallback |
| **Store** | Images are versioned in a **revision-protocol** store. A revision holds the core blob in object-store-protocol (content-addressed, zstd-compressed); a provenance manifest (source commit, SBCL version, OS, arch, loaded systems, boot-probe result); an inventory of definitions with source-form hashes; the reload recipe; its parents |
| **Operations** | commit = suspend; checkout = resume (the recipe when provenance does not match); branch = fork a warm image for a subagent; diff = the inventory diff through diff-protocol; log / tree next to the conversation tree |
| **Where metadata lives** | Metadata may live in git / jj; cores stay in the object store. Content-defined chunking is deferred until measured |
| **Safety (from the Autolith review)** | A core is selectable only after a clean **boot probe** plus a list of load-bearing functions. `sb-ext:*init-hooks*` release saved mutexes. The saver scrubs credentials and refuses while secrets are in use. `checkpoint-detach-state`-style GFs let tool runtimes detach and reattach |
| **Trace / profile** | Stays here: `repl-protocol` trace / profile GFs and their tools |

### H4g — code mode and `deftool`

| Topic | Decision |
|-------|----------|
| **Code mode** | The agent's tools are callable as functions in the workbench, with an explicit allowlist of tools per eval. Self-mutation tools are excluded, payloads are capped, an interrupted callback is logged as unknown-outcome. The form scanner reports a bridge call as a `lisp:calls <tool>` permission resource |
| **`deftool`** | Typed functions whose schema comes from the lambda list and declarations. `tool_register` runs them inside the confined image, never in the harness. Promote writes them into an extension system |
| **Self-change journal** | pending → installed → checked → replay script → selected, with exact undo |
| **Executable skills** | A data-only manifest: system, entrypoint, self-test, I/O contracts, needed host tools |
| **Restart retry** | Stateless: repeat the call naming a restart, allowed by the scanner only for pure / defines forms. The held-thread mode (H4b) stays |

### H4h — canvases

HTML pages that a session makes. **A canvas is a plain CL function defined in the session image**: no canvas object, no registry, no `defcanvas` / `defhandler` macros.

| Topic | Decision |
|-------|----------|
| **A canvas** | A function that takes keyword arguments (the request parameters) and returns an html-protocol tree. State is ordinary image state. Redefining the function changes what the next request shows. The agent defines canvases with `lisp_eval` |
| **Live (default)** | Pages are generated on each request and never written to disk. A canvas lives as long as its definition in the image. Persistence, branching, rewind and image diff come from H4e, because canvases are just definitions |
| **Frozen** | `canvas_freeze` calls the function with the given arguments, inlines the result, drops the hx links, and writes a self-contained `.html` (no network, no CDN) into the session dir; "Save to workspace" is offered. For sharing, PRs and demo output. Tables are plain HTML; charts are SVG rendered in Lisp, no JS library |
| **Static from the start** | The same as frozen, for final reports |
| **URL** | `/canvas/<session>/<package>::<name>?key=value`. The server checks the token, then calls the function in the session image through repl-protocol. Query and form parameters arrive as keyword → string; the function parses them or uses `check-type`. The result is serialized with escaping |
| **Interactivity** | Vendored htmx: `hx-get` / `hx-post` point at other canvas functions, and `canvas-url 'fn :k v` builds those links. They run **in the confined session image** and return HTML fragments. Live updates over SSE (the htmx SSE extension) come from a function that returns a generator, or from a unit tail, pushed through the same server |
| **Exposure** | Only the functions the agent explicitly opened with `canvas_open 'fn …`: an allowlist per session. The form scanner classified each function when it was defined; a mutating function behind `hx-post` needs the same approval as when the agent calls it |
| **Server** | One local server per harness session: the H8d-1 web view on http-server-protocol + http-backend-async. Loopback only; a random per-session token in the URL, exchanged for a cookie; strict CSP (`script-src 'self'`, no inline scripts, no outside connections). Serves `/canvas/…` next to the H8d unit views and routes each request to the image that owns the session: one port, one auth, one permission layer |
| **HTML** | html-protocol trees, which escape by construction. Library functions: table (server-side sort and paging), svg-chart (line, bar, scatter, histogram), diff-view, form, log-tail |
| **Surfaces** | A TUI transcript entry and `/canvas`; an ACP resource link in `session/update`; the path or URL in the `-p` JSON stream |
| **Tools** | `canvas_open`, `canvas_freeze`, `canvas_list`, `canvas_snapshot` (a text / accessibility summary, so the agent checks its page without a browser). No `canvas_create` / `canvas_update`: definitions go through `lisp_eval` |
| **Prior art** | Claude artifacts and ChatGPT canvas (client-side only); Jupyter, marimo, Observable (a live kernel); CLOG (a Lisp GUI over websockets) |
| **First demo** | A benchmark table and chart, frozen and live (filter, drill into a run's log) |

### Small items (any time)

- An **interpreter-discipline** context rule: `python3 -c` through `bash` gets a nudge toward the workbench.
- A **tool-storm guard**: withhold repeated identical calls and A-B-A oscillation.
- A **pristine recovery core** plus a read-only diagnosis turn after a crash, and an `--immutable` mode.

### Credit: the Autolith review

Several H4e / H4g / H6 decisions come from reviewing [lambda-symbolics/autolith](https://github.com/lambda-symbolics/autolith) (ISC). What to avoid, from the same review: one package for everything (distribution wrappers broke); self-mutation without per-call approval; overrides that never reach source; polling clients; plaintext non-loopback endpoints.

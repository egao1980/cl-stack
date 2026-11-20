# lisp-mcp/agent (H4a): Lisp image tools for a native agent

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H4 ("`lisp-mcp/agent` native tool source (no MCP hop); … form scanner (pure / defines / mutates / io / read-eval) as permission resources; … read-only observe mode")
**Status:** milestone **H4a locked**. The contract is on branch `agent/h4a-contract-cfba` of [`egao1980/lisp-mcp`](https://github.com/egao1980/lisp-mcp): systems `lisp-mcp/agent` and `lisp-mcp/agent/tests` (Rove). Every new function calls `lisp-mcp::%not-implemented`. It will be implemented through **team-solve**. Version target **lisp-mcp 0.6.0**. H4b–H4e are listed under [Roadmap](#roadmap-h4bh4e).

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
| **Repo / system** | `egao1980/lisp-mcp`, a new system `lisp-mcp/agent` (`src/agent/`, package `lisp-mcp/agent`) and tests `lisp-mcp/agent/tests` (`tests/agent/`). The scanner is in core `lisp-mcp` (`src/scan-forms.lisp`, exported `form-resources`). **Version 0.6.0** for both systems. CI gets a second job, `test-system.yml` with `system: lisp-mcp/agent`. | The tool source reuses about 2 300 lines of lisp-mcp internals: the tool registry, locators, renderers, output store, jobs and state. A separate repo would either copy them or turn them into a public API in lockstep with lisp-mcp. A subsystem is the mirror image of `ai-agent-protocol/mcp`: the MCP server core gains no `ai-agent-protocol` dependency, and `lisp-mcp/agent` pulls in `mcp-protocol` only through `lisp-mcp`. The scanner depends only on lisp-source-protocol, which the core already loads, so a later MCP `--observe` flag can use it (H4b). |
| **Dependencies (new, agent system only)** | `ai-agent-protocol` ≥ 0.12.0, `llm-protocol` ≥ 0.5.0, `json-protocol` ≥ 0.2.0, `json-backend-jzon` ≥ 0.2.0. `:ci :with ("swank" "slynk")`, as in core. | JSON arguments are decoded with the stack's JSON protocol, the same way agent-tools does it. Swank and Slynk are install roots for spawned images, never dependencies. |
| **No MCP hop** | `call-lisp-tool` finds the handler in `lisp-mcp::*tools*`, wraps it exactly as `make-lisp-mcp-server` does (`bounded-handler`, plus `job-handler` for job tools), and calls it with `lisp-mcp:*state*` bound to the source's own state and `lisp-mcp::*server*` bound to NIL. | Same texts, same bounding, same jobs. NIL `*server*` makes progress and log notifications no-ops, which they already are without a client. |
| **State** | One `lisp-mcp-state` per `lisp-tools`, made by `lisp-mcp::make-state` with the root and groups. Calls may run in parallel worker threads (the protocol's function-tool path); the state's lock already serializes what needs it. | Two sources (an observer and a full one) never share connections or jobs. |
| **Tool names** | **lisp-mcp's names, unchanged** (`repl-eval`, `debug-invoke-restart`, `source-read`, …). Rules read `("repl-eval" "lisp:io" :ask)`. | One vocabulary across MCP, native, docs and the `lisp-mcp-tooling` skill. Server instructions name tools, and renaming would make them wrong. Hyphens are valid in Anthropic and OpenAI tool names. |
| **Catalog** | `:groups` takes what lisp-mcp's `--tools` takes (NIL = all, keywords, or `"code"` / `"image"` / `"all"` / comma lists), via `lisp-mcp::parse-tool-groups`. `:tools` (a name list) narrows it further. Names always stay in lisp-mcp registration order (`(reverse lisp-mcp::*tools*)`). Descriptors use lisp-mcp's description and `tool-schema`. A tool outside the catalog is `agent-unknown-tool`. | The same selection logic as the MCP server, and the descriptor bytes stay inside lisp-mcp's catalog budget. |
| **Instructions** | `lisp-tools-instructions` returns lisp-mcp's `server-instructions` for the source's groups without the `Resources:` line. In observe mode it adds one line that starts with `OBSERVE MODE`. The product appends it to the agent's instructions. | Common arguments (path, locator, connection, …) carry no schema description; the instructions explain them once. ai-agent-protocol has no hook for tool sources to add instructions (H4b may add one). |
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

## Roadmap (H4b–H4e)

| Slice | Content | Depends on |
|-------|---------|------------|
| **H4b** | **Debugger → agent inbox bridge.** A debugger entry in a spawned or attached image, outside any tool call (another thread), becomes an inbox message for the agent: condition, restarts, top frames. Choosing a restart goes through `debug-invoke-restart` and its `restart:` rule. `shell-timeout`'s `continue` / `run-in-background` restarts are offered the same way. The same slice adds observe mode to the MCP server (`--observe`) and a tool-source instructions hook | H3 (inbox), repl-protocol events |
| **H4c** | **Image ↔ source drift + promote to source.** Compare definitions in the image (xref / `find-definitions`, function source forms) with the files (`source-outline` + hashes). Drift blocks a commit (an H6 revision hook). "Promote" writes the image's version of a form to its file with `edit-replace` | revision-protocol, H4a |
| **H4d** | **Remote and confined images.** SSH port forward, Swank secret, Podman via `agent-runtime-backend-podman`, observe mode as the default for production attaches, `image:` resources with host names | agent-runtime-protocol |
| **H4e** | **Checkpoints, trace and profile.** Reload recipe (systems + evaluated forms journal), `fork` on Unix, saved cores. `repl-protocol` trace / profile GFs and their tools | repl-protocol 0.3 |

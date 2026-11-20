# cl-stack-code (H3a): the coding agent's headless shell

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H3 ("Product shell: interactive / `-p` / JSON stream / RPC / SDK; settings layering (user, project, local); … `AGENTS.md` discovery"). The repo was decided there (Decision 1).
**Status:** milestone **H3a locked**. The contract is in [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code) (`cl-stack-code/tests`, Rove), and every function that does work calls `%not-implemented`. It will be implemented through **team-solve**. Version target **cl-stack-code 0.1.0**. Later slices: [Roadmap](#roadmap-h3bh3e).

`cl-stack-code` is the product: a coding agent CLI on cl-stack. H3a is the **headless** half only:

```
cl-stack-code -p "fix the failing test" --output-format stream-json --permission-mode acceptEdits
```

It parses the command line with [cli-protocol](cli.md), merges settings from user, project and local files and the flags, finds `AGENTS.md` files, assembles the system prompt, wires the [agent-tools](agent-tools.md) file and [shell](agent-tools-shell.md) tools rooted at the working directory, maps permission rules onto [ai-agent-protocol](ai-agent.md), runs one agent run on a libuv loop, and prints the answer as text, one JSON object, or a stream of JSON lines. Anything that would need a human approval is denied with a tool result that says why. The interactive TUI, sessions, RPC and the SDK come later.

The product adds no protocol. Everything it does is composition: `llm-protocol` backends, the `ai-agent-protocol` loop, rules, approvals and lazy instruction discovery, `steer-protocol`'s base prompt, `agent-tools` sources, `cli-protocol` parsing, `json-protocol` encoding and `cl-stack-pathlib` file access.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code `claude -p` | `-p` with a positional prompt, stdin when there is none; `--output-format text \| json \| stream-json`; a final `result` object with `subtype`, `is_error`, `num_turns`, `session_id`, `usage`, `permission_denials`; `--max-turns`, `--model`, `--allowed-tools` / `--disallowed-tools` as `Tool(spec)` rule strings; `--permission-mode default \| acceptEdits \| bypassPermissions \| plan`; `--append-system-prompt`; user / project / local settings files under the CLI flags, with deny > ask > allow across all of them; an `env` key | `--input-format stream-json` and `--resume` / `--continue` (H3c, H3d); `total_cost_usd` (no price table); `--include-partial-messages` (stream-json always carries deltas here); MCP config, hooks, managed settings; its message-envelope event shape |
| Codex `codex exec` | `AGENTS.md`: a user-level file first, then the files from the git root down to the working directory, root first; a per-file size cap; `--cd`; JSONL events ending in usage; a non-interactive run never asks for approval | Sandbox modes (confinement stays in `compute-backend-*`); the "must be in a git repo" check; TOML config, profiles, `-c key=value`; `--output-last-message` |
| pi `pi -p` / `--mode json` | `--append-system-prompt`; `AGENTS.md` **and** `CLAUDE.md`; walking parent directories from the working directory; global settings overridden by project settings | No permissions at all; `--mode rpc` (H3d); JSONL sessions (sessions are a revision store here, H3c) |
| opencode `opencode run` | `provider/model` designators (here llm-protocol's `provider:model`); `AGENTS.md` with `CLAUDE.md` as the fallback; a user-level file under `~/.config/`; ordered allow / ask / deny patterns; `--format json` events | Agents and modes config, sharing, the server / client split (H6) |

---

## Decisions (locked)

| Decision | Choice | Reason |
|----------|--------|--------|
| **Repo / system** | `egao1980/cl-stack-code`, system `cl-stack-code` (nickname `stack-code`), tests `cl-stack-code/tests`. **Version 0.1.0.** | Plan Decision 1. A product, so it exports functions, not GFs to specialize. |
| **Dependencies** | `ai-agent-protocol` ≥ 0.10.0, `agent-tools` ≥ 0.2.0, `llm-protocol` ≥ 0.5.0, `llm-protocol-anthropic` ≥ 0.3.0, `llm-protocol-openai` ≥ 0.4.0, `steer-protocol` ≥ 0.3.0, `cli-protocol` + `cli-backend-clingon` ≥ 0.1.0, `json-protocol` + `json-backend-jzon`, `cl-stack-pathlib` ≥ 0.6.0, `event-protocol` + `event-backend-libuv`, `http-protocol` + `http-backend-async`. Tests add `rove`. | Own stack only (HTTP is `http-backend-async` × libuv). `(asdf:load-system "cl-stack-code")` is enough to run against Anthropic or an OpenAI-compatible server. |
| **H3a scope** | Headless only. `-p` / `--print` is required. Without it the run is a usage error (exit 2) saying the interactive mode arrives in H3b. | One slice, one contract. |
| **Entry** | `(run-cli argv &key output error-output input providers user-config-dir getenv)` runs one invocation and **returns the exit code**; it never quits the image. `(main)` is `(uiop:quit (run-cli (uiop:command-line-arguments)))`. The `.asd` declares `program-op` with entry point `cl-stack-code:main` and build pathname `bin/cl-stack-code`. | Tests drive `run-cli` with string streams, a scripted backend and a private config directory. A polished single binary (natives preloaded) is H6. |
| **Arguments** | One `stack-cli` command built on its own clingon backend instance (`*cli-backend*` is left alone), parsed with `stack-cli:parse` and cli-protocol's default option styles. Free arguments are the prompt, joined with single spaces. No free argument, or the single argument `-`, reads all of `input`. A blank prompt is a usage error. | cli-protocol is the stack's CLI layer, and it already accepts PowerShell and CMD spellings on Windows. |
| **Model designator** | llm-protocol's provider ref: `provider:model` or `provider` (the provider's default model), via `parse-provider-ref`. Default `"anthropic"`. Built-in providers: `anthropic` (`make-anthropic-backend`) and `openai` (`make-openai-compat-backend`, any OpenAI-compatible server through `OPENAI_BASE_URL`). | No model ids baked into the product; they go stale. |
| **Providers are factories** | A provider is `(lambda (model env) …) → llm-backend`, where MODEL is the designator's model or NIL and ENV is the effective environment lookup (below). The backend is built once per run, **after** settings merge, with the model as its default model. `run-cli :providers` (an alist `name → factory`) is consulted before the built-ins. An unknown provider signals `model-not-found` (exit 2). | Settings `env` can hold the API key or base URL, so backends must be built after the merge. The agent loop passes no `:model` to `generate` ([ai-agent-protocol#25](https://github.com/egao1980/ai-agent-protocol/issues/25)), so the model has to be the backend's default. |
| **Event loop and HTTP** | `run-cli` makes its own libuv event loop and binds `event-protocol:*event-backend*` / `*event-loop*` around the run. When `http-protocol:*http-backend*` is NIL it binds an `http-backend-async` backend, and it adds `http-protocol:*http-backend*` to `ai-agent-protocol:*off-loop-specials*` for the run. | ai-agent-protocol needs a bound loop; provider HTTP calls run off-loop. |
| **Settings files** | User `<user-config-dir>/settings.json`; project `<project-dir>/.cl-stack-code/settings.json`; local `<project-dir>/.cl-stack-code/settings.local.json`; then the flags. `<project-dir>` is the project root when there is one, else the working directory. `<user-config-dir>` is `$CL_STACK_CODE_CONFIG_DIR`, else `$XDG_CONFIG_HOME/cl-stack-code/`, else `~/.config/cl-stack-code/` (every OS); a relative value is ignored. | Claude Code's three files; one config directory on every OS. `settings.local.json` is for the user's untracked overrides (and H3b's saved "always" replies). |
| **Settings format** | A JSON object (json-protocol): `model` string; `maxTurns` integer ≥ 1; `permissionMode` one of the four mode names; `permissions` an object with `allow`, `ask`, `deny` arrays of rules; `env` an object of string or `null` values; `appendSystemPrompt` string. Unknown keys are ignored. A missing file is no layer. Bad JSON, a non-object, or a wrong type signals `settings-error` naming the file and the key path (`maxTurns`, `permissions.allow[1]`, `env.FOO`). | Small, typed, forward compatible. |
| **Merge rules** | Layers merge in order user, project, local, flags. **Scalars** (`model`, `maxTurns`, `permissionMode`, `appendSystemPrompt`): the last layer that sets one wins. **Rule lists** (`allow`, `ask`, `deny`): concatenated in layer order; a later duplicate (same tool, resource and effect) is dropped. **`env`**: merged key by key, the later layer wins; a `null` value marks the key **unset**, which a later layer can set again. `settings-files` lists the files read, in order. | Precise and predictable. Lists accumulate because every layer's rules matter; precedence among them comes from the effect (next row), not from the layer. |
| **Rule precedence** | Across all layers **deny beats ask beats allow**. The agent's rule list (last match wins) is: the mode's base rules, then every allow, then every ask, then every deny. | Claude Code's semantics: a project file cannot loosen a user's deny. |
| **Rule syntax** | A string `TOOL` or `TOOL(SPEC)`, or an object `{"tool", "resource", "feedback"}`. `TOOL` is an ai-agent-protocol action glob. `SPEC` becomes the resource: kept as written when it is `*` or starts with `path:` `bash:` `program:` `cd:` `read:` `write:` `job:`; otherwise prefixed by the tool: `path:` for `read write edit multi_edit glob grep ls`, `bash:` for `bash`, `job:` for `job_output job_input job_kill`, nothing for any other tool or a glob. A bare `TOOL` has resource `*`. The object form takes `resource` literally (default `*`); `feedback` is the text a deny shows the model. An empty string, `TOOL()`, an unbalanced parenthesis, text after the `)`, or whitespace in `TOOL` signals `permission-rule-error`. | `bash(git *)` and `edit(src/*)` read naturally and map onto agent-tools' resources (`bash:git *`, `path:src/*`); the prefix escape reaches `program:` and `write:`. |
| **Flag rules** | `--allowed-tools` adds allow rules and `--disallowed-tools` deny rules, to the flag layer. Both repeat; each value splits on commas and whitespace **outside** parentheses (`"read,grep" "bash(git log --oneline)"`). | Claude Code's flags; parentheses keep a command's spaces. |
| **Hidden tools** | A deny rule with resource `*` (from any layer) removes every tool its action glob matches from the tools offered to the model. Other denies stay rules. | The model is not offered a tool it can never use (Claude Code does the same for a bare `--disallowed-tools` name). |
| **Permission modes** | `default`: base rules ask for `write`, `edit` and `multi_edit` (`("write" "*" :ask)` …); `bash` and `job_input` ask by the shell source's own default; read-only tools are allowed. `acceptEdits`: base rules allow `write`, `edit` and `multi_edit`. `bypassPermissions`: no base rules, and every ask that remains is approved; denies still win. `plan`: no base rules, and a `:permission-policy` denies `write`, `edit`, `multi_edit`, `bash` and `job_input` with `+plan-mode-feedback+`; a policy only tightens, so no allow rule can lift it. The default mode is `default`. | ai-agent-protocol's model: base rules are the lowest layer, a policy only tightens, approvals are restarts. File tools are confined to the working directory by agent-tools, so `acceptEdits` cannot write outside it. |
| **Headless approval** | A handler on `agent-approval-required` around the run calls `invoke-deny` with `+headless-denial-feedback+` (or `invoke-approve` in `bypassPermissions`). The model gets ai-agent-protocol's rejection text with that feedback as an error result, and the run goes on. Every refused call is listed in the result's `permission_denials`. | Nobody can answer an approval in `-p`; the model learns what to do instead, and the caller learns which flag to pass. |
| **Tools** | `make-code-tools`: an agent-tools `file-tools` (ignore `:auto`) then a `shell-tools` (`:needs-approval t`, `:env` = the merged settings `env`), both rooted at the working directory, offered in `+file-tool-names+` then `+shell-tool-names+` order minus hidden tools. The shell tools are closed when the run ends. | The H2 tool set as it stands. |
| **Environment** | The effective lookup for a name is the merged settings `env` (an unset key gives NIL) and then `getenv` (`run-cli :getenv`, default `uiop:getenv`). Provider factories read API keys and base URLs through it. Shell commands get the merged `env` on top of the parent environment, so an unset key is removed there too. The process environment is never modified. | `setenv` mid-process is unreliable (Linux ignores it for some readers), and tests need a private environment. |
| **Project root** | The nearest directory, from the working directory upward, holding a `.git` entry (directory or file, so worktrees count). None → no project root. | git is where projects begin; no git binary needed. |
| **Instruction discovery** | At startup: the user-level file in `<user-config-dir>`, then one file per directory from the **project root** (or, without one, the **filesystem root**) **down to** the working directory. In each directory the first of `+instruction-file-names+` (`AGENTS.md`, then `CLAUDE.md`) that is a regular file counts, so `CLAUDE.md` is only a fallback. Empty or blank files are skipped. Each file's text is capped at `+max-instruction-chars+` (32 000) characters, followed by `[truncated: <path> is over 32000 characters]`. Below the working directory, discovery is lazy: settings extra `:instructions-discovery` is a steer `instruction-discovery` rooted at the working directory with the same names and `:include-root nil`, so a file the tools touch in `sub/` injects `sub/AGENTS.md`. | Codex's root-first walk, pi's and Claude Code's walk past the project when there is none, opencode's `CLAUDE.md` fallback. Repos that keep both (a `CLAUDE.md` that imports `AGENTS.md`) get `AGENTS.md` once. |
| **System prompt** | Sections joined by one blank line, in this order: (1) `(steer-protocol:build-system-prompt :tools <offered names> :model <backend>)`; (2) the environment section (below); (3) each instruction file in discovery order as `<instructions path="<native namestring of its truename>">` LF text (trailing whitespace trimmed) LF `</instructions>`; (4) the merged `appendSystemPrompt`. It is the agent's `:instructions`. | The stack's base prompt and tool guidance; the most specific instructions come last, then the caller's text. |
| **Environment section** | `# Environment`, then `- Working directory: <native namestring>`, `- Project root: <native namestring or "none">` (directory namestrings keep their trailing separator), `- Platform: <darwin \| linux \| windows \| other>`, `- Permission mode: <mode name>`, one per line. No date or time. | Deterministic prompts, and a stable prompt-cache prefix. |
| **Max turns** | `maxTurns` (default `+default-max-turns+`, 50) is the agent's `:max-steps`, with settings extra `:max-steps-wrap-up nil`. Reaching it finishes `:max-steps`: result subtype `error_max_turns`, error message `reached max turns (N)`, exit 1. | An exact budget for scripts: N model calls, no extra wrap-up call. |
| **Output: text** | Success: the final text, trailing newlines trimmed, then one LF, on `output`. A failed run: nothing on `output`, `cl-stack-code: <message>` on `error-output`. | `$(cl-stack-code -p …)` gets just the answer. |
| **Output: json** | One line on `output`: the `result` object (below), on success and on a failed run alike. | One parse for scripts. |
| **Output: stream-json** | One JSON object per line on `output`: `system` init first, then `text_delta` / `assistant` / `tool_use` / `tool_result` events as the run goes, then `result` last. Nothing else is written to `output`. | Claude Code's and Codex's JSONL streams, one shared vocabulary for H3d's RPC notifications. |
| **Before the run** | Usage and configuration errors (bad flags, no prompt, no `-p`, a missing `--cwd`, a bad rule, a bad settings file, an unknown provider) write `cl-stack-code: <message>` to `error-output` and exit 2, whatever the output format. | Nothing has run, so there is no result to report. |
| **Session id** | 32 lowercase hex characters, random per run, the same in every event. Not persisted in H3a. | H3c makes it a revision-store id. |
| **Exit codes** | 0 success; 1 the run failed (`error_during_execution`) or hit max turns (`error_max_turns`); 2 usage or configuration error; 130 interrupted (SIGINT cancels the run with `cancel-agent-run`). `condition-exit-code` maps a condition to its code. | cli-protocol's 0 / 1 / 2, plus the shell convention for SIGINT. |
| **Trust** | Project settings are trusted as written, as Claude Code's `-p` does. | Project trust is H3e. |
| **Stubs** | `%not-implemented` (internal, `src/package.lisp`). The implementation removes it and every call. The package, the conditions, the `settings` and `invocation` classes with `make-settings` and their readers, `condition-exit-code`, and the constants are given. | — |

---

## Surface

```lisp
;; entry
(run-cli argv &key (output *standard-output*) (error-output *error-output*)
                   (input *standard-input*) providers user-config-dir
                   (getenv #'uiop:getenv))      ; → exit code, never quits
(main)                                          ; uiop:quit with RUN-CLI's code
+version+                                       ; "0.1.0"

;; arguments
(parse-arguments argv)   ; → INVOCATION; bad argv → CODE-USAGE-ERROR (PERMISSION-RULE-ERROR for a bad rule)
invocation  invocation-print-p  invocation-prompt (string or NIL = read input)
invocation-output-format (:text :json :stream-json)  invocation-cwd (string or NIL)
invocation-help-p  invocation-version-p
invocation-settings      ; the flag layer, a SETTINGS

;; settings
settings  make-settings (&key model max-turns permission-mode allow ask deny env
                              append-system-prompt files)
settings-model  settings-max-turns  settings-permission-mode   ; :default :accept-edits
                                                               ; :bypass-permissions :plan
settings-allow  settings-ask  settings-deny    ; lists of AI-AGENT-PROTOCOL:PERMISSION-RULE
settings-env                                   ; alist (name . value-or-NIL), first set first
settings-append-system-prompt  settings-files  ; files read, in order
(parse-settings json-string &key file)         ; → SETTINGS; SETTINGS-ERROR
(read-settings-file pathname)                  ; → SETTINGS, or NIL when missing; SETTINGS-ERROR
(merge-settings &rest layers)                  ; NIL layers skipped → SETTINGS
(user-config-directory &key (getenv #'uiop:getenv))  ; → directory pathname
(settings-file-paths cwd &key user-config-dir) ; → (user project local) pathnames
(load-settings cwd &key user-config-dir cli)   ; user, project, local, CLI merged
(permission-mode-name keyword)                 ; :accept-edits → "acceptEdits"
(parse-permission-mode string)                 ; "acceptEdits" → :accept-edits, unknown → NIL
+permission-mode-names+                        ; ("default" "acceptEdits" "bypassPermissions" "plan")
+default-max-turns+                            ; 50

;; permissions
(parse-permission-rule designator effect)      ; string or json object → PERMISSION-RULE
(split-rule-list string)                       ; flag value → rule strings
(settings-permission-rules settings)           ; base, allows, asks, denies
(settings-permission-policy settings)          ; plan's deny rules, or NIL
(hidden-tool-names settings names)             ; NAMES a resource-* deny matches, in order
+headless-denial-feedback+  +plan-mode-feedback+

;; project and prompt
(find-project-root directory)                  ; → truename directory or NIL
(instruction-files cwd &key user-config-dir)   ; → truenames, prompt order
(assemble-system-prompt cwd &key tools backend settings user-config-dir)
                                               ; → (values prompt instruction-files)
+instruction-file-names+                       ; ("AGENTS.md" "CLAUDE.md")
+max-instruction-chars+                        ; 32000

;; models and tools
(resolve-model designator &key providers (env (constantly nil)))
                                               ; → (values backend provider-name model)
(default-providers)                            ; → (("anthropic" . fn) ("openai" . fn))
+default-model+                                ; "anthropic"
(make-code-tools cwd &key settings)            ; → (file-tools shell-tools)

;; conditions
code-error (error)                 code-error-message
code-usage-error (code-error)                                   ; exit 2
permission-rule-error (code-usage-error)  permission-rule-error-text
settings-error (code-error)        settings-error-file  settings-error-key
                                   ; restarts CONTINUE (skip the file → NIL), USE-VALUE
model-not-found (code-error)       model-not-found-designator   ; restart USE-VALUE (a backend)
run-failed (code-error)            run-failed-cause             ; exit 1
(condition-exit-code condition)    ; 2 for usage / settings / model, 1 otherwise
```

---

## Command line

```
cl-stack-code -p [options] [prompt …]
```

| Option | Value | Layer key |
|--------|-------|-----------|
| `-p`, `--print` | flag; required in H3a | — |
| `--output-format` | `text` (default), `json`, `stream-json`; anything else → usage error naming the three | — |
| `--model` | provider ref | `model` |
| `--max-turns` | integer ≥ 1; `0`, a negative number or a non-integer → usage error | `maxTurns` |
| `--cwd` | directory; relative to the process's directory; missing or not a directory → usage error | — |
| `--allowed-tools`, `--disallowed-tools` | rule lists, repeatable | `permissions.allow` / `permissions.deny` |
| `--permission-mode` | one of `+permission-mode-names+`; anything else → usage error | `permissionMode` |
| `--append-system-prompt` | text | `appendSystemPrompt` |
| `--help` | prints `stack-cli:format-usage` to `output`, exit 0 | — |
| `--version` | prints `cl-stack-code 0.1.0` LF, exit 0 | — |

An unknown option is a usage error. `--help` and `--version` work without `-p` and a prompt.

---

## Output events

Every object carries `"type"` and `"session_id"`. `step` is the 1-based generate step. Keys are snake_case.

| `type` | Other keys | When |
|--------|-----------|------|
| `system` | `subtype` `"init"`, `version`, `cwd` and `project_root` (directory namestrings, `project_root` `null` without one), `model` (the designator as given), `permission_mode` (mode name), `tools` (offered names, in order), `instructions` (instruction file namestrings, in prompt order) | first line |
| `text_delta` | `step`, `text` | each streamed text part; a step's deltas concatenate to its `assistant` text |
| `assistant` | `step`, `text` (`""` when the step only called tools), `finish_reason` (`"stop"` `"tool_use"` `"length"` `"content_filter"`), `usage` (this step) | each response, after its deltas |
| `tool_use` | `step`, `id`, `name`, `input` (the arguments decoded as a JSON object, or the raw string when they are not one) | once per invocation, after its step's `assistant` |
| `tool_result` | `step`, `id`, `name`, `status` (`"done"` `"error"` `"denied"`), `is_error`, `content` (the text the model gets) | once per invocation, after every `tool_use` of its step; tools of one step may finish in any order |
| `result` | `subtype` (`"success"` `"error_max_turns"` `"error_during_execution"`), `is_error`, `result` (the final text, `""` when none), `error` (message or `null`), `num_turns`, `duration_ms` (integer), `usage`, `permission_denials` (`[{id, name, input, reason}]`, `reason` `"denied"` for a rule or policy, `"headless"` for a refused ask) | last line; the whole output in `json` mode |

`usage` is `{"input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens"}`, integers, summed over the steps for `result`; a missing count is 0.

---

## Conditions and restarts

| Condition | Parent | When | Restarts | Exit |
|-----------|--------|------|----------|------|
| `code-usage-error` | `code-error` | bad flags, no `-p`, no prompt, a bad `--cwd` | — | 2 |
| `permission-rule-error` | `code-usage-error` | a rule string or object does not parse | — | 2 |
| `settings-error` | `code-error` | a settings file is not JSON, not an object, or has a wrong type (key path in `settings-error-key`, NIL for the first two) | `continue` (skip the file: `read-settings-file` returns NIL), `use-value` (a `settings` to use instead) | 2 |
| `model-not-found` | `code-error` | no provider by that name | `use-value` (an `llm-backend`; `resolve-model` returns it) | 2 |
| `run-failed` | `code-error` | the agent run signalled (a generate error the loop gave up on, an `agent-error`); `run-failed-cause` holds it | — | 1 |

Restarts are established around the signal inside the function, so a `handler-bind` around `read-settings-file`, `load-settings` or `resolve-model` sees them. `run-cli` handles every `error`: it prints `cl-stack-code: <message>` to `error-output` (plus the `result` event for a run that started, in the JSON formats) and returns `condition-exit-code`. A `settings-error` inside a rule list carries the rule's text and the key path.

---

## Windows

The same flags, files and outputs. `~/.config/cl-stack-code/` resolves under `user-homedir-pathname`. cli-protocol also accepts `-Model x` and `/Model:x`. The shell tools run `cmd.exe /d /s /c` over pipes, as agent-tools 0.2.0 does; contract tests that run a shell command use `pick` (POSIX / cmd syntax). The Windows console's UTF-8 output is the caller's to configure.

---

## Out of scope (H3a)

- The interactive TUI, approval dialogs, saved "always" replies (H3b).
- Sessions, `--continue` / `--resume`, `/tree`, `/fork`, `/clone`, export (H3c).
- RPC mode, `--input-format stream-json` (H3d).
- The SDK, skills, prompt templates, `--system-prompt` and system-prompt files, project trust (H3e).
- MCP servers, hooks, subagents, a cost table, retries beyond llm-protocol's `*retry-policy*`.
- `@file` imports inside `AGENTS.md` / `CLAUDE.md`.
- Sandboxing (`compute-backend-*`).

---

## Contract (tests)

`cl-stack-code/tests`, Rove. Every end-to-end test runs `run-cli` against a **scripted mock LLM backend** in `tests/mock-llm.lisp` (complete code, not a stub): a `scripted-backend` (an `llm-backend`) that answers each `generate` / `stream-generate` with the next step of a script, streams text in word-sized `llm-text-part` deltas through `:on-part`, reports fixed usage per step, records every request (turns, offered tool names) and the model its factory received, and fails loudly when the script runs out. It is offered to `run-cli` as provider `mock`. llm-protocol's `mock-llm-backend` echoes or calls one handler; the contract needed scripted multi-step runs with streaming, usage and request capture, and test code belongs in tests. Each test uses a fresh temporary project (a `.git/` directory unless the test says otherwise) and a private user config directory; no network, no real `~/.config`.

**99 tests (132 cases with the parametrized rows), about 370 `ok` forms.** On the stubs every case fails except `version-constant`, `condition-exit-codes` and `permission-feedback-constants`, which check given code (129 of 132 fail, every failure a `%not-implemented` error). No throwaway prototype was run for this contract; the implementation may find test bugs, which go through a contract-fix commit as in H2c.

| File | Covers |
|------|--------|
| `support` | temp project and config directories, `make-tree`, `code` (one `run-cli` call → exit, stdout, stderr, backend), JSON-lines decoding, `jget`, `pick`, `real-failure` |
| `mock-llm` | the scripted backend and its `mock` provider factory |
| `args-test` | `-p` / `--print`, prompt words, `-`, every option and its layer key, rule splitting, bad values, unknown options, `--help`, `--version` |
| `settings-test` | parse every key, `null` env values, missing / bad / non-object files, wrong types with key paths (parametrized), `continue` and `use-value`, scalar / list / env merge rules, config-directory precedence, file paths with and without a project root, three files plus the flag layer |
| `permissions-test` | the rule syntax table (parametrized), errors, object form with feedback, mode base rules, deny > ask > allow across layers, plan policy, hidden tools |
| `instructions-test` | project root (`.git` directory, `.git` file, none), discovery order, `CLAUDE.md` fallback and precedence, blank files, truncation, system prompt section order and exact environment section |
| `providers-test` | built-in anthropic and openai backends from the env lookup, a provider ref with and without a model, `:providers` overriding, `model-not-found` and `use-value` |
| `cli-test` | text output and stderr, stdin prompt, exit 2 cases (no `-p`, no prompt, bad `--cwd`, bad settings, unknown provider), the model reaching the factory from flags and settings, the system prompt the model sees, max turns, a failing backend |
| `json-test` | `json` result fields (success, max turns, failure), `stream-json` order, deltas, tool events, ids, usage sums, one session id |
| `tools-test` | offered tools, a read result reaching the model, root confinement, headless denial of write and bash, `acceptEdits`, `--allowed-tools`, settings rules, deny beating allow across layers, `bypassPermissions`, `plan`, hidden tools, settings `env` in a shell command, lazy `AGENTS.md` |

---

## Roadmap (H3b–H3e)

| Slice | Scope | Builds on |
|-------|-------|-----------|
| **H3b** interactive | Running without `-p`: full-screen TUI on `tui-backend-tty` with `tui-protocol/widgets` and `tui-markdown` — scrolling transcript with streamed markdown, multi-line input with history and `@` file mentions, status line, approval dialog (once / always / deny / deny all → `invoke-approve-always`, `invoke-deny-all`), "always" replies saved to `settings.local.json` through a `permission-rule-store`, `/model`, `/clear`, `/help`, Ctrl-C cancels the turn | H1, H3a |
| **H3c** sessions | Sessions as a `revision-protocol` store: one revision per turn, `--continue`, `--resume <id>`, `/tree`, `/fork`, `/clone`, export; `session_id` becomes the store's id; steering vs follow-up queue on `agent-run-post` | R0, H3a |
| **H3d** RPC | `--mode rpc`: JSON-RPC 2.0 over stdio (`rpc-protocol-json` + `rpc-backend-stdio`) — prompt, steer, follow-up, abort, approve, deny; the stream-json events as notifications; `--input-format stream-json` for `-p` | H3a, H3c |
| **H3e** SDK and configuration | A Lisp SDK (start a session, send prompts, receive events as CLOS objects, answer approvals); skills (`SKILL.md` via `steer-protocol`), prompt templates (`.cl-stack-code/prompts/*.md` as `/name`), `--system-prompt` and system-prompt files, `@file` imports, project trust (project allow rules and `env` wait for the user's yes) | H3a–H3d |

After H3: the image layer (H4), plan → project → approve (H5), extensions and a single binary (H6).

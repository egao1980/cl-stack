# cl-stack-code (H3a, H3b): the coding agent's headless and interactive shell

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H3 ("Product shell: interactive / `-p` / JSON stream / RPC / SDK; settings layering (user, project, local); … `AGENTS.md` discovery"). The repo was decided there (Decision 1).
**Status:** milestone **H3a** shipped as cl-stack-code **0.1.0** ([`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), `cl-stack-code/tests`, Rove; implemented through **team-solve**). Milestone **H3b locked** (the interactive mode, version target **0.2.0**): [H3b — locked](#h3b--locked). Later slices: [Roadmap](#roadmap-h3bh3e).

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

## H3b — locked

Contract: branch `agent/h3b-contract-b7d4` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.2.0**. It holds the stubs, which call `%not-implemented`, and the Rove tests in `cl-stack-code/tests` that define them. The file headers in `src/interactive.lisp`, `src/transcript.lisp`, `src/mentions.lisp`, `src/rule-store.lisp` and `src/program.lisp` give the exact rules. This section summarizes them. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

Running `cl-stack-code` without `-p` starts an interactive session on the terminal. The screen has a scrolling transcript with streamed markdown, compact tool calls and diffs for edits, a multi-line input with history and `@path` completion, slash commands, approval dialogs, Esc to interrupt, a queue for follow-ups, and a status line. The session uses the same settings, rules, tools, `AGENTS.md` and system prompt as `-p`.

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Shape** | Three layers. (1) A **pure core**: `(interactive-update state event) → (values state effects)`. Events and effects are plain lists. The core does no I/O and never calls the agent. (2) **Pure views**: `transcript-lines`, `status-line-text`, `tool-call-summary`, `approval-message`, `tool-call-preview`. (3) The **program** (`code-program`, a tui-protocol program). It turns keys and agent callbacks into events and carries out the effects in order. | Most of the behaviour is tested without a terminal or an agent. The program layer only glues. |
| **Dependencies** | Adds `tui-protocol` ≥ 0.2.0 with `tui-protocol/widgets`, `tui-markdown` ≥ 0.2.0, `tui-backend-tty` ≥ 0.1.1, `diff-protocol` ≥ 0.3.0 and `bordeaux-threads`. The tests add `tui-backend-terminal` 0.1.0, `terminal-protocol` and `terminal-backend-lisp` 0.2.0, `pty-protocol` 0.1.0 and `pty-backend-native` 0.2.1. | All are H1 parts that are already published. No third-party TUI library. |
| **State** | `interactive-state` is given (not a stub). `interactive-update` changes it in place and returns it, as tui widgets do. Readers: `state-transcript` (entries), `state-busy-p`, `state-queue`, `state-approvals`, `state-model`, `state-permission-mode`, `state-cwd`, `state-rules`, `state-usage`, `state-quit-p`. | Same idiom as `tui-protocol/widgets`. A copy per key press buys nothing. |
| **Entries** | An `entry` struct (given) of kind `:user`, `:assistant`, `:tool`, `:notice` or `:error`. A tool entry has the invocation's id, name, input, status, result and error-p. Streamed text is added to the last entry when that entry is `:assistant`; otherwise it starts a new one. | One list renders the whole transcript. |
| **Events → effects** | Events: `:submit`, `:interrupt`, `:quit`, `:part`, `:usage`, `:invocation`, `:turn-end` (`:reason` `:stop` / `:max-steps` / `:canceled` / `:failed` / `:approval`, with `:pending` and `:message`), `:reply`, `:model-set`, `:notice`, `:error`. Effects: `:run`, `:cancel`, `:approve`, `:deny`, `:resume`, `:restore-input`, `:new-conversation`, `:set-model`, `:set-permission-mode`, `:quit`. | Each effect maps to one ai-agent-protocol call or one widget change. |
| **Approvals** | The dialog answers map onto ai-agent-protocol 0.12.0: **once** → `approve-invocation`, **always** → `approve-invocation :always t`, **reject** → `deny-invocation :feedback text`, **reject all** → `deny-invocation :all t`. `(:resume)` follows every answer, and the program resumes only when the run has no `:proposed` invocation left. No handler answers `agent-approval-required`, so an ask pauses the run (`:approval`) and the dialog takes over. The exception is `bypassPermissions`, which approves every ask, as in `-p`. | This uses the protocol's pause/resume. Nothing blocks the event loop while the user decides. An "always" can approve the other pending calls too, so the core reads `state-approvals` back through the invocations' statuses. |
| **Saved "always"** | The agent's `permission-rule-store` is a `settings-rule-store` on `<project-dir>/.cl-stack-code/settings.local.json`. Saving appends `format-permission-rule` (the inverse of `parse-permission-rule`, which falls back to the `{"tool","resource"}` object form) to `permissions.allow` and keeps every other key. A bad file signals `settings-error` and writes nothing. | This was the H3a roadmap's promise. The next start, or a `-p` run, reads the rule as an ordinary settings rule. |
| **Dialog** | `w:confirm-dialog` with `+approval-choices+` (Allow once / Always allow / Reject / Reject all). Reject asks for feedback (an empty answer is allowed). The title is "Permission", or "Permission (I of N)". The message is `approval-message`: the summary, plus up to 12 lines of the edit's diff preview. Esc in the dialog is `:interrupt`, which rejects every pending call, and the run goes on. | Codex and Claude Code offer the same four answers. The preview shows the edit before the user decides. |
| **Diff preview** | `tool-call-preview root name input` computes the diff that `edit` / `multi_edit` / `write` would make. It produces the same text that agent-tools puts in its edit result (`--- a/REL`, `+++ b/REL`, then `diff:render-diff` of the text engine with context 3). It never signals. `tool-result-diff` pulls the diff back out of an edit result. | A test checks that the preview equals the diff the tool reports after the edit. |
| **Transcript** | `transcript-lines entries width &key streaming`. Blocks are separated by one empty line. User text is `> ` + wrapped text. Assistant text is `md:render-markdown`, or a live `markdown-stream` for the last entry while streaming. A tool entry is `● summary`, then the edit diff (`md:render-diff-lines` at W−2, indented by 2) or `  ⎿ first line` plus `    … +N lines`. A notice is shown as is. An error is `error: …`. | Codex's and Claude Code's compact tool rows, and tui-markdown as H1c planned. |
| **Turn control** | Esc, or Ctrl-C while busy, sends `:interrupt`, which runs `cancel-agent-run`. A message submitted while a turn runs goes to the queue. When the turn ends normally, the first queued message becomes the next turn (`continue-ai-agent-async`, history kept). When a turn is canceled or fails, the queue goes back into the input (`:restore-input`, joined by LF). | This is the "follow-up" queue. Steering (`agent-run-post` mid-turn) is H3c's. Returning the queue to the input on Esc matches Claude Code. Nothing is sent that the user stopped. |
| **Commands** | `/help`, `/clear` (new conversation, usage zeroed), `/model [MODEL]` (the program resolves the model with the same providers; success sends `:model-set`, failure sends `:error`; the history is kept), `/permissions [MODE]` (shows the mode and the settings rules, or switches the mode from the next turn on), `/exit`. While a turn runs, only `/help` and `/exit` work. The others add an error entry. | The pi / Claude Code minimum. Prompt templates as `/name` are H3e. |
| **@ mentions** | `project-files` lists every entry under the working directory: root-relative, sorted, directories ending in `/`, `.gitignore` / `.ignore` applied, `.git` skipped. The program reads it at start and after every turn. `mention-candidates` ranks entries in three groups: path prefix, then segment prefix, then substring (case-insensitive), with at most 20 candidates. `expand-mentions` appends `<file path="REL">…</file>` blocks for the regular files mentioned under the root. Each file is capped at 32 000 characters. | The model sees the file without needing a tool call. The transcript shows what the user typed. |
| **Input** | `w:text-input` with prompt `> `, placeholder `Message, @file, /help`, history kept in memory, completion `mention-candidates` with 5 menu rows. The external editor (Ctrl-G) is ignored in H3b. | Persistent history goes with sessions (H3c). |
| **Status line** | Left: ` <model> · <mode> · <cwd>`, with the home directory shown as `~`. Right: `<in> in · <out> out ` (summed tokens). Drawn inverse on the last row. | Model, directory, mode and usage at a glance. The widget's layout rules cut a long path from the left side. |
| **Layout** | From the bottom: the status line; then the dialog or the input (at most 8 rows); then a `─` rule; then, while busy, the queued messages and a spinner (`Working… (Esc to interrupt)`); the transcript viewport fills the rest and follows the tail. PgUp, PgDn and the mouse wheel scroll it. | The bottom rows are fixed, so the snapshot tests can check them exactly. |
| **Threads** | Agent work never runs on the UI thread. Agent events come back as messages sent with `tui-send`, so only `tui-update` touches the state and the widgets. | The tui-markdown stream and the widgets are not thread-safe. |
| **Entry and terminal** | `make-code-program invocation &key providers user-config-dir getenv` signals the same configuration errors as `-p`, before the terminal is touched. `close-code-program` is idempotent. `run-cli` without `-p` runs the program on a `tty-backend` when `input` / `output` are the process's own standard streams and `tty-available-p` is true. Otherwise it signals a `code-usage-error` that names the terminal and `-p` (exit 2). Quitting returns 0. A prompt given as arguments is the first message. `--output-format` without `-p` is a usage error. tui-backend-tty restores the terminal on `:quit`, on a condition, and on exit. | Tests drive `run-cli` with string streams, so the "not a terminal" path is deterministic and a test run can never grab the developer's terminal. |
| **Keys** | Enter sends the message. Alt/Shift+Enter or Ctrl+J inserts a newline. Up/Down browse the history. Tab completes. Esc interrupts. Ctrl-C interrupts while busy, clears the input when there is text, and quits on an empty input. Ctrl-D on an empty input quits. In the dialog: Up/Down, 1–4, Enter, and Esc to reject all. | See below. |
| **Stubs** | `%not-implemented` is back in `src/package.lisp`. The entry struct, the state class and its readers, `make-interactive-state`, `make-settings-rule-store`, `+help-text+`, `+approval-choices+` and `+max-mention-chars+` are given. `run-cli`'s dispatch is left as in 0.1, so the H3a tests keep passing on the stubs. | — |

### Surface (new in 0.2.0)

```lisp
;; core
(make-interactive-state &key model permission-mode cwd rules)  → interactive-state
(interactive-update state event)            → (values state effects)
(state-approvals state)                     ; pending, unanswered, still :proposed
(status-line-text state)                    → (values left right)
+help-text+  +approval-choices+

;; transcript
entry  make-entry (&key kind text id name input status result error-p)
entry-kind entry-text entry-id entry-name entry-input entry-status entry-result entry-error-p
(transcript-lines entries width &key streaming)   → lines of runs
(tool-call-summary name input)              → string
(tool-result-diff result)                   → unified diff text or NIL
(tool-call-preview root name input)         → unified diff text or NIL
(approval-message root invocation)          → string

;; mentions
(project-files root &key (limit 10000))     → ("README.md" "src/" "src/a.lisp" …)
(mention-candidates files token &key (limit 20))  → ("@src/a.lisp" …)
(expand-mentions text root)                 → (values prompt attached-rels)
+max-mention-chars+                         ; 32000

;; saved rules
(format-permission-rule rule)               → "edit(src/a.lisp)" | {"tool","resource"}
settings-rule-store  (make-settings-rule-store file)  settings-rule-store-file
;; + methods on ai-agent-protocol:save-permission-rule / list-permission-rules

;; program
code-program  (make-code-program invocation &key providers user-config-dir getenv)
(close-code-program program)
code-program-state  code-program-input  code-program-dialog
```

### Key bindings

| Where | Key | Action |
|-------|-----|--------|
| input | Enter | send the message; queued while a turn runs |
| input | Alt+Enter, Shift+Enter, Ctrl+J, or `\` before Enter | newline |
| input | Up / Down (first / last row) | history |
| input | `@…`, Tab, Up/Down, Enter | file completion |
| anywhere | Esc | interrupt the turn (closes the completion menu first) |
| anywhere | Ctrl-C | busy: interrupt; text in the input: clear it; empty: quit |
| anywhere | Ctrl-D | empty input: quit |
| transcript | PgUp / PgDn, mouse wheel | scroll; at the bottom it follows again |
| dialog | 1–4, Up/Down + Enter | once / always / reject (asks for feedback) / reject all |
| dialog | Esc | reject all pending; the run goes on |

### Conditions

No new conditions. `make-code-program` signals H3a's `code-usage-error`, `settings-error` and `model-not-found`, and `run-cli` maps them to exit 2. Running without a terminal is a `code-usage-error`. A bad local settings file during an "always" reply signals `settings-error` from `save-permission-rule`; the program shows it as an error entry. A failed turn becomes `(:turn-end :reason :failed :message …)` and an error entry, and the session goes on. tui-backend-tty's `tty-not-a-terminal` / `tty-system-error` are caught by `run-cli` (exit 2 / 1) after the terminal is restored.

### Contract tests

`cl-stack-code/tests` grows by 7 files (one of them helpers): **82 new deftests (106 cases with the parametrized rows)**. The 99 H3a tests (132 cases) stay; their version checks now expect 0.2.0. Every LLM interaction goes through the scripted mock backend. It gains one step kind, `(:gate GATE STEP)`, which holds a generate until the test opens the gate, so interrupts and queued follow-ups are deterministic.

| File | Covers |
|------|--------|
| `interactive-support` | events → effects helpers, `proposed` invocations, `with-code-tui` (a `code-program` on `tui-backend-terminal`'s headless driver with the pure-Lisp emulator), screen and row waits |
| `core-test` | submit / blank / queue, streamed parts, usage sums, invocation entries, interrupt, cancel and failure returning the queue, max turns, approvals and every reply, reject-all, Esc in approvals, quit and `/exit`, `/help`, `/clear`, `/model`, `/permissions`, unknown commands, status line text (home as `~`) |
| `transcript-test` | tool summaries (16 parametrized rows), result diffs, previews equal to agent-tools' own edit diff, write / multi_edit / replace_all previews, NIL cases, approval messages with the 12-line cut, exact transcript lines for every entry kind, markdown and live streams, tool bodies, header truncation, edit diffs, entry separation |
| `mentions-test` | project file listing with ignore files and limits, candidate ranking and limits, file blocks, duplicates, text left alone (emails, directories, outside the root, binary, missing), truncation |
| `rule-store-test` | `format-permission-rule` round trips (10 parametrized rows) and the object form, file creation, keeping the other keys, no duplicates, ask rules, bad files signalling `settings-error` and writing nothing, the next start reading the rules |
| `program-test` | first-screen layout (exact bottom rows), resize, a full turn with markdown and usage, tool rows, initial prompt, `AGENTS.md`, scrolling, approve once / always (rule saved and honoured) / reject with feedback / reject all / the second of two / Esc, deny rules and bypass with no dialog, Esc interrupt, queued follow-ups (layout and order), queue restored on interrupt, `@` completion and attachment, the file list refreshed, history, multi-line input, `/help`, `/clear`, `/model` (failure, then success with the history kept), `/permissions`, `/exit`, Ctrl-D / Ctrl-C quitting and clearing, Ctrl-C interrupt, configuration errors |
| `interactive-cli-test` | no terminal → exit 2 naming the terminal and `-p`, `--output-format` without `-p`, configuration errors first, and the **pty smoke test**: a child SBCL running `run-cli` on a `pty-protocol` pty, with its screen read back through the emulator. It checks the first frame, the status line, one mock turn, quitting with Ctrl-C (exit 0) and `stty -g` restored. Unix only; on Windows it calls `skip`, as tui-backend-tty's crash test does. |

On the stubs every H3b case fails, and every H3a case passes. No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, as in H3a and H2c.

### Non-goals (H3b)

- Sessions: `/tree`, `/fork`, `/clone`, `--continue` / `--resume`, persistent input history, and steering mid-turn with `agent-run-post` (H3c).
- RPC mode and `--input-format stream-json` (H3d). The SDK, prompt templates as `/name`, skills, and project trust (H3e).
- Running the external editor. Ctrl-G emits `edit-event`, and H3b ignores it.
- Showing rules saved by "always" in `/permissions` during the same session (they show from the next start), rule editing in the UI, and a cost table.
- Syntax highlighting of code blocks (tui-markdown's hook stays empty), images, mouse selection and copy, themes.
- `SIGTSTP` / Ctrl-Z suspend (tui-backend-tty leaves it out).

---

## Roadmap (H3b–H3e)

| Slice | Scope | Builds on |
|-------|-------|-----------|
| **H3b** interactive | Locked: [H3b — locked](#h3b--locked) | H1, H3a |
| **H3c** sessions | Sessions as a `revision-protocol` store: one revision per turn, `--continue`, `--resume <id>`, `/tree`, `/fork`, `/clone`, export; `session_id` becomes the store's id; steering vs follow-up queue on `agent-run-post` | R0, H3a |
| **H3d** RPC | `--mode rpc`: JSON-RPC 2.0 over stdio (`rpc-protocol-json` + `rpc-backend-stdio`) — prompt, steer, follow-up, abort, approve, deny; the stream-json events as notifications; `--input-format stream-json` for `-p` | H3a, H3c |
| **H3e** SDK and configuration | A Lisp SDK (start a session, send prompts, receive events as CLOS objects, answer approvals); skills (`SKILL.md` via `steer-protocol`), prompt templates (`.cl-stack-code/prompts/*.md` as `/name`), `--system-prompt` and system-prompt files, `@file` imports, project trust (project allow rules and `env` wait for the user's yes) | H3a–H3d |

After H3: the image layer (H4), plan → project → approve (H5), extensions and a single binary (H6).

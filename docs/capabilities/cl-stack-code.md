# cl-stack-code (H3a–H3c, H5a, H5b): the coding agent's headless and interactive shell, its sessions, plan mode, and checkpoints

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H3 ("Product shell: interactive / `-p` / JSON stream / RPC / SDK; settings layering (user, project, local); … `AGENTS.md` discovery"). The repo was decided there (Decision 1).
**Status:** milestone **H3a** shipped as cl-stack-code **0.1.0** ([`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), `cl-stack-code/tests`, Rove; implemented through **team-solve**). Milestone **H3b** (the interactive mode) shipped as **0.2.0**: [H3b — locked](#h3b--locked). Milestone **H3c** (sessions and steering) shipped as **0.3.0**: [H3c — locked](#h3c--locked). Milestone **H5a** (plan → project → approve over files) shipped as **0.4.0** (0.4.1: the shell runs in the area): [H5a — locked](#h5a--locked). Milestone **H5b locked** (checkpoints and rewind, with V3: git and jj as composite parts; version target **0.5.0**): [H5b — locked](#h5b--locked). Later slices: [Roadmap](#roadmap-h3bh3e).

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
| **Permission modes** | `default`: base rules ask for `write`, `edit` and `multi_edit` (`("write" "*" :ask)` …); `bash` and `job_input` ask by the shell source's own default; read-only tools are allowed. `acceptEdits`: base rules allow `write`, `edit` and `multi_edit`. `bypassPermissions`: no base rules, and every ask that remains is approved; denies still win. `plan`: no base rules, and a `:permission-policy` denies `write`, `edit`, `multi_edit`, `bash` and `job_input` with `+plan-mode-feedback+`; a policy only tightens, so no allow rule can lift it (**superseded in 0.4.0**: plan mode runs in a plan area, see [H5a — locked](#h5a--locked)). The default mode is `default`. | ai-agent-protocol's model: base rules are the lowest layer, a policy only tightens, approvals are restarts. File tools are confined to the working directory by agent-tools, so `acceptEdits` cannot write outside it. |
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

- Sessions: `/tree`, `/fork`, `/clone`, `--continue` / `--resume`, persistent input history, and steering mid-turn with `agent-run-post` (H3c, [locked](#h3c--locked)).
- RPC mode and `--input-format stream-json` (H3d). The SDK, prompt templates as `/name`, skills, and project trust (H3e).
- Running the external editor. Ctrl-G emits `edit-event`, and H3b ignores it.
- Showing rules saved by "always" in `/permissions` during the same session (they show from the next start), rule editing in the UI, and a cost table.
- Syntax highlighting of code blocks (tui-markdown's hook stays empty), images, mouse selection and copy, themes.
- `SIGTSTP` / Ctrl-Z suspend (tui-backend-tty leaves it out).

---

## H3c — locked

Contract: branch `agent/h3c-contract-5904` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.3.0**. It holds the stubs, which call `%not-implemented`, and the Rove tests in `cl-stack-code/tests` that define them. The file headers in `src/sessions.lisp`, `src/session-views.lisp`, `src/interactive.lisp` ("H3c"), `src/headless.lisp` and `src/program.lisp` ("H3c") give the exact rules. This section summarizes them. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

Every conversation, headless or interactive, is a session: a `revision-protocol` store with one revision per turn and a `head` ref. `--continue`, `--resume ID` and `--session-id ID` pick it; `--fork-session` resumes into a copy. The interactive mode adds `/tree`, `/fork`, `/rewind`, `/clone`, `/export` and `/session`, plus steering: a message sent into the running turn instead of queued after it.

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Store** | `session-store`: a subclass of `revision-protocol`'s `in-memory-store`, written through to one directory per session. Every write (`commit-revision`, `move-ref`, `tag-revision`, `delete-ref` as `:around` methods) takes the session's lock file, reads what other processes wrote since, runs the in-memory method and writes the new files. Rejected: **conversation-backend-sql on SQLite**, because it stores flat turn lists keyed by session (no DAG, no refs, no CAS) and would bring `sql-query-sqlite3` and a native library into a CLI that has none; **a new general file backend** (`revision-backend-file`), because policy would make it a first-party repo with its own contract, and one product needs it. The store is product-internal, and the graph, CAS, walks and restarts are the in-memory store's own, so the R0a law suite already covers them. | A session is small, append-mostly data that one or two processes touch. Files plus the in-memory store's semantics keep every revision-protocol query working with no new dependency. |
| **Layout** | `<data-dir>/sessions/<project-key>/<id>/`, holding `session.sexp` (id, project directory, `cloned-from`, version), `revisions/<rev>.sexp` (one immutable file per revision: id, parents, recorded time as unix seconds + nanoseconds, message, provenance, content), `refs/<name>` (`<rev id>` LF, tags `tag <rev id>` LF + annotation), and `lock` (`<pid> <universal-time>` LF while a write runs). `<project-key>/last` names the session that committed last. Every file is written to a temporary name and renamed. It is read with `*read-eval*` NIL and keywords only, and an unreadable file signals `session-error` naming it. | Readers never see half a file. Revision files never change, so concurrent readers need no lock. sexp keeps the store dependency-free and diffable. |
| **Data directory** | `user-data-directory`: `$CL_STACK_CODE_DATA_DIR`, else `$XDG_DATA_HOME/cl-stack-code/`, else (Windows) `%LOCALAPPDATA%\cl-stack-code\`, else `~/.local/share/cl-stack-code/`. Empty or relative values are ignored. `run-cli` and `make-code-program` take `:data-dir`, and the tests always pass a temporary one. | XDG on Unix and the Windows convention. Config stays under `~/.config` as in H3a. Sessions are data, not configuration. |
| **Project key** | The project directory (project root, else working directory), as a native namestring without the trailing separator, with every character other than an ASCII letter or digit replaced by `-` (`/Users/me/proj` → `-Users-me-proj`). | Claude Code's scheme, readable on disk. `session.sexp` records the real path. |
| **Ids** | Session ids are 32 lowercase hex characters (H3a's format). `--session-id` and `--resume` also accept a UUID, which is normalized. `--resume` and `open-session` take a unique prefix of at least 4 characters. Revision ids are the in-memory store's 40 hex characters, and clones keep them. | H3a's `session_id` becomes the store's id unchanged. |
| **Turn record** | A revision's content is a `turn-record` plist: `prompt` (as typed), `turns` (the `llm:turn-state`s the turn added, never `:system`), `replace` (TURNS is the whole conversation, for a run that rewrote its history), `finish` (`:stop :max-steps :canceled :failed`), `model`, `permission-mode`, `usage`, `steering` (texts as typed), `version`. The message is the prompt's first line, cut to 72 characters. The provenance is `(:kind :turn)`. The conversation at a revision is the fold of the records on its first-parent line. | Deltas keep a long session linear on disk. Storing turn states keeps provider parts (tool calls, thinking signatures) exact. The system prompt is rebuilt by every process, so edited `AGENTS.md` files apply on resume. |
| **What a resume restores** | The conversation and the model (`--model` > the head record's model > settings > default). Rules, mode, env and max turns come from the current settings and flags. | A stored `bypassPermissions` must not come back silently, and a project file's new deny rule must apply. |
| **Laziness** | `create-session` writes nothing. A session's directory appears with its first write, so starting and quitting leaves no session. | No empty sessions in `--list-sessions`. |
| **Concurrency** | Each store remembers its **base**: the head it read or last wrote. `commit-turn`, `move-session-head`, `rewind-session` and `fork-turn` move `head` by compare-and-swap from it, under the lock, against the state on disk. A lost race signals **`session-conflict`** (expected, actual) and writes nothing. `commit-turn` offers the restart **`fork-session`**, which saves the turn as a new session cloned at the expected head. The lock waits `*session-lock-timeout*` (5 s) and then signals `session-locked`. A lock file older than 30 s is stale and is broken. | revision-protocol's `move-ref` CAS made cross-process: the lock makes the CAS atomic across processes, and the base gives it the right expected value. No turn is lost and no history is interleaved. |
| **Conflict policy** | Headless and interactive both take `fork-session`. `-p` writes `cl-stack-code: session OLD changed in another process; this turn was saved as session NEW` to stderr, the `result` carries NEW and the exit code is the run's. The TUI switches to NEW with a notice. | A clear error that keeps the work. Two terminals on one session diverge instead of corrupting each other. |
| **Headless** | Before the run: `check-session-flags`, then the session (`--continue` → `last`; `--resume`; else new, with `--session-id` or random; `--fork-session` → `clone-session` at the head). The run gets `session-turns` + the prompt. Once it has started, the turn is committed **before** the result is written, whatever its outcome (failed, max turns and interrupted runs too). Every event's `session_id` is the store's id. **The JSON shapes are unchanged.** `--list-sessions` prints `session-summary-lines` and exits 0. | Claude Code's `-c` / `-r` / `--session-id` / `--fork-session`. `$(cl-stack-code -p …)` scripts keep working. |
| **Flags** | `-c/--continue`, `-r/--resume ID`, `--session-id ID`, `--fork-session`, `--list-sessions`. Usage errors (exit 2): `--continue` with `--resume`; `--fork-session` alone; `--session-id` with resume and no fork; a bad id; `--list-sessions` with any session flag; an existing `--session-id`. A missing session is `session-not-found` (exit 2). | Each combination either means one thing or is refused. |
| **Interactive start** | `make-code-program` resolves the session as `-p` does, and signals before the terminal is touched. A resumed session starts with `session-entries` as the transcript, its prompts as the input history (the persistent history H3b deferred), and its id. | One resolution path for both modes. |
| **Interactive turns** | Each terminal turn end (not `:approval`) commits the turn on the agent thread before the `:turn-end` reaches the UI. A commit error shows as an error entry, and those turns go into the next commit. | Disk state is current whenever the UI goes idle, which the tests rely on. |
| **Commands** | `/session` (id), `/tree` (`session-tree-lines` as a notice), `/fork [AT]` (head → AT's parent, AT's prompt back into the input; AT is a turn number on the current line or an id prefix from `/tree`; default the last turn), `/rewind [N]` (head N turns back, default 1; the turns stay in `/tree`), `/clone` (continue in a copy of the current line), `/export FILE` (markdown, or JSON for `.json`), `/steer MESSAGE`. `/clear` now also starts a new session. While busy, `/session`, `/tree` and `/steer` work. The others give H3b's "not available while a turn runs" error. | pi's tree commands. `/fork` re-asks (pi), `/rewind` just goes back (Claude Code's conversation rewind; files are H5). |
| **Tree** | Depth first in insertion order. `●` marks the head's line, `○` other branches, and `  (head)` the head. A straight line does not indent. Branch points draw `├─ ` / `└─ ` with `│  ` continuations. Long messages are cut to the width with `…`. | A 50-turn linear session stays 50 flat rows, and only real branches indent. |
| **Export** | Markdown: `# Session <id>`, `## Turn N`, `**User**` / `**Assistant**` blocks, `**Tool** \`name\` args` (+ ` (error)`) with the result in a fence longer than any backtick run in it, `_notice_`. JSON: `session_id`, `project`, `head`, `turns[]` with revision, parent, prompt, model, permission_mode, finish, usage, steering and messages (typed parts). | Readable and lossless enough to re-import later. |
| **Steering vs follow-up** | **Enter** while a turn runs queues a **follow-up** (H3b, unchanged). **Ctrl-T** (or `/steer`) sends **steering**: `agent-run-post` on the agent thread, which ai-agent-protocol injects before the run's next generate. A post that arrives while the model's final answer streams makes the loop take one more step. The run's `:inbox` event becomes `(:steered TEXTS)` and adds the user entry where the model took it. A post that comes too late (the run had finished) stays pending and becomes the **first** queued follow-up. Esc or a failure returns pending steering, then the queue, to the input, and empties the run's inbox. Rows while busy: `steering: …` above `queued: …` above the spinner. Idle, Ctrl-T is Enter. | **No ai-agent-protocol change is needed.** `agent-run-post` and the `:inbox` event exist since 0.5, and 0.13.0 (#29) makes continue-after-cancel clean. Enter stays the follow-up key because H3b locked it, and Alt/Shift+Enter is already newline. Ctrl+Enter is not distinguishable on legacy terminals. Ctrl-T is a distinct control byte that is unbound in `w:text-input` and reaches the program in raw mode (ISIG off, so no SIGINFO on macOS). Headless steering is H3d's RPC `steer`. |
| **Dependencies** | Adds `revision-protocol` ≥ 0.3.0 and `datetime-protocol` ≥ 0.1.3. `ai-agent-protocol` ≥ **0.13.0** (fresh turn after cancel, #29), so the H3b `%reopen-run` workaround can go. | All published. |
| **Stubs** | `%not-implemented` is back in `src/package.lisp`. Given (not stubs): the conditions, `turn-record` and its constructor, the `session-store` class and its readers, the constants and `*session-lock-timeout*`, the new `invocation` slots and their parsing, the core's new state slots, the `:data-dir` keywords and `+help-text+`. Stubbed: every new function, the four write-through `:around` methods, the core's `%session-command` / `%session-event`, and the program's new effects. `run-cli`'s headless path is as in 0.2, so the H3a and H3b tests keep passing on the stubs. | — |

### Surface (new in 0.3.0)

```lisp
;; where
(user-data-directory &key getenv (platform :posix|:windows))   → directory
(sessions-directory cwd &key data-dir)    → <data-dir>/sessions/<key>/
(project-session-key directory)           → "-Users-me-proj"
(normalize-session-id string)             → 32 hex | NIL

;; records
turn-record  (make-turn-record &key prompt turns replace-p finish model permission-mode usage steering version)
record-prompt record-turns record-replace-p record-finish record-model record-permission-mode
record-usage record-steering record-version
(record-content record) (content-record plist) (revision-record revision)

;; store
session-store (rev:in-memory-store)  session-id session-directory session-project-dir
                                     session-cloned-from session-base
+head-ref+ "head"  +session-format+ 1  *session-lock-timeout* 5  +stale-lock-seconds+ 30
(create-session dir &key id project-dir)  (open-session dir designator)  (sync-session store)
(list-sessions dir)  (last-session dir)
(session-head store)  (session-line store &optional d)  (session-records store &optional d)
(session-turns store &optional d)
(commit-turn store record &key expected id)        → (values revision store)
(resolve-turn store at)  (move-session-head store d &key expected)
(rewind-session store n)  (fork-turn store at) → (values head prompt)
(clone-session store &key id at sessions-dir)

;; views
(session-entries store &optional d)  (session-tree-lines store &key width)
(session-summary-lines dir)  (export-session store stream &key format designator)

;; command line
invocation-continue-p invocation-resume invocation-session-id invocation-fork-session-p
invocation-list-sessions-p  (check-session-flags invocation)
(run-cli … &key data-dir)  (make-code-program … &key data-dir)

;; core
state-steering  state-session-id  (make-interactive-state … &key session-id)
;; events (:steer T) (:steered TS) (:session ID) (:session-reset :entries E :input T :notice M)
;; effects (:steer T) (:tree) (:fork AT) (:rewind N) (:clone) (:export FILE)
```

### Conditions

```
code-error
└── session-error (session)                          exit 1
    ├── session-not-found (designator)               exit 2 (it comes from the flags)
    ├── session-conflict (expected actual)           commit-turn: restart fork-session (&optional id); abort
    ├── session-locked (file)
    └── session-turn-not-found (designator)          /fork AT, /rewind N
```

`ref-conflict` from raw `revision-protocol` calls on a `session-store` keeps its own restarts (`use-current`, `retry`). They run with the lock held, against the synced state.

### Key bindings (added)

| Where | Key | Action |
|-------|-----|--------|
| input, busy | Ctrl-T | steer: send the input into the running turn |
| input, idle | Ctrl-T | send (as Enter) |
| input, busy | Enter | queue a follow-up (H3b) |

### Contract tests

`cl-stack-code/tests` grows by 6 files (one of them helpers): **76 new deftests (103 cases with the parametrized rows), about 470 `ok` forms.** The 181 H3a + H3b deftests (238 cases) stay. Their version checks now expect 0.3.0, and their helpers pass a private `:data-dir`. Every LLM interaction goes through the scripted mock backend. Every file test uses a temporary data or sessions directory. Two store objects on one directory stand in for two processes, and the headless and TUI conflict tests use a second thread and a gated mock step.

| File | Covers |
|------|--------|
| `session-support` | temp sessions directories, records with tool calls, commits, turn summaries, fixed clocks |
| `session-store-test` | data-directory precedence (9 parametrized rows), project keys, id forms (9 rows), the record plist, lazy creation, commit and reopen (recorded times kept), files on disk (immutable revisions, `refs/head`, `last`, lock released), replace records, messages and caller ids, prefixes and ambiguity, listing order under fixed clocks, summary lines, existing ids, unreadable files, cross-store `session-conflict` (slots, nothing written), `fork-session` and abort, explicit `:expected`, lock timeout, stale lock, CAS linearizable for 2 stores × 15 threaded commits with `retry`, raw ref and tag writes persisting, `sync-session`, clones (line only, same ids, at a turn, empty), rewinds, `resolve-turn`, `fork-turn`, `move-session-head` CAS |
| `session-view-test` | entries (tool results, errors, steering, injected instructions skipped, interrupted), exact tree lines (branches, marks following the head, width cut, two roots, empty), exact markdown (fence lengthening, errors, notices), JSON fields |
| `session-cli-test` | flag parsing, flag combinations (6 rows), a run is a session in the data directory, resume carries the conversation, prefix and UUID, `--continue`, not-found exit 2, `--session-id`, `--fork-session` (with `--session-id`, with `-c`), the session's model vs `--model`, failed and max-turn runs saved, stream-json ids, `--list-sessions`, a concurrent commit forking the turn |
| `session-core-test` | `/session`, every command's effect, usage errors (5 rows), busy rules, `:steer` busy and idle, `:steered` placement, untaken steering becoming the next turn, cancel and failure restoring steering then the queue, `:session-reset`, help text |
| `session-program-test` | each turn saved, resume (transcript, history, history sent), `--continue` and resume errors before the terminal, the **`/tree` screen snapshot**, `/rewind`, `/fork` with the prompt back, `/clone`, `/export` (md and json), `/clear` as a new session, Ctrl-T steering reaching the same turn (no extra request, transcript order, record), Ctrl-T idle, steering and follow-up rows and order, Esc restoring steering, a concurrent commit forking the session |

On the stubs, 101 of the 103 H3c cases fail, and every error is a `%not-implemented` one. The two that pass, `session-cli-parses-session-flags` and `core-help-mentions-sessions-and-steering`, check given code. All 238 H3a and H3b cases pass. No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, as in H3a and H3b.

### Non-goals (H3c)

- Restoring files with a rewind, checkpoints as composite revisions (H5).
- Steering from `-p`, `--input-format stream-json`, RPC `steer` / `follow_up` (H3d).
- An interactive session picker (`/resume`, `--resume` without an id), session names and titles, deleting or pruning sessions, GC.
- Compaction (cl-stack-code does not enable it; `replace` records are read but not written).
- A project-wide input history across sessions, and hosted sharing.
- Cross-machine sessions. The lock assumes one filesystem with atomic rename and exclusive create, so not NFS.

---

## H5a — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, H5 ("Plan → project → approve: edits … as plans; approvals show `state-diff`; tests run against projections …"), on R4a alone ("R4a alone is enough for H5") and V1. H5a is its first slice: **files only**.

Contract: branch `agent/h5a-contract-4f0a` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.4.0**. It holds the stubs, which call `%not-implemented`, and the Rove tests in `cl-stack-code/tests` that define them. The file headers of `src/plans.lisp`, `src/headless.lisp` ("H5a"), `src/interactive.lisp` ("H5a"), `src/program.lisp` ("H5a"), `src/transcript.lisp` (`:plan` entries), `src/instructions.lisp` (`%plan-environment-sections`) and `src/arguments.lisp` (`check-plan-flags`) give the exact rules. This section summarizes them. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

`--permission-mode plan` stops being read-only. The agent's edits and shell commands run in a **plan area**, a copy of the project. At the end of the turn the product shows the **projected change** as a unified diff. The user **approves** it (it is applied to the real working copy), **rejects** it (the area is discarded), or **continues** (more turns in the same area). The agent's shell runs the project's tests inside the area before anything is approved. If the working copy changed meanwhile, approval detects the overlap and offers restarts: rebase, overwrite, or abort.

```
cl-stack-code -p --permission-mode plan "fix the failing test"   # bash runs in the area (0.4.1)
cl-stack-code -p --resume 3f9a --apply                    # apply it later
cl-stack-code -p --permission-mode plan --apply --on-drift rebase "…"
```

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Where the code lives** | All of H5a is in cl-stack-code (`src/plans.lisp` plus hooks in the headless path, the core, the program, the transcript and the prompt). **No stack change is needed.** agent-tools already roots its file and shell tools at any `:root` (they get `plan-tool-root`). pathlib R4a and revision-backend-git V1 are used through their public API. | The smallest change. A plan is product policy that combines two published backends. |
| **Dependencies** | Adds `revision-backend-git` ≥ **0.4.0** (git ≥ 2.56 at run time, only for `:git` plans). `cl-stack-pathlib` stays ≥ 0.6.0 (R4a areas and snapshots shipped in 0.5.0). The tests add `revision-backend-git` and `cl-stack-pathlib`. | All are published. |
| **Two kinds behind one value** | A `plan` is `:copy` or `:git`. **`:copy`**: R4a. `fs-open-area :copy :ignore :auto` copies the project into `<plan dir>/tree/`, and the pathlib area object is closed `:keep` at once. The base is `fs-snapshot` of the fresh copy, stored in the project's directory snapshot store `<plans dir>/store/`. **`:git`**: V1. The base is a commit of the working copy's state: `project-state` of the `git-working-copy`, with uncommitted and untracked files and without ignored ones, then `commit-projection` (parent HEAD, ref `refs/cl-stack-code/plans/<id>`). The area is `add-worktree` of that commit (detached) at `<plan dir>/tree/`, so `git status` and `git diff` work in the area. **`:auto`** (the default) picks `:git` when the project directory is a worktree top level that `make-git-store` opens, and `:copy` otherwise. `--plan-area auto\|git\|copy` overrides it. | This follows the plan's R4 consumer rule: "an area over a git working copy clones the working copy (uncommitted changes included) and commits back through that backend's `commit-projection`". The copy kind works everywhere else. |
| **Why not `fs-area-changes` / the in-memory area** | A plan has to outlive the process (`--resume`, the later `--apply`) and must be re-based on drift. pathlib's `area` object can do neither: it has no reopen and no rebase. So the truth is on disk, as R4 says ("snapshots are content-addressed blobs … the truth"). Changes are `snapshot-changes` between the base and a fresh `:auto` snapshot of the area. R4a's law makes that equal to `fs-area-changes`. | No pathlib change. An `fs-reopen-area` that keeps the mtime shortcut is an optimization for later (roadmap), not a dependency. |
| **Layout** | `<data-dir>/plans/<project-key>/<id>/` holds `plan.sexp` (`:format 1 :id :kind :project-dir :root :base :status :session :opened-at :version`, written atomically and read with `*read-eval*` NIL) and `tree/` (the area). `<plans dir>/store/` is the copy kind's blob store. Ids use H3c's format: 32 lowercase hex characters. The data directory and the project key are H3c's, so the area is never inside the project. | Everything needed to reopen the plan, next to the sessions. |
| **Tools** | In plan mode the file tools and the shell tools are rooted at `plan-tool-root`, which is the area directory matching the working directory. `@` mentions read from the area. The base rules allow `write`, `edit` and `multi_edit`, as `acceptEdits` does, because the file tools cannot leave the area. **Since 0.4.1 they also allow `bash` and `job_input`** (`("bash" "*" :allow)`, `("job_input" "*" :allow)`), so the shell runs in the area without asking, in `-p --permission-mode plan` and in the interactive program alike. These are the lowest rules: a settings or flag `ask` rule still asks (and `-p` refuses it), and a `deny` rule still wins. **The shell is not confined.** It starts in the area, but a command can still read or write outside it (an absolute path, `cd ..`, the network) until R4d confines it. `settings-permission-policy` is NIL in every mode, so the H3a read-only policy is gone. | The user's decision (0.4.1): plan mode exists so the agent can edit and run the tests in a copy without interruptions, and a shell that asks every time defeats that. Changes the shell makes inside the area are part of the projected diff and still need approval. Writes outside the area are the known gap until R4d; deny rules cover the commands a user never wants run. 0.4.0 kept `bash` behind approval. |
| **System prompt** | `assemble-system-prompt :plan` makes the `# Environment` section point at the area (working directory, project root) and adds `- Plan: <id> (<kind>), a copy of <project dir>`. A section with `+plan-mode-feedback+` follows, which tells the model that it works in a copy and that nothing reaches the project until approval. The instruction files are still the working directory's own. | The model has to use the area's paths. Absolute paths into the real tree would be refused by the jail. |
| **The projected diff** | `plan-changes` returns `((kind path) …)`, sorted, with kinds `:added :removed :modified :mode-changed` and no rename detection. `plan-diff` is a diff-protocol **tree diff** (tree engine, `:detect-renames nil`, level `:changes`, `:context 3`) from the base's versions of the changed paths to the area's versions. Text means valid UTF-8 with no NUL in the first 8000 octets, else binary. A symlink is its target with mode 120000. `plan-diff-text` is `render-diff … :unified`. Both kinds give the same text. | The diff goes through diff-protocol, and one renderer serves both kinds. The tests compute the expected text with diff-protocol directly. |
| **Approve** | (1) Read the working copy now: a `:auto` snapshot for copy, `project-state` for git. (2) Path P conflicts when the working copy's entry at P differs from the base's **and** from the area's. Identical edits on both sides do not conflict, and drift at paths the plan did not touch is kept. (3) Conflicts signal `plan-drift` once, with every such path, before anything is written. (4) Apply each changed path with `fs-write-atomic :expected-hash`, using the hash read in step 1 (`:absent` for a new file). A file that changes after the check therefore signals pathlib's `content-hash-mismatch` instead of being lost. The execute bit follows the area, and directories emptied by removals are removed. (5) For git, `commit-projection` records the area's state as one commit whose parent is the base, and the plan ref moves to it by CAS. (6) The area is removed and the status becomes `:applied`. Returns `(values changes :applied)`, or `(values nil :empty)`. | Path-wise CAS writes never lose a concurrent edit. `(setf target-state)` was rejected: it rewrites the whole tree and deletes files created after the check. `execute-plan` was rejected as well: the base commit holds the user's uncommitted work, so moving HEAD would commit that work too. HEAD, the branch and the index stay as they are, and the change lands as uncommitted edits, as in Claude Code and Codex. |
| **Drift restarts** | **`rebase-plan`**: the working copy becomes the new base (a new snapshot, or a commit with the ref CAS-moved and the area's HEAD moved). The area becomes the three-way merge of the old base, the area and the working copy. A path changed on one side takes that side. A conflicting path that is text on all three sides gets `diff:merge-texts` with the labels `plan` / `working copy` (clean, or with markers). Any other conflict (binary, symlink, mode, modify/delete, add/add) keeps the area's version. Nothing is applied. It returns `(values conflicts :rebased)` and the plan stays open for review. **`overwrite-plan`**: apply, with the area winning at the conflicting paths. **`abort-approval`**: write nothing and keep the plan open. Unhandled, nothing is written. | A rebase never writes the real tree, so the user always approves a diff they have seen. The same Lisp merge serves both kinds, so the marker text is identical. |
| **Reject / continue** | `reject-plan` removes the area (for git, also `remove-worktree :force` and the ref) and sets the status to `:discarded`. To continue, keep the plan open and send another message, which runs in the same area. | — |
| **Sessions (H3c)** | `turn-record` gains `plan`, which holds `plan-record`: `(:id :kind :base :root :status)`. It is serialized as an optional `:plan` key, `+session-format+` stays 1, and old records read back with NIL. A resume in plan mode reopens the head record's plan while it is `:open` and its area exists. Otherwise a new plan opens, and stderr says `plan OLD is no longer open; opened plan NEW` if the old plan was lost. After `--apply`, the turn record carries the `:applied` status. | Resuming continues the same projection. An applied plan is never reopened. |
| **Headless** | Plan runs (the mode, or any plan flag) call `check-plan-flags` first, with exit 2 on a bad combination. **stream-json**: `{"type":"plan","subtype":"opened"\|"reopened",plan_id,kind,area,base}` after `system`, then `"projected"` (`changes`, `diff`) before `result`, then `"applied"`, `"rebased"` or `"drift"` with `--apply`. **result** gains `"plan"` (`id kind status area base changes diff conflicts`) **in plan runs only**, so the other shapes do not change. **text**: the answer, an empty line, the diff; stderr gets `plan ID: N file[s] changed, not applied (… --resume SESSION --apply …)`. **`--apply`** runs only after a `success` run, and `--on-drift abort\|rebase\|overwrite` picks the restart (default abort). Anything not applied exits 1. **Action only**: `--apply` or `--reject` with `--resume` / `--continue` and no prompt makes no run and no LLM call, does not read stdin, and commits no turn. Text mode prints the applied diff. | "Prints the projected diff, applies nothing unless `--apply`." The two-step flow (plan, review the diff, then `--apply`) works in scripts. |
| **Flags** | `--apply`, `--reject`, `--on-drift MODE`, `--plan-area KIND`. Usage errors (exit 2): `--apply` with `--reject`; `--reject` with a prompt or without a resume; `--on-drift` without `--apply`; `--apply` (with a prompt) or `--plan-area` outside plan mode; a bad value; `--plan-area git` outside a git worktree. A resumed session with no open plan is also an error (`session ID has no open plan`). | Each combination either means one thing or is refused, as in H3c. |
| **Interactive** | In plan mode the first `:run` opens (or reopens) the plan on the agent thread. The program swaps the agent's tools and instructions to the area, drops the run (the turn starts on `session-turns`), and sends `(:plan-opened …)`. After a `:stop` / `:max-steps` plan turn it sends `(:plan-projected …)`, which adds a `:plan` transcript entry (`● plan <id8>: N files changed` plus `md:render-diff-lines`). When the program is idle and there are changes, it opens the **plan dialog** "Plan <id8>" with `+plan-choices+` (Approve / Keep planning / Reject). Approve can lead to the **drift dialog** "Plan <id8>: the working copy changed" with `+drift-choices+` (Rebase onto the working copy / Overwrite / Cancel). Esc means Keep planning, or Cancel in the drift dialog. The commands are `/plan`, `/approve` and `/reject`. `/clear`, and `/permissions` with another mode, are refused while a plan is open. Once a plan is applied or discarded, the program gets the working directory's tools back, and the next message opens a new plan. | The approval-dialog idiom from H3b, through the same `:reply` events. Tool approvals still come first. |
| **Stubs** | `%not-implemented` is back in `src/package.lisp`. **Given:** the conditions, the `plan` class with its readers, the constants (`+plan-format+`, `+plan-ref-prefix+`, `+plan-kinds+`, `+plan-choices+`, `+drift-choices+`), the new invocation slots and their parsing, `record-plan` and its serialization, the core's `state-plan` / `state-plan-prompt`, plan mode's base rules and the NIL policy, the new `+plan-mode-feedback+` text, and the hooks in `%run-headless`, `%loop-start-turn`, `%turn-callback`, `%run-effect`, `%sync-widgets` and the result object. **Stubbed:** every function in `src/plans.lisp`, `check-plan-flags`, `%plan-environment-sections`, `%headless-plan`, `%headless-plan-finish`, `%run-plan-action`, `%plan-command`, `%plan-event`, `%plan-entry-lines`, `%ensure-plan`, `%plan-turn-end`, `%show-plan`, `%approve-plan-effect`, `%reject-plan-effect` and `%sync-plan-dialog`. Non-plan runs never reach a stub, so the H3a–H3c tests keep passing. | — |

### Surface (new in 0.4.0)

```lisp
;; plans
plan  plan-p  plan-id plan-kind plan-project-dir plan-root plan-base plan-status
      plan-session-id plan-directory plan-opened-at
+plan-format+ 1   +plan-ref-prefix+ "refs/cl-stack-code/plans/"   +plan-kinds+ (:auto :git :copy)
(plans-directory cwd &key data-dir)                         → <data>/plans/<key>/
(open-plan project-dir &key (kind :auto) data-dir session-id id)  → plan
(reopen-plan plans-dir id)  (list-plans plans-dir)
(plan-tool-root plan cwd)   (plan-changes plan) → ((kind path) …)
(plan-diff plan) → diff     (plan-diff-text plan) → string
(approve-plan plan &key message) → (values result :applied|:empty|:rebased|:aborted)
(reject-plan plan) → :discarded     (plan-record plan) → plist
;; restarts: rebase-plan  overwrite-plan  abort-approval

;; sessions, prompt, command line
record-plan   (make-turn-record … :plan P)
(assemble-system-prompt cwd … &key plan)
invocation-apply-p invocation-reject-p invocation-on-drift invocation-plan-area
(check-plan-flags invocation mode)

;; core
state-plan  state-plan-prompt  +plan-choices+  +drift-choices+
;; events (:plan-opened …) (:plan-projected …) (:plan-drift :paths P) (:plan-closed :status S …)
;; effects (:show-plan) (:approve-plan [:on-drift M]) (:reject-plan)
```

### Conditions and restarts

```
code-error
└── plan-error (plan)                          exit 1
    ├── plan-not-found (designator)            exit 2 (it comes from the flags)
    └── plan-drift (paths)                     approve-plan: rebase-plan, overwrite-plan, abort-approval
```

`content-hash-mismatch` (pathlib) escapes with its own restarts `overwrite` / `use-current` when a file changes between the drift check and its write. revision-backend-git's conditions (`ref-conflict` on the plan ref, `git-command-error`) propagate unchanged.

### Contract tests

`cl-stack-code/tests` grows by 5 files (one of them helpers): **76 new deftests (122 cases with the parametrized rows), about 385 `ok` forms.** Most of them are parametrized over **both kinds**: `:git` runs against a **real temporary git repository** (git on PATH, ≥ 2.56, with a local identity), and `:copy` runs in a project whose `.git/` is not a repository. Every LLM interaction goes through the scripted mock backend. Expected diffs come from diff-protocol directly, and git facts come from git run inside the test (`worktree list`, `status --porcelain`, `rev-list --parents`, `hash-object .git/index`).

| File | Covers |
|------|--------|
| `plan-support` | real git projects, `with-kind-project`, plans of a project, `expected-diff`, stream-json plan events, git queries |
| `plan-test` | kind selection, `:git` outside a worktree; opening (uncommitted and untracked work copied, ignored files left out, layout, ids); the copy base as a stored snapshot, the git base as a commit on the plan ref; the tool root; changes (all kinds, sorted, edits reverted, `/bin/sh` edits); diff text equal to diff-protocol's, binary files; approve (writes, removals, emptied directories, area gone, status, twice refused), empty, execute bit; drift elsewhere kept, identical edits; `plan-drift` (paths, restarts offered, nothing written, plan open); abort, overwrite, rebase (clean: merged, new base, re-approve; markers equal to `merge-texts`; binary keeps the area); reject; reopen, lost area, unreadable `plan.sexp`, listing; `plan-record`; git: the area as a linked worktree (HEAD = base, `git status` in it, main HEAD and index untouched), the approved commit (parent = base, message, uncommitted landing), reject cleanup |
| `plan-cli-test` | flag errors (7 rows) and `check-plan-flags`; `--plan-area git` outside a repo; text output (answer + diff + stderr), no changes; stream-json order and fields, json, other modes unchanged; the plan system prompt; tests run in the projection (`/bin/sh` sees the area), the shell runs without a rule (0.4.1; 0.4.0: it asked), a deny or ask rule still stops it, git in the area; `--apply`, `--apply` after a failed run; resume reopens (the edit is seen), resume after apply, lost plan notice; action-only apply / stream-json / reject / no open plan; drift on `--apply` × {abort, overwrite, rebase} × both kinds |
| `plan-core-test` | `:plan-opened` / `:plan-projected` (dialog, empty, busy), dialog replies (3 rows), Esc, drift and its replies (3 rows), `:plan-closed` notices (6 rows), commands with and without a plan and while busy, leaving plan mode refused, tool approvals first, help and choices |
| `plan-program-test` | a plan turn on screen (dialog, diff, entry, project untouched), approve, reject, keep planning then `/approve`, the drift dialog with overwrite, the turn record's plan |

Four H3a tests change meaning with plan mode. `tools-plan-mode` now expects the write to land in the area, and it fails on the stubs. `permission-mode-base-rules`, `permission-plan-policy` and `permission-feedback-constants` expect the new given code, and they pass. The version checks expect 0.4.0. On the stubs, every new case fails except `plan-core-help`, which checks given constants. All H3a–H3c cases pass except `tools-plan-mode` (measured: 341 passing, 122 failing = 121 new + `tools-plan-mode`; the failures are `%not-implemented` errors or assertions downstream of them). No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, as in H3a–H3c.

### Non-goals (H5a) and the H5 roadmap

| Slice | Scope | Builds on |
|-------|-------|-----------|
| **H5a** files | This section | R4a, V1, H3c |
| **H5b** checkpoints and rewind | Locked (0.5.0): [H5b — locked](#h5b--locked). `--apply commit` moved to a later slice | H5a, V3 |
| **H5c** shadow DB | Migrations as plans through `sql-migrate` on revision + diff (R2), with approval showing `state-diff`; tests against a shadow database | R2 |
| **H5d** image projections | The Lisp image spawned in the area with its ASDF registry pointing there; image checkpoints | H4 |
| **H5e** subagent areas | One plan area per subagent instead of a git worktree, merged back through `rebase-plan` | H5a, subagents |
| later | `fs-reopen-area` / journals (R4b) for cheap rescans; COW areas (R4c); confined shells (R4d); per-path `.lisp` merges through `diff-backend-lisp-source` (R3); jj working copies (V2) | R4b–R4d, R3, V2 |

Also out of scope in H5a: confinement of the shell (R4d; since 0.4.1 plan mode allows `bash` in the area unconfined), hunk-level partial approval, plans in RPC mode (H3d), two processes approving the same plan (no plan lock), GC of applied or discarded plan directories, and `.gitignore` changes inside a plan changing what the base compares (each side uses its own `:auto` rules).

---

## H5b — locked

**Plan rows:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, H5 ("checkpoints are composite revisions (conversation + files + db + image); rewind = transitions per part"), together with Track V, **V3** ("git/jj as composite-revision parts in agent checkpoints"), on R4a ("A checkpoint's `:files` part is a snapshot id"). The 2026-11-20 decisions put H5b first after H5a. H5b covers the conversation and files parts. The db and image parts are reserved for H5c and H5d.

Contract: branch `agent/h5b-contract-16ad` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.5.0**. It holds the stubs, which call `%not-implemented`, and the Rove tests in `cl-stack-code/tests` that define them. The file headers of `src/checkpoints.lisp`, `src/headless.lisp` ("H5b"), `src/interactive.lisp` ("H5b"), `src/program.lisp` ("H5b"), `src/session-views.lisp` (`:marked`), `src/settings.lisp` (the `checkpoints` object), `src/plans.lisp` (`approve-plan :checkpointer`, `plan-rewind`) and `src/arguments.lisp` (`check-rewind-flags`) give the exact rules. This section summarizes them. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

Every turn that changes the project's files records a **checkpoint**: a composite revision whose parts are the turn's session revision (H3c) and the files. The files part is a pathlib snapshot in a plain folder, a git commit on a private ref in a git repository, or the jj commit of `@` in a jj workspace. A **rewind** goes back to a turn per part: the conversation, the files, or both. A files rewind is an H5a plan, drift-checked as H5a approves, so uncommitted work the user did since the last checkpoint is detected, not overwritten.

```
cl-stack-code -p --resume 3f9a --list-checkpoints
cl-stack-code -p --resume 3f9a --rewind 2                       # conversation and files
cl-stack-code -p --resume 3f9a --rewind 0 --rewind-mode files --on-drift rebase
/checkpoints   /rewind   /rewind 2 files   /tree                  # interactive
```

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Where the code lives** | All of H5b is in cl-stack-code: `src/checkpoints.lisp`, plus hooks in the headless path, the core, the program, the tree view, settings, the command line and `approve-plan`. **V3 needs no backend change.** git uses V0/V1's `make-git-working-copy :stamp-ref`, `capture-revision` and `commit-revision`, plus `update-ref` through `run-git` as H5a does. jj uses V2's `working-copy-revision`, `make-revision-filesystem` and `state-diff`. pathlib uses R4a's snapshots. | The smallest change. A checkpoint is product policy over three published backends, as an H5a plan is. |
| **Dependencies** | Adds `revision-backend-jj` ≥ **0.3.1** (jj ≥ 0.47.1 at run time, only for `:jj` checkpoints). Raises `revision-backend-git` to ≥ **0.5.1**, `revision-protocol` to ≥ **0.4.0** and `cl-stack-pathlib` to ≥ **0.7.0**. The tests add `revision-backend-jj`. | **Locked dependencies:** git 0.5.0 and jj 0.3.0 do not load next to pathlib 0.7.0 (their read-only filesystems' `fs-write-atomic` methods lack `:mode`), fixed in [revision-backend-git#10](https://github.com/egao1980/revision-backend-git/issues/10) (0.5.1) and [revision-backend-jj#6](https://github.com/egao1980/revision-backend-jj/issues/6) (0.3.1). git 0.5.0 also uses `refs/…` names as given, which the private checkpoint refs rely on. The copy kind's sweep needs [cl-stack-pathlib#39](https://github.com/egao1980/cl-stack-pathlib/issues/39) (`snapshot-store-ids` / `snapshot-store-delete`) published before the implementation. |
| **A checkpoint** | A `commit-composite` revision in the session's **checkpoint store**. Manifest parts in this order: `:files` (always), then `:conversation` (the H3c turn revision, `depends-on (:files)`). The conversation part is absent for a checkpoint recorded before turn 1. `:db` and `:image` are reserved (`+checkpoint-roles+`) and never recorded in H5b. The provenance is `(:kind :checkpoint :reason R :turn N :ordinal K :files-kind K :version V)`, and the message is the turn's message, or `session start`. The product reads it as a `checkpoint` struct (id, ordinal, reason, turn, turn-id, files-kind, files-id, message, recorded-at, expired-p, revision). | This is the plan's composite revision. `rev:composite-manifest`, `part-store` and `part-depends-on` work on it as on any R0b composite. |
| **The checkpoint store** | `<session dir>/checkpoints/` follows H3c's file rules: `revisions/<id>.sexp`, `refs/checkpoints` (the tip), `refs/expired`, its own `lock`, and `store/` (the copy kind's blobs). It is an in-memory store written through, as `session-store` is. Checkpoints form **one chain in recording order**, whatever conversation branch they belong to. A record runs under the lock against the tip on disk, so two processes append and never conflict. On disk the content is `(:checkpoint 1 :parts ((:role :files :kind K :revision ID) (:role :conversation :kind :session :revision ID :depends-on (:files))))`. In memory it is a `rev:revision-manifest`. The conversation part's store is the session store. The files part's store is the open git or jj store, and NIL when the checkpoint was read back from disk or is a pathlib snapshot. | It sits beside the session it belongs to. Putting it in the session store itself was rejected, because the checkpoints would show in `/tree`, in `heads` and in id prefixes. A separate directory leaves every H3c file and test as it is. |
| **Kinds (V3)** | `:auto` (the default) picks `:jj`, else `:git`, else `:copy`. **`:jj`**: the project directory is a jj workspace root that `make-jj-store` opens. The files are the commit id of `@` right after jj's snapshot, through `working-copy-revision` and its `:commit-id`. Nothing else is written. jj keeps every snapshot of `@` as a hidden commit in its operation log, and a commit id names it forever. `@`, its change and bookmarks are never touched. **`:git`**: a worktree top level, by H5a's rule. The files are a commit of what `git add -A` records, with parents = HEAD and message `cl-stack-code checkpoint <session> <ordinal>`, on the private ref `refs/cl-stack-code/checkpoints/<session>/<ordinal>`. Files read at record time go through `capture-revision` on a working copy stamped by that ref. Files read earlier (the `:before` state) go through `commit-revision` of their tree, with the ref created by CAS. HEAD, the branch, the index and the files are never touched. **`:copy`**: `fs-snapshot :ignore :auto` into `store/`. `checkpoints.kind` overrides `:auto`. An explicit kind that does not fit signals `checkpoint-error` before the run. Each checkpoint records its own kind. | This is the plan's V3: git and jj as composite parts. jj `capture-revision` was rejected, because it turns `@` into a "capture" commit in the user's history. A visible jj commit through `commit-revision` was rejected too, because it adds a head to `jj log`. jj has no private refs, but its snapshots are already the checkpoints. |
| **Same files** | Two states are the same when their trees are equal. `:copy` compares snapshot ids, `:git` tree ids, and `:jj` uses an empty `state-diff :summary`. States of different kinds are never the same. | These are cheap comparisons, so nothing has to be committed to compare. |
| **When** | `begin-checkpoint-turn` reads the files (PRE) before the run. `end-checkpoint-turn` runs after the turn is committed, whatever its finish, and reads POST. If POST equals PRE or the tip's files, nothing is recorded. Otherwise a `:before` checkpoint (the turn's parent, with PRE) is recorded first when there is no tip or the tip's files differ from PRE. Then a `:turn` checkpoint (the turn, with POST). A turn forked into a new session records there. Headless and interactive work the same way. The interactive program records before the `:turn-end` reaches the UI. | "Each turn that changed files". The `:before` checkpoint gives turn 0 a state, and it also keeps the user's edits made between turns, which a later rewind compares against. |
| **The files at a turn** | `turn-checkpoint store at` takes AT as `0` or a `resolve-turn` designator. Let L be AT's first-parent line. The candidates are the checkpoints whose conversation revision is on L, plus those with no conversation part. The answer is the deepest one, and the most recent among equals. With no candidate, the answer is the session's first checkpoint when it descends from AT, since no earlier turn changed files. Otherwise NIL. | Branches (`/fork`) resolve on their own line. A turn that changed nothing maps to the last state before it. |
| **Rewind = transitions per part** | `rewind-to cp store at &key (parts '(:conversation :files))`. The parts run in the manifest's dependency order. **Files first**: TARGET = `turn-checkpoint AT`, and TIP = the newest checkpoint. A **rewind plan** is opened: an H5a `:copy` plan with base = TIP's files, area = TARGET's files (git and jj trees read through `make-revision-filesystem`), and `plan-rewind` = `(:session S :to ID :from ID)`. Then comes `approve-plan`. A path the rewind changes whose working-copy entry differs from both TIP's and TARGET's is **drift**. **Then the conversation**: the head moves to AT by CAS (H3c's `move-session-head`, deleted for `0`). The CAS base is checked before the files are touched (`session-conflict`). After files were applied or merged, a `:rewind` checkpoint records the result, with the new head as its conversation part. | The task's rule that a files rewind is a plan transition, drift-checked like H5a's approve. The H5a machinery (views, path-wise CAS writes, merges) is reused unchanged. revision-protocol's `restore-composite` was rejected: `execute-plan`'s drift policy is whole-tree (`capture-and-continue` / `discard-drift`), so it would clobber or capture the user's edits wholesale. |
| **Drift restarts** | H5a's restarts on `plan-drift`, whose plan is the rewind plan. **`overwrite-plan`**: TARGET wins at the drifted paths. **`rebase-plan`**: H5a's rebase (old base TIP, area TARGET, the working copy, `diff:merge-texts` with the labels `plan` / `working copy`), then the plan is approved again at once, so the merge is written. Status `:merged`, with the conflicts. **`abort-approval`**: nothing is written, the plan is discarded, status `:aborted`, and the conversation is not moved. Paths the rewind does not change are never touched. | These are the same restarts as H5a. A rebase in a rewind writes the merge, because the user asked for a restore. Paths only the user changed keep the user's version. |
| **Result** | `(:turn T :parts P :conversation :moved\|:unchanged\|:skipped :files :applied\|:merged\|:empty\|:aborted\|:skipped :changes CH :conflicts X :drift D :checkpoint K)`. `rewind-description` gives the phrase both modes print: `conversation`, `files (N files changed)`, `conversation and files (…)`, `files (no changes)`, `files (N files changed, merged with the working copy; conflicts in P)`, or `nothing restored`. | One result for the headless JSON and the interactive notice. |
| **Plan mode** | With an enabled checkpointer, `approve-plan plan :checkpointer cp` returns a third value: the files state read before anything was written (`:applied` only). `record-plan-checkpoints cp store pre turn` then records `:plan-before` and `:plan-after` with the plan's turn as the conversation part. Interactive mode passes the head. Headless `--apply` after a run approves before the turn is committed (as in H5a) and records after the commit, with the committed revision. `end-checkpoint-turn` then records nothing, because the files are the tip's. Action-only `--apply` passes the head. | "An approved plan creates a checkpoint before and after". The checkpoints belong to the turn that ran the plan, so rewinding to the turn before it undoes the plan. |
| **Retention** | `checkpoints.keep` (default **50**) per session. After every record, `gc-checkpoints` expires checkpoints older than the newest N. `refs/expired` moves forward and never back, so raising keep does not revive anything. Expiring deletes what the product owns. For git it deletes the private refs (`update-ref -d`), and git's gc prunes the objects later. For copy it deletes the blobs in `store/` that no retained snapshot uses, through `snapshot-store-ids` and `snapshot-store-delete` ([cl-stack-pathlib#39](https://github.com/egao1980/cl-stack-pathlib/issues/39), a locked dependency: it ships first, and the implementation raises the pathlib pin to that release). For jj it deletes nothing, because jj's operation log owns its commits. The composite revisions stay, marked `expired-p`. A files rewind that needs an expired checkpoint signals `checkpoint-expired`. | revision-protocol revisions are immutable, so expiring drops the parts, not the composite. A dropped part is the R0b case of a part whose store no longer has its revision. |
| **Settings** | `"checkpoints": {"enabled": true, "keep": 50, "kind": "auto"}`, merged per key across layers. Bad values signal `settings-error` with the key path (`checkpoints`, `checkpoints.enabled`, `.keep`, `.kind`). `checkpoint-settings` returns `(values enabled keep kind)`. With `enabled false` nothing is recorded automatically. Existing checkpoints can still be listed and rewound. | It is the project's choice, as permissions are. |
| **Headless** | `--list-checkpoints` (with `--resume` / `--continue`, with or without `-p`) prints `checkpoint-summary-lines`. `--rewind TURN` (`0`, a number or an id prefix) is action only: no run, no LLM call, no turn committed. `--rewind-mode both\|conversation\|files` (default both). `--on-drift abort\|rebase\|overwrite` (default abort) now also goes with `--rewind`. **text**: the written diff on stdout, and `cl-stack-code: session S rewound to turn T: <description>` on stderr. **stream-json**: `{"type":"rewind",…}` and then the result. **json**: the result only. The result gains `"rewind"` (turn, parts, conversation, files, changes, conflicts, drift, checkpoint) in rewind actions only. A drift abort exits 1 with `rewind to turn T: the working copy changed at P; nothing restored (use --on-drift rebase or --on-drift overwrite)`. No files state for the turn → `checkpoint-not-found` (exit 2). Every other output shape is unchanged: a turn's checkpoints add no events. | Scripts can list, then rewind, as H5a's plan-then-`--apply`. |
| **Flags** | Usage errors (exit 2): `--rewind-mode` without `--rewind`; `--rewind` / `--list-checkpoints` with `--fork-session`; `--rewind` with `--apply` / `--reject`; `--rewind` with a prompt or without a resume; a bad `--rewind` value; `--list-checkpoints` with `--rewind` or a prompt, or without a resume; `--rewind` without `-p`. `--on-drift` alone now says `--on-drift needs --apply or --rewind`. | Each combination either means one thing or is refused, as in H3c and H5a. |
| **Interactive** | `/checkpoints` (also while busy) lists the checkpoints. `/tree` marks turns that have a retained checkpoint with ` ◆` (`session-tree-lines :marked`). `/rewind [N]` stays H3c's when turn T's files equal the tip's. Otherwise it opens the **rewind dialog** "Rewind to turn T" ("Files to restore: …") with `+rewind-choices+`: Conversation and files / Conversation only / Files only / Cancel. `/rewind [N] PART` (`conversation`, `files`, `both`) rewinds at once. Drift opens "Rewind: the working copy changed" with H5a's `+drift-choices+`. A files rewind is refused while a plan is open. The notice reads `rewound to turn T: <description>`. | It follows Claude Code's rewind menu, with H3c's `/rewind N` (N turns back) kept. |
| **Stubs** | `%not-implemented` is back in `src/package.lisp`. **Given:** the conditions; the `checkpoint` and `files-state` structs; the `checkpoint-store` and `checkpointer` classes and readers; the constants; `checkpoints-directory`; the settings object, its parsing, merging and `checkpoint-settings`; the new invocation slots and their parsing; `plan-rewind` and its `plan.sexp` key; the session store's cache slot; the core's state slots, `+rewind-choices+`, the help text and the command/event routing; the routing in `run-cli`, `%run-headless` and `%run-effect`; `--rewind` without `-p`; and `check-plan-flags` accepting `--on-drift` with `--rewind`. **Stubbed:** every function in `src/checkpoints.lisp` (and the write-through methods), `check-rewind-flags`, `%run-rewind-action`, `%list-checkpoints`, `%rewind-command`, `%rewind-event`, `%checkpoints-effect`, `%rewind-parts-effect`, `session-tree-lines :marked`, and `approve-plan :checkpointer`. **Left to the implementation:** the per-turn hooks (headless around `%commit-headless-turn`, interactive on the agent thread), the `/tree` marks, H3c's `/rewind` turning into the dialog, the rewind dialogs in `%sync-widgets`, and the plan-approval checkpoints. Old paths never reach a stub, so the H3a–H5a tests keep passing. | — |

### Surface (new in 0.5.0)

```lisp
;; values and stores
checkpoint  checkpoint-p checkpoint-id checkpoint-ordinal checkpoint-reason checkpoint-turn
            checkpoint-turn-id checkpoint-files-kind checkpoint-files-id checkpoint-message
            checkpoint-recorded-at checkpoint-expired-p checkpoint-revision
files-state files-state-kind files-state-id
checkpoint-store (rev:in-memory-store)  checkpoint-store-p checkpoint-store-session
(checkpoint-store session) (checkpoints-directory session)
+checkpoint-format+ 1  +checkpoint-kinds+ (:auto :jj :git :copy)
+checkpoint-reasons+ (:before :turn :plan-before :plan-after :rewind)
+checkpoint-roles+ (:files :conversation :db :image)  +checkpoint-ref+ "checkpoints"
+expired-ref+ "expired"  +checkpoint-ref-prefix+ "refs/cl-stack-code/checkpoints/"
+default-checkpoint-keep+ 50  +rewind-parts+ (:conversation :files)

;; recording
(resolve-checkpoint-kind project-dir &key (kind :auto)) → :jj | :git | :copy
(make-checkpointer project-dir &key kind keep enabled data-dir)  (close-checkpointer cp)
checkpointer-p checkpointer-project-dir checkpointer-kind checkpointer-keep
checkpointer-enabled-p checkpointer-data-dir
(read-files-state cp store)  (record-checkpoint cp store reason &key turn files)
(begin-checkpoint-turn cp store) → pre   (end-checkpoint-turn cp store pre turn) → checkpoints
(approve-plan plan &key message checkpointer) → (values result status pre)
(record-plan-checkpoints cp store pre turn)   (gc-checkpoints cp store)

;; reading, rewinding, views
(session-checkpoints store &key all) (tip-checkpoint store) (find-checkpoint store designator)
(turn-checkpoint store at)  (rewind-to cp store at &key parts) → result plist
(rewind-description result) (checkpoint-summary-lines store &key width)
(session-tree-lines store &key width marked)  plan-rewind

;; settings and command line
settings-checkpoints (checkpoint-settings settings) → (values enabled keep kind)
invocation-rewind invocation-rewind-mode invocation-list-checkpoints-p (check-rewind-flags inv)

;; core
state-rewind state-rewind-prompt +rewind-choices+
;; events (:rewind-prompt :n :turn :paths) (:rewind-drift :paths) (:rewound …result)
;; effects (:checkpoints) (:rewind N :parts P [:on-drift M])
```

### Conditions and restarts

```
code-error
└── checkpoint-error (session)                    exit 1   (an explicit kind that does not fit, store files)
    ├── checkpoint-not-found (designator)         exit 2   no files state for the turn; find-checkpoint
    └── checkpoint-expired (checkpoint)           exit 1   the files were garbage-collected
plan-error
└── plan-drift (plan paths)                       rewind-to: rebase-plan, overwrite-plan, abort-approval (plan = the rewind plan)
session-conflict, session-turn-not-found          rewind-to's conversation part (H3c)
```

`content-hash-mismatch` (pathlib) still escapes with its own restarts when a file changes between the drift check and its write, as in H5a. Backend conditions (`git-command-error`, `jj-command-error`, `vc-tool-version-error`) propagate.

### Contract tests

`cl-stack-code/tests` grows by 5 files (one of them helpers): **64 new deftests (125 cases with the parametrized rows), about 470 `ok` forms.** The 470 H3a–H5a cases stay. Their version checks now expect 0.5.0. Every LLM interaction goes through the scripted mock backend. Most store-level tests run over the **three kinds**: plain folders (`:copy`), **real temporary git repositories** (`:git`, git ≥ 2.56) and **colocated temporary jj repositories** (`:jj`, jj ≥ 0.47.1). The jj rows are skipped with Rove's `skip`, and the body is not run, when jj is missing or older. Expected values come from the files on disk, from pathlib directly (`snapshot`, `snapshot-entries`, `snapshot-store-contains-p`), and from git and jj run inside the test (`show`, `cat-file`, `rev-list --parents`, `for-each-ref`, `hash-object .git/index`, `status --porcelain`; `jj file show`, `jj log -T change_id`, `jj bookmark list`). Merge texts come from `diff:merge-texts` and diffs from diff-protocol.

| File | Covers |
|------|--------|
| `checkpoint-support` | three kinds of temp project (jj skip rule), the checkpointer and sessions, `edit-turn` (begin → edits → commit → end), checkpoint files read independently per kind, private refs, blob ids, headless edit runs |
| `checkpoint-test` | kind selection (auto × 3, explicit, errors); unchanged turns; the first change (`:before` + `:turn`, ordinals, turns, messages, files) × 3 kinds; later turns and user edits between turns; copy ids = pathlib snapshot ids; git commits on private refs (parents = HEAD, message, untracked files, HEAD / branch / index / status untouched); jj `@` commits (same change, no bookmark); the composite revision (roles, depends-on, part stores, V3 git part resolving, provenance, chain, tip ref); persistence across stores (files on disk, no `last`, the reloaded manifest); the files-at-a-turn rule (start, quiet turns, branches, id prefixes); `find-checkpoint`; files rewinds × 3 kinds (content, removals, additions, the `:rewind` checkpoint, git back to clean); both parts and the follow-up turn; conversation only (`:unchanged`, turn 0); drift × {abort, overwrite, rebase} × {copy, git} (paths, restarts, nothing written first, the rewind plan, user work kept, merge text); a clean merge; errors (no checkpoint, unknown turn, bad parts, conversation CAS); retention × {copy, git} (expired flags, `refs/expired`, refs deleted, blobs swept, `checkpoint-expired`, raising keep); disabled; summary lines (format, cut, marks, labels × 5); `/tree` marks; plan approval × {copy, git} (`pre`, `record-plan-checkpoints`, undo by rewind, aborted approval) |
| `checkpoint-cli-test` | the settings object (parse, defaults, merge per key, 5 error rows); `-p` with settings (disabled, keep 1, kind copy in git, a bad explicit kind failing before the run); a run's checkpoints × {copy, git} with the stream unchanged; a failed turn's checkpoints; plan `--apply` after a run and action-only (their turn, undo); `--list-checkpoints`; flag errors (11 rows) and `check-rewind-flags`; `--rewind` text × {copy, git} (diff, stderr, no LLM call); modes (3 rows); stream-json / json shapes; drift × {default, abort, overwrite, rebase}; drift in stream-json; no checkpoint (exit 2), unknown turn, conversation-only fallback |
| `checkpoint-core-test` | `/checkpoints` (also busy); `/rewind` with parts (5 rows) and its state; usage errors (4 rows); busy and open-plan refusals; the rewind prompt; dialog replies (4 rows) and Esc; drift replies (3 rows) and Esc; approvals answered first; `:rewound` notices (6 rows); `rewind-description` (4 rows); help and choices |
| `checkpoint-program-test` | a turn's checkpoints recorded before idle and `/checkpoints` on screen; `/tree` marks; the rewind dialog → both, files only, cancel; `/rewind N PART` without a dialog; the drift dialog with overwrite; H3c's `/rewind` when the files did not change |

On the stubs, 109 of the 125 new cases fail, and every error is a `%not-implemented` one or an assertion downstream of one. The 16 that pass check given code: the settings object (6), three flag rows (`--rewind-mode` parsing, `--rewind` without `-p`, `--on-drift` alone), `approve-plan` without a checkpointer, `/checkpoints` and H3c's `/rewind` / `/rewind N` routing, approvals answered first, the help text, and H3c's `/rewind` when no files changed (which the implementation must keep). All 470 H3a–H5a cases pass (measured with jj 0.47.1 and git 2.56: 486 passing, 109 failing). No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, as in H3a–H5a.


### Non-goals (H5b)

- The db and image parts (H5c, H5d). `rewind-to` refuses them (`type-error`) until then.
- `--apply commit` (`execute-plan` onto the branch when the working copy is clean), from the H5a roadmap. It moves to a later H5 slice, because H5b's scope (2026-11-20) is checkpoints and rewind.
- Rewinding to a specific checkpoint id rather than a turn, rewinding with a prompt in the same `-p` call, rewinding in RPC mode (H3d), and hunk-level partial rewinds.
- Cloning checkpoints with `/clone` or `--fork-session`. A clone starts without checkpoints. `--rewind` with `--fork-session` is refused.
- Cross-process races beyond the lock: a sweep of `store/` while another process holds an unrecorded pre-turn snapshot of the same session.
- Tracked files that `.gitignore` also matches: rewinds compare the working copy with pathlib's `:auto` rules, as H5a's copy plans do.
- jj commits pruned from jj's operation log (`jj op abandon` plus `jj util gc`) read as expired.
- GC of rewind plan directories (as H5a's plan directories).

---

## Roadmap (H3b–H3e)

| Slice | Scope | Builds on |
|-------|-------|-----------|
| **H3b** interactive | Shipped (0.2.0): [H3b — locked](#h3b--locked) | H1, H3a |
| **H3c** sessions | Locked (0.3.0): [H3c — locked](#h3c--locked). Sessions as a file-backed `revision-protocol` store; `--continue` / `--resume` / `--session-id` / `--fork-session` / `--list-sessions`; `/tree` `/fork` `/rewind` `/clone` `/export`; steering (Ctrl-T) vs follow-up (Enter) on `agent-run-post` | R0, H3a, H3b |
| **H3d** RPC | `--mode rpc`: JSON-RPC 2.0 over stdio (`rpc-protocol-json` + `rpc-backend-stdio`) — prompt, steer (H3c's `agent-run-post` path), follow-up, abort, approve, deny, and the session commands (tree, fork, rewind, clone, export); the stream-json events as notifications; `--input-format stream-json` for `-p` | H3a, H3c |
| **H3e** SDK and configuration | A Lisp SDK (start a session, send prompts, receive events as CLOS objects, answer approvals); skills (`SKILL.md` via `steer-protocol`), prompt templates (`.cl-stack-code/prompts/*.md` as `/name`), `--system-prompt` and system-prompt files, `@file` imports, project trust (project allow rules and `env` wait for the user's yes) | H3a–H3d |

After H3: the image layer (H4), plan → project → approve (H5: [H5a — locked](#h5a--locked), later slices in its roadmap), extensions and a single binary (H6).

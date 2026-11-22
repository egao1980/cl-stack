# cl-stack-code (H3a–H3d, H5a, H5c-0, H5b, H4b, H8d, H3e-1, H3e-2): the coding agent's headless and interactive shell, its sessions, plan and preview modes, checkpoints, its Lisp image, its SDK and JSON-RPC server, its views of running units, its instructions, skills and rules, and its MCP servers

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H3 ("Product shell: interactive / `-p` / JSON stream / RPC / SDK; settings layering (user, project, local); … `AGENTS.md` discovery"). The repo was decided there (Decision 1).
**Status:** milestone **H3a** shipped as cl-stack-code **0.1.0**; **0.1.1** runs H3a with no stack workarounds: `--help` / `--version` come from `stack-cli:parse` (cli-protocol 0.2.1, clingon 0.2.1; no argv pre-scan), options and commands are built with `make-option` / `make-command :backend`, the designator's model reaches the backend as the agent's `:model` (ai-agent-protocol 0.12.0), and each run makes its own HTTP backend (http-backend-async 0.2.20) ([`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), `cl-stack-code/tests`, Rove; implemented through **team-solve**). Milestone **H3b** (the interactive mode) shipped as **0.2.0**: [H3b — locked](#h3b--locked). Milestone **H3c** (sessions and steering) shipped as **0.3.0**: [H3c — locked](#h3c--locked). Milestone **H5a** (plan → project → approve over files) shipped as **0.4.0** (0.4.1: the shell runs in the area): [H5a — locked](#h5a--locked); since 0.15.0 it is **preview mode** (renamed, same function). Milestone **H5c-0 locked** (plan mode plans: explore in a confined copy, propose a `plan.md`, approve, revise or reject it, run it in the project with a checklist, the plan next to the diff; version target **0.15.0**): [H5c-0 — locked](#h5c-0--locked). Milestone **H5b** (checkpoints and rewind, with V3: git and jj as composite parts) shipped as **0.5.0**: [H5b — locked](#h5b--locked). Milestone **H4b** (the Lisp image: lisp-mcp/agent tools, debugger events in the agent's inbox) shipped as **0.6.0**: [H4b — locked](#h4b--locked). Milestone **H3d** (the SDK and `--rpc`, JSON-RPC 2.0 over stdio) shipped as **0.7.0**: [H3d — locked](#h3d--locked). Milestone **H8d locked** (a supervisor per session, the TUI process panel `/ps` / Ctrl-P, the `units/*` RPC methods; version target **0.8.0**): [H8d — locked](#h8d--locked). **0.9.0** adds model sampling parameters: the `modelParams` settings key and `--model-param KEY=VALUE` ([Model parameters](#model-parameters-090)). Milestone **H3e-1 locked** (`@path` imports, Agent Skills and the `skill` tool, path-scoped rules, `contextFiles`; version target **0.12.0**, after steer-protocol 0.4.0): [H3e-1 — locked](#h3e-1--locked). Milestone **H3e-2a locked** (MCP servers: `.mcp.json` and `mcpServers` as Claude Code, project trust, stdio servers as supervised units, streamable HTTP, `mcp__server__tool` names and rules, `/mcp`, `mcp/list`; version target **0.13.0**, after mcp-protocol 0.4.0 and ai-agent-protocol 0.15.0): [H3e-2 — locked](#h3e-2--locked). Later slices: [Roadmap](#roadmap-h3bh3e).

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
| **Settings format** | A JSON object (json-protocol): `model` string; `maxTurns` integer ≥ 1; `permissionMode` one of the four mode names; `permissions` an object with `allow`, `ask`, `deny` arrays of rules; `env` an object of string or `null` values; `appendSystemPrompt` string; `modelParams` an object of model parameters (0.9.0, [below](#model-parameters-090)). Unknown keys are ignored. A missing file is no layer. Bad JSON, a non-object, or a wrong type signals `settings-error` naming the file and the key path (`maxTurns`, `permissions.allow[1]`, `env.FOO`). | Small, typed, forward compatible. |
| **Merge rules** | Layers merge in order user, project, local, flags. **Scalars** (`model`, `maxTurns`, `permissionMode`, `appendSystemPrompt`): the last layer that sets one wins. **Rule lists** (`allow`, `ask`, `deny`): concatenated in layer order; a later duplicate (same tool, resource and effect) is dropped. **`env`**: merged key by key, the later layer wins; a `null` value marks the key **unset**, which a later layer can set again. **`modelParams`** (0.9.0): merged key by key like `env`. `settings-files` lists the files read, in order. | Precise and predictable. Lists accumulate because every layer's rules matter; precedence among them comes from the effect (next row), not from the layer. |
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
settings-model-params                          ; 0.9.0: alist (wire-name . value), :null = unset
(model-params-llm-settings settings)           ; 0.9.0: → LLM-SETTINGS or NIL
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
| `--model-param` | `KEY=VALUE`, repeatable (0.9.0); VALUE read as JSON, else a string; no `=` / empty KEY / non-number `temperature` or `top_p` → usage error | `modelParams.KEY` |
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
- MCP servers ([H3e-2](#h3e-2--locked)); hooks, subagents, a cost table, retries beyond llm-protocol's `*retry-policy*`.
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

**Renamed in 0.15.0 ([H5c-0](#h5c-0--locked)):** this behaviour is now **preview mode** (`--permission-mode preview`, `"permissionMode": "preview"`), and "plan mode" means H5c-0's explore-and-propose mode. The function is unchanged: every rule below holds with "plan mode" read as "preview mode". The user-facing names change (`--preview-area`, stream-json `"preview"` events and result object, `preview ID: …` on stderr, the "Preview <id8>" dialog, `/preview`, RPC `preview/apply` and `preview/reject`); `--apply`, `--reject` and `--on-drift` keep theirs. The Lisp API below keeps its names until a follow-up rename. Its tests moved with it (H5c-0's contract tests).

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
| **Tools** | In plan mode the file tools and the shell tools are rooted at `plan-tool-root`, which is the area directory matching the working directory. `@` mentions read from the area. The base rules allow `write`, `edit` and `multi_edit`, as `acceptEdits` does, because the file tools cannot leave the area. **Since 0.4.1 they also allow `bash` and `job_input`** (`("bash" "*" :allow)`, `("job_input" "*" :allow)`), so the shell runs in the area without asking, in `-p --permission-mode plan` and in the interactive program alike. These are the lowest rules: a settings or flag `ask` rule still asks (and `-p` refuses it), and a `deny` rule still wins. **The shell is not confined** in 0.4.x: it starts in the area, but a command can still read or write outside it (an absolute path, `cd ..`, the network). **Superseded in 0.10.0 (R4d-4b):** `bash` and `job_input` run confined to the area (Seatbelt on macOS, Landlock on Linux; network off unless `--allow-network` / `sandbox.network`; `sandbox.extraWritable`, `sandbox.failIfUnavailable`), and where no sandbox can be used they ask before each call after a notice ([confinement.md § R4d-4](confinement.md)). `settings-permission-policy` is NIL in every mode, so the H3a read-only policy is gone. | The user's decision (0.4.1): plan mode exists so the agent can edit and run the tests in a copy without interruptions, and a shell that asks every time defeats that. Changes the shell makes inside the area are part of the projected diff and still need approval. Writes outside the area were the known gap until R4d (closed in 0.10.0, R4d-4b); deny rules cover the commands a user never wants run. 0.4.0 kept `bash` behind approval. |
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
| **H5c-0** plan mode plans | Locked (0.15.0): [H5c-0 — locked](#h5c-0--locked). H5a becomes preview mode | H5a, H5b, R4d-4b, ACP-2 ([acp.md](acp.md)), policy-protocol 0.1.0 |
| **H5c** shadow DB | Migrations as plans through `sql-migrate` on revision + diff (R2), with approval showing `state-diff`; tests against a shadow database | R2 |
| **H5d** image projections | The Lisp image spawned in the area with its ASDF registry pointing there, as a **confined** `:image` unit (moved here from R4d-4, 2026-11-22: until then `--lisp-image` stays refused in plan mode); image checkpoints | H4e, R4d |
| **H5e** subagent areas | One plan area per subagent instead of a git worktree, merged back through `rebase-plan` | H5a, subagents |
| later | `fs-reopen-area` / journals (R4b) for cheap rescans; COW areas (R4c); confined shells (R4d); per-path `.lisp` merges through `diff-backend-lisp-source` (R3); jj working copies (V2) | R4b–R4d, R3, V2 |

Also out of scope in H5a: confinement of the shell (R4d; 0.4.1 allowed `bash` in the area unconfined, and 0.10.0 / R4d-4b confines it), hunk-level partial approval, plans in RPC mode (H3d), two processes approving the same plan (no plan lock), GC of applied or discarded plan directories, and `.gitignore` changes inside a plan changing what the base compares (each side uses its own `:auto` rules).

## H5c-0 — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, H5 ("Plan → project → approve"), the first slice after [H5a](#h5a--locked) and [H5b](#h5b--locked). The user's direction (2026-11-22): "Plan mode is supposed to _plan_ changes. It can run exploratory scripts, but it's not for creating a full solution." And: "the current plan behaviour is valuable but let's not call it plan mode."

Contract: branch `agent/h5c0-contract-d9d4` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.15.0** (ACP-2 0.11.0, H3e-1 0.12.0, H3e-2a 0.13.0 and H3f 0.14.0 land first; the number follows merge order). The rules are in the header of `src/plan-docs.lisp`. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

There are now **two modes**, and "plan" means only the first:

- **plan** explores and proposes. File tools read a throwaway copy of the project, exploratory shell commands run confined in it (R4d-4b), the model may write scratch files, it can ask the user questions, and it ends with `propose_plan`, which writes a markdown `plan.md` outside the project. Nothing reaches the project. The user approves, edits, revises or rejects the **document**. On approval the plan runs in the real project under the mode the user picks, with a live checklist, and the run ends with the plan shown next to the actual diff.
- **preview** is H5a + R4d-4b unchanged, under a new name: edits and confined shell commands in a copy, the projected diff, `--apply` / `--reject` / `--on-drift`. It is also an execution target of an approved plan ("approve and run in preview").

```
cl-stack-code -p --permission-mode plan "add a greeting"          # → plan.md, exit 0
$EDITOR ~/.local/share/cl-stack-code/plan-docs/<key>/<id>/plan.md   # optional
cl-stack-code -p --resume 3f9a --approve-plan                       # runs it (acceptEdits)
cl-stack-code -p --resume 3f9a --approve-plan --permission-mode preview --apply
cl-stack-code -p --resume 3f9a --permission-mode plan "in French"   # revision 2
cl-stack-code -p --permission-mode preview "fix the test"            # H5a, renamed
```

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code plan mode | Read-only exploration ended by a tool call carrying the plan (`ExitPlanMode`); approval offers "accept edits" or "ask before edits"; ACP agents show it as a permission request of kind `switch_mode` | Read-only held by the prompt alone; plans in `~/.claude/plans` with no revisions; no execution checklist |
| Codex | `update_plan` as a live step list during execution | No saved document |
| Cursor | Editable plan markdown, a Build button, "Save to workspace" | Its UI flow |
| Gemini CLI | `ask_user` with options during planning | Its read-only tool subset (ours is a policy) |
| Kiro | Specs: requirements ("WHEN … THE SYSTEM SHALL"), design, tasks, as an optional template | Gates per phase, `.kiro/specs` in the repository |
| Armin Ronacher, [What is plan mode?](https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/) | Plan mode is a prompt-and-tooling convention around a document the user can read and change | — |

**Our difference:** exploratory scripts run, but confined to a copy whose changes are never applied; the plan is a document with revisions that the user edits; the policy, not the prompt, refuses edits; and the result is approved too (the plan next to the diff, H5b's rewind one key away, or the whole execution in preview).

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Names** | `"plan"` is the new mode only. H5a's behaviour is the mode **`preview`** (`--permission-mode preview`, `"permissionMode": "preview"`, ACP mode id `preview`). `+permission-mode-names+` = default, acceptEdits, bypassPermissions, plan, preview. | It previews the result before it lands, as an IDE's refactoring preview computes every change and shows the diff before applying it. `sandbox` was rejected: the `sandbox.*` settings already configure the confinement that **both** modes use, and Claude Code's sandbox writes to the project directly. `staged` was rejected: in a git project it would be read as git's index, while a preview lands as unstaged edits. |
| **Renames (user-facing)** | Everything users see of H5a says "preview": stream-json `{"type":"preview",…,"preview_id"}` and the result's `"preview"` object, stderr `preview ID: …`, the TUI dialog "Preview <id8>", the entry "● preview …", "Keep working", `/preview`, `--preview-area` (`--plan-area` stays an alias with a deprecation line on stderr through 0.15.x). `--apply`, `--reject` and `--on-drift` keep their names, scoped to preview. The full list is in the header ("USER-FACING RENAMES", "Other texts"). | "Plan" must mean one thing on every surface. |
| **Lisp names** | H5a's Lisp API keeps its names in 0.15.0 (`plan`, `open-plan`, `approve-plan`, `plan-drift`, `rebase-plan`, checkpoint reasons `:plan-before` / `:plan-after`, the core's `:plan-opened` events). New SDK names `client-apply-preview` / `client-reject-preview` are given. The rename to `preview-*`, with aliases for one minor, is a follow-up issue after the in-flight slices merge. | Four contracts edit the same files now; a global rename would collide with all of them. Users see the new names already. |
| **RPC** | `preview/apply` and `preview/reject` are H5a's methods. `plan/approve`, `plan/reject`, `plan/revise`, `plan/get`, `plan/update`, `plan/save` act on the plan document. Through 0.15.x `plan/approve` and `plan/reject` on a session with an open preview and no proposed plan still act on the preview, and the result gains `"deprecated": "plan/approve on a preview is preview/apply; the alias goes in 0.16.0"`. | The old names cannot be plain aliases, because they now name the document's methods. A session never has both waiting: a plan executing in preview was approved first, so dispatching by state is unambiguous. |
| **stream-json** | `"plan"` events carry plan documents (`opened`, `reopened`, `proposed`, `approved`, `step`, `executed`, `rejected`); `"preview"` events replace H5a's. No duplicate old events. | Emitting both would show every consumer two events per change, and the old type now has a new meaning. |
| **Migration** | An existing `"permissionMode": "plan"` (and `--permission-mode plan`) means the **new** plan mode. The first plan run on a data directory prints a one-time notice (stderr in `-p`, a TUI notice): `"plan" mode now plans first … The old behaviour … is the "preview" mode`, with the marker `<data-dir>/notices/plan-mode-0.15`. Old sessions: a record with H5a's `:plan` key and mode `:plan` reads back as `:preview`; the `:plan` key stays the preview's and areas stay in `<data-dir>/plans/`, so `--resume OLD --apply`, `--reject` and `--resume OLD --permission-mode preview "…"` keep working. | The new plan mode is strictly safer than the old one (nothing is written anywhere that could be applied). A user who wanted the old flow gets one clear sentence and the new name, once. |
| **Exploration area** | A plan's shell and file tools work in an H5a area of the working copy (kind auto / `--preview-area`), opened with the document, confined by R4d-4b's sandbox (same probe, same notices; unconfined → bash asks and `-p` refuses), kept across revisions and discarded at approval or rejection. It is **never applied**. The model's scratch directory is `<area>/.plan-scratch/`, which is copied to `<plan dir>/scratch/` at approval so the execution can use the scripts. | Exploratory commands write: build outputs, caches, lock files, git's index. A read-only project would make them fail; the copy lets them run and keeps the project untouched. Keeping it across revisions keeps the model's experiments; discarding it at approval removes any temptation to treat it as the solution. |
| **Tool policy** | Plan mode's base rules are preview's (write / edit / multi_edit allowed; bash and job_input allowed while confined). The new rule logic is a **policy-protocol** policy, `plan-mode-tools` (`defpolicy`, `:last-match`): edits are forbidden with `+plan-mode-edit-feedback+` ("project files cannot be edited now. Describe the change in the plan instead …") except under `path:.plan-scratch`; `update_plan` is forbidden. `settings-permission-policy` returns `plan-mode-permission-policy`, an adapter for ai-agent-protocol's `:permission-policy` hook, in plan mode (and NIL otherwise). A policy only tightens, so an allow rule cannot lift the refusal. | The workspace rule (rules-and-logic): new rule logic goes through policy-protocol (0.1.0, published). **L4b** (moving the mode base rules and R4d-4b's sandbox states onto policy-protocol) is not done, so the rest stays on ai-agent-protocol rules as today; when ai-agent-protocol/policy (0.15.0, H3e-2 row 2) ships its adapter, ours becomes a call of it. |
| **The document** | `<data-dir>/plan-docs/<project-key>/<id>/`: `meta.sexp`, `plan.md` (the user may edit it), `revisions/N.md`, `scratch/`. Statuses drafting → proposed → approved → executed \| interrupted; drafting or proposed → rejected; an interrupted plan can be approved again. One open document per session. | Outside the project, beside the sessions, like H5a's areas. |
| **Format** | Markdown read with markdown-protocol. Required headings: Goal and Steps (`planTemplate` `"default"`), or Requirements, Design and Tasks (`"spec"`, Kiro-style). Optional: Findings, Files to change, Risks, Test plan. Steps are the items of the first list under the steps heading; files are the first code span of each item under "Files to change". A missing heading is `plan-format-error` (its `missing` list), which `propose_plan` returns as a tool error with the template, so the model can retry. | Steps and files must be read back from what the user edited, so the structure lives in the markdown, not in tool arguments. |
| **Tools** | Plan turns get `propose_plan {markdown}` and `ask_user {question, options?}`; execution turns get `update_plan {step, status}`. None needs approval. `propose_plan` **ends the run**: no model step follows (if ai-agent-protocol has no way for a tool to end a run, that is added there). A plan turn may also end without a plan (an answer, a question). `ask_user` asks in the TUI; elsewhere it returns `+ask-user-unavailable+` ("make a reasonable assumption, state it under Findings"). | Claude Code's ExitPlanMode shape; Codex's update_plan; Gemini's ask_user. Ending the run makes the handover to the user explicit. |
| **Approval** | Approve (accept edits / ask before edits / run in preview), Edit in `$EDITOR`, Revise, Reject, Save to workspace. Approval first records the user's edits of `plan.md` as a `:user` revision. Headless: `--resume ID --approve-plan` runs under `--permission-mode` when given (not plan), else **acceptEdits**; `--reject-plan`, `--save-plan` and `--propose-only` (an alias of `--permission-mode plan`). Revise is just the next plan turn: its prompt is the feedback. | Headless cannot ask, and the user has just approved the plan, the files it names included; a user who wants every edit asked passes `--permission-mode default`. |
| **ACP** | Modes: the five names, plan and preview listed separately. `plan` updates come from plan documents (steps, pending / in_progress / completed); preview events are no longer `plan` updates. Approval is a **`session/request_permission`** inside the prompt that proposed, on the `propose_plan` tool call (kind `switch_mode`, the markdown as content), with the options acceptEdits / default / preview (allow) and plan / reject (reject_once / reject_always); an approval sends `current_mode_update` and runs the execution in the same prompt. `session/set_mode` out of plan while a plan is proposed approves it under that mode, and the next prompt runs it. | ACP's own `switch_mode` tool kind exists for this, and editors render a permission request with its content inline (Zed shows Claude Code's ExitPlanMode this way). `set_mode` alone cannot say revise or reject, so it is the secondary path. |
| **Execution** | One turn in the project under the chosen mode, whose user text is `plan-execution-prompt`: the preamble, `<plan id revision>` with the markdown, the scratch directory, steps already done (interrupted plans) and the user's extra instructions. The checklist is a TUI entry replaced in place, stream-json `step` events and ACP `plan` updates. At the end, **plan versus diff**: steps done, planned files against changed files (planned / not in the plan / planned, unchanged) and the diff of the turn's H5b PRE → POST files (read even with checkpoints disabled); in preview, the projected changes. The TUI's result dialog offers Keep / Rewind the files (H5b) / Save. | H5b's checkpoints make the diff and the undo cheap; a preview makes the whole execution reviewable before it lands. |
| **Records** | Turn records gain `plan-document` (content key `:plan-document`: id, revision, status, author, markdown, feedback), only in turns that changed the document; `+session-format+` stays 1. `/tree` marks such turns ` ✎ rN`, `/export` adds the revision, and a conversation rewind sets the document back to the latest revision on the rewound line. Settings: `planTemplate`, `planSaveDirectory` (default `docs/plans`). | Revisions are part of the conversation, so the conversation tools see them. |
| **Stubs** | `%h5c0-pending` (`src/plan-docs.lisp`). **Given:** exports, constants, conditions, the structs and classes with their readers, `plan-documents-directory`, `plan-document-path`, the policy, the preview SDK names, `+preview-mode-feedback+`, the `.asd`. **Stubbed:** every other function in the file. **Left to the implementation:** the renames and every hook in settings, arguments, sessions, headless, interactive, program, client and rpc. The contract's edits to shared files are the `.asd` and the version line only, so it merges after the in-flight slices with little conflict. | — |

### Surface (new in 0.15.0)

```lisp
;; documents (src/plan-docs.lisp)
plan-document plan-document-p plan-document-{id project-dir directory session-id status revision
  template title steps files area-id execution-mode opened-at}
plan-step make-plan-step plan-step-{index text status}   plan-revision plan-revision-{index author markdown feedback recorded-at}
(plan-documents-directory cwd &key data-dir)  (open-plan-document project-dir &key data-dir session-id id template)
(reopen-plan-document dir id)  (list-plan-documents dir)  (plan-document-path doc)  (plan-document-markdown doc)
(parse-plan-markdown text &key template) → (values title steps files)   (plan-template-text template)
(propose-plan-revision doc markdown &key author feedback) → N   (sync-plan-document-edits doc)  (plan-document-revisions doc)
(approve-plan-document doc &key mode)  (reject-plan-document doc)  (plan-execution-prompt doc &optional extra)
(set-plan-step doc index status)  (finish-plan-execution doc &key changes interrupted)  (plan-steps-lines doc)
(plan-versus-diff doc changes)  (plan-versus-diff-lines doc changes)  (save-plan-to-workspace doc &key directory)
(plan-document-object doc)  (plan-document-record doc &key feedback)
plan-tools (make-plan-tools doc &key phase ask)   plan-mode-tools (policy)   (plan-mode-permission-policy &key policy)
+plan-document-statuses+ +plan-step-statuses+ +plan-templates+ +plan-execution-modes+ +plan-scratch-directory-name+
+plan-tool-names+ +plan-document-choices+ +plan-result-choices+ +acp-plan-approval-options+ +plan-mode-section+
+plan-mode-edit-feedback+ +plan-execution-preamble+ +ask-user-unavailable+ +plan-mode-migration-notice+
+default-plan-template+ +spec-plan-template+ +default-plan-save-directory+ +preview-mode-feedback+
;; elsewhere
settings-plan-template settings-plan-save-directory record-plan-document
state-plan-document state-plan-document-prompt
invocation-approve-plan-p invocation-reject-plan-p invocation-save-plan-p invocation-propose-only-p invocation-preview-area
client-plan-document client-approve-plan-document client-reject-plan-document client-revise-plan-document
client-update-plan-document client-save-plan-document   client-apply-preview client-reject-preview
;; RPC: plan/approve plan/reject plan/revise plan/get plan/update plan/save preview/apply preview/reject
;; flags: --approve-plan --reject-plan --save-plan --propose-only --preview-area (--plan-area: deprecated alias)
```

### Conditions

```
code-error
└── plan-document-error (document)              exit 1
    ├── plan-document-not-found (designator)    exit 2   RPC -32030
    ├── plan-document-state-error (status)      exit 2   RPC -32031
    └── plan-format-error (missing)             a tool error for propose_plan; RPC plan/update -32602 "missing"
```

H5a's `plan-error` tree, its restarts and pathlib's `content-hash-mismatch` are unchanged and belong to previews.

### Contract tests

`cl-stack-code/tests` grows by 6 files (one of them helpers): **98 new deftests (133 cases with the parametrized rows), about 495 `ok` forms.** Every LLM interaction goes through the scripted mock backend, and the exploration shell runs through the suite's model confinement backend or a recording backend (R4d-4b's helpers).

| File | Covers |
|------|--------|
| `plan-doc-support` | the sample plans (default, a revision, spec), propose / update / ask steps, plan documents of a project, plan runs and their events, line records, a fake `$EDITOR` |
| `plan-doc-test` | constants; the directory; **the policy evaluated directly** (edits forbidden, scratch permitted, a prefix is not the directory, reads and the shell undecided, the feedback) and its adapter; open, reopen, list, unreadable meta; **the format** (title, steps, files, nested lists, case-insensitive headings, 5 missing-heading rows, spec); revisions, a bad proposal writing nothing, **user edits as revisions**; approve (state errors, plan refused, 4 modes, the user's edit), reject, the execution prompt, steps and their saving, interrupted and resumed; **plan versus diff** and its lines; save to workspace (date, slug, `-2`, fallback); object and record; the record round trip; **old records read as preview**; the tool source; settings and 5 error rows |
| `plan-doc-cli-test` | **an edit refused with feedback** (also despite an allow rule), **a scratch write allowed**, **exploratory bash confined in the area with the network off and the project unchanged**, no sandbox → ask refused; **propose_plan writes plan.md and ends the run**; stream-json order and fields; no proposal → null; result only in plan runs; a bad plan as a tool error; the system prompt and tools; the spec template; ask_user headless; `--propose-only`; 10 flag-error rows and the readers; `--plan-area` deprecated alias; **`--resume ID --approve-plan` in the project under acceptEdits, the plan as the turn's instructions, step events, the executed event**; text with **plan versus diff**; extra instructions; default mode still asking; **approve in preview** (and `--apply`); no plan; **the user's edit runs and is recorded**; **revise (revision 2, feedback, both revisions in the record)**; reject; save; `/tree` mark and export; **a conversation rewind restores the revision**; the **migration notice once**, none in preview |
| `plan-doc-core-test` | opened, proposed (dialog, entry, busy), 6 reply rows (approve × 3 switching the mode, edit, reject, save), revise and Esc, 7 command rows, `/approve` usage, commands without a plan, a waiting plan (`/clear` refused, `/permissions` fine), **the checklist replaced in place**, executed and its dialog, 3 result-reply rows, 3 closed rows, help |
| `plan-doc-program-test` | **the dialog on screen**, **approve → execution in the project → the checklist and plan versus diff → the result dialog**, rewind the files, **revise → r2**, reject, **edit in `$EDITOR`**, **approve in preview → the preview dialog**, ask_user dialog, save, the turn record, the migration notice once |
| `plan-doc-client-test` | SDK propose → approve → wait, revise / update / save / reject, no plan, ask_user unavailable; **RPC plan/get, plan/revise, plan/approve, plan/update (format error -32602), plan/save, plan/reject, -32030 / -32031**; **plan/approve and plan/reject on a preview: deprecated aliases** |

**Moved tests** (H5a's meaning under the name preview; assertions otherwise unchanged): `plan-cli-test` (`--permission-mode preview`, `"preview"` events and `preview_id`, the result's `"preview"`, `preview ID:` stderr, `--preview-area`, the `- Preview:` prompt line, `+preview-mode-feedback+`), `plan-core-test` and `plan-program-test` ("preview <id8>", "Preview <id8>", "Keep working", `/preview`, "no proposed plan or open preview"), `client-plan-test` (`:preview`, `client-apply-preview` / `client-reject-preview`), `rpc-test` (`rpc-preview-apply-and-reject` on `preview/apply` / `preview/reject`, the flag message, the method list), `sandbox-test`, `sandbox-cli-test`, `sandbox-program-test`, `sandbox-support` and the real-sandbox tests (through `plan-run`), `checkpoint-cli-test` (preview `--apply` checkpoints, through `plan-run`), `checkpoint-core-test` (the open-preview refusal), `tools-test` (`tools-preview-mode`), `permissions-test` (base rules for both modes, the policy only in plan mode, the feedback constants), `lisp-image-test` (two preview rows), `settings-test` (five mode names). `plan-test` (H5a's Lisp API) does not change. The version checks expect 0.15.0.

On the stubs (macOS, git 2.56, measured): **1077 cases, 841 passing, 236 failing.** 128 of the 133 new cases fail, each on `%h5c0-pending`, on a flag or mode that does not exist yet, or on an assertion downstream of the missing wiring. The 5 that pass check given code: the constants, the directory, **the policy itself** (`plan-mode-tools` evaluated through policy-protocol), the result without a plan outside plan mode, and no notice in preview mode. 108 moved cases fail until the rename (27 of them on `unknown --permission-mode "preview"`). Every untouched case passes. No throwaway prototype was run, so the implementation may find test bugs; those go through a contract-fix commit, as before.


### ACP-2 adjustments (after this lands)

ACP-2 ([cl-stack-code#31](https://github.com/egao1980/cl-stack-code/pull/31)) maps permission modes to session modes and H5a plan objects to ACP `plan` updates. After H5c-0 it must:

1. List **five** modes (`+acp-mode-ids+` follows `+permission-mode-names+`), with titles "Plan" (explore and propose) and "Preview" (work in a copy, approve the diff).
2. Map `"preview"` events (H5a's, renamed) to no `plan` update; map `"plan"` events to `plan` updates from the document's steps (`proposed`: pending; `step`: the whole list; `rejected`: empty).
3. Send the plan approval as `session/request_permission` on the `propose_plan` tool call, kind `switch_mode`, with `+acp-plan-approval-options+`, call `client-approve-plan-document` with the chosen mode, send `current_mode_update`, and run the execution in the same prompt.
4. Treat `session/set_mode` out of plan with a proposed plan as approval under that mode (ACP-2's `client-set-permission-mode` plus `client-approve-plan-document`); the next prompt's text is extra instructions.
5. Add the seven ACP tests listed in `.team-solve/task.md` to `cl-stack-code/acp/tests`.

### Non-goals (H5c-0)

- `ask_user` over the SDK, RPC and ACP (ACP elicitation), and deferred approval of a plan inside one `-p` call.
- Path templates for `planTemplate` (only `default` and `spec`), per-phase gates as in Kiro, and plans spanning several sessions.
- Hunk-level plan-versus-diff (it compares files), and automatic re-planning when the working copy changes during planning (the area is not refreshed; execution reads the real project).
- The Lisp API rename (`plan` → `preview` for H5a's API, checkpoint reasons, merge labels), a follow-up issue; removing the `plan/approve` alias (0.16.0).
- Image projections in either mode (`--lisp-image` stays refused in plan and preview modes until H5d).

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

## H4b — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, H4 ("debugger → agent inbox bridge (restarts gated by permissions)"). The bridge itself is lisp-mcp/agent **0.7.0**: [lisp-agent-tools.md, H4b — locked](lisp-agent-tools.md#h4b--locked). This section is the product half.

Contract: branch `agent/h4b-contract-e2a7` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.6.0**. The rules are in the headers of `src/lisp-image.lisp`, `src/interactive.lisp` ("H4b"), `src/program.lisp` ("H4b") and `src/settings.lisp` (the `lispImage` object). **Order:** this contract depends on `lisp-mcp/agent` 0.7.0. Implement, merge and publish lisp-mcp's H4b contract (same branch name in lisp-mcp) first. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

```
cl-stack-code --lisp-image spawn                       # a fresh SBCL with Swank
cl-stack-code -p --lisp-image attach:4005 --lisp-observe "why is the worker stuck?"
```

The agent gets lisp-mcp's image tools (`repl-eval`, `debug-*`, `inspect*`, `source-*`, `edit-*`, …) next to the file and shell tools, rooted at the working directory, with one live image named `image` that the product starts. When the image enters the debugger in a thread no tool call waits on, the event reaches the agent. While a turn runs, it goes into the inbox before the next generate. When no turn runs, it starts a turn or stays a notice, as `lispImage.onDebugger` says. The interactive mode shows a banner and marks the status line. The agent answers with `debug-invoke-restart`, behind the same `restart:<name>` rules, an approval dialog interactively, and a deny in `-p` unless a rule allows it.

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Where the code lives** | `src/lisp-image.lisp` plus hooks in settings, the command line, the tools, the prompt, the core, the program and the headless path. The bridge (events, queue, `post-image-events`) is lisp-mcp/agent's. **No ai-agent-protocol change.** | The inbox, `agent-run-post` and "a post during the final answer takes one more step" exist since 0.5 and 0.14. |
| **Dependencies** | Adds `lisp-mcp` and `lisp-mcp/agent` ≥ **0.7.0**. `:properties (:cl-repo (:ci (:with ("swank" "slynk"))))`: spawned images load Swank or Slynk, as in lisp-mcp. The tests add `repl-protocol`. | Own stack only. |
| **Settings** | `"lispImage": {"image": "off"\|"spawn"\|"attach:[HOST:]PORT", "backend": "swank"\|"slynk", "observe": false, "onDebugger": "turn"\|"notice"}`, merged per key across layers. Bad values signal `settings-error` with the key path (`lispImage`, `lispImage.image`, …). `lisp-image-settings` returns `(values image backend observe on-debugger)` with the defaults (off, swank, false, turn). `parse-lisp-image-designator` gives `(:off)`, `(:spawn)` or `(:attach host port)`. The host defaults to `127.0.0.1`, and the port must be 1..65535. **Given code.** | It is the project's choice, as checkpoints are. A project can turn the image on for everyone. |
| **Flags** | `--lisp-image spawn\|attach:[HOST:]PORT\|off` and `--lisp-observe` go to the flag layer. A bad value is a usage error naming the three forms. **Given code.** | `off` lets a user override a project file. |
| **Checks** | When any layer sets a lispImage key: observe without attach → `--lisp-observe needs --lisp-image attach:[HOST:]PORT (an observer attaches; it does not spawn)`. The image in plan mode → `--lisp-image is not available in plan mode yet (the image would not see the plan area)`. Both are `code-usage-error`s (exit 2), raised before anything starts. | Observe attaches (H4a). Plan areas need image projections (H5d). Until then a live image would see the real tree while the tools edit the area. |
| **Tools** | `make-code-tools` returns `(file-tools shell-tools lisp-tools)` when the image is on: `make-lisp-tools` at the working directory, every group, `:observe` mode for observers, `:needs-approval t`, `:image-events t`, the hidden-tool rule applied (a `repl-eval` deny with resource `*` hides it). The offered names are the three sources' in that order. Rules use lisp-mcp's names and resources as written: `repl-eval(lisp:pure)`, `debug-invoke-restart(restart:retry-later)`, `repl-load-system(system:my-app)`. | H3a's tool composition. H4a's resources need no new rule syntax: a spec for "any other tool" is kept as written. |
| **Starting the image** | `start-lisp-image`: the product calls `repl-spawn {"backend","name":"image"}` or `repl-connect {"host","port","backend","name":"image"}` itself, before the first turn and outside the permission rules. A failure is `lisp-image-error` (exit 1): `cannot start the Lisp image: …` or `cannot attach to the Lisp image at H:P: …`, before any model call. At the end (`-p`) or on `close-code-program`, `close-lisp-tools` kills a spawned image and leaves an attached one running. | The user asked for the image, so asking again would be noise. Starting it eagerly makes a bad port an immediate error, not a confused first turn. |
| **System prompt** | After the environment section: `# Lisp image`, `- Image: <description>` (`image (spawned, swank)`, `image (attached H:P, B[, observe])`), then `lisp-tools-instructions` (lisp-mcp's instructions, the `IMAGE EVENTS:` line, the `OBSERVE MODE` line). `assemble-system-prompt :lisp-image tools`. | The H4a plan: the product appends the instructions. There is no ai-agent-protocol hook. |
| **Headless** | `system` init gains `"lisp_image": {"name","kind","backend","host","port","observe"}`, only when the image is on. Each queued event, when it arrives, is a `{"type":"image_event","kind","connection","thread","level","job","text"}` line (written on the loop thread), and while the run is going it is posted into the run. `-p` never waits for events after the run, and the tools close. A restart asks (H4a) and `-p` denies the ask unless a rule allows it (`permission_denials` reason `"headless"`). The result object is unchanged. | Scripts see what happened. The run sees the event at its next step, and a post during the final answer takes one more step. |
| **Interactive** | The state gets `state-image` (`:name :description :observe :on-debugger :debuggers`). Core events: `(:image-event …)` adds a notice (`λ image entered the debugger (thread T, level L): <condition>` / `λ image: job jN done`). A debugger goes to the front of `:debuggers`. Busy → `(:post-image-events)`. Idle with `turn` → busy and `(:image-turn)`. Idle with `notice` → nothing. The queued events then reach the model with the user's next message, right after it. `(:image-return …)` removes the thread's levels at or below L. `(:image-pending N)` after a turn end starts an image turn under `turn`. The program posts on the agent thread, and an image turn's message is the first event's turn. | "When no turn is running, it becomes a follow-up turn, or a notice, depending on a setting." A debugger left in another thread must not be forgotten while the user types. |
| **Banner and status line** | Banner: `λ image is in the debugger: <condition's first line> (thread T)` (` (+K more)` when more wait), one row directly above the `─` rule, while any debugger waits. Status line left side: ` <model> · <mode> · λ image[ (observe[, debugger])] · <cwd>`. | The debugger is visible whatever the transcript shows, and the marker says which image the tools drive. |
| **Observe mode** | A hard gate: observers are not offered restarts, and a mutating `repl-eval` is a tool result error even under `bypassPermissions`. The image never sees the form. | H4a's mode, not a rule. |
| **Stubs** | `%not-implemented` is back in `src/package.lisp`. **Given:** the settings object and its merge, the flags, `parse-lisp-image-designator`, `lisp-image-settings`, `lisp-image-enabled-p`, `lisp-image-error`, `state-image` and `make-interactive-state :image`, the core's routing of the three events, the status-line hook, and `assemble-system-prompt :lisp-image`. **Stubbed:** every function in `src/lisp-image.lisp` (`check-lisp-image-settings`, `make-code-lisp-tools`, `start-lisp-image`, `lisp-image-description`, `%lisp-image-sections`, `lisp-image-state`, `image-event-notice`, `image-event-message`, `image-banner-text`, `%image-marker`, `%image-event`). **Left to the implementation:** the headless and program wiring (`make-code-tools`' third source, the start, the callbacks, the effects, the banner row, closing). Old paths never reach a stub, so the H3a–H5b tests keep passing. | — |

### Surface (new in 0.6.0)

```lisp
;; settings and flags (given)
settings-lisp-image  (lisp-image-settings s) → (values image backend observe on-debugger)
(lisp-image-enabled-p s)  (parse-lisp-image-designator string) → (:off) | (:spawn) | (:attach host port)
+lisp-image-backend-names+ ("swank" "slynk")  +on-debugger-names+ ("turn" "notice")
;; the image
+lisp-image-connection+ "image"
(check-lisp-image-settings settings mode)  (make-code-lisp-tools cwd settings &key on-image-event)
(start-lisp-image tools settings) → text   (lisp-image-description settings) → string
(assemble-system-prompt … &key lisp-image)
;; interactive
state-image  (make-interactive-state … &key image)  (lisp-image-state settings)
(image-event-notice event)  (image-event-message event)  (image-banner-text state)
;; events (:image-event …) (:image-return …) (:image-pending N)
;; effects (:post-image-events) (:image-turn)
;; conditions
lisp-image-error (code-error)  lisp-image-error-image  lisp-image-error-cause     ; exit 1
```

### Contract tests

`cl-stack-code/tests` grows by 4 files (one of them helpers): **30 new deftests (61 cases with the parametrized rows)**. Every LLM interaction goes through the scripted mock backend. The image tests spawn real `ros +Q run` images with Swank. The observe tests attach to a second image that the test drives through lisp-mcp/agent (`swank:create-server`). The asynchronous debugger entry is a background `sb-thread` in the image.

| File | Covers |
|------|--------|
| `lisp-image-support` | the background-error forms, `wait-until`, image turns found by their tag, a Swank server to attach to |
| `lisp-image-test` | designators (13 rows), the settings object (defaults, parse, merge per key), its errors (5 rows), flags and the usage error, the checks (8 rows), descriptions (4 rows), the three sources (observe, hidden tools, none without an image), the system prompt section and its place, status markers (4 rows) and H3b's line unchanged, the core (idle `turn`, busy post, `notice`, debuggers and returns, jobs and pending, no image), the banner, `lisp-image-state`, event notices and messages |
| `lisp-image-cli-test` | `-p --lisp-image spawn` (init, tools, prompt, a tool result), no image (init unchanged), **a background debugger in a run** (the event in the inbox before the next generate, an `image_event` line, `restart:abort` denied headless, `retry-later` allowed by a rule), a tool call's debugger (`DEBUGGER level 1`, no event, `=> 42`), **observe as a hard gate** under `bypassPermissions` against an attached image, attach failure (exit 1, no model call), usage errors (3 rows), the project settings file and `--lisp-image off` |
| `lisp-image-program-test` | **the turn policy** (marker, banner above the rule, notice, an automatic turn with the event, the restart dialog, the banner gone after the restart), the notice policy (no turn, then the event after the user's next message), the observe marker against an attached image, configuration errors before the terminal |

On the stubs, 39 of the 61 new cases fail (101 failing assertions). Every error is a `%not-implemented` one or an assertion downstream of one (lisp-mcp's H4b stubs count too: the run used the lisp-mcp contract worktree). The 22 that pass check given code or guard old shapes: the designators (13), the settings object and its errors (6), the flags, H3b's status line, and the init event without an image. All 595 H3a–H5b cases pass (measured with git 2.56 and jj 0.47.1). No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, as before.

### Non-goals (H4b)

- More than one image per session, and choosing among connections in the UI (the tools can still `repl-spawn` more, and events name their connection).
- The image in plan mode (H5d: image projections), image checkpoints (H5d / H4e).
- `/image` commands (restart from a menu, reconnect). The agent answers the debugger, and the user answers the approval dialog.
- Waiting for image events after a `-p` run, and events in RPC mode (H3d).
- Remote and confined images, SSH and secrets (H4d).

---

## H3d — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, H3 ("RPC (`rpc-protocol-json` over stdio) / SDK"). H3d takes the RPC half of the roadmap row and the SDK that the roadmap had put in H3e: the server is a thin adapter over the SDK, so they ship together.

Contract: branch `agent/h3d-contract-68ea` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.7.0**, and branch `agent/h3d-contract-68ea` of [`egao1980/rpc-backend-stdio`](https://github.com/egao1980/rpc-backend-stdio), version **0.2.0**. The rules are in the headers of `src/client.lisp` (the SDK), `src/rpc.lisp` (the server, the error table, the subprocess client) and `src/arguments.lisp` (`check-rpc-flags`) in cl-stack-code, and of `src/backend.lisp` and `src/pipe.lisp` in rpc-backend-stdio. **Order:** rpc-backend-stdio 0.2.0 first (implement, merge, publish), then cl-stack-code 0.7.0, which requires it. Both go through **team-solve** (`.team-solve/task.md`: `system: rpc-backend-stdio` / `cl-stack-code`, `test-system: …/tests`, this brief).

```
cl-stack-code --rpc --cwd ~/proj --model anthropic          # JSON-RPC 2.0 on stdin / stdout
→ {"jsonrpc":"2.0","id":1,"method":"session/new","params":{"permission_mode":"acceptEdits"}}
← {"jsonrpc":"2.0","method":"event","params":{"type":"system","subtype":"init","session_id":"3f9a…",…}}
← {"jsonrpc":"2.0","id":1,"result":{"type":"system","subtype":"init","session_id":"3f9a…",…}}
→ {"jsonrpc":"2.0","id":2,"method":"turn/start","params":{"session_id":"3f9a…","prompt":"fix the test"}}
← {"jsonrpc":"2.0","id":2,"result":{"session_id":"3f9a…"}}
← {"jsonrpc":"2.0","method":"event","params":{"type":"text_delta",…}}   … tool_use, approval_request …
→ {"jsonrpc":"2.0","id":3,"method":"approval/respond","params":{"session_id":"3f9a…","id":"toolu_1","decision":"once"}}
← {"jsonrpc":"2.0","method":"event","params":{"type":"result","subtype":"success",…}}
```

```lisp
(cl-stack-code:with-client (c :cwd "~/proj" :on-approval (lambda (s req) (declare (ignore s req)) :once))
  (let ((s (cl-stack-code:client-new-session c :permission-mode :accept-edits)))
    (cl-stack-code:event-value (cl-stack-code:client-query s "fix the test") "result")))
```

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code SDK control protocol (`--input-format stream-json`, `control_request`) | The stream-json events as the one event vocabulary; approvals answered by the caller with a feedback text; interrupt; one turn at a time per session | Requests multiplexed inside the event stream (here plain JSON-RPC); `can_use_tool` with input rewriting; hooks and MCP over the control channel |
| Codex app-server (JSON-RPC over stdio, `thread/*`, `turn/*`) | Several conversations per server, `thread/fork`-style forks, `turn/start` that returns at once and streams notifications, `turn/interrupt`, `turn/steer` | Approvals as server→client requests (here `approval_request` events and an `approval/respond` call, so a client needs no request handler); its item/delta model; auth and login methods |
| MCP | JSON-RPC 2.0 framing, newline-delimited over stdio, the reserved error range, `initialize` returning capabilities | `initialize` being mandatory; capability negotiation; tools as the server's surface |
| pi `--mode rpc` | `prompt` / `steer` / `follow_up` / `abort` as separate commands, the session commands next to the turn commands, events as JSON lines | One session per process; its own non-JSON-RPC framing; `follow_up` queues (here a second `turn/start` is refused) |

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **One core** | `src/client.lisp` is the SDK: `make-client`, sessions, `client-turn` / `client-query`, steering, interrupts, approvals, plans, checkpoints, rewinds, settings, tools. `src/rpc.lisp` maps each JSON-RPC method onto one SDK function and sends the SDK's events as notifications. The headless run's `%report` becomes the single emitter with one sink per destination (stream-json lines for `-p`, the session's callbacks for the SDK), so `-p` keeps its output byte for byte. | The RPC layer cannot drift from the SDK, and the SDK cannot drift from `-p`. |
| **One schema** | SDK values, `-p --output-format stream-json` lines and `--rpc` notifications are the same json-protocol objects (EQUAL hash tables, snake_case keys). A turn's events after `system` are exactly the `-p` stream of the same script (tests compare them with `session_id` and `duration_ms` aside). New types, absent from `-p`: `approval_request`, `approval_resolved`, `steering` (`taken` / `dropped`), `session` (`forked`), and the plan subtype `discarded`. `+event-types+` lists every type. | The roadmap promised "the stream-json events as notifications". CLOS event classes (roadmap H3e) would have been a second schema; `event-type` / `event-value` read the objects. |
| **SDK** | `(make-client &key cwd settings providers user-config-dir data-dir getenv on-event on-approval plan-area)`, `close-client`, `with-client`. Sessions: `client-new-session`, `client-resume-session` (an id, a prefix, a UUID or `:last`; `:fork`), `client-fork-session` (`:at`), `client-close-session`, `client-find-session`, `client-sessions`, `client-list-sessions`. Turns: `client-turn` → a `code-turn` (returns once the turn runs), `client-wait`, `client-query` → `(values result events)`, `client-steer`, `client-interrupt`. Approvals: `client-pending-approvals`, `client-respond-approval`. `client-approve-plan`, `client-reject-plan`, `client-checkpoints`, `client-rewind`, `client-settings`, `client-tools`, `client-busy-p`. | The functions name what the TUI does through keys and `-p` through flags. |
| **Threads** | One loop thread per client runs one libuv loop for all its sessions, with `%run-headless`'s bindings, writing to no stream. Callbacks run on it, in event order; an error in a callback is dropped. Every client function works from any thread: elsewhere it runs on the loop thread and waits; inside a callback it runs at once (so a callback can answer an approval). `client-wait` / `client-query` refuse the loop thread (`code-usage-error`). | The TUI's rule ("agent work never runs on the UI thread") turned around: the caller's thread never runs agent work. |
| **Sessions** | Set up as `make-code-program` does (same functions, same configuration errors, nothing left open when one signals): settings of the session's own working directory under the client's flag layer, then the session's `model` / `permission-mode` overrides; the agent's rule store is the local settings file, so "always" is saved as in the TUI. Created lazily (H3c). Its init event is `-p`'s `system` init object (plus `turns` on resume, `forked_from` on a fork) and is also `session/new`'s result. Resuming a session already open returns it. A fork is `clone-session` (`--fork-session`, Codex's `thread/fork`), not H3c's `/fork` head move, which `rewind` covers. | One session per conversation, many per client; `:last` is `--continue`. |
| **Concurrency** | **Several sessions per server, one turn per session.** A second `turn/start` while a turn runs or waits for approvals is an **error** (`turn-busy`, -32003), not a queue. Mid-turn input is `turn/steer` (H3c's `agent-run-post`): taken before the next generate, `steering` `taken`; posts not taken by the end are drained and reported `dropped`, never sent later. | A server-side queue would need its own list, cancel and ordering rules, and the client already sees `result`. Steering covers "add this to what you are doing"; "do this next" is the client's next `turn/start`. |
| **Turns** | First turn (and the first after a rewind moved the head): `run-ai-agent-async` on `session-turns`; later: `continue-ai-agent-async`. `@path` in the prompt expands as in the TUI; `mentions` attaches more files (a path that is not a file under the root is refused before anything runs). A terminal end commits the turn (H3c record, steering included) and records its checkpoints (H5b) **before** `result` is delivered. A commit conflict forks the session as `-p` does (`session` `forked` event; the handle takes the new id). Plan sessions open or reopen their plan at the first turn, and every plan turn ends with `plan` `projected` before `result`. | Disk state is current when a caller sees `result`, which is what scripts and tests read. |
| **Approvals** | No handler answers `agent-approval-required` (bypassPermissions approves, as in `-p`), so an ask pauses the run. Each pending call is an `approval_request` event (`id`, `name`, `input`, `summary` = `tool-call-summary`, `preview` = `tool-call-preview` or null), then `on-approval` may answer it: `:once`, `:always`, `:reject`, `(:reject "feedback")`, `:reject-all`, or NIL (wait). `approval/respond` / `client-respond-approval` answer later and return the ids resolved; each gets `approval_resolved`. The run resumes when nothing waits. `turn/interrupt` while calls wait denies them (`interrupt`) and ends the turn without resuming. Result `permission_denials` reasons: `denied` (rule) and `rejected` (an answer). | H3b's four answers mapped onto ai-agent-protocol 0.12+ exactly as the dialog does. An event plus a call keeps the client simple: no server→client requests to answer. |
| **Plans, checkpoints, rewinds** | `plan/approve` (`on_drift` abort / rebase / overwrite) returns `-p`'s `plan` object (`applied`, `rebased`, `drift`), approving with the checkpointer and recording plan checkpoints with the head; `plan/reject` returns `discarded`. `checkpoint/list` returns objects, newest first. `rewind` returns `-p`'s `rewind` object; a drift abort is a value (`files` `aborted`). All refuse a busy session. | H5a's and H5b's "plans in RPC mode" and "rewinding in RPC mode" non-goals, with `-p`'s shapes. |
| **Methods** | `initialize` (optional), `session/new`, `session/resume`, `session/list`, `session/fork`, `session/close`, `turn/start`, `turn/steer`, `turn/interrupt`, `approval/respond`, `plan/approve`, `plan/reject`, `checkpoint/list`, `rewind`, `settings/get`, `tools/list` (`+rpc-methods+`). Params are objects with snake_case keys, `session_id` the exact id of a session open in the server. Every server→client message is the notification `event` with the event object as params. Notifications may arrive before the response that caused them. | The task's list, plus `initialize` (MCP / Codex) and `session/close` (a long-lived server holding several sessions needs to free one). |
| **`settings/get`** | The merged settings in the settings-file shape, rules as `format-permission-rule` strings, `env` as the sorted **names** only, plus the files read. | Env values hold API keys; a client never needs them. |
| **Errors** | `rpc-error-for` maps a condition to `(values code message data)`: the first matching type of `+rpc-error-codes+` (below), message = the condition's text, data = `{"condition": type name, …fields}`. An `rpc-protocol:rpc-error` keeps its code and data. Bad params → -32602 `"METHOD: KEY must be …"`. | A documented table, conditions first (CLHS 9), codes as data for clients. |
| **`--rpc`** | `run-cli` → `check-rpc-flags` (exit 2), then `serve-rpc` on a stdio transport over `input` / `output` until EOF, exit 0. Only JSON-RPC on stdout. EOF closes the client: running turns are interrupted and committed. Refused with `--rpc`: `-p`, a prompt, `--output-format`, the session flags, the plan / rewind action flags. Allowed: `--cwd` (default directory of new sessions), `--model`, `--max-turns`, `--permission-mode`, the rule flags, `--append-system-prompt`, `--model-param`, `--lisp-image`, `--lisp-observe` (every session's flag layer), `--plan-area`. | The flag layer is the server's; per-session choices go in `session/new`. |
| **Subprocess client** | `connect-rpc-client :command argv` (or `:transport`), `rpc-client-call`, `rpc-client-events`, `rpc-client-wait-event`, `rpc-client-process`, `close-rpc-client` (stdin closed first → the child exits 0). | The optional half of the SDK, and what the subprocess test drives. |
| **The image** | With `lispImage` on, each session has its own image (started with the session). `image_event` as in `-p`; posted into a running turn; while idle delivered at once and posted after the next turn's prompt. `onDebugger` `turn` does not start turns in the SDK. | H4b's "events in RPC mode" non-goal. The caller owns the turn schedule. |
| **rpc-backend-stdio 0.2.0** (dependency, contracted in its repo) | **Server**: parse errors answer -32700 with `id: null`, non-objects and bad envelopes -32600, batches as one array line, blank lines and stray responses ignored, and the loop always goes on (0.1.2 signalled out of `rpc-serve` on a bad line). **Client**: a reader thread routes responses by id (0.1.2 read the next line as the response, so a server notification before it became the result), notifications to `:on-notification`, server requests to `:on-request` (-32601 without it); `:timeout` → `stdio-rpc-timeout`; EOF fails every waiting call. **Pipes**: `make-stdio-pipe` and `make-stdio-rpc-pair`, portable in-memory pipes (trivial-gray-streams) for in-process round trips. `:command` children get `:error-output` (default inherited, 0.1.2 left an unread pipe), and `close-stdio-rpc-transport` closes stdin first and waits `:timeout`. | Each is a bug or gap that `--rpc` hits; fixed in the stack, not around it. rpc-protocol and rpc-protocol-json need no change. |
| **Dependencies** | Adds `rpc-protocol` ≥ 0.2.0, `rpc-protocol-json` ≥ 0.1.0, `rpc-backend-stdio` ≥ **0.2.0**, `process-backend-uiop`. Tests add `rpc-protocol`, `rpc-backend-stdio`. | Own stack only. |
| **Stubs** | `%not-implemented` is back in `src/package.lisp`. **Given:** the conditions, the `--rpc` flag and `invocation-rpc-p`, the `run-cli` dispatch, the `code-client` / `code-session` / `code-turn` / `rpc-client` classes and readers, `with-client`, `event-type`, `event-value`, the constants (`+event-types+`, `+approval-decision-names+`, `+rpc-methods+`, `+rpc-error-codes+`, `+rpc-event-method+`, `+rpc-protocol-version+`). **Stubbed:** every function in `src/client.lisp` and `src/rpc.lisp`, `check-rpc-flags`, `%run-rpc`; in rpc-backend-stdio `make-stdio-pipe` and `make-stdio-rpc-pair` (the reader thread and the server answers change existing functions, so their tests fail on 0.1.2's code). Old paths never reach a stub. | — |

### Error codes

| Code | Condition (first match wins) | `data` beyond `condition` |
|------|------------------------------|---------------------------|
| -32700 / -32600 | parse error / invalid request (rpc-backend-stdio) | — |
| -32601 | unknown method | — |
| -32602 | bad params; `code-usage-error` (bad `cwd`, bad session id, blank prompt, bad mention, `permission-rule-error`) | — |
| -32603 | any other `error` | — |
| -32000 | any other `code-error` (`run-failed`, …) | — |
| -32001 | `session-not-found` | `designator` |
| -32002 | `session-not-open` | `session_id` |
| -32003 | `turn-busy` | `session_id` |
| -32004 | `turn-not-running` | `session_id` |
| -32005 | `approval-not-found` | `id` |
| -32006 | `session-conflict` | `expected`, `actual` |
| -32007 | `session-turn-not-found` | `designator` |
| -32008 | `plan-error` (`plan-not-found`, `plan-drift`) | `plan_id` |
| -32009 | `checkpoint-error` (`checkpoint-not-found`, `checkpoint-expired`) | `designator` (not found) |
| -32010 | `settings-error` | `file`, `key` |
| -32011 | `model-not-found` | `designator` |
| -32012 | `lisp-image-error` | — |
| -32013 | `session-locked` | — |
| -32014 | `client-closed` | — |
| own | `rpc-protocol:rpc-error` | its own |

### Surface (new in 0.7.0)

```lisp
;; values
event-type event-value +event-types+ +approval-decision-names+
;; the client
code-client (make-client &key cwd settings providers user-config-dir data-dir getenv
                         on-event on-approval plan-area)
(close-client c) (with-client (var &rest args) &body) client-cwd client-closed-p client-sessions
;; sessions
code-session code-session-id code-session-client code-session-cwd code-session-model
code-session-permission-mode code-session-init code-session-store
(client-new-session c &key cwd model permission-mode session-id)
(client-resume-session c designator &key cwd model permission-mode fork session-id)
(client-fork-session s &key at session-id) (client-close-session s) (client-find-session c id)
(client-list-sessions c &key cwd) (client-busy-p s)
;; turns
code-turn code-turn-session code-turn-prompt code-turn-events code-turn-result code-turn-done-p
(client-turn s prompt &key mentions on-event) (client-wait turn &key timeout)
(client-query s prompt &key mentions on-event timeout) → (values result events)
(client-steer s text) (client-interrupt s)
(client-pending-approvals s) (client-respond-approval s id decision &key feedback)
;; plans, checkpoints, introspection
(client-approve-plan s &key on-drift) (client-reject-plan s) (client-checkpoints s)
(client-rewind s turn &key mode on-drift) (client-settings s-or-c) (client-tools s)
;; conditions (code-error)
client-closed session-not-open turn-busy turn-not-running approval-not-found
;; --rpc
invocation-rpc-p (check-rpc-flags inv) +rpc-protocol-version+ +rpc-methods+ +rpc-event-method+
+rpc-error-codes+ (rpc-error-for condition) → (values code message data)
(make-rpc-handler c) (serve-rpc transport &rest client-args) → 0
rpc-client (connect-rpc-client &key command transport on-event error-output)
(rpc-client-call rc method params &key timeout) (rpc-client-events rc &key type session-id)
(rpc-client-wait-event rc predicate &key timeout) (rpc-client-process rc) (close-rpc-client rc &key timeout)

;; rpc-backend-stdio 0.2.0
(make-stdio-rpc-transport &key input output command error-output on-notification on-request)
stdio-rpc-transport-on-notification stdio-rpc-transport-on-request stdio-rpc-transport-process
stdio-rpc-timeout (stdio-rpc-timeout-method stdio-rpc-timeout-seconds)
(make-stdio-pipe &key capacity) → (values input output)
(make-stdio-rpc-pair &key on-notification on-request) → (values server client)
(close-stdio-rpc-transport tx &key force timeout)
```

### Contract tests

`cl-stack-code/tests` grows by 6 files (one of them helpers): **72 new deftests (104 cases with the parametrized rows), about 450 `ok` forms.** The 656 H3a–H4b cases stay; their version checks expect 0.7.0. Every LLM interaction goes through the scripted mock backend; gated steps make busy, steering, interrupt and EOF cases deterministic. RPC round trips run `serve-rpc` on `make-stdio-rpc-pair` in-process; one test drives a child SBCL running `run-cli --rpc` through `connect-rpc-client :command`.

| File | Covers |
|------|--------|
| `rpc-support` | event collectors and waits, `normalized` / `same-events-p`, `with-test-client`, `with-rpc` (server thread + client on a pair), `call`, `fault`, `rpc-result` |
| `client-test` | make / close / closed; init object (keys, first event, lazy disk); overrides; configuration errors leave nothing open; existing session ids; the result object (-p's keys, order, deltas); **SDK events = `-p` stream-json** for one script; commit before `result`; conversation continues; two sessions; resume (prefix, already open, missing), `:last`, `:fork`; `client-fork-session :at`; list objects; close; **turn-busy**; interrupt (idle NIL, record `:canceled`); steering taken / not running / dropped; mentions (order, dedupe, refusals); blank prompt; wait and query timeouts; max turns and failures; **conflict fork**; callbacks on one loop thread, inline calls, dropped errors; settings (env names only); tools; the image during a turn and while idle |
| `client-approval-test` | the request object and preview; once; always (saved as `edit(a.txt)`); reject with feedback (`rejected`); reject-all; resume after the last answer; callback answers; not found, bad decisions, busy; interrupt while waiting; bypass and deny rules |
| `client-plan-test` | plan turn and approve × {copy, git} (opened first, projected before result, checkpoints); reject; drift then overwrite; a new plan after apply; busy refusals; checkpoint objects; rewind both (next turn on the new head); files-only drift, overwrite, conversation-only, errors |
| `rpc-test` | `--rpc` parsing and 8 refused combinations (exit 2, nothing on stdout); bad `--cwd`; constants; `rpc-error-for` (20 rows) and data fields; **`run-cli --rpc` on string streams**; turn round trip; **notifications = `-p` stream-json**; -32003 / -32002 / -32601; invalid params (6 rows), non-object params; approvals; steer and interrupt; session methods; plans; checkpoints and rewind; settings and tools; configuration error codes; **EOF interrupts and commits** |
| `rpc-process-test` | a child `cl-stack-code --rpc`: initialize, session/new, a turn, result, exit 0 on stdin EOF, the record on disk |

rpc-backend-stdio 0.2.0 adds `tests/peer-test.lisp`: **27 deftests (32 cases)**: pipes (round trip, blocking, close, capacity, broken pipe, thread-safe writes), pairs, interleaved notifications, ids, timeouts, a closed peer, server requests, the server's answers (parse error, 6 invalid-request rows, batches, null ids, blank lines) and a child process with `:error-output`.

On the stubs, 103 of the 104 new cl-stack-code cases fail (`rpc-constants` checks given code), every one a `%not-implemented` error or an assertion downstream of one, and all 656 old cases pass (measured: 657 passing, 103 failing, with the rpc-backend-stdio contract worktree in the registry). In rpc-backend-stdio, 31 of the 32 new cases fail (stubs, or 0.1.2's reader and server; the `no-method` row already passes) and the 6 old ones pass. No throwaway prototype was run, so the implementation may find test bugs; those go through a contract-fix commit, as before.

### Non-goals (H3d)

- `--input-format stream-json` for `-p` (the roadmap's H3d item): `--rpc` covers driving a session from a program; a stream-json input mode would be a second control protocol.
- A follow-up queue on the server, changing an open session's model or mode (`/model`, `/permissions`), and server→client requests.
- Other transports for the same methods (HTTP / SSE / WebSocket through `rpc-backend-http` and `-sse`): the adapter is transport-agnostic, but only stdio is contracted.
- Several clients on one server, authentication, and sharing a session between servers beyond H3c's lock and fork-on-conflict.
- An interactive session picker, session names, deleting sessions (as H3c).
- Typed CLOS event classes in the SDK (one schema instead).

---

## H8d — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H8d ("Visual tools to observe and control running units"), "Decisions (2026-11-21)" item 3. The units, their logs and the search engine are [supervisor-protocol](supervisor.md) 0.3.0 (H8a–H8c); the agent's unit tools are [agent-tools 0.3.0](agent-tools-units.md). This section is the product half: the session's supervisor, the TUI process panel and the same model over `--rpc`.

Contract: branch `agent/h8d-contract-38cf` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.8.0**. The rules are in the headers of `src/units.lisp` (the supervisor, the unit tree, the JSON objects, the resource sampler, the permission decision), `src/unit-panel.lisp` (layout, keys, views), `src/interactive.lisp` ("H8d"), `src/program.lisp` ("H8d"), `src/client.lisp` ("H8d", the SDK functions), `src/rpc.lisp` (the `units/*` methods) and `src/headless.lisp`. **Order:** supervisor-protocol 0.3.0 and agent-tools 0.3.0 are published; nothing else comes first. The implementation goes through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

```
cl-stack-code                     # /ps or Ctrl-P: the session's units
→ {"jsonrpc":"2.0","id":7,"method":"units/subscribe","params":{"session_id":"3f9a…","since":0}}
← {"jsonrpc":"2.0","method":"event","params":{"type":"unit","seq":1,"unit_id":"shell-job-1","event":"state","from":null,"to":"starting",…}}
← {"jsonrpc":"2.0","id":7,"result":{"subscription":"sub-1","seq":9,"complete":true}}
→ {"jsonrpc":"2.0","id":8,"method":"units/control","params":{"session_id":"3f9a…","unit":"shell-job-2","action":"stop"}}
← {"jsonrpc":"2.0","id":8,"error":{"code":-32017,"message":"stop shell-job-2 needs confirmation: …","data":{"condition":"unit-control-needs-confirmation","resource":"stop:shell-job-2",…}}}
```

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| `htop` / `top`, `docker ps`, `systemctl status` | One row per process with state, pid, uptime, CPU% (Δcpu / Δwall, one core = 100), RSS; tree by owner | Sort / filter keys, signals menu, per-thread rows |
| Claude Code background tasks (`/bashes`), Codex `unified_exec` | Shell jobs and agents in one list; read a job's output while it runs | A job list separate from servers and subagents |
| `journalctl -u … -f`, `less +F`, `kubectl logs -f` | Follow a unit's log, scroll back, `/` search with highlighted hits, `n` / `N` | A query language |
| k9s / lazydocker | A pane over a live event stream; stop / restart from the list with a confirm | Port-forward, shell exec, attach (later: H8a-1 executors) |
| H3b, H3d (this product) | The confirm dialog, the status line, `--rpc` events as notifications and condition-named errors | — |

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Supervisor ownership** | One supervisor per interactive program, per SDK / `--rpc` session and per `-p` run, made by `make-code-supervisor` (given) before the tools. State directory `units-directory` = `<data-dir>/units/<project key>/` (the sessions' key). It outlives conversation changes (`/clear`, `/clone`, a conflict fork): it belongs to the running session, not to one conversation id. Root scope = the session; agent-tools adds `:tool-source "shell"`; a plan's area tools get `"shell"` under `:agent "plan-<id8>"`. Close: unit tools, shell tools, then `shutdown-supervisor` (one stop wave; logs kept) | A per-project state directory lets every start sweep what a crashed cl-stack-code left in that project (live owners are kept) and gives unit-tools the earlier runs' logs as previous logs. A supervisor per session keeps one session's controls away from another's units |
| **Tools** | `make-code-tools :supervisor` (given): bash commands are `:shell-job` units, and the five unit tools come **last**: `(file shell [lisp] units)`, so `(third sources)` stays the lisp tools. -p, the TUI and the SDK all offer them; deny rules hide them as any tool. The init event's `tools` grow by the five names | One tool list everywhere; the H8c tools reach the agent only through the product |
| **Unit model** (`src/units.lisp`) | `unit-tree` = depth-first rows: a scope's own units (start order), then its child scopes (creation order), root units at depth 0, empty scopes omitted. `unit-status-word` = agent-tools' (`running`, `exited 0`, `failed 3`, `exited` / `failed` for threads, `killed`). `unit-last-line` = the last output record cleaned (ANSI and controls removed). `unit-object` / `unit-objects` (tree order, filters kind / state / owner glob) are the **one** source for the panel rows and `units/list` | The panel and RPC cannot disagree |
| **Panel** | `/ps` (idle or busy) or **Ctrl-P** opens it; Ctrl-P / Esc / `q` close it. It replaces the transcript, the queue / spinner / banner rows and the input (the input keeps its text); the status line stays. Row 0 title `Units · N running · M total`, row 1 the column header, then the tree. Fixed columns `"~a~20a ~9a ~9a ~6@a ~6@a ~5@a ~6@a  ~a"`: mark (`> ` selected, inverse), name (indented id), status, kind, pid (`-` threads), uptime (`1m04s`, `-` finished), CPU%, RSS (`12.3M`), last line. Scope rows `  shell/`. The row above the rule is the help (`+unit-list-help+`), the last action's result, or the panel's prompt | Fixed widths make exact snapshot tests possible (the clock-driven columns are masked); one help row says every key |
| **Keys** | List: Up / Down (scope rows skipped), Home / End, Enter follow, `s` stop, `r` restart, `i` input (prompt `input> `, the line + LF), `e` close input, Esc / `q` / Ctrl-P close. Log view: Up / Down / PgUp / PgDn / Home scroll, End follow, `/` search (`search> `), `n` / `N` hits (wrapping), `s r i e`, Esc clears the search, then back. An approval dialog always takes the keys first | `less` / `htop` muscle memory; the agent is never left waiting behind the panel |
| **Follow and search** | The log view loads the last 2000 output lines (`log-read`), follows with `log-follow` (:wait 0.25) on a thread, drops the oldest past 2000. Lines `"~a~5d  ~a"` (mark `>` on hits), TAB to the next 8 columns, stderr red, gaps as unit_read shows them. Search = `ss:search-logs` on the unit tools' own index, `:units (id) :k 50`; every occurrence of the query's terms (`ss:query-terms`, longest first) is inverse; a hit outside the loaded lines reloads the window around it. Title `Log <id> (<status>) · following` / `· lines A-B`, then `· search "Q": I of N` | The H8b reader and the H8c engine, as the agent uses them; no second index |
| **CPU / RSS** | `sample-unit-resources` (one OS call for all units): macOS / Linux `ps -A -o pid= -o pgid= -o rss= -o time=` (LC_ALL=C), summed over the unit's process group; Windows `Get-CimInstance Win32_Process` (WorkingSetSize, KernelModeTime + UserModeTime), the unit's pid and descendants. CPU% = Δcpu / Δwall × 100 between two samples. Sampled every 2 s (Unix) / 5 s (Windows) while the panel is open, and on `units/list` with `resources`. Threads: `-` | `ps -o pgid,rss,time` exists on macOS and Linux (`/proc` is Linux-only, `libproc` macOS-only, both native); CIM is already the H8a inspector's Windows source and costs ~0.5–1 s per call, hence the slower rate. The group / descendant tree is the one stop and sweep act on. No portable per-thread CPU. The sampler moves into supervisor-protocol's `os-inspector` later ([supervisor-protocol#4](https://github.com/egao1980/supervisor-protocol/issues/4)) |
| **Permission parity** | A panel or RPC action **is** the agent's unit_control call: `unit-control-arguments` (close_input = `input` with `""` and `eof: true`, resource `input:<id>`), decided by `unit-action-permission` = `ai-agent-protocol:agent-permission` of the session's agent on its unit tools (its rules, saved rules, unit_control's default ask); `bypassPermissions` turns an ask into allow, a deny stays. Allowed actions run `tools:call-unit-tool "unit_control"`, so texts and effects are the tool's. TUI: deny → help row + transcript error `stop rpc-1 denied by unit_control(*:rpc-*)`; ask → confirm dialog "Unit control" (Yes / No, no "always"); allow → done, result as help row and `unit_control: …` notice | One layer, tested both ways: rules like `unit_control(stop:shell-job-*)` decide for the agent and the user alike. No "always": unit ids are per supervisor, so a saved id rule would match another unit next session |
| **Live updates** | The program subscribes at `tui-init` (from the current seq); each event updates the status line count (`(:units :running N)`) and, for a `:state` → `:failed`, adds the notice `unit <id> (<kind>) failed with exit code N; /ps to inspect` (`(:unit-failed :notice …)`); the open panel redraws, ticks every 1 s and samples on its own thread | The H8a stream is ordered and replayable, so nobody polls states |
| **Status line** | Right side `N running · <in> in · <out> out ` while N > 0, unchanged at 0 (given `%units-marker`) | Every H3b–H4b status-line test stays exact |
| **`--rpc`** | Six methods (`+rpc-methods+`): `units/list`, `units/subscribe` (`since` replays every retained event after it, then live, in seq order, each once; `complete` false when older events were dropped), `units/unsubscribe`, `units/read` (unit or ref, `start_line` / `limit` / `tail` / `streams`), `units/search`, `units/control` (`confirmed` answers an ask). Notifications are `event` with `{"type":"unit",…}` (`+event-types+` gains `"unit"`). Thin adapters over `client-units`, `client-subscribe-units`, `client-unsubscribe-units`, `client-read-unit`, `client-search-units`, `client-control-unit` | H3d's one-core rule: RPC = SDK = the panel's model. An ask is a −32017 the client answers with its own dialog (no server→client requests, as H3d) |
| **Web page** | **Out of 0.8.0** (a later row, H8d-1) | A listening socket is new attack surface even read-only (unit logs carry tokens and env; it needs a per-run token, origin checks and a bind policy); `--rpc` already serves external UIs, and a page is best a thin client over the same methods once `rpc-backend-http` / `-sse` exist (H3d's transport non-goal), not a second server; the stack has no live-page layer yet (SSE + JS); and every OS would need browser-free tests. Plan: `--units-web 127.0.0.1:PORT`, read-only, over the `units/*` methods. The same per-session server will also serve **canvases** (H4h, 2026-11-22: `/canvas/<session>/<package>::<name>`, a plain function called in the session image; loopback, a per-session token exchanged for a cookie, strict CSP), see [lisp-agent-tools.md, H4h](lisp-agent-tools.md#h4h--canvases) |
| **Stubs** | `%h8d-pending` (`src/package.lisp`). **Given:** the conditions and their RPC codes / data fields, constants, `units-directory`, `make-code-supervisor`, `make-code-tools :supervisor`, `code-unit-tools`, the `unit-panel` class and readers, the program slots (`code-program-supervisor`, `-unit-tools`, `-panel`), `state-units-running` and `%units-marker`, `/ps` and the event routing in the core, `+rpc-methods+`, `+event-types+`. **Stubbed:** every function in `src/units.lisp` and `src/unit-panel.lisp` past the given ones, the SDK functions. **Left to the implementation:** the wiring in the program, the client sessions, -p and the `units/*` handlers. Old paths never reach a stub | — |

### Surface (new in 0.8.0)

```lisp
;; supervisor and tools (given)
(units-directory cwd &key data-dir)  (make-code-supervisor cwd &key data-dir getenv (exit-hook t))
(make-code-tools cwd &key settings on-image-event supervisor scope)  (code-unit-tools sources)
;; model
(unit-status-word u) (unit-tree sup &key scope) (unit-last-line u)
(format-unit-uptime s) (format-unit-rss b) (format-unit-cpu p) (parse-ps-cpu-time string)
(sample-unit-resources units) → id → (:cpu-time s :rss b)   (unit-cpu-percent prev cur seconds)
(unit-object u &key stats cpu-percent depth now) (unit-objects sup &key kind state owner stats cpu now)
(unit-event-object event &key subscription session-id) (unit-record-object r) (unit-gap-object g)
(unit-control-arguments action unit-id &key input)
(unit-action-permission agent unit-tools action unit-id &key input mode) → (values effect rule resources)
(unit-action-message action unit &key input) (unit-failure-notice event)
;; views and the panel
(unit-row-text row width &key header selected stats cpu now) (unit-panel-lines rows width height &key …)
(unit-log-lines records gaps width &key hits query) (unit-log-title unit &key following first-line …)
unit-panel unit-panel-open-p unit-panel-mode unit-panel-selected unit-panel-unit unit-panel-query
unit-panel-hits unit-panel-hit-index  code-program-supervisor code-program-unit-tools code-program-panel
state-units-running  ;; core: (:units :running N) (:unit-failed :notice T) → effect (:units-panel)
;; SDK
code-session-supervisor code-session-unit-tools
(client-units s &key kind state owner resources) (client-subscribe-units s &key since) → (values id seq complete)
(client-unsubscribe-units s id) (client-read-unit s &key unit ref start-line limit tail streams)
(client-search-units s query &key units kinds streams since until k context)
(client-control-unit s unit action &key input confirmed)
;; constants
+unit-panel-key+ +unit-log-scrollback+ +unit-tick-interval+ +unit-stats-interval+ +unit-rpc-actions+
+unit-action-choices+ +unit-panel-columns+ +unit-list-help+ +unit-log-help+
;; conditions (code-error)
unit-not-found unit-control-denied unit-control-needs-confirmation unit-control-failed subscription-not-found
```

### Error codes (added)

| Code | Condition | `data` beyond `condition` |
|------|-----------|---------------------------|
| -32015 | `unit-not-found` | `unit` |
| -32016 | `unit-control-denied` | `unit`, `action`, `rule` |
| -32017 | `unit-control-needs-confirmation` | `unit`, `action`, `resource` |
| -32018 | `subscription-not-found` | `subscription` |
| -32019 | `unit-control-failed` | `unit`, `action` |

### Contract tests

`cl-stack-code/tests` grows by 6 files (one of them helpers): **58 new deftests (99 cases with the parametrized rows), about 490 `ok` forms**, on macOS, Linux and Windows. Child processes are this SBCL (an echo server, exit codes, a CPU burner) or portable shell commands (`sleep` / `ping -n`, `sort`, `echo`, `exit 3`). The fixture session (H8a's, product-side): **two background shell jobs the agent started with bash** (the mock LLM), a fake stdio server (`:rpc`) and a subagent thread in scope `sub`. Panel tests run on tui-backend-terminal's headless driver at 120 × 30; rows are compared exactly with the UP / CPU% / RSS columns masked, styles through `tui-snapshot` cells.

| File | Covers |
|------|--------|
| `units-support` | child argv, portable commands, `with-test-supervisor`, `with-units-tui` (the fixture), `with-gap-supervisor`, independent row / status / time formatters, cell styles |
| `units-test` | constants; `units-directory`; `make-code-supervisor`; `make-code-tools :supervisor` (order, scope, hiding); RPC error rows (5); uptime / RSS / CPU / `ps` time tables (30 rows); `unit-cpu-percent`; status words; tree order; last line; exact row texts; panel lines (title, scroll, inverse); log lines (marks, TAB, stderr red, highlight runs, gaps); titles; unit / event / record / gap objects; filters; control arguments; **permission table (9 rows) = the agent's own decision**; dialog messages; failure notices; **live resource samples** (RSS of a child, CPU of a busy child, none for threads and finished units) |
| `units-core-test` | `/ps` idle and busy, its usage error, the running count and the status line, the failure notice |
| `units-program-test` | **panel snapshot over the fixture**; open / close keys and the kept input; **live update on a state change** and a new unit; failure notice in the transcript; **follow + search highlight** (hit mark, inverse cells, `n`, new lines while following, Esc twice); **stop through the confirm dialog** (Yes, No, Esc); **stop through an allow rule** (no dialog; restart still asks); a deny rule; input and close input to the echo server; **panel rows = `unit-objects`**; wiring (unit tools offered, close shuts the supervisor down) |
| `units-client-test` | a supervisor per session (state dir, init tools, close); `client-units` (order, statuses, filters, resources); read by unit / ref / tail / streams and errors; search hits = read lines, kinds-only, filters; **subscribe with replay since 0 then live, no gap or duplicate**; control (confirmation, stop, input + EOF to sort, failures); deny beats confirmed; **permission parity (4 rows): the agent's unit_control and the caller's control agree** |
| `units-rpc-test` | `initialize`; `units/list` shape and filters; **RPC = SDK for one script**; **`units/subscribe` replay, live, unsubscribe**; live-only subscribe; `units/read`; `units/search`; `units/control` (-32017, confirmed, input / close_input, -32019, -32602, -32015); deny (-32016 with the rule) |

The old suites change only where 0.8.0 changes them: version checks expect 0.8.0, the init / `tools/list` names end with the unit tools (`client-test`, `json-test`), and `rpc-constants` lists the six methods. Locally (macOS, stubs): of the 99 new cases 11 pass (given code: constants, directories, `make-code-supervisor`, `make-code-tools :supervisor`, the five RPC error rows, `initialize`) and 88 fail, each on `%h8d-pending`, a `-32601` for an unimplemented `units/*` method, or downstream of the missing wiring (a NIL supervisor). Of the 760 old cases, `client-new-session-init` and `stream-json-init-and-result` fail as intended (their tool lists now end with the unit tools); every other old case matches a run of `main` on the same machine (38 git-backed plan / checkpoint cases fail locally on both: the sandboxed temp directory is "not a git worktree"; CI runs them). The systems load with no new warnings. No throwaway prototype was run, so the implementation may find test bugs; those go through a contract-fix commit, as before.

### Non-goals (H8d)

- The local web page (H8d-1, above), which H4h canvases build on.
- Attaching to a pty or tmux unit: no executor gives a unit a terminal until H8a-1; the panel gets an `a` key then.
- Previous sessions' logs in the panel (the agent's `unit_list include_previous` has them), deleting logs, a retention policy (H6's daemon).
- Streaming a unit's output as `--rpc` notifications (clients page with `units/read` after `next_line`), and a server-side follow.
- Sorting / filtering keys in the panel, per-thread CPU, GPU / network stats, CPU% normalised by cores.
- "Always allow" in the unit dialog; editing rules from the panel.

---

## H3e-1 — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H3 ("… `AGENTS.md` discovery"); the first slice of [H3e](#roadmap-h3bh3e). It lets cl-stack-code use the agent configuration that [lisp-workspace](https://github.com/egao1980/lisp-workspace) (`<workspace>/.lisp-workspace`: `AGENTS.md`, `CLAUDE.md`, `skills/`, `rules/`, `plugin/context.md`) writes for Claude Code. The harness could not see four parts of it before: `@` imports (`CLAUDE.md` is `@AGENTS.md`), Agent Skills, path-scoped rules and the plugin context file.

Contract: branch `agent/h3e1-contract-d2ef` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.12.0** (ACP-2 is 0.11.0 and lands first). The rules are in the headers of `src/imports.lisp`, `src/skills.lisp`, `src/rules.lisp` and `src/instruction-sets.lisp`.

**Changed 2026-11-22, before the implementation started: the instruction set is revisioned.** The first version of this contract kept the loaded path-scoped rules as a per-turn `:rules` list in the turn records plus `session-loaded-rules`. The user's direction: "Rewind: rules are part of instruction set, same as mcps, skills etc. We can have revision based in-memory store." So the **instruction set** (the instruction files with their expanded imports, the contextFiles, the skills index, the rules and the rules loaded so far, and H3e-2's MCP servers) is now one revisioned thing, kept in revision-protocol's in-memory store as the conversation (H3c) and the files (H5b) are, and restored by rewind, fork and resume together with the conversation. The rows marked **(instruction set)** below replace the old "Once per session" record rule; `record-rules` and `session-loaded-rules` are gone. The team-solve run had not reached the solver, so nothing implemented is lost.

**Order:** [steer-protocol#5](https://github.com/egao1980/steer-protocol/issues/5) comes first and ships as steer-protocol **0.4.0**: SKILL.md frontmatter decoded by `yaml-protocol`, because today's line parser turns `description: >-` into `">-"` and drops block lists. The implementation then requires `(:version "steer-protocol" "0.4.0")`. It runs through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

```
.lisp-workspace/CLAUDE.md          @AGENTS.md            → AGENTS.md inside CLAUDE.md's block
.lisp-workspace/skills/rove/SKILL.md                     → "- rove: Rove quick ref …" in # Skills; skill {"name":"rove"}
.lisp-workspace/rules/cl-stack-conditions.md  paths: ["**/*.lisp"]  → injected the first time a tool reads src/x.lisp
cl-stack-code --context-file ~/w/.lisp-workspace/plugin/context.md   (the lisp-workspace launcher)
{"type":"system","subtype":"init",…,"instructions":[…],"imports":[{"path":…,"from":…}],"skills":[…],"rules":[…],"notes":[…]}
```

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code memory ([code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory), read 2026-11-22) | `@path` imports. Paths are relative to the importing file, and absolute or `~/` paths are allowed. "A maximum depth of four hops". "Import parsing skips Markdown code spans and fenced code blocks". The path ends at the first space, a backslash escapes a space, and a quoted path is not imported. Imports load together with the importing file. `.claude/rules/**/*.md` with `paths:` (a YAML list or a comma-separated string) loads "when Claude uses the Read, Write, or Edit tool on a matching file". A rule without `paths` is always loaded. `~/.claude/rules/`. A file loaded both directly and through an import is read once | The external-import approval dialog (H3e project trust), HTML comment stripping, `CLAUDE.local.md`, `.claude/CLAUDE.md`, `claudeMdExcludes`, nested `.claude/rules` in subdirectories, Bash `cat` counting as a read |
| Claude Code skills ([code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)) | Descriptions are in context and bodies load on use. `Skill(name)` permission rules. Duplicate names follow a precedence | Personal over project precedence (ours is project first, decision 2 below), `/name` invocation, `allowed-tools`, `disable-model-invocation`, nested skill directories, plugins, re-attaching after compaction |
| [agentskills.io](https://agentskills.io/) specification | `<dir>/<name>/SKILL.md`, YAML frontmatter with `name` (lowercase letters, digits and hyphens, at most 64 characters, equal to the directory name) and `description` (required, at most 1024 characters) | `license`, `compatibility`, `metadata` and `allowed-tools` are read but not used |
| H3a (this product) | Instruction files are found one per directory from the project root down to the cwd, plus the user file. Each is cut at 32 000 characters. Nested `AGENTS.md` files are discovered lazily through ai-agent-protocol's instruction discovery (steer-protocol's `instruction-discovery`) | — |

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Import syntax** | An import is an `@` that starts a line or follows whitespace, followed by a path. The path runs to the next unescaped whitespace, and `\ ` is a space. A path that starts with `"` or `'` is not an import, and neither is a lone `@`. `a@b.c` (an email) is not an import. Only **text inlines** of `markdown-protocol:parse-markdown` are scanned. Code spans, fenced code blocks and link destinations are skipped. `~/…` is the user's home. An absolute path is taken as written. Anything else is relative to the **including file's directory**. Distinct imports keep their order of appearance | Claude Code's documented rules. markdown-protocol (already loaded through tui-markdown) is the stack's CommonMark parser, so code spans and fences come from the parser and not from a new scanner |
| **Expansion** | Inside the including file's `<instructions path="…">` block, each import becomes `<import path="NATIVE">` LF text LF `</import>`, in token order and **before** the including file's own text. The `@token` stays in the text. Imports nest: an imported file's imports are expanded the same way, inside its `<import>` block. A file appears at most once per prompt: a later import of it, or of a top-level file shown earlier, becomes a note | Without source positions from the parser an import cannot replace its token. Putting imports first matches Claude Code's `@AGENTS.md` pattern: "Claude reads the imported file first, then the rest" |
| **Depth and cycles** | The instruction file is hop 0. Imports expand up to **hop 4**, as in Claude Code's "four hops", which is five files in a chain. A file already on the current chain gives the note `import cycle`, once at the import that closes the cycle, and the chain stops there | The documented limit. The chain is the cycle check, so a cycle is noted once and never looped |
| **Notes in the prompt** | In place of an `<import>` block the prompt gets one line: `[import not found: @TOKEN (NATIVE)]` (a missing or unreadable file, or a directory), `[import cycle: @TOKEN (NATIVE) is already being included]`, `[import already included: @TOKEN (NATIVE)]`, `[import not expanded: @TOKEN (NATIVE) is more than 4 hops deep]`, `[import outside the project not expanded: @TOKEN (NATIVE)]`. Each note also goes to the context's notes as `INCLUDING-NATIVE: <the text inside the brackets>`. None of them is an error | The model and the user both see why a file is missing. A bad import never stops a run |
| **External imports** | A **project** instruction file (the per-directory chain) may import only files under the project root, or under the top-level file's own directory when there is no project root. Anything outside gets the "outside the project" note. **User-scope** files (the user `AGENTS.md` and `contextFiles`) may import any path. H3e's project trust will add the approval that lets a project import more | Claude Code shows an approval dialog for external imports in project files. Without one, a cloned repository could pull `@~/.ssh/config` into the prompt that goes to the provider |
| **Truncation** | `+max-instruction-chars+` (32 000) applies to **each file's own text before expansion**: top-level files and imported files alike, with the H3a `[truncated: …]` line. Imports are scanned in the kept text only. There is no limit across the expanded tree | Claude Code counts "each CLAUDE.md, rules file, and `@path` import" as a separate file. One shared limit would let a large import cut off the text of the file that imports it |
| **One file per directory** | Unchanged: AGENTS.md, else CLAUDE.md, per directory, with blank files skipped. A `CLAUDE.md` that is only `@AGENTS.md` and sits next to an `AGENTS.md` is never read | H3a's rule. Imports apply to whichever file is chosen |
| **contextFiles** | `"contextFiles": ["/abs/file.md", "~/f.md"]` and `--context-file PATH` (repeatable) add user-scope instruction files. They come after the user `AGENTS.md` and before the project chain, in order. A missing file gives the note `context file not found: NATIVE`. A file that is also in the chain appears once, at its first place. The values must be absolute or start with `~/`, else `settings-error` with the key path `contextFiles[i]` (for a flag, `code-usage-error`) | This is how the lisp-workspace launcher (`scripts/cl-stack-code.sh`) passes `plugin/context.md` to projects outside the workspace |
| **No automatic plugin context** | `.lisp-workspace/plugin/context.md` is **not** read just because the project has `.lisp-workspace/` | `context.md` is a condensed copy of lisp-workspace's `AGENTS.md`. A workspace that has `.lisp-workspace/` already gets `AGENTS.md` through its root `AGENTS.md` / `CLAUDE.md` (`@.lisp-workspace/CLAUDE.md`), so reading `context.md` too would put the same rules into context twice. A project that wants it writes `@.lisp-workspace/plugin/context.md` |
| **Skill roots, in precedence order** | (1) `<project>/.cl-stack-code/skills/` "project", (2) `<project>/.claude/skills/` "claude", (3) `<project>/.lisp-workspace/skills/` "lisp-workspace" (when that directory exists), (4) `<user-config-dir>/skills/` "user", (5) each `skillDirs` entry "setting", in order. `<project>` is the project root, else the cwd. Roots that do not exist are skipped silently, except a `skillDirs` entry, which gives the note `skill directory not found: NATIVE` | The coordinator's order. The project's own skills win over shared ones |
| **skillDirs and contextFiles layers** | Both are read from the **user file and the flag layer only**, like `sandbox.*`. In the project and local files they are dropped. The user and flag lists are concatenated and duplicates dropped | Both point outside the repository. A cloned project must not be able to say "also read `~/notes/`": the project's own skills and instructions already live in `.cl-stack-code/`, `.claude/` and its instruction files |
| **Skill format** | A skill is `<root>/<name>/SKILL.md` (one level; symlinked directories are followed), read with **`steer:load-skill`** (steer-protocol 0.4.0: YAML through yaml-protocol; cl-stack-code parses no YAML). `name` must be present and match `[a-z0-9]+(-[a-z0-9]+)*`, at most 64 characters, equal to the directory name. `description` must be a non-empty string. Otherwise the skill is skipped with the note `skill at NATIVE-SKILL.md: REASON` (`no frontmatter`, `bad frontmatter (…)`, `name is missing`, `name "X" is not lowercase letters, digits and hyphens (at most 64)`, `name "X" does not match its directory "Y"`, `description is missing`) | agentskills.io's rules. One parser in the stack |
| **Duplicates** | Duplicates are resolved in root order and **the first wins**. A later skill with the same name gives the note `skill NAME at LATER-NATIVE is shadowed by FIRST-NATIVE`. The same file (equal truenames) reached through two roots counts once, with no note: in lisp-workspace, `.claude/skills/*` are symlinks into `.lisp-workspace/skills/` | First-wins precedence needs no policy or logic engine (decision **Rules and logic** below) |
| **Listing** | After the instruction blocks and the always-on rule blocks comes the section `# Skills` LF `+skill-listing-preamble+` LF, then one line per skill: `- NAME: DESCRIPTION`. The description has its whitespace runs collapsed to one space and is trimmed. Past `+max-skill-description-chars+` (1024) it becomes its first 1023 characters plus `…`. The lines appear in precedence order, and inside one root by name. Lines are added while their total stays within `+skill-listing-budget+` (8000 characters). After that, skills are listed as `- NAME` lines while those fit, and the last line is `(N more skills not listed; the skill tool names them all)`. No skills means no section | Bodies load on demand. The listing stays a bounded part of every request |
| **`skill` tool** | It is offered (last in the source list: `(file shell [lisp] units skill)`) only when at least one skill was found and no `skill` deny-all rule hides it. Arguments: `name` (required) and `path` (optional, relative to the skill directory). Result for `name`: `<skill name="NAME" directory="NATIVE-DIR">` LF body LF `</skill>`. Result for `name` plus `path`: `<skill-file name="NAME" path="NATIVE">` LF text LF `</skill-file>`. An unknown name gives the tool error `no skill named "X"; skills: a, b, c`. A path that leaves the directory gives `PATH is outside the skill directory NATIVE-DIR`. A missing file gives `no file PATH in skill NAME`. The skill's own files never trigger instruction discovery (`tool-instruction-paths` is NIL) | The file tools are confined to the project root, while skills often live elsewhere (the user directory, `skillDirs`). The skill tool reads inside its own directory, so the read tool's root confinement stays intact |
| **Skill permission** | The rule action is `skill`, and its resource is the skill name, so `skill(rove)` and `skill(cl-*)` work. The tool never needs approval, so it is **allowed in every mode, plan included**, because it only reads. Deny rules apply: `skill(deploy)` denies one skill, and a `skill` deny rule hides the tool | Same as `Skill(name)` in Claude Code. A read-only tool needs no ask in plan mode |
| **Rule roots** | `<project>/.cl-stack-code/rules/`, `<project>/.claude/rules/`, `<project>/.lisp-workspace/rules/`, `<user-config-dir>/rules/`, each searched recursively for `*.md`, in that order and by relative path inside a root. Equal truenames count once (the first is kept). Rules have no names, so every file loads and there is no precedence | Claude Code finds rules recursively and loads all of them. lisp-workspace's `.claude/rules/*` are symlinks into `.lisp-workspace/rules/` |
| **Rule format** | Frontmatter is optional and is read with `steer:load-skill … :kind :rule`. `paths` is a list of glob strings or one comma-separated string. Every other key is ignored (lisp-workspace's Cursor keys `globs` and `alwaysApply` included). A rule without `paths`, or with an empty `paths`, is **always on**: its text goes into the system prompt as `<rule path="NATIVE">` LF body LF `</rule>`, after the instruction blocks. Bad frontmatter skips the rule with the note `rule at NATIVE: REASON` | Claude Code's format |
| **Globs** | A pattern is matched against the file's path **relative to the project directory** (the project root, else the cwd), in POSIX form, with **`cl-stack-pathlib:match-p`** anchored at that directory (`"/" + relative path` against `"/" + pattern`). That gives pathlib globs: `*`, `?`, `[…]`, and `**` for any number of directories. A file outside the project directory never matches | This is the stack's one glob matcher, so cl-stack-code adds none (issue #24 already lists its exponential `%glob-match-p`) |
| **Lazy loading** | `make-code-instruction-discovery` makes a `code-instruction-discovery`, a subclass of `steer:instruction-discovery`, and uses it in place of today's discovery in `%agent-settings`. For the paths that finished tool calls name (ai-agent-protocol's `tool-instruction-paths`, the same paths that trigger nested `AGENTS.md`), it returns the nested `AGENTS.md` directives as before, and then each path-scoped rule that matches and is **not yet loaded in this session**, in rule order. A rule's directive has its native path as its name, `", "`-joined patterns as its scope and the body as its body. ai-agent-protocol injects them as one user turn (`steer:compile-instructions`): `<instructions path="NATIVE" scope="**/*.lisp">` LF body LF `</instructions>` | This reuses the nested `AGENTS.md` mechanism with no second injector |
| **Once per session** | The loaded set belongs to the session, not to one run: the copies that ai-agent-protocol makes for each run **share** it (`copy-instruction-discovery` is specialized). It is the live state of the instruction set's `:rules` component (below): a resumed session's discovery is seeded from the loaded rules of its head's instruction-set revision, and a rewind restores the set of the turn it goes back to, so a rule loaded later loads again on the next matching path. A compaction's `forget-instructions` removes the rules it drops (and commits the set) until H3f re-injects them instead | The rule text is already in the history that is replayed, so injecting it again would only add a duplicate |
| **Instruction set (instruction set)** | One revisioned value per session: the instruction files with their expanded imports and content hashes, the contextFiles list, the skills index, every rule found with the loaded ones, and later H3e-2's MCP servers and their tools. Kept as revisions of an **`instruction-store`**, a `revision-protocol` `in-memory-store` (pinned revision-protocol 0.4.0) per session store (`session-instruction-store`). A process works on an **`instruction-set`** over it: its components, its current revision id | The user's direction. The conversation (H3c) and the files (H5b) are already revisions; the third thing the model sees should be one too, not a side list in the records |
| **Components (instruction set)** | The set is made of **components** behind three generic functions: `(component-role c)` → a keyword unique in the set, `(component-snapshot c store)` → the state now as data (strings, integers, keywords, T, NIL, lists; long texts through `intern-instruction-text`), `(component-restore c snapshot store)` → make the live state equal the snapshot. `instruction-set-components` (a GF) lists them in registration order; `add-instruction-component` registers one (a duplicate role → `instruction-set-error`). Built-in, in this order (`+instruction-set-roles+`): `:instruction-files`, `:context-files`, `:skills`, `:rules`; the snapshot formats are in the header of `src/instruction-sets.lisp`. A restore skips components whose role the revision lacks and ignores roles without a component | **H3e-2 adds `:mcp-servers` with one `add-instruction-component` call where it connects the servers and calls `commit-instruction-set` when a server is added, removed or reconnected or its tool list changes**; nothing in H3e-1's code changes |
| **Revisions and ids (instruction set)** | `commit-instruction-set set reason` → `(values id new-p)`. Content `(:instruction-set 1 :components ((:role R :snapshot S) …))` in component order; id = the 64 hex digits of sha256 (pathlib's `octets-hash`) of the UTF-8 of the content printed as H3c prints its files. **Content-addressed:** an unchanged set is the same revision however often it is committed (`new-p` NIL, nothing committed), and a set that returns to an earlier state gets that state's id back. Revisions are roots (`:parents ()`); message `instructions: <reason>`, provenance `(:kind :instructions :reason R :version V)`. Commits: `:start` (a new session; it also sets the store's ref `start`), `:resume` (a continued session re-reads the disk: an edited instruction file, skill directory, rule or contextFiles list gives a new revision, an unchanged one the head's id), `:rule` (one per `discover-instructions` call that loaded rules), `:forget`, `:component` (H3e-2). Each **turn record** names the revision current at its end: `record-instructions`, content key `:instructions` (present only when set, so older records read unchanged) | Ids that are content hashes are stable across processes, forks and machines, need no counter, and give "unchanged sets share one revision" for free. Parents would make the id depend on history, which the turn records already carry |
| **Durability (instruction set)** | **A sidecar next to the session**, `<session dir>/instructions/`: `revisions/<id>.sexp` (H3c's revision file format), `texts/<hex>` (the UTF-8 of each interned text: instruction blocks, rule bodies), `refs/start`. **Persist on reference:** a commit writes nothing; the session's next write (`commit-turn`, a head move, `clone-session`) first writes, under the session's lock, every revision, text and the start ref not yet on disk, so a record is never on disk without the revision it names and a program started and quit leaves nothing. Files are immutable and content-addressed (two processes write identical bytes). **Resume re-hydrates** the memory store from the revision files (texts on demand); a revision whose content does not hash to its name, or a text that does not match its hash, is a `session-error` / `instruction-set-error` | Not inside the turn records: a set that many turns share is stored once, and the record stays one id. The same directory rules as `checkpoints/` (H5b), so nothing new to learn |
| **Rewind, fork, resume (instruction set)** | **Conversation-coupled, no mode of its own.** Whenever this process moves the session's head (`rewind-to`'s conversation part, H3c's `/rewind`, `/fork` at an earlier turn, the SDK's rewind), it calls `restore-instruction-set` with `session-instruction-set` of the new head (the start revision for no head or `"0"`) before the next model call: rules loaded after that turn are no longer loaded and load again lazily on a matching access; the system prompt is rendered from the revision's stored texts (`instruction-set-blocks`), so the next call sees exactly the set of turn N. A files-only rewind leaves the set alone. **Fork into a new session** (`--fork-session`, `/clone`, the SDK's fork, a conflict fork): `clone-session` copies the instruction revisions the copied records name, the start ref and their texts. **Resume** re-reads the disk (as H3a: every process assembles the prompt again) with the head revision's loaded rules, and commits `:resume` | A loaded rule's text lives in the conversation's history. Moving the instruction set without the conversation would either drop a rule whose text is still in the history (a duplicate when it loads again) or keep one whose text is gone. So the two parts move together, and `--rewind-mode` keeps its three values |
| **Checkpoints (instruction set)** | Each new H5b checkpoint's manifest gets an **`:instructions` part**: kind `:instruction-set`, revision `session-instruction-set` of the conversation part (of `"0"` without one), `depends-on (:conversation)` when there is a conversation part, store = the session's instruction store (also when read back). On disk `(:role :instructions :kind :instruction-set :revision ID :depends-on (:conversation))`. Absent when that id is NIL, so checkpoints of records written without the wiring (and every older one) read unchanged. `checkpoint-instructions-id`; `+checkpoint-roles+` gains `:instructions` | The plan's composite revision: one part per role, here the third thing a checkpoint restores. It is derived from the conversation part and restored with it |
| **Compaction (H3f)** | H3f re-injects the loaded rules after a compaction from the **current revision** (`instruction-text` of their `:text` hashes; the set does not change) instead of `forget-instructions`. Until then a forget commits `:forget` | The revision already holds the rule texts, so a compaction needs no disk read and cannot pick up an edited rule mid-session |
| **Init event** | `system`/`init` gains `"imports"` (`[{"path","from"}]`, the expanded ones, in prompt order), `"skills"` (`[{"name","description","path","source"}]`, the winners in listing order, `path` = SKILL.md), `"rules"` (`[{"path","paths": [...] or null,"loaded": bool}]`, every rule found; always-on rules and the rules seeded from the session are `true`) and `"notes"` (strings), and **`"instruction_set"`** (the id of the set's current revision after the `:start` or `:resume` commit). These keys are always present, with empty arrays when there is nothing. `"instructions"` stays the native paths of the top-level files and now includes context files. -p, the SDK and `--rpc` share `%system-init-keys` | Tests and users can see what the model got without `--verbose` |
| **instructions event** | When a run injects lazily discovered instructions, -p stream-json, the SDK and `--rpc` emit `{"type":"instructions","files":[{"path":NATIVE,"kind":"agents"|"rule"}],"instruction_set":ID}` (ID: the revision after the load, which the turn then ends on unless more loads follow) after the triggering tool results and before the next model call. `+event-types+` gains `"instructions"` before `"unit"` | Lazy loads are visible too |
| **TUI** | At startup each note is added to the transcript as a notice (`(:notice "note: …")`), once | The interactive user sees shadowed skills and broken imports |
| **Rules and logic** | **Not needed.** Precedence here is either first-wins over a fixed root order (skills) or none at all (every rule loads, and files are deduplicated by truename). Rule selection is glob matching. No layered allow/deny or state-dependent rule exists in this slice, so nothing goes through policy-protocol or logic-protocol. The `skill` permission is an ordinary ai-agent-protocol rule. The instruction set adds none either: components are a fixed registration order, identity is a content hash, and a restore copies a snapshot back. `/tree` is unchanged (a 64-hex id per row is noise; the records, the init and instructions events and the checkpoint part carry the id) | Per the rules-and-logic rule: no new hand-rolled precedence code, because no precedence logic is introduced |
| **Stubs** | `%h3e1-pending` (`src/package.lisp`). **Given:** conditions (`skill-format-error`, `rule-format-error`), constants, settings keys and `--skill-dir` / `--context-file`, `instruction-files :context-files`, the `instruction-context` class and its readers, the `skill-tools` and `code-instruction-discovery` classes, the record's `instructions` slot and its content round trip, `"instructions"` in `+event-types+`; and in `src/instruction-sets.lisp` the constants, the component GFs, the `instruction-store` and `instruction-set` classes and readers, `instructions-directory`, `instruction-set-error`, the session store's `instructions` slot, the checkpoint struct's `instructions-id` and `:instructions` in `+checkpoint-roles+`. **Stubbed:** every function in `src/imports.lisp`, `src/skills.lisp`, `src/rules.lisp` and `src/instruction-sets.lisp` beyond those. **Left to the implementation:** the wiring into `assemble-system-prompt` (`:context`, `:instruction-set`), `make-code-tools`, `%agent-settings`, `%system-init-keys`, the turn records, the sidecar writes in the session's write path and `clone-session`, re-hydration in `sync-session`, the checkpoint part, the restores on head moves, the program and the client. Old paths never reach a stub | — |

### Surface (new in 0.12.0)

```lisp
;; imports (src/imports.lisp)
(import-tokens text) → ("AGENTS.md" "~/x.md" …)          (resolve-import token from &key home) → pathname
(instruction-block path &key home boundary user-scope seen) → (values block imports notes)
+max-import-hops+  ;; 4
;; context
(load-instruction-context cwd &key settings user-config-dir home session-rules) → instruction-context
instruction-context  context-files context-imports context-skills context-rules context-notes
context-project-dir context-loaded-rules
(instruction-files cwd &key user-config-dir context-files)          ; :context-files new
(assemble-system-prompt cwd &key … context) → (values prompt files context)
;; skills (src/skills.lisp)
(skill-roots cwd &key settings user-config-dir) → ((dir . source) …)
(parse-skill-file path) → steer-directive   ; or skill-format-error
(discover-skills cwd &key settings user-config-dir) → (values skills notes)
(skill-directory skill) (skill-source skill) (skill-listing-section skills) → string or NIL
(make-skill-tools skills) skill-tools skill-tools-p skill-tools-skills (code-skill-tools sources)
(skill-tool-result skill &optional path)
+skill-tool-name+ +skill-source-names+ +skill-listing-budget+ +max-skill-description-chars+
+skill-listing-preamble+
;; rules (src/rules.lisp)
(rule-roots cwd &key user-config-dir) (parse-rule-file path) → steer-directive  ; or rule-format-error
(discover-rules cwd &key user-config-dir) → (values rules notes)
(rule-patterns rule) (rule-always-p rule) (rule-matches-p rule path project-dir) (rule-block rule)
(make-code-instruction-discovery cwd &key rules project-dir loaded) code-instruction-discovery
(discovery-loaded-rules discovery) → native strings, load order
;; settings and sessions
settings-skill-dirs settings-context-files   (make-settings … :skill-dirs :context-files)
record-instructions (make-turn-record … :instructions)
;; the instruction set (src/instruction-sets.lisp)
(component-role c) (component-snapshot c store) (component-restore c snapshot store)   ; GFs
(instruction-set-components set)                                                       ; GF
instruction-store (rev:in-memory-store) instruction-store-p instruction-store-session
(session-instruction-store session) (instructions-directory session)
instruction-set instruction-set-p instruction-set-store instruction-set-current
(make-instruction-set store &key context discovery) (add-instruction-component set c)
(commit-instruction-set set reason) → (values id new-p)   (restore-instruction-set set id) → id
(read-instruction-set store id) → ((role . snapshot) …)   (instruction-set-id content) → 64 hex
(instruction-set-blocks store id) (instruction-set-loaded-rules store id)
(intern-instruction-text store string) → "sha256:…"   (instruction-text store hash)
(session-instruction-set session &optional designator) → id or NIL
+instruction-set-format+ +instruction-set-roles+ +instruction-set-reasons+ +instruction-start-ref+
checkpoint-instructions-id   (assemble-system-prompt … :instruction-set set)
;; conditions (code-error)
skill-format-error skill-format-error-path skill-format-error-reason
rule-format-error rule-format-error-path rule-format-error-reason
instruction-set-error
```

### Contract tests

`cl-stack-code/tests` grows by 7 files (one of them helpers), with **97 new deftests (139 cases with the parametrized rows)**: `imports-test`, `skills-test`, `rules-test`, `instruction-sets-test`, `h3e1-cli-test` (-p, stream-json, resume, rewind, fork, checkpoints), `h3e1-client-test` (the SDK, the TUI note), and `h3e1-support`. They cover:

- **Imports:** relative, home, nested, cycle, missing, code-span and fenced-block exclusion, emails and quotes, escaped spaces, the depth limit, duplicates, external imports, and the truncation rule.
- **Skills:** discovery order and precedence, frontmatter parsing (folded `>-`), bad frontmatter skipped with a note, the system prompt listing and its budget, the `skill` tool results and errors, the default permission in every mode, a deny rule, and `skillDirs` from the user file versus the project file.
- **Rules:** always-on versus path-scoped, lazy loading on read, edit and write of a matching path, loading once per session, a path that does not match, and the loaded set surviving resume.
- **The instruction set:** a fake component's commit and restore, the revision's content, id (the sha256 of the printed content, recomputed in the test), message and provenance, content-addressed sharing (unchanged, back to an earlier state, another session), component order and duplicate roles, a role a revision lacks, non-data snapshots, texts; the sidecar (nothing before the session's first write, the revision, text and start ref files read independently), re-hydration on open, tampered revisions and texts; `session-instruction-set` along a line and at `"0"`; `clone-session` copying only what the copied records name; the built-in components' snapshots from a context; `instruction-set-blocks` equal to the system prompt's blocks and unchanged after an edit on disk; a linked discovery committing on load and forget, a restore dropping a later rule that then loads again lazily; end to end: the init and instructions events' ids, resume giving the head's revision back, a `--rewind` to before the load (the rule loads again, once in the request), `--fork-session` copying the revision, the checkpoint's `:instructions` part in memory and on disk, and the SDK's rewind restoring the set in the same process.
- **contextFiles** and the **init event** contents.
- **The lisp-workspace fixture:** root `CLAUDE.md` `@.lisp-workspace/CLAUDE.md`, which holds `@AGENTS.md`, plus `.lisp-workspace/skills/rove/SKILL.md`, `.lisp-workspace/rules/lisp.md` (`paths:` list, comments, Cursor keys) and `plugin/context.md`, which must not be read. With the mock LLM: the prompt, the skill call and the rule loaded on read.

Old suites change only where 0.12.0 changes them: the version checks expect 0.12.0.

Run locally on macOS against the stubs: 126 of the 139 new cases fail, each on `%h3e1-pending` or on wiring that is not there yet. 13 pass on given code: the settings keys and flags (7), the record's `:instructions` round trip, `+event-types+`, and three guards that already hold (a path that does not match, a deny rule, no automatic plugin context), plus the bad `--context-file` flag. The 940 old cases pass (git 2.56, `ros dynamic-space-size=4096`, issue #18). The `:rules` record and `session-loaded-rules` tests are replaced by the instruction-set ones. The systems load with no new warnings. No throwaway prototype was run, so the implementation may find test bugs. Those go through a contract-fix commit, as before.

### Non-goals (H3e-1)

- Approving external imports (H3e project trust), `CLAUDE.local.md`, `.claude/CLAUDE.md`, HTML comment stripping, `claudeMdExcludes`.
- `/name` skill invocation, prompt templates, `allowed-tools`, `disable-model-invocation`, plugins, nested skill or rule directories in subdirectories, and re-attaching skills after compaction.
- Rules triggered by shell reads (`cat`), and rules for plan-mode area paths (nested `AGENTS.md` does not cover those either; both follow H5's area mapping).
- Live reload of skills or rules changed during a session (a continued session re-reads them; a later slice may commit `:component` from a watcher).
- An instruction-set part rewound on its own (`--rewind-mode` stays conversation / files / both), and garbage collection of unreferenced instruction revisions (they are small and content-addressed).

---


## H3e-2 — locked

**Plan row:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) Track H, row H3; the MCP part of [H3e](#roadmap-h3bh3e) (H3a had "MCP servers, hooks, subagents" out of scope). cl-stack-code runs stdio MCP servers, connects to streamable-HTTP ones, and offers their tools to the model, with the configuration files Claude Code already reads: lisp-workspace's and cl-stack-sample's `.mcp.json` work unchanged.

The slice is split, because the whole of it did not fit one honest contract:

- **H3e-2a** (this contract, version **0.13.0**): configuration and trust, stdio and HTTP transports, supervised server units, prefixed tools, permissions and plan mode, result mapping, error behaviour, cached tool lists, timeouts, `/mcp`, the init event, `mcp/list` / `mcp/reconnect`, and the SDK entry ACP-2 calls.
- **H3e-2b** (later): sampling, elicitation, server instructions in the prompt, deferred tool loading, roots, resources and prompts, deferred approvals for `-p`. See [Later](#later-h3e-2b).

Contract: branch `agent/h3e2-contract-74d3` of [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code), version **0.13.0**. ACP-2 (0.11.0) and H3e-1 (0.12.0) land first.

**Follow-up (2026-11-22, H3e-1's instruction set):** the MCP server set and the servers' tool lists are part of the session's revisioned **instruction set** ([H3e-1](#h3e-1--locked), rows marked "instruction set"). H3e-2 adds an `:mcp-servers` component through H3e-1's protocol and changes no H3e-1 code: a class with methods on `component-role`, `component-snapshot` and `component-restore`, registered with `add-instruction-component` on the session's `instruction-set` where the manager connects the servers, and `commit-instruction-set set :component` after a server is added, removed or reconnected, or a list_changed refreshed its tools. The snapshot is data, e.g. per server `(:name :scope :transport :status :tools ((:name N :sha256 H-of-the-tool-JSON) …))`; what `component-restore` does on a rewind (filter the offered tools to the revision's, reconnect, or only report a difference) is H3e-2's decision and gets its own tests. The init event's `"instruction_set"` then covers the servers too. The H3e-2 contract ([cl-stack-code#33](https://github.com/egao1980/cl-stack-code/pull/33)) adds this component and its tests before its implementation starts. The rules are in the headers of `src/mcp-config.lisp` (configuration, layers, `${VAR}`, trust, timeouts) and `src/mcp.lisp` (connections, transports, tools, permissions, visibility, SDK and RPC). The implementation runs through **team-solve** (`.team-solve/task.md`: `system: cl-stack-code`, `test-system: cl-stack-code/tests`, this brief).

**Order.** The harness reimplements nothing, so the stack fixes come first. Implement, merge and publish each, in this order:

| # | Repo, issue | Ships as | What | Contract |
|---|-------------|----------|------|----------|
| 1 | [mcp-protocol#14](https://github.com/egao1980/mcp-protocol/issues/14) | **mcp-protocol 0.4.0** | The client keeps every tool field (annotations, title, outputSchema, icons, `_meta`), `list-tools` returns `nextCursor`, `list-all-tools`, server notifications and requests reach the client (`mcp-client-transport-handlers`, list_changed generation and hook, log and progress handlers), `call-tool :timeout` with `notifications/cancelled` | [mcp-protocol#15](https://github.com/egao1980/mcp-protocol/pull/15) (draft; brief [mcp.md](mcp.md#040--the-client-side-for-hosts-locked)) |
| 2 | [ai-agent-protocol#37](https://github.com/egao1980/ai-agent-protocol/issues/37) | **ai-agent-protocol 0.15.0**, **ai-agent-protocol/mcp 0.2.0**, new **ai-agent-protocol/policy** | Tool-source combinators (wrapper, combined, prefixed, renamed, filtered, prepared, approval-required; predicates are functions or policy-protocol policies), `agent-tool-output` (text, image parts, structured content) through the loop, and the MCP tool source (cached list, visibility, result mapping, `tool-error-behavior`, `process-tool-call`, timeouts) | [ai-agent-protocol#38](https://github.com/egao1980/ai-agent-protocol/pull/38) (draft; brief [ai-agent.md](ai-agent.md#0150--tool-source-combinators-locked)) |
| 3 | [mcp-backend-stdio#7](https://github.com/egao1980/mcp-backend-stdio/issues/7) | mcp-backend-stdio **0.3.0** | Wire `mcp-client-transport-handlers` into the transport (`:dispatch :concurrent`), pass the client's handlers | issue only |
| 4 | [mcp-backend-streamable-http#9](https://github.com/egao1980/mcp-backend-streamable-http/issues/9) | mcp-backend-streamable-http **0.4.0** | `:headers`, SSE notifications to the client, `mcp-transport-unsupported` for legacy HTTP+SSE | issue only |
| 5 | [supervisor-protocol#13](https://github.com/egao1980/supervisor-protocol/issues/13) | supervisor-protocol **0.5.0** | Channel units: stdin and stdout handed to the caller, stderr in the unit log | issue only |

Rows 3–5 are small and have no contract branch yet; each issue states its tests. cl-stack-code's `.asd` names today's published versions so the contract loads. The implementation raises them to the rows above.

```
cl-stack-code -p "list the systems" --output-format stream-json     # .mcp.json + user servers
cl-stack-code --mcp-config ci-servers.json --strict-mcp-config -p "…"
cl-stack-code                                                        # /mcp, /mcp reconnect lisp
→ {"jsonrpc":"2.0","id":3,"method":"mcp/list","params":{"session_id":"3f9a…"}}
```

### Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Claude Code (code.claude.com/docs/en/mcp, read 2026-11-22) | `.mcp.json` and the `mcpServers` object as written; `command` / `args` / `env`, `type: http \| sse` (alias `streamable-http`) with `url` / `headers`; `${VAR}` and `${VAR:-default}` in command, args, env, url and headers, an empty value counting as set; project servers need approval: `enableAllProjectMcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers` (disabled wins, from any file); `--mcp-config` (repeatable, a file or JSON text) and `--strict-mcp-config`; `MCP_TIMEOUT` (startup) and `MCP_TOOL_TIMEOUT`, per-server `timeout` as the tool timeout (values below 1000 ignored); the whole entry of the winning scope, no per-field merge; `mcp__<server>__<tool>` with other characters as `_`; `/mcp` | An unset `${VAR}` loading as literal text (an error here); a `url` without `type` being an error (inferred here); `ws`, `headersHelper`, `alwaysLoad`, OAuth, plugin and connector servers, managed servers; approvals in `~/.claude.json` per project (here `NAME@<project>` entries in the user settings); local scope over project over user (here the files' layer order) |
| pydantic-ai (pydantic.dev/docs/ai/mcp/client, …/tools-toolsets/toolsets) | Toolsets as composable sources (combined, prefixed, renamed, filtered, prepared, approval-required, wrapper), now ai-agent-protocol 0.15.0; `cache_tools` with list_changed invalidation and its caveat (modern servers notify only during a request, so caching can be turned off per server); `tool_error_behavior` retry / failed / error; `process_tool_call`; an error for an unset variable; the transport inferred from the URL; `disabled` | Deferred tool loading, sampling, elicitation and instructions (H3e-2b); `DeferredToolRequests` (Later) |
| H4b, H8d (this product) | The lisp-image tools beside MCP tools; supervised units, `/ps`, `units/*`; the init event growing a key only when the feature is in use | — |

### Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| **Where the code lives** | `src/mcp-config.lisp` (after settings) and `src/mcp.lisp` (after the unit panel). Small hooks: the `mcp` slot of `settings` and its parse / merge / layer lines in `src/settings.lisp`, two options in `src/arguments.lisp`, `state-mcp` / `state-mcp-prompt`, `/mcp` and three events in `src/interactive.lisp`, two methods and an error code in `src/rpc.lisp`. The exports sit in `src/mcp.lisp`, so the merges with ACP-2 and H3e-1 stay a few lines. | The other two contracts edit the same files in parallel. |
| **Dependencies** | `mcp-protocol` 0.4.0, `mcp-backend-stdio` 0.3.0, `mcp-backend-streamable-http` 0.4.0, `ai-agent-protocol` 0.15.0 with `ai-agent-protocol/mcp` 0.2.0, `supervisor-protocol` 0.5.0 (rows 1–5). All cl-stack. The tests need nothing new beyond them (`mcp-protocol`, `mcp-backend-streamable-http`, `http-protocol`), so they stay in `cl-stack-code/tests`, not a separate system. | Stack rule: the gaps are fixed in the stack, not around it. |
| **Configuration sources** | User settings `mcpServers` (scope `user`), `<project root or cwd>/.mcp.json` (`project`), project settings `mcpServers` (`project`), local settings `mcpServers` (`local`), each `--mcp-config` in order (`flag`), the SDK's `:mcp-servers` (`sdk`). The server object is Claude Code's, plus `disabled`, `startupTimeout`, `cacheTools`, `toolErrorBehavior`. Unknown keys are ignored. With no `type`: `command` → stdio (command wins over url); else a URL path ending in `/sse` → sse, else http. | Existing files just work; the extra keys are opt-in. |
| **Precedence (decided)** | **Per server, the last source wins**, whole entry, no per-field merge; the winner's scope decides its trust. `--strict-mcp-config` keeps only `--mcp-config` and SDK servers. Disabled servers stay listed. | One rule for every key, as the settings layers. Half a stdio entry over an http one means nothing, so entries are not merged (Claude Code does the same). |
| **`${VAR}`** | Expanded after the layers merge, through the effective environment (settings `env`, then the process). `${VAR:-default}` when unset; empty counts as set. Unset without a default → `settings-error` with the server's file, the key path (`mcpServers.srv.args[1]`) and "`${VAR} is not set (MCP server srv)`" (exit 2 before anything runs). | Claude Code's syntax; pydantic-ai's error, because a server started with a literal `${TOKEN}` fails late and obscurely. |
| **Errors** | Bad JSON, a non-object, a wrong type or a missing `command` / `url` signal `settings-error` with the file and the key path, as every settings key does. | One error shape. |
| **Trust** | `user`, `flag` and `sdk` servers are trusted. `project` and `local` servers start only when approved: `disabledMcpjsonServers` (any layer) → rejected; else `enableAllProjectMcpServers`, or an `enabledMcpjsonServers` entry (`NAME` or `NAME@<project dir>`) from the **user file or the flags** → approved; else unapproved. | A repository must not approve its own servers (the `sandbox` rule). Local settings live in the repository directory and can be committed, so they count as project files. A deny only takes away, so it counts from anywhere. |
| **Asking** | Headless `-p` never asks: an unapproved server is skipped, with a notice on stderr and `"status": "unapproved"` in the init event. The TUI asks once per server, at start (Yes, trust it in this project / No, never in this project / Not now). Yes and No are saved in the user settings as `NAME@<project dir>`; Not now saves nothing. The SDK and RPC never ask: their servers are trusted, and project servers follow the saved approvals. | Claude Code's behaviour; the answer is per project, as Claude Code keeps it. |
| **stdio transport** | A supervised **channel unit** of the session's supervisor: kind `mcp-server`, owner scope `mcp`, label `server`, the config's argv and env, cwd the session's directory. Stdin and stdout are the JSON-RPC pipes; stderr and the server's log notifications (`[mcp LEVEL] DATA`) go to the unit log. It shows in `/ps` and `units/*`. **Restart policy `:never`**: a restarted child has lost its MCP session, so the supervisor must not resurrect it behind the client's back; `/mcp reconnect` starts a new unit and a new client. | H8d's one supervisor per session; the logs stay readable after a crash. |
| **http transport** | mcp-backend-streamable-http with the config's headers on every request, over the run's `http-protocol:*http-backend*`, bound in the connecting thread. | Own stack HTTP. |
| **Legacy sse** | Reported per server as `"status": "unsupported"`, error "transport sse is not supported yet", and a notice. Never a crash. | No backend speaks the 2024-11-05 HTTP+SSE transport (mcp-backend-streamable-http#9). |
| **Lifecycle** | Servers connect at session start, in parallel, each bounded by its startup timeout: `startupTimeout`, else settings `mcpTimeout`, else `MCP_TIMEOUT`, else 30 s. A server that fails (spawn error, exit, initialize error, timeout) does not block the session: its tools are absent, its status and error are shown, `/mcp reconnect` retries it. The session's end closes every client and stops every unit, so stdio children are reaped (-p, `close-code-program`, `client-close-session`). | One bad server must not cost the session. |
| **Tool timeout** | `timeout` (per server, ms ≥ 1000), else `mcpToolTimeout`, else `MCP_TOOL_TIMEOUT`, else **10 minutes**; a timeout cancels the request (`notifications/cancelled`) and is a tool error. | Claude Code's keys. Its ~28 h default would let one hung server stall a headless run for a day. |
| **Tools and names** | One source after the unit tools: `(file shell [lisp] units mcp)`. Each connected server is `make-prefixed-tool-source` over `make-mcp-tool-source` with `mcp__<server>__`; other characters become `_`. Lists are cached and refreshed on list_changed (`cacheTools: false` per server turns the cache off). App-only tools (`_meta.ui.visibility` without `"model"`) are hidden. A reconnect or a list_changed changes the next step's tools. | Claude Code's names, so rules and habits carry over; ai-agent-protocol's combinators, so nothing MCP-specific lives in the product. |
| **Permissions** | Rules take the names and globs as any action: `mcp__lisp__*`, `mcp__lisp__repl-eval`, `mcp__*`; deny > ask > allow across layers; a deny with resource `*` hides the tool. **Default effect: ask.** **Allow by default only when the tool's `readOnlyHint` is true and its server is trusted** (user, flag, sdk). `-p` denies the ask, as for bash. | A hint is the server's own claim. It may lower the bar only for servers the user chose; a repository's "read-only" tool still asks until a rule allows it. |
| **Plan mode** | MCP tools are **denied** in plan mode (feedback `+mcp-plan-mode-feedback+`) unless read-only-and-trusted, or an allow rule names the tool. | A separate process or a remote host is outside the plan area: the sandbox cannot confine it and the projected diff cannot show its effects. An explicit allow is the user's informed choice. |
| **Results** | The model reads the text items (joined by LF; placeholders such as `[image image/png]` for the rest). Images reach the next model call as image parts (ai-agent-protocol 0.15.0's parts turn). The `tool_result` event gains `images` [{`media_type`, `data`}] and `structured` when present. `isError` → `status "error"`, `is_error` true, the server's text. `toolErrorBehavior` (`retry` default, `failed`, `error`) picks how an error result is recorded; transport and protocol errors are always tool errors of the harness, never "failed calls" of the server. | llm-protocol tool results are text; parts carry the rest without a provider change. |
| **Visibility** | Init event `"mcp_servers"`: [{`name`, `scope`, `transport`, `status`, `tools`, `error`, `unit`, `file`}], only when a server is configured; `"tools"` end with the MCP names. Stderr notices for unapproved, failed, unsupported and rejected servers. TUI `/mcp` lists servers, status and tools; `/mcp reconnect [NAME]`. | As H4b's `lisp_image`: old outputs are unchanged without servers. |
| **RPC (decided)** | Two methods, `mcp/list` {`session_id`} and `mcp/reconnect` {`session_id`, `server`?}, both → {`servers`: [...]}. `session/new` takes `mcp_servers` (an mcpServers object). Unknown server → `mcp-server-not-found`, -32020, data `server`. | The `units/*` pattern: a namespace per feature, the SDK underneath. |
| **SDK and ACP** | `client-new-session … :mcp-servers` (configs or a decoded mcpServers object; scope `sdk`, trusted), `client-add-mcp-servers session servers` (after start; a name already present is replaced), `client-mcp-servers`, `client-reconnect-mcp`. **ACP-2 maps `session/new` / `session/load` `mcpServers` (ACP's list of `{name, command, args, env}` / `{type: "http", name, url, headers}`) to an mcpServers object and passes it as `:mcp-servers`**, or calls `client-add-mcp-servers` for a loaded session. | The editor is the host; it chose those servers. |
| **Overlap with H4b** | A server running lisp-mcp (say `lisp`) offers `mcp__lisp__repl-eval` next to the built-in `repl-eval`. Both stay, under their distinct names; nothing is merged or hidden. **Use the built-in layer for Lisp work**: one image the product owns, debugger events in the inbox, `restart:` rules, plan-mode checks. Keep lisp-mcp in `.mcp.json` for Claude Code and other hosts. | Hiding a user's server would surprise; the prompt and docs point to the built-in layer. |
| **Stubs** | `%h3e2-pending` (`src/mcp-config.lisp`). **Given:** the config class and constructor, the settings slot and its merge and layer tagging, the flags, constants, `mcp-connection` / `mcp-manager` classes, `mcp-server-not-found`, `mcp-settings`, `mcp-server-trusted-p`, the core's state slots and routing, the RPC method names and error code. **Stubbed:** the parser, `.mcp.json`, expansion, `effective-mcp-servers`, approvals, timeouts, the manager and every runtime function, the views, `/mcp`, the SDK entry points. **Left to the implementation:** the wiring in -p, the program, the client sessions and the RPC handlers. Old paths never reach a stub. | — |

### Surface (new in 0.13.0)

```lisp
;; configuration (src/mcp-config.lisp)
mcp-server-config make-mcp-server-config  mcp-server-config-{name scope transport command args env
  url headers disabled-p timeout startup-timeout cache-tools tool-error-behavior file}
settings-mcp (mcp-settings s) → (values servers enable-all enabled disabled timeout tool-timeout files strict)
(parse-mcp-servers object &key file scope)  (mcp-json-path cwd)  (read-mcp-json path &key scope)
(expand-mcp-variables config env)  (effective-mcp-servers cwd settings &key user-config-dir sdk-servers env)
(mcp-server-trusted-p c)  (mcp-server-approval c settings &key project-dir) → :approved | :rejected | :unapproved
(save-mcp-approval name project-dir :yes|:no|:later &key user-config-dir)
(mcp-timeouts c settings env) → (values startup-s tool-s)
invocation-mcp-config invocation-strict-mcp-config-p
+default-mcp-timeout-ms+ +default-mcp-tool-timeout-ms+ +mcp-json-file-name+ +mcp-transports+ +mcp-scopes+
;; runtime (src/mcp.lisp)
mcp-manager make-mcp-manager start-mcp-servers reconnect-mcp-server add-mcp-servers close-mcp-manager
mcp-manager-tool-source mcp-connection mcp-connection-{config status error client unit source name}
(mcp-tool-name server tool) (mcp-connection-tools c) (mcp-connection-object c)
(mcp-status-notice c &key user-config-dir) (mcp-status-lines servers) (mcp-approval-message c)
+mcp-tool-prefix+ +mcp-plan-mode-feedback+ +mcp-statuses+ +mcp-approval-choices+ +mcp-unit-kind+
;; interactive: state-mcp state-mcp-prompt; events (:mcp-status S) (:mcp-approval NAME MSG) (:mcp-reply C)
;; effects (:mcp-reconnect NAME|NIL) (:mcp-approve NAME CHOICE); /mcp [reconnect [NAME]]
;; SDK: (client-new-session … :mcp-servers) client-add-mcp-servers client-mcp-servers client-reconnect-mcp
;; RPC: mcp/list mcp/reconnect; session/new "mcp_servers"; mcp-server-not-found -32020
```

### Contract tests

`cl-stack-code/tests` grows by 5 files (one of them helpers): **71 new deftests (139 cases with the parametrized rows)**. The fake stdio server is this SBCL (no init files) loading mcp-protocol and mcp-backend-stdio from the parent's sources and fasls (no registry of its own, no compilation, no network), started as the server command; modes `serve`, `crash` and `hang`. The fake HTTP server is mcp-backend-streamable-http's real Clack app in process, reached through a loopback `http-protocol` backend (no socket). Every wait is bounded.

| File | Covers |
|------|--------|
| `mcp-support` | the fake server script and its argv, `.mcp.json` / user-settings writers, the loopback HTTP backend and server, init-event and pid helpers |
| `mcp-config-test` | constants; transport inference (9 rows); every field and default; order and `disabled`; **errors with key paths (19 rows)**; the settings keys; `.mcp.json` reading and its restarts; **`${VAR}` expansion (9 rows), url / headers, unset → `settings-error`**; **layers, last source wins, scopes**; flags and SDK; `--strict-mcp-config`; a missing config file; settings `env` feeding expansion; **trust (18 rows)**; saving approvals; **timeouts (8 rows)**; names (4 rows); connection objects; notices; `/mcp` lines; approval messages; **the core's `/mcp`, reconnect, usage, busy, approval queue** |
| `mcp-cli-test` | init `mcp_servers` and the tools offered; no key without servers; **read-only of a user server runs; default ask denied headless; allow rules (2 rows); deny hides**; error result; image result; env expansion reaching the child; unset variable exit 2; **a crashing server (absent, status, notice, the other server fine)**; **a hanging server (startup timeout, bounded)**; **unapproved project server (skipped, notice); approvals (4 rows); a project cannot approve itself; a project's read-only tool still asks**; disabled; sse unsupported; strict config; bad `.mcp.json`; **plan mode (deny, read-only runs, an allow rule lifts it)**; **the child reaped after -p**; **streamable HTTP (connect, call, `${VAR}` in a header reaching the server), its error result** |
| `mcp-client-test` | **the stdio server as a unit (kind, owner, label, stderr in its log)**; server log lines in the unit log; **close reaps the unit**; `:mcp-servers` from the SDK (trusted); servers added mid-session reach the next turn; reconnect (a new unit) and `mcp-server-not-found`; **RPC `mcp/list`, `mcp/reconnect`, -32020**; `session/new` `mcp_servers`; the error code |
| `mcp-program-test` | **`/mcp` in the TUI** (connected with tools, a failed server, reconnect); no servers; **the approval dialog: Yes (saved, connected), No (saved, rejected)**; approved servers do not ask |

The old suites change only where 0.13.0 changes them: version checks expect 0.13.0, `rpc-constants` lists the two methods, `units-constants` finds the six `units/*` methods anywhere in the list, and `program-help` gets 32 rows (/help grew by the /mcp line). On the stubs (macOS, git 2.56, measured): **135 of the 139 new cases fail**; the 4 that pass check given code (`mcp-constants`, `mcp-trusted-p`, `mcp-rpc-error-code`, and the init event without servers). Every old case passes. Every new failure is a `%h3e2-pending` error, a −32601 for an unimplemented method, or an assertion downstream of the missing wiring; the passing new cases check given code (constants, `mcp-server-trusted-p`, the error code, the method list). No throwaway prototype was run, so the implementation may find test bugs; those go through a contract-fix commit, as before.

### Non-goals (H3e-2a)

- Sampling, elicitation, instructions, deferred loading (H3e-2b, below).
- OAuth for remote servers, `headersHelper`, `ws`, the legacy HTTP+SSE transport (needs mcp-backend-streamable-http#9 and a GET stream), managed and plugin servers.
- `cl-stack-code mcp add|list|remove` commands (edit the files; `/mcp` shows the result).
- Output token caps for large results (`MAX_MCP_OUTPUT_TOKENS`); a later row with H6's budgets.
- Folder trust (Claude Code honours approvals in a trusted folder's local settings).

### Later (H3e-2b)

| Item | Plan |
|------|------|
| **Sampling** | `sampling/createMessage` from a server goes to the session's model (or the server's `samplingModel`) through `make-mcp-sampling-handler`, behind an ask permission (action `mcp_sampling`, resource the server name); `-p` denies unless a rule allows. |
| **Elicitation** | Through the existing approval UI: a TUI dialog for flat schemas only (pydantic-ai's limit), refused in `-p`, ACP later. |
| **Instructions** | A server's `instructions` join the prompt only for trusted servers with `includeInstructions` (default on for user servers, off for project servers), as their own `<mcp-instructions server="x">` block after the stable prefix, so a change does not invalidate the cached system prompt. |
| **Deferred loading** | ai-agent-protocol 0.16.0: a source wrapper that hides a large server's tools behind a `tool_search` tool until the model finds them. |
| **Roots, resources, prompts** | Roots = the working directory; resources as `@` mentions; prompts as `/mcp__server__prompt`. |
| **Deferred approvals** | `-p` ending with pending approvals lists them in the result, and `--resume ID --approve CALL-ID` continues (pydantic-ai's `DeferredToolRequests`). It needs H3c's resume to carry a paused run, which it does not today, so it waits. |

---

## Roadmap (H3b–H3e)

| Slice | Scope | Builds on |
|-------|-------|-----------|
| **H3b** interactive | Shipped (0.2.0): [H3b — locked](#h3b--locked) | H1, H3a |
| **H3c** sessions | Locked (0.3.0): [H3c — locked](#h3c--locked). Sessions as a file-backed `revision-protocol` store; `--continue` / `--resume` / `--session-id` / `--fork-session` / `--list-sessions`; `/tree` `/fork` `/rewind` `/clone` `/export`; steering (Ctrl-T) vs follow-up (Enter) on `agent-run-post` | R0, H3a, H3b |
| **H3d** RPC and SDK | Locked (0.7.0): [H3d — locked](#h3d--locked). The in-process SDK (`make-client`, sessions, `client-turn` / `client-query`, approvals, steering, interrupts, plans, checkpoints, rewinds) and `--rpc`, a JSON-RPC 2.0 server over stdio that is a thin adapter over it; the stream-json events as notifications. `--input-format stream-json` dropped (non-goal) | H3a, H3c, H5a, H5b, rpc-backend-stdio 0.2.0 |
| **H3e** configuration | **H3e-1** locked (0.12.0): [H3e-1 — locked](#h3e-1--locked): `@path` imports, Agent Skills and the `skill` tool, path-scoped rules, `contextFiles` / `skillDirs`. **H3e-2a** locked (0.13.0): [H3e-2 — locked](#h3e-2--locked): MCP servers (config, trust, stdio units, HTTP, tools, `/mcp`, RPC). **H3e-2b**: MCP sampling, elicitation, instructions, deferred tool loading. Then prompt templates (`.cl-stack-code/prompts/*.md` as `/name`), `--system-prompt` and system-prompt files, project trust (project allow rules, `env` and external imports wait for the user's yes) | H3a–H3d; H3e-1 needs steer-protocol 0.4.0 |
| **ACP-2** `cl-stack-code/acp` | A new system: cl-stack-code as an Agent Client Protocol agent over `acp-backend-stdio`, a thin adapter over the H3d SDK as `--rpc` is. Brief: [acp.md](acp.md). Order (2026-11-22): right after H4e | ACP-0 (`acp-protocol` 0.1.0), ACP-1 (`acp-backend-stdio`), H3d |

After H3: the image layer (H4: [H4b — locked](#h4b--locked) is the product half of the debugger bridge; image-first slices H4c–H4h in [lisp-agent-tools.md](lisp-agent-tools.md#roadmap-h4bh4h)), plan → project → approve (H5: [H5a — locked](#h5a--locked), now preview mode; [H5c-0 — locked](#h5c-0--locked), plan mode plans; later slices in the H5 roadmap), extensions and a single binary (H6).

## Model parameters (0.9.0)

| Topic | Rule | Why |
|-------|------|-----|
| **Key** | `"modelParams": {"temperature": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0.0, "presence_penalty": 0.0, "repeat_penalty": 1.0, "chat_template_kwargs": {"enable_thinking": true, "preserve_thinking": true}}`. Keys are **wire names** (what the provider's request body calls them). `temperature` and `top_p` must be numbers (or `null`); other values may be any JSON. A non-object, or a non-number `temperature` / `top_p`, signals `settings-error` with key path `modelParams` / `modelParams.KEY`. | Local servers (llama.cpp, vLLM, LM Studio) take sampler fields the OpenAI wire does not name; one open object covers them without a release per field. |
| **Merge** | Per key across user, project, local and the flag layer, the later wins; `null` unsets (as `env`). `--model-param KEY=VALUE` (repeatable) is the flag layer; VALUE is read as JSON (`20`, `0.95`, `false`, `{"enable_thinking":false}`, `null`), else taken as a string. | The same rules as `env`; one flag for any key. |
| **Request** | `model-params-llm-settings` maps the merged object onto the agent's `:llm` settings: `temperature` → `:temperature`, `top_p` → `:top-p`, every other key into `:extra` as a plist of wire-name strings (first-set order). No key set → NIL (no LLM settings, as before). Every model call of every run, session and RPC session gets them. The backend copies `:extra` into the request body (llm-protocol-openai `%apply-settings-extra`; first-class keys the backend sets itself win). | One mapping, in the settings layer; the providers stay generic. |

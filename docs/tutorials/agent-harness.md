# Tutorial: an agent that survives long runs

**You will build** a coding agent on `ai-agent-protocol` that:
- retries when the provider is overloaded;
- compacts its history when the context fills up;
- ends cleanly at its step limit;
- tells the model how to recover from tool errors;
- asks before risky edits;
- delegates research to background subagents;
- picks up `AGENTS.md` files as it reaches them.

Every step has a runnable example in [`examples/agents/`](../../examples/agents/). The examples use the mock LLM backend, so they run offline and in CI (`cl-repo test --system cl-stack/examples`). Swap in a real backend to try them live.

| Package | Version | What it adds here |
|---------|---------|-------------------|
| [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.6.0** | the loop: retries, compaction trigger, wrap-up, typed tool failures, permissions, subagents, instruction discovery |
| [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.4.0** | `retry-policy`, `llm-retry-class`, `llm-context-overflow`, cache-aware `llm-usage`, `anchored-token-count` |
| [`llm-protocol-anthropic`](https://github.com/egao1980/llm-protocol-anthropic) | **0.2.0** | prompt cache breakpoints, API-side compaction, `Retry-After` |
| [`conversation-protocol`](https://github.com/egao1980/conversation-protocol) | **0.3.0** | `summary-memory` + `compact-turns` (templated summary, verbatim tail) |
| [`steer-protocol`](https://github.com/egao1980/steer-protocol) | **0.3.0** | `instruction-discovery`, `build-system-prompt` |

```lisp
(asdf:load-system "cl-stack/examples")   ; pulls in everything above
(in-package #:cl-stack-examples/agents)
```

All runs below need a bound event loop. `with-agent-loop` from [`package.lisp`](../../examples/agents/package.lisp) binds a libuv loop and closes it on exit (`close-event-loop`, event-protocol 0.2.2):

```lisp
(defmacro with-agent-loop (&body body)
  `(let* ((eb (event-backend-libuv:make-libuv-backend))
          (el (event-protocol:make-event-loop eb)))
     (unwind-protect
          (event-protocol:with-event-backend (eb)
            (event-protocol:with-event-loop-var (el) ,@body))
       (event-protocol:close-event-loop eb el))))   ; whoever makes a loop closes it
```

---

## 1. The real backend

For a live run, use Anthropic:

```lisp
(asdf:load-system "llm-protocol-anthropic")

(defvar *claude*
  (stack-llm-anthropic:make-anthropic-backend
   :default-model "claude-opus-5-5"   ; ANTHROPIC_API_KEY from the environment
   :prompt-cache :auto                ; default: 4 cache breakpoints on the official API
   :server-compaction 150000))        ; optional: let the API compact at 150k input tokens
```

**Prompt cache.** Every request marks the last tool, the system prompt and the last two messages. A long run then re-reads tools, system and history from cache. `llm-usage-cache-read-tokens` and `llm-usage-cache-write-tokens` show what it saved.

**API-side compaction** (beta `compact-2026-01-12`) lets Anthropic summarize in place. It combines with the agent-side compaction in step 3. The agent's threshold then only matters for backends without it.

**Another provider.** The agent takes any `llm-protocol` backend in `:backend`, and the model is that backend's default model. Pick the provider by building the matching backend:

| Provider | Backend | Credentials / endpoint |
|----------|---------|------------------------|
| Anthropic | `(stack-llm-anthropic:make-anthropic-backend :default-model "claude-opus-5-5")` | `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL` |
| OpenAI | `(stack-llm-openai:make-openai-compat-backend :base-url "https://api.openai.com/v1" :default-model "gpt-4o")` | `OPENAI_API_KEY` |
| OpenRouter | `(stack-llm-openai:make-openai-compat-backend :base-url "https://openrouter.ai/api/v1" :api-key (uiop:getenv "OPENROUTER_API_KEY") :default-model "anthropic/claude-sonnet-4.5")` | `OPENROUTER_API_KEY` |
| LM Studio | `(stack-llm-openai:make-openai-compat-backend :default-model "qwen/qwen3-coder-30b")` | default base `127.0.0.1:1234/v1`; `LM_API_TOKEN` when server auth is on |
| Ollama / vLLM | `make-openai-compat-backend :base-url "http://127.0.0.1:11434/v1"` (vLLM: `:8000/v1`) | none |
| vLLM / llama-server, Anthropic wire | `make-vllm-anthropic-backend`, `make-llama-server-anthropic-backend` | local |
| llama.cpp in-process | `(llm-backend-llama-cpp:make-llama-cpp-backend :model-path #p"…gguf")` | none |
| Tests | `(stack-llm:make-mock-llm-backend :handler …)` | none |

Omitted initargs come from the environment: `OPENAI_BASE_URL`, `OPENAI_API_KEY` or `LM_API_TOKEN`, and `OPENAI_MODEL`, which defaults to `gpt-4o-mini`. A provider catalog (`stack-llm:make-in-memory-provider-catalog`, `register-provider`, `resolve-backend "anthropic:claude"`) maps names to backends; an unknown name signals `llm-unknown-provider` with a `use-value` restart. The [sample project](https://github.com/egao1980/cl-stack-sample#choose-the-model-provider) wraps this in a `"provider:model"` designator chosen with `SAMPLE_LLM`. The model must support tool calls.

The OpenAI-compatible and Anthropic backends talk HTTP through `http-protocol`. Bind the async backend once:

```lisp
(setf http-backend-async:*event-backend-maker* #'event-backend-libuv:make-libuv-backend
      http-protocol:*http-backend* (http-backend-async:make-async-backend))
```

---

## 2. Retry by failure class

`llm-retry-class` sorts a failure:
- 429 is `:rate-limit`;
- 503 and 529 are `:overloaded`;
- other retryable 5xx errors are `:transient`;
- an over-long prompt is `:context-overflow`.

The loop retries the classes the policy covers and fails at once on anything else, such as 400 or 401. The wait is the delay below, scheduled on the event loop rather than by blocking it:

```text
min(max-delay, Retry-After  or  base × 2^(attempt-1) × (2 if overloaded))
```

```lisp
(make-ai-agent :name "coder" :backend *claude*
               :settings (make-agent-settings
                          :extra (list :retry-policy (stack-llm:make-retry-policy
                                                      :max-attempts 6 :base-delay 2 :max-delay 30))))
```

[`example-retry`](../../examples/agents/long-runs.lisp) fails twice with 529 and then answers:

```lisp
(example-retry)
;; ⇒ (:TEXT "back online" :ATTEMPTS 3 :RETRIES (:OVERLOADED :OVERLOADED))
```

Each retry emits `:retry` with `(:reason :attempt :delay :condition)`. A `handler-bind` on `agent-generate-error` still wins: invoke `retry`, `use-value` or `abort` yourself.

---

## 3. Compaction

Give the run a summary memory:

```lisp
(make-ai-agent :name "coder" :backend *claude*
               :settings (make-agent-settings
                          :extra (list :compaction (stack-conversation:make-summary-memory
                                                    :backend *claude* :tail-tokens 15000)
                                       ;; optional: default is the context window − max-tokens
                                       :compact-at 150000)))
```

- **When.** Before a step, the loop counts the prompt as the last response's measured usage plus an estimate for the turns since (`anchored-token-count`). Over the threshold, it compacts. On `llm-context-overflow` it compacts once and retries the step.
- **What.** `compact-turns` sends the old turns as one plain-text transcript. Tool results are clipped, thinking is dropped, and a previous summary is merged in. The model writes a summary under fixed headings: Objective, Requirements, Decisions, Work State, Next Move, Relevant Files, Important Context. About 15k tokens of the newest turns stay verbatim. The cut never separates a tool result from its call.

```lisp
(example-compaction)
;; ⇒ (:TEXT "fits now" :COMPACTED T :TURNS-SENT (3 2))  ; full history overflowed; summary + newest turn fit
```

---

## 4. Ending at the step limit

At `:max-steps` the run does not simply stop. It sends one more request with `tool-choice :none` and asks for a summary of what is done, what is left and what comes next. The tools stay in that request, so the cached prefix still matches.

```lisp
(example-max-steps)
;; ⇒ (:FINISH :MAX-STEPS :TEXT "Done: 2 searches. Left: none. Next: read the hits." :LAST-TOOL-CHOICE :NONE)
```

Override the prompt with `:max-steps-prompt`. Turn the wrap-up off with `:max-steps-wrap-up nil`.

---

## 5. Tool errors the model can act on

Signal a `tool-failure` subtype from a handler. The model gets a result that says what to do:

| Condition | The model reads |
|-----------|-----------------|
| `tool-input-error` | "Tool x rejected its arguments: … Fix the arguments … and call it again." |
| `tool-unavailable` | "… is unavailable … Do not call it again in this run" |
| `tool-timeout` | "… timed out … Retry with a smaller request" |
| any other `error` | "Tool x failed: …" |

```lisp
(define-agent-tool agent "lookup" (:description "Look up a user by id.") (args)
  (unless (search "\"id\"" args)                  ; ARGS is the raw JSON string
    (error 'tool-input-error :message "id is required"))
  "user 42: Ada")

(example-typed-tool-failure)
;; ⇒ (:FIRST-RESULT "Tool lookup rejected its arguments: id is required …" :TEXT "User 42 is Ada.")
```

An unknown tool name gets the list of tools the model may call. Specialize `tool-failure-text` for your own condition types.

---

## 6. Permissions

A rule is `{action, resource, effect}`:
- `action` globs the tool name;
- `resource` globs one string the call touches, given by `tool-permission-resources` or `:permission-resources` on a function tool;
- `effect` is `:allow`, `:deny` or `:ask`.

Rules come in layers: the agent's `:permissions` first, then the run's `:extra :permissions`. The last match wins. When a call touches several resources, a deny on any of them wins. A policy layer, `:permission-policy` or `*permission-policy*`, can only make the result stricter.

```lisp
(make-ai-agent :name "coder" :backend *claude*
               :permissions (list '("*" "*" :ask)
                                  '("edit" "src/*" :allow)
                                  (make-permission-rule "edit" "secrets/*" :deny
                                                        :feedback "Secrets are off limits; edit src/ only."))
               :settings (make-agent-settings
                          :extra (list :permission-policy '(("edit" "*.pem" :deny)))))
```

A deny does not abort the run. The model gets an error result with your feedback and continues:

```lisp
(example-permissions)
;; ⇒ (:STATUSES (:DONE :DENIED :DENIED) :FEEDBACK-SEEN T :RAN 1 :FINISH :STOP)
```

`:ask` is the approval pause. Reject with feedback and resume:

```lisp
(let ((run (run-ai-agent agent "document it")))          ; finish reason :approval
  (deny-invocation run (first (agent-run-pending run))
                   :feedback "Use docs/ instead of the README.")
  (resume-ai-agent run))                                 ; the model reads the feedback

(example-permission-ask)
;; ⇒ (:PAUSED :APPROVAL :FINISH :STOP :RESULT "… Use docs/ instead of the README. …" :RAN 0)
```

---

## 7. Background subagents

```lisp
(asdf:load-system "json-backend-jzon")            ; the subagent tool parses JSON arguments
(let ((researcher (make-ai-agent :name "researcher" :backend *claude*
                                 :instructions "Find one source for the claim.")))
  (make-ai-agent :name "lead" :backend *claude*
                 :tools (list (make-subagent-tool (list researcher)))))
```

- **Start.** The model calls `subagent {"agent": "researcher", "prompt": "…"}`. The call returns an id such as `sub-1` at once, and the tool description says not to poll.
- **Report.** When the child finishes, its reply reaches the parent before the parent's next generate, as `<subagent id="sub-1" name="researcher">…</subagent>`.
- **Continue.** `{"id": "sub-1", "prompt": "…"}` continues the same child.
- **One level only.** A child cannot start children of its own.
- **Parent finishing.** A parent that ends its turn waits for live children (event `:waiting`). Change this with `:subagents-on-finish` set to `:cancel` or `:detach`. `cancel-agent-run` on the parent cancels its children.

```lisp
(example-subagent)
;; ⇒ (:STARTED "Started subagent researcher with id sub-1. Do not poll or wait; …"
;;    :TEXT "Lead: <subagent id=\"sub-1\" name=\"researcher\">Source for \"conditions\": CLHS 9.</subagent>"
;;    :WAITED T)
```

---

## 8. Instructions found as the agent reaches them

Don't load every `AGENTS.md` up front. Let tool calls pull them in:

```lisp
(make-ai-agent :name "coder" :backend *claude* :tools tools
               :settings (make-agent-settings
                          :extra (list :instructions-discovery #p"/work/proj/")))
```

When a tool call names a path (`path`, `file_path`, … or the tool's permission resources), the run looks from that file's directory up to the root. Any `AGENTS.md` not yet in context goes in as one turn before the next generate.
- Each file is injected once per run, and again if its content changes.
- After a compaction, the injected files are re-injected.

```lisp
(example-instructions)
;; ⇒ (:INJECTED ("AGENTS.md" "src/AGENTS.md") :INSTRUCTION-TURNS 1 :FINISH :STOP)
```

A short system prompt that names only the tools the agent has:

```lisp
(stack-steer:build-system-prompt :tools '("read" "edit" "bash") :model "claude-opus-5-5")
```

---

## 9. All together

```lisp
(defun make-coder (root tools)
  (let ((researcher (make-ai-agent :name "researcher" :backend *claude*
                                   :instructions "Answer one question with sources.")))
    (make-ai-agent
     :name "coder" :backend *claude*
     :instructions (stack-steer:build-system-prompt :tools tools :model "claude-opus-5-5")
     :tools (cons (make-subagent-tool (list researcher)) tools)
     :permissions '(("*" "*" :ask) ("read" "*" :allow) ("edit" "src/*" :allow)
                    ("bash" "git status *" :allow))
     :settings (make-agent-settings
                :max-steps 60
                :extra (list :retry-policy (stack-llm:make-retry-policy :max-attempts 6)
                             :compaction (stack-conversation:make-summary-memory
                                          :backend *claude* :tail-tokens 15000)
                             :instructions-discovery root)))))
```

Watch it with `:on-event`. The kinds: `:retry`, `:compacted`, `:permission`, `:subagent`, `:waiting`, `:inbox`, `:instructions`, plus the usual `:step`, `:invocation` and `:finished`.

What is not covered yet:
- Durability does not journal subagents, inbox contents or the set of injected instructions.
- opencode's "always allow" replies are not implemented.

Reference: [ai-agent cookbook](../cookbooks/ai-agent.md) · [LLM cookbook](../cookbooks/llm.md) · [conversation](../cookbooks/conversation.md) · [steer](../cookbooks/steer.md).

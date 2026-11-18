# Cookbook: AI agent loop

**Audience:** run a CLOS agent over `llm-protocol` **without** putting MCP/A2A/AG-UI in the core.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-ai-agent`) | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.6.0** |
| MCP sampling + peer | `ai-agent-protocol/mcp` | **0.1.0** |
| AG-UI encode | `ai-agent-protocol/ag-ui` | **0.2.0** |
| A2A expose | `ai-agent-protocol/a2a` | **0.1.0** |

Brief: [ai-agent.md](../capabilities/ai-agent.md). Do **not** call this `run-agent` — that's `ag-ui-protocol:run-agent`.

```lisp
(cl-repo:load-system "ai-agent-protocol" :version "0.6.0")
```

---

## 1. Echo (bound event loop)

Sync `run-ai-agent` awaits the bound `event-protocol` loop. Sync `generate` / tool handlers run **off-loop**.

```lisp
(asdf:load-system "ai-agent-protocol")
(asdf:load-system "event-backend-libuv")

(let* ((eb (event-backend-libuv:make-libuv-backend))
       (el (event-protocol:make-event-loop eb))
       (agent (stack-ai-agent:make-ai-agent
               :name "echo"
               :backend (stack-llm:make-mock-llm-backend)
               :instructions "Be brief.")))
  (event-protocol:with-event-backend (eb)
    (event-protocol:with-event-loop-var (el)
      (stack-ai-agent:agent-run-text
       (stack-ai-agent:run-ai-agent agent "hi")))))
;; ⇒ "echo: hi"
```

---

## 2. CL function-tool

```lisp
(define-agent-tool agent "sum" (:description "add") (args)
  (declare (ignore args))
  "3")
```

`function-tool` with `:approval-required-p t` pauses `:approval`. `invoke-approve` then `resume-ai-agent`.

---

## 3. Nested agent vs handoff

`:tools` — manager keeps control; child run returns text.

```lisp
(make-ai-agent :name "manager" :backend parent-backend
               :tools (list (make-ai-agent :name "researcher" :backend child-backend)))
```

`:handoffs` — specialist **takes the run**.

```lisp
(make-ai-agent :name "triage" :backend manager-backend
               :handoffs (list (make-ai-agent :name "writer" :backend specialist-backend)))
```

`defagent` is `defclass` + `:default-initargs`. Optional conversation memory: [conversation.md](conversation.md) (`:memory` + `:session`). Rules / `SKILL.md`: [steer.md](steer.md) (`:steering`).

---

## 4. MCP sampling + peer tools

**Not** in `llm-protocol`. Host `create-message` → `generate`:

```lisp
(asdf:load-system "ai-agent-protocol/mcp")
(setf (mcp-protocol:mcp-client-sampling-handler client)
      (ai-agent-protocol/mcp:make-mcp-sampling-handler :backend b))
```

MCP server as a tool source: `make-mcp-tool-source` on `:tools`.

AG-UI: `ai-agent-protocol/ag-ui` (`*ag-ui-emit*`). A2A: `ai-agent-protocol/a2a`.

Interactive desk: [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui).

---

## 5. Live LM Studio (CL tool cycle)

Bind **async × libuv**. `scripts/demo.lisp` in `ai-agent-protocol`.

```bash
set -a && source ../.env && set +a   # LM_API_TOKEN / OPENAI_MODEL
CL_SOURCE_REGISTRY="$PWD/../:" ros -l scripts/demo.lisp
```

---

## 6. Long runs: retries, compaction, wrap-up, tool failures (0.4)

All of these are settings `:extra` keys. For a walkthrough with runnable code, see [tutorials/agent-harness.md](../tutorials/agent-harness.md).

```lisp
(make-ai-agent :name "coder" :backend backend
               :settings (make-agent-settings
                          :max-steps 40
                          :extra (list :retry-policy (stack-llm:make-retry-policy :max-attempts 6)
                                       :compaction (stack-conversation:make-summary-memory
                                                    :backend backend :tail-tokens 15000))))
```

| Key | Does |
|-----|------|
| `:retry-policy` | retries `:rate-limit`, `:overloaded` and `:transient` failures with backoff, honouring `Retry-After`; the retry is scheduled on the loop (event `:retry`) |
| `:compaction` / `:compact-at` | summarizes old turns before a step over the threshold, and once on `llm-context-overflow` (event `:compacted`) |
| `:max-steps-wrap-up` / `:max-steps-prompt` | at `max-steps`, makes one more generate with `tool-choice :none` that summarizes what is done, what is left and what comes next |

Tool handlers can signal `tool-input-error`, `tool-unavailable` or `tool-timeout`. The model then reads what to do next (`tool-failure-text`).

---

## 7. Permissions (0.5)

```lisp
(make-ai-agent :name "coder" :backend backend
               :permissions '(("*" "*" :ask) ("edit" "src/*" :allow) ("bash" "rm *" :deny)))
```

- For each resource, the last matching rule wins. A deny on any resource wins over the rest.
- `:permission-policy` can only make the result stricter.
- `:ask` is the approval pause.
- A deny becomes an error tool result carrying `:feedback`; it does not abort the run.
- Resources come from `tool-permission-resources` or `make-function-tool :permission-resources`.

---

## 8. Background subagents (0.5)

`(make-subagent-tool (list researcher))`:
- Starting returns an id such as `sub-1` at once.
- The reply arrives as `<subagent id="sub-1" …>` before the parent's next generate.
- `{"id": "sub-1", "prompt": …}` continues the same child.
- Only one level deep: a child cannot start its own subagents.
- `:subagents-on-finish` is `:wait`, `:cancel` or `:detach`.
- Needs a `json-protocol` backend.

---

## 9. `AGENTS.md` found as the agent reaches them (0.6)

With `:extra (list :instructions-discovery #p"/work/proj/")`, paths in tool calls pull in the `AGENTS.md` files from that directory up to the root. Each file goes in once per run, and again after it changes or after a compaction. See [steer.md](steer.md).

---

## What not to do

- Don’t name the GF `run-agent`.
- Don’t put MCP/A2A/AG-UI deps on the core `.asd`.
- Don’t put sampling in `llm-protocol`.
- Don’t nest `event:run` inside a sync tool handler — handlers already run off-loop.

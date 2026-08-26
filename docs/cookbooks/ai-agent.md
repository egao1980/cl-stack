# Cookbook: AI agent loop

**Audience:** run a CLOS agent over `llm-protocol` **without** putting MCP/A2A/AG-UI in the core.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-ai-agent`) | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.1.0** |
| MCP sampling + peer | `ai-agent-protocol/mcp` | (same) |
| AG-UI expose | `ai-agent-protocol/ag-ui` | (same) |
| A2A expose | `ai-agent-protocol/a2a` | (same) |

Brief: [ai-agent.md](../capabilities/ai-agent.md). Do **not** call this `run-agent` — that's `ag-ui-protocol:run-agent`.

```lisp
(cl-repo:load-system "ai-agent-protocol" :version "0.1.0")
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

`function-tool` with `:approval-required-p t` pauses `:approval`. `approve-invocation` then `resume-ai-agent`.

---

## 3. Nested agent vs handoff

`:tools` — manager keeps control; child run returns text.

```lisp
(make-ai-agent :name "manager" :backend parent-backend
               :tools (list (make-ai-agent :name "researcher" :backend child-backend)))
```

`:handoffs` — specialist **takes the run** (rewrites the system turn, continues).

```lisp
(make-ai-agent :name "triage" :backend manager-backend
               :handoffs (list (make-ai-agent :name "writer" :backend specialist-backend)))
```

`defagent` is `defclass` + `:default-initargs`:

```lisp
(defagent researcher ()
  "Looks things up."
  (:name "researcher")
  (:instructions "Be thorough."))
```

---

## 4. MCP sampling + peer tools

**Not** in `llm-protocol`. Host `create-message` → `generate`:

```lisp
(asdf:load-system "ai-agent-protocol/mcp")
(setf (mcp-protocol:mcp-client-sampling-handler client)
      (ai-agent-protocol/mcp:make-mcp-sampling-handler :backend b))
```

MCP server as a tool source: `make-mcp-tool-source` on `:tools`.

AG-UI: `make-ai-agent-ag-ui-handler` (needs a bound loop). A2A: `a2a-ai-agent-handler`.

---

## What not to do

- Don’t name the GF `run-agent`.
- Don’t put MCP/A2A/AG-UI deps on the core `.asd`.
- Don’t put sampling in `llm-protocol`.
- Don’t clone PydanticAI toolsets.
- Don’t nest `event:run` inside a sync tool handler — handlers already run off-loop.

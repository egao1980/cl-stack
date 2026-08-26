# ai-agent-protocol (P2)

**Issues:** leftover of [#195](https://github.com/egao1980/cl-stack/issues/195) · parent [#192](https://github.com/egao1980/cl-stack/issues/192)  
**Status:** wave-1 (`ai-agent-protocol` **0.1.0**) · cookbook [ai-agent.md](../cookbooks/ai-agent.md)

Async-first CLOS **agent loop** over [`llm-protocol`](llm.md). **Not** blackboard core. **Not** `ag-ui-protocol:run-agent` — use `run-ai-agent` / `run-ai-agent-async`.

```
AG-UI  ── expose ──┐
A2A    ── expose ──┼──► ai-agent-protocol (async-first)
MCP    ── call  ───┘
                    ├── function-tool (CL handler)
                    ├── nested ai-agent as tool (manager keeps control)
                    ├── handoff (specialist takes the run)
                    └── llm-protocol ──► models
```

**Core has zero MCP/A2A/AG-UI deps.** Optional systems: `ai-agent-protocol/mcp`, `/ag-ui`, `/a2a`.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| OpenAI Agents / Vercel `ToolLoopAgent` | name + instructions + tools + settings | kwargs soup, `as_tool()` wrappers |
| OpenAI / Vercel subagents | agent in `:tools` = one peer tool | wrapping execute lambdas |
| OpenAI handoffs | specialist **takes the run** | `Handoff` objects, `transfer_to_*` zoo |
| PydanticAI toolsets | — | Combined / Filtered / Prefixed |

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `ai-agent` + `run-ai-agent-async` / `run-ai-agent`. Primitive = callback + cancel token (http `send-async`). |
| **Name** | Do **not** steal `run-agent` (`ag-ui-protocol`). |
| **Loop** | Bound `event-protocol` `*event-backend*` / `*event-loop*`. Sync generate / tool handlers run **off-loop**. |
| **Tools** | `function-tool` (CL handler). Flat list — no toolsets. |
| **Nested** | `ai-agent` on `:tools` = one `llm-tool` named after the agent. Manager keeps control. |
| **Handoff** | `:handoffs` replaces `agent-run-agent`, rewrites the system turn, continues. |
| **`defagent`** | `defclass` + `:default-initargs`. Superclasses default to `(ai-agent)`. |
| **MCP sampling** | `ai-agent-protocol/mcp:make-mcp-sampling-handler` — **not** `llm-protocol`. |
| **Approvals** | Pause `:approval`. `approve-invocation` / `deny-invocation` / `complete-invocation` then `resume-ai-agent`. |
| **Promises** | Later facade. No Blackbird in the protocol. |

---

## Protocol surface

```lisp
(defgeneric run-ai-agent-async (agent turns &key settings tools on-event
                                callback error-callback))
(defgeneric run-ai-agent (agent turns &key settings tools on-event))
(defgeneric resume-ai-agent-async (run &key callback error-callback on-event))
(defgeneric list-agent-tools (source &key context))
(defgeneric collect-run-tools (agent &key context extra))
(defgeneric invoke-tool-async (source name arguments &key context callback
                               error-callback))
```

Finish: `:stop` `:length` `:approval` `:deferred` `:max-steps` `:error` `:canceled`.

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) |
| MCP sampling + peer tools | `ai-agent-protocol/mcp` |
| AG-UI handler | `ai-agent-protocol/ag-ui` |
| A2A handler | `ai-agent-protocol/a2a` |

---

## Non-goals (wave-1)

- Blackboard / KSAR in this package
- PydanticAI toolsets
- Promises / Blackbird
- Colocating OpenAI or any product backend

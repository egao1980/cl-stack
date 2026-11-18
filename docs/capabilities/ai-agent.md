# ai-agent-protocol (P2)

**Issues:** leftover of [#195](https://github.com/egao1980/cl-stack/issues/195) · parent [#192](https://github.com/egao1980/cl-stack/issues/192)
**Status:** wave-1 (`ai-agent-protocol` **0.2.2** + `/mcp` **0.1.0** · `/ag-ui` **0.2.0** · `/a2a` **0.1.0**). Current **0.6.0**: `:durability` / `/telemetry` (0.3), retries, compaction, max-steps wrap-up, typed tool failures (0.4), permissions, background subagents (0.5), `AGENTS.md` discovery (0.6) · cookbook [ai-agent.md](../cookbooks/ai-agent.md) · tutorial [agent-harness.md](../tutorials/agent-harness.md)

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

**Core has zero MCP/A2A/AG-UI/task-protocol/telemetry-protocol deps.** Optional systems: `ai-agent-protocol/mcp`, `/ag-ui`, `/a2a`, `/durability`, `/telemetry`.

`on-event` kinds: `:started` `:step` `:part` `:response` `:invocation` `:handoff` `:finished`, plus `:retry` `:compacted` `:wrap-up` `:permission` `:subagent` `:waiting` `:inbox` `:instructions` (0.4–0.6). `%do-generate` uses `stream-generate` (`:on-part` hops onto the event loop). `ai-agent-protocol/ag-ui` encodes to AG-UI events via `*ag-ui-emit*`.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `ai-agent` + `run-ai-agent-async` / `run-ai-agent`. Primitive = callback + cancel token (http `send-async`). |
| **Name** | Do **not** steal `run-agent` (`ag-ui-protocol`). |
| **Loop** | Bound `event-protocol` `*event-backend*` / `*event-loop*`. Sync generate / tool handlers run **off-loop**. |
| **Tools** | `function-tool` (CL handler). Nested `ai-agent` on `:tools` = one peer tool. |
| **Handoff** | `:handoffs` — specialist **takes the run**. |
| **`defagent`** | `defclass` + `:default-initargs`. |
| **MCP sampling** | `ai-agent-protocol/mcp:make-mcp-sampling-handler` — **not** `llm-protocol`. |
| **Approvals** | Pause `:approval`. `invoke-approve` / `invoke-deny` then `resume-ai-agent*`. |
| **Memory** | Optional `conversation-protocol` `:memory` / `:session`. Recall on prepare; remember on terminal finish. Not RAG. |
| **Steering** | `steer-protocol` `:steering`. Rules / `SKILL.md` after recall. Not A2A `agent-skill`. `:instructions-discovery` injects path-scoped `AGENTS.md` as tool calls reach them (0.6). |
| **Long runs** | `:extra` `:retry-policy` (by `llm-retry-class`), `:compaction` / `:compact-at` (`compact-turns`; once on `llm-context-overflow`), `:max-steps` wrap-up with `tool-choice :none`. Tool errors: `tool-failure` subtypes → model-readable results (0.4). |
| **Permissions** | `{action, resource, effect}` rules, last match wins, deny on any resource wins; `:permission-policy` only tightens; `:ask` pauses `:approval`; deny returns feedback, does not abort (0.5). |
| **Subagents** | `make-subagent-tool`: background children, reply injected before the parent's next generate; one level; `:subagents-on-finish` `:wait` / `:cancel` / `:detach` (0.5). |
| **Promises** | Later facade. No Blackbird in the protocol. |

---

## Protocol surface

```lisp
(defgeneric run-ai-agent-async (agent turns &key settings tools on-event on-part
                                callback error-callback))
(defgeneric run-ai-agent (agent turns &key settings tools on-event))
(defgeneric resume-ai-agent-async (run &key callback error-callback on-event))
```

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) **0.6.0** (wave-1: 0.2.2) |
| MCP sampling + peer tools | `ai-agent-protocol/mcp` **0.1.0** |
| AG-UI encoder | `ai-agent-protocol/ag-ui` **0.2.0** |
| A2A expose | `ai-agent-protocol/a2a` **0.1.0** |

Products: [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui) (desk chat). Local canary: [`cl-stack-llm-demo`](https://github.com/egao1980/cl-stack-llm-demo) (not on GHCR).

---

## Non-goals (wave-1)

- Blackboard / KSAR in this package
- PydanticAI toolsets
- Promises / Blackbird
- Colocating OpenAI or any product backend

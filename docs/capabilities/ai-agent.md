# ai-agent-protocol (P2)

**Issues:** leftover of [#195](https://github.com/egao1980/cl-stack/issues/195) · parent [#192](https://github.com/egao1980/cl-stack/issues/192)
**Status:** wave-1 (`ai-agent-protocol` **0.2.2** + `/mcp` **0.1.0** · `/ag-ui` **0.2.0** · `/a2a` **0.1.0**). Current **0.7.0**: `:durability` / `/telemetry` (0.3), retries, compaction, max-steps wrap-up, typed tool failures (0.4), permissions, background subagents (0.5), `AGENTS.md` discovery (0.6) · cookbook [ai-agent.md](../cookbooks/ai-agent.md) · tutorial [agent-harness.md](../tutorials/agent-harness.md)

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
| Protocol | [`egao1980/ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) **0.7.0** (wave-1: 0.2.2) |
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

## 0.15.0 — tool-source combinators (locked)

Issue [ai-agent-protocol#37](https://github.com/egao1980/ai-agent-protocol/issues/37), contract [ai-agent-protocol#38](https://github.com/egao1980/ai-agent-protocol/pull/38) (branch `agent/h3e2-ai-agent-protocol-contract-c7cd`, team-solve), after mcp-protocol 0.4.0. Rules: the headers of `src/toolsets.lisp`, `src/policy/policy.lisp` and `src/mcp/source.lisp`. Prior art: pydantic-ai's toolsets and `MCPServer` (pydantic.dev/docs/ai/tools-toolsets/toolsets, …/mcp/client).

| Topic | Rule |
|-------|------|
| **Combinators** | CLOS sources with methods on `list-agent-tools`, `tool-executable-p`, `tool-needs-approval-p`, `invoke-tool-async`, so they nest: `wrapper-tool-source` (delegates; subclass for logging, metrics, timeouts), `combined` (duplicate names → `tool-name-conflict`, restart `continue` keeps the first), `prefixed`, `renamed` (alist new → old), `filtered` (a predicate on context and tool, every step), `prepared` (rewrite definitions per step; adding or renaming → `agent-error`), `approval-required` (a predicate on context, tool and arguments). |
| **Predicates** | `tool-predicate-p`: a function, or (new system `ai-agent-protocol/policy`) a policy-protocol `policy` / `layered-policy` evaluated with the tool name as action and `*tool-policy-context*` facts. As a filter, `:forbid` hides; as an approval, `:ask` or `:forbid` asks. Rules that decide tools are policies (the rules-and-logic rule). |
| **Rich output** | A callback may receive `agent-tool-output` (text, parts, structured). The invocation keeps text as its result, plus `agent-invocation-parts` and `agent-invocation-structured`; when a step's invocations carry parts, the next generate gets one :user turn after the tool results with `[output of tool NAME (ID)]` and the parts. llm-protocol tool results stay text. |
| **MCP source (ai-agent-protocol/mcp 0.2.0)** | One source per peer, unprefixed (hosts wrap it in `prefixed`). The tool list is fetched with `list-all-tools`, cached until the client's tools generation changes (`:cache-tools nil` turns that off), app-only tools hidden. Results: text items joined by LF, placeholders for images, audio and blobs, image parts, `structuredContent`. `isError` → `:tool-error-behavior` `:retry` (default: `mcp-tool-result-error`, retryable), `:failed` (not retryable), `:error` (`mcp-tool-run-error`). Transport and protocol errors are passed through as themselves. `:process-tool-call (context call-fn name args)`; `:timeout` per call. |
| **Later** | Deferred tool loading: locked as [0.17.0](#0170--deferred-tool-loading-locked) (0.16.0 went to H3f's resilience). |

## 0.17.0 — deferred tool loading (locked)

Issue [ai-agent-protocol#44](https://github.com/egao1980/ai-agent-protocol/issues/44), contract [ai-agent-protocol#45](https://github.com/egao1980/ai-agent-protocol/pull/45) (branch `agent/h3e2b-ai-agent-protocol-contract-344b`, team-solve), after 0.16.0 ([#39](https://github.com/egao1980/ai-agent-protocol/issues/39); renumber in merge order). Rules: the headers of `src/deferred.lisp` and `src/mcp/adapter.lisp`. Needed by cl-stack-code H3e-2b ([cl-stack-code.md](cl-stack-code.md#h3e-2b--locked)). Prior art: pydantic-ai's deferred loading, Claude Code's ToolSearch.

| Topic | Rule |
|-------|------|
| **The source** | `make-deferred-tool-source inner &key (mode :auto) (threshold 40) keep (search-tool-name "tool_search") (max-results 5) on-load`, a wrapper. Deferrable: INNER's tools that KEEP (a `tool-predicate-p` predicate) does not hold for. Active: `:always` with one deferrable tool, `:auto` with more than THRESHOLD, never `:never` (`deferred-tool-source-active-p`). |
| **Listing** | Inactive: INNER's. Active: INNER's order without the deferred tools not loaded, then the search tool (description `+tool-search-description+` and the deferred names; parameters `query` required, `max_results` 1..20). `deferred-tool-source-deferred` → the names not loaded. |
| **The search tool** | Executable while active, never needs approval, resources `("*")`. `select:A,B` loads those names (missing ones reported); other text: `tool-search-matches` (per word 2 for a name hit, else 1 for a description hit; ties in INNER's order; at most `max_results`). Matches join the loaded set; ON-LOAD gets the new names. Result: "Loaded N tools; they can be called from the next step:" and `- NAME: DESCRIPTION` lines, or "No deferred tool matches …". Bad arguments → an `agent-error` tool error. |
| **Deferred calls** | A deferred tool not loaded is not executable; its call → `agent-deferred-tool-error` (an `agent-unknown-tool-error`) "tool NAME is deferred: call tool_search with select:NAME first". |
| **The loaded set** | `deferred-tool-source-loaded` (load order; `setf` replaces it, for a host restoring a revision; names INNER no longer lists are skipped and kept). Per source, so a per-session source keeps it across runs. Under a lock. |
| **Sampling handler (ai-agent-protocol/mcp 0.3.0)** | `make-mcp-sampling-handler &key backend model max-tokens`: MODEL is GENERATE's `:model` (modelPreferences never are: 0.2 passed the first hint); `maxTokens` = min(request, MAX-TOKENS); image content → `llm-image-part`, audio → "[audio omitted]"; includeContext ignored; the result's `model` the response's, else MODEL. |
| **Tests** | `tests/deferred-test.lisp` and `tests/sampling-handler-test.lisp`: 28 cases (26 fail on the stubs; two max-tokens rows that pass a request's value through hold already). |

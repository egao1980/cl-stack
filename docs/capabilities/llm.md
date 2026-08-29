# llm-protocol (P2)

**Issues:** [#195](https://github.com/egao1980/cl-stack/issues/195) · parent [#192](https://github.com/egao1980/cl-stack/issues/192)  
**Status:** wave-1 (`llm-protocol` **0.1.0** + [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) **0.1.0**) · cookbook [llm.md](../cookbooks/llm.md)

CLOS generation protocol. **Not** a `blackboard-protocol` dependency. **Demiurge is a consumer**, not the driver.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Anthropic Messages, Gemini `Part`, OpenAI Responses Items, Vercel `LanguageModelV2` | Typed **parts**; **role on the turn** | Chat Completions “one message, glued concerns” as the *protocol* |
| Vercel `generateText`/`streamText`, Anthropic `messages.create`/`stream`, `cl-completions` callback | `generate` + `stream-generate` GFs | Agent `maxSteps`, `tool.execute`, UIMessage |
| All provider SDKs | `llm-settings`, `llm-usage`, finish-reason keywords | Kwargs soup on the GF |
| `quasi/cl-llm-provider` | `backend-supports-p` | Telos, embedding in wave-1 |
| OpenAI-compat / LM Studio | First **backend** wire | Protocol ≠ `/v1/chat/completions` |
| PydanticAI | — | `ModelRequest` part-encodes-role, `ModelRequestParameters` |
| Demiurge | — | `generate-text` / `generate-with-tools` split |

Product/agent loop, tool *execution*, UI transcripts, server-side `previous_response_id` stay out. Those are blackboard / capability / ag-ui / a later store.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `llm-backend` + `generate` / `stream-generate` + `respond` / `stream-respond`. Turns + parts + items. Tools optional. |
| **Roles** | Keywords `:system` `:user` `:assistant` `:tool` on `llm-turn`. |
| **Parts** | `llm-text-part` `llm-image-part` `llm-tool-call-part` `llm-tool-result-part` `llm-thinking-part`. |
| **Settings** | `llm-settings` (or a plist). Not flattened onto the GF. |
| **Tools** | `llm-tool` = name / description / JSON-schema parameters. **Not** an executor. |
| **Finish** | `:stop` `:length` `:tool-use` `:content-filter`. |
| **Wire** | [`llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai): `POST {base}/chat/completions` + `POST {base}/responses`. HTTP = `http-backend-async` × libuv. Default `http://127.0.0.1:1234/v1`. |
| **Capability** | Optional `llm-protocol/capability` — `:llm` catalogue (`make-llm-catalogue`) + `complete` → `generate`. Lookup is `capability-supported-p`, not a parallel flag object. |
| **MCP** | Optional `ai-agent-protocol/mcp` — map sampling → `generate`. No second `create-message`. Not in this repo. |
| **Stream** | GF exists. Mock yields parts via `on-part`. OpenAI wave-1 → `llm-unsupported`. |
| **Autolith** | Do not fork `cl-llm-provider-api`. |

---

## Protocol surface

```lisp
(defclass llm-backend () ())
(defgeneric generate (backend turns &key model settings tools tool-choice))
(defgeneric stream-generate (backend turns &key model settings tools tool-choice on-part))
(defgeneric respond (backend items &key model settings tools tool-choice))
(defgeneric stream-respond (backend items &key model settings tools tool-choice on-part))
(defgeneric list-models (backend &key))
(defgeneric backend-supports-p (backend feature))
```

`turns`: string, `llm-turn`, or a sequence. Result is `llm-response` (`llm-response-text`, `llm-response-tool-calls`, `llm-response-thinking`, `llm-usage`). Items: `llm-item` (`llm-message-item`, `llm-function-call-item`, …).

| Layer | Repo |
|-------|------|
| Protocol + mock | [`egao1980/llm-protocol`](https://github.com/egao1980/llm-protocol) |
| OpenAI-compat | [`egao1980/llm-protocol-openai`](https://github.com/egao1980/llm-protocol-openai) |
| Capability | `llm-protocol/capability` |
| MCP sampling | [`ai-agent-protocol/mcp`](https://github.com/egao1980/ai-agent-protocol) — **not** `llm-protocol` |

Gaps vs Py/Node/Java: [AI-GAP.md](../AI-GAP.md).

Env: `OPENAI_API_KEY` / `LM_API_TOKEN` · `OPENAI_BASE_URL` · `OPENAI_MODEL`. Tests inject `request-fn` plus an async×libuv fixture; live HTTP behind `LLM_OPENAI_LIVE=1`.

---

## Non-goals (wave-1)

- Blackboard / KSAR in this package
- Anthropic native backend (parts already round-trip thinking + signature)
- Embedding GF
- Autolith fork
- Provider-side conversation store

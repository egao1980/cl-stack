# conversation-protocol (P1)

**Status:** `conversation-protocol` **0.1.0** + `ai-agent-protocol` **0.2.2** `:memory` · cookbook [conversation.md](../cookbooks/conversation.md)

CLOS **conversation memory** over [`llm-turn`](llm.md). **Not** RAG. **Not** GFs on `llm-protocol`.

Comparators: LangChain buffer / window / summary; Spring `ChatMemory`; PydanticAI message history.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Package** | Own protocol (`stack-conversation`). Do not hang GFs on `rag-protocol` or `llm-protocol`. |
| **Turns** | `llm-turn` / `coerce-turns`. No parallel message type. |
| **Store vs policy** | `conversation-store` persists; `conversation-memory` recalls / remembers. |
| **Window** | Turn count, not tokens (`llm-usage` is after-the-fact). Keep all `:system`. |
| **remember** | Append. `:replace t` snapshots (agent finish uses this). |
| **In-tree** | `in-memory-conversation-store`, `buffer-memory`, `window-memory`. |
| **Not 0.1.0** | LLM summary-memory; SQL persist; token window. Later backends. |
| **Agent** | Optional `:memory` / `:session`. `prepare-agent-turns` recalls; terminal finish remembers. Approval / deferred do not persist. |

---

## Protocol surface

Package nick: `stack-conversation`.

```lisp
(defgeneric load-session (store session))
(defgeneric save-session (store session turns))
(defgeneric delete-session (store session))
(defgeneric recall (memory incoming &key session))
(defgeneric remember (memory turns &key session replace))
(defgeneric clear-memory (memory &key session))
```

| Layer | Repo | Ver |
|-------|------|-----|
| Protocol + in-process store / buffer / window | [`egao1980/conversation-protocol`](https://github.com/egao1980/conversation-protocol) | **0.1.0** |
| Agent hook | [`egao1980/ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.2.2** |

Conditions: `conversation-missing-backend` (`use-value`); `conversation-session-not-found` (`continue`).

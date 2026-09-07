# Cookbook: conversation memory

**Audience:** persist chat turns across `generate` / `run-ai-agent` calls. **Not** RAG — [rag.md](rag.md).

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol + buffer / window (`stack-conversation`) | [`conversation-protocol`](https://github.com/egao1980/conversation-protocol) | **0.1.0** |
| Agent hook | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.2.2** |
| Turns | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.2.1** |

Brief: [conversation.md](../capabilities/conversation.md).

```lisp
(cl-repo:load-system "conversation-protocol" :version "0.1.0")
```

---

## 1. Buffer / window

```lisp
(asdf:load-system "conversation-protocol")

(let ((mem (stack-conversation:make-window-memory :window-size 6 :session "chat-1")))
  (stack-conversation:remember mem
                               (list (stack-llm:user-turn "hi")
                                     (stack-llm:assistant-turn "hello")))
  (stack-conversation:recall mem "again" :session "chat-1"))
```

`recall` = stored + incoming (incoming is not persisted). `remember` appends; `:replace t` snapshots. Window = last N **non-system** turns + all `:system`.

Share a store across policies:

```lisp
(let ((store (stack-conversation:make-in-memory-conversation-store)))
  (stack-conversation:make-buffer-memory :store store :session "a")
  (stack-conversation:make-window-memory :store store :session "b" :window-size 4))
```

---

## 2. Agent `:memory`

```lisp
(asdf:load-system "ai-agent-protocol")

(make-ai-agent :name "echo" :backend backend
               :memory (stack-conversation:make-window-memory :window-size 8)
               :session "chat-1")
```

`prepare-agent-turns` recalls. Terminal finish remembers the full run (`:replace t`). `:session` on `run-ai-agent` overrides. Approval / deferred pauses do not persist.

Hand-wire without the slot:

```lisp
(run-ai-agent agent (stack-conversation:recall mem incoming :session "s1"))
(stack-conversation:remember mem (agent-run-turns run) :session "s1" :replace t)
```

---

## What not to do

- Don’t put this on `rag-protocol` or `llm-protocol`.
- Don’t window by tokens — no tokenizer protocol yet.
- Don’t treat `remember` of a full `agent-run-turns` as append (use `:replace t`).
- Don’t put rules / `SKILL.md` here — [steer.md](steer.md).

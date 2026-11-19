# Cookbook: steer (rules / skills)

**Audience:** inject rules or `SKILL.md` into the system prompt. **Not** A2A `agent-skill` (card advertisement). **Not** RAG — [rag.md](rag.md).

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol + in-memory + loader (`stack-steer`) | [`steer-protocol`](https://github.com/egao1980/steer-protocol) | **0.3.0** |
| Agent hook | [`ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.7.0** |

Brief: [steer.md](../capabilities/steer.md). Conversation history → [conversation.md](conversation.md).

```lisp
(cl-repo:load-system "steer-protocol" :version "0.3.0")
```

---

## 1. Rules + SKILL.md

One type: `steer-directive` with `:kind` `:rule` or `:skill`.

```lisp
(asdf:load-system "steer-protocol")

(let ((src (stack-steer:make-in-memory-steering
            (list (stack-steer:make-steer-rule "cite" :body "Always cite.")
                  (stack-steer:load-skill #p"skills/review/SKILL.md")))))
  (stack-steer:apply-steering "review this" src))
```

`compile-steering` → one system-prompt string (`# rule: name` / `# skill: name`). Disabled directives are skipped. `load-skills-from-directory` walks `**/SKILL.md`.

Frontmatter is Cursor/Codex YAML (`name`, `description`). Missing source → `steer-missing-source` (`use-value`). Unknown name → `steer-unknown-directive` (`use-value` / `continue`). Missing file → `steer-skill-not-found` (`use-value`).

---

## 2. Agent `:steering`

```lisp
(asdf:load-system "ai-agent-protocol")

(make-ai-agent :name "echo" :backend backend
               :steering (list (stack-steer:make-steer-rule "cite"
                                                           :body "Always cite.")))
```

`prepare-agent-turns` applies after memory recall; compiled text merges into the `:system` turn. `defagent` accepts `(:steering form)`.

---

## 3. `AGENTS.md` found as the agent reaches them (0.3)

```lisp
(defvar *disc* (stack-steer:make-instruction-discovery #p"/work/proj/" :include-claude t))
(stack-steer:discover-instructions *disc* "src/net/http.lisp")
;; → directives for AGENTS.md and src/net/AGENTS.md (outermost first)
(stack-steer:discover-instructions *disc* "src/net/tls.lisp")   ; → NIL, already in context
(stack-steer:forget-instructions *disc*)                        ; after a compaction
```

- A changed file (`instruction-content-hash`) is returned again.
- `compile-instructions` renders `<instructions path=… scope=…>` blocks.
- An unreadable file signals `steer-instruction-unreadable`, with `use-value` and `continue` restarts.
- In the agent loop: settings `:extra (list :instructions-discovery root)` ([ai-agent.md](ai-agent.md) §9, [tutorial](../tutorials/agent-harness.md) §8).

## 4. Base system prompt (0.3)

```lisp
(stack-steer:build-system-prompt :tools (list read-tool bash-tool) :model "claude-opus-5-5")
```

The prompt gives one guidance line per tool that is actually present.
- Variants are CLOS: `prompt-variant-for` takes a model name, a family keyword or a backend.
- To change the wording, specialize `tool-guidance` or `render-system-prompt`.
- To add guidance for a new tool, use `register-tool-guidance`.

---

## What not to do

- Don’t name this `agent-skill` — that’s A2A card advertisement.
- Don’t hang GFs on `llm-protocol` or `rag-protocol`.
- Don’t treat a skill body as a tool handler — tools stay on `ai-agent-protocol`.

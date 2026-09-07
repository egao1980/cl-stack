# steer-protocol (P3)

**Issues:** [#198](https://github.com/egao1980/cl-stack/issues/198)
**Status:** `steer-protocol` **0.1.0** + `ai-agent-protocol` **0.2.2** `:steering` · cookbook [steer.md](../cookbooks/steer.md)

CLOS **rules / skills** compiled into a system prompt. **Not** A2A `agent-skill`. **Not** GFs on `llm-protocol`. **Not** RAG.

Comparators: Cursor/Codex `SKILL.md`; Autolith `skill.load`.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Package** | Own protocol (`stack-steer`). Do not hang GFs on `llm-protocol` or `rag-protocol`. |
| **Name** | `steer-protocol`. Never `agent-skill` (A2A card field). |
| **Type** | One `steer-directive`. `:kind` `:rule` or `:skill`. |
| **Compile** | Enabled directives → one system-prompt string. |
| **Apply** | Merge into a `:system` turn (`coerce-turns`). |
| **Files** | Cursor/Codex `SKILL.md` YAML frontmatter. `load-skills-from-directory`. |
| **In-tree** | `in-memory-steering`. |
| **Agent** | `:steering` after memory recall. `defagent` `(:steering form)`. |
| **Not 0.1.0** | Tool-bearing skills; remote skill registries. |

---

## Protocol surface

Package nick: `stack-steer`.

```lisp
(defgeneric list-directives (source &key))
(defgeneric find-directive (source name &key))
(defgeneric register-directive (source directive &key))
(defgeneric unregister-directive (source name &key))
(defgeneric compile-steering (source &key))
(defgeneric apply-steering (turns source &key))
```

| Layer | Repo | Ver |
|-------|------|-----|
| Protocol + in-memory + `SKILL.md` | [`egao1980/steer-protocol`](https://github.com/egao1980/steer-protocol) | **0.1.0** |
| Agent hook | [`egao1980/ai-agent-protocol`](https://github.com/egao1980/ai-agent-protocol) | **0.2.2** |

Conditions: `steer-missing-source` (`use-value`); `steer-unknown-directive` (`use-value` / `continue`); `steer-skill-not-found` (`use-value`).

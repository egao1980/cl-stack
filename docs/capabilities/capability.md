# capability-protocol (P2)

**Issues:** [#194](https://github.com/egao1980/cl-stack/issues/194) · parent [#192](https://github.com/egao1980/cl-stack/issues/192) · board [#193](https://github.com/egao1980/cl-stack/issues/193)  
**Status:** wave-1 **done** (`capability-protocol` **0.2.0**, colocated in [`blackboard-protocol`](https://github.com/egao1980/blackboard-protocol)) · cookbook [blackboard.md](../cookbooks/blackboard.md)

Extract of Demiurge `defcapability` / registry. Core `.asd` has **zero** AI-wire deps. MCP may later *project* a capability as `mcp-tool` in an adapter.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Abstract `capability` + `defcapability` + `defcatalogue` + query GFs on a host (board or live catalogue) |
| **Dispatch** | Typed GFs + portable `invoke-operation` (no SBCL eql-specializer) |
| **Not MCP** | Do not map world I/O onto `mcp-tool` in this layer |
| **COW** | Cap/KS registries **shared by pointer** across `fork-workspace`. Sandboxed I/O is an adapter (e.g. workspace-local compute env). |
| **Catalogues** | Vocabulary (`defcatalogue` / `catalogue-defines-p`) vs instances (`register-capability` / `get-capability` / `capability-supported-p`). Interned spec is read-only; `make-catalogue` copies for live register. Registering a name not in the vocabulary → `unknown-capability`. |
| **Domains (GFs only)** | `:world` — `:compute` `:code-editing` `:version-control` `:web-search` `:communication`. `:llm` — `:llm-generation` (complete / stream-complete) plus modality names (`:llm-vision` `:llm-audio` `:llm-video` `:llm-files` `:llm-speech` …). **No** provider types here. |
| **Schema** | Optional `schema-protocol` on op descriptors. Not required wave-1. |

---

## Protocol surface

```lisp
(defclass capability () ())
(defgeneric capability-name (cap))
(defgeneric capability-operations (cap))
(defgeneric invoke-operation (cap op-name &rest args))
(defgeneric register-capability (host cap))
(defgeneric get-capability (host name))
(defgeneric capability-supported-p (host name))
(defmacro defcapability (name doc &body operations) …)
(defmacro defcatalogue (name doc &body capability-names) …)
(defun make-catalogue (name))
```

Concrete backends (`llm-protocol` / `llm-protocol-openai`, compute via `process-protocol`) are **separate repos**. They implement these GFs; they do not pull MCP/A2A into `capability-protocol`. Demiurge **consumes** the protocol — it does not define it.

---

## Non-goals (wave-1)

- Provider HTTP clients
- MCP / A2A / AG-UI
- Plugin DSL beyond `defcapability`
- Worktree / git isolation (capability *may* take a workspace argument)

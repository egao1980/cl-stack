# capability-protocol (P2)

**Issues:** TBD  
**Status:** brief **locked** — CLOS world-I/O protocol. Sits **on** [blackboard.md](blackboard.md). **Not** MCP tools.

Extract of Demiurge `defcapability` / registry. Core `.asd` has **zero** AI-wire deps. MCP may later *project* a capability as `mcp-tool` in an adapter.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Abstract `capability` + `defcapability` + registry on the blackboard |
| **Dispatch** | Typed GFs + portable `invoke-operation` (no SBCL eql-specializer) |
| **Not MCP** | Do not map world I/O onto `mcp-tool` in this layer |
| **COW** | Cap/KS registries **shared by pointer** across `fork-workspace`. Sandboxed I/O is an adapter (e.g. workspace-local compute env). |
| **Domains (GFs only)** | `:compute` `:code-editing` `:version-control` `:web-search` `:communication`. `:llm-generation` may exist as GF names; **no** provider types here. |
| **Schema** | Optional `schema-protocol` on op descriptors. Not required wave-1. |

---

## Protocol surface

```lisp
(defclass capability () ())
(defgeneric capability-name (cap))
(defgeneric capability-operations (cap))
(defgeneric invoke-operation (cap op-name &rest args))
(defgeneric register-capability (bb cap))
(defgeneric get-capability (bb name))

(defmacro defcapability (name doc &body operations) …)
```

Concrete backends (`llm-backend-openai`, compute via `process-protocol`) are **separate repos**. They implement these GFs; they do not pull MCP/A2A into `capability-protocol`.

---

## Non-goals (wave-1)

- Provider HTTP clients
- MCP / A2A / AG-UI
- Plugin DSL beyond `defcapability`
- Worktree / git isolation (capability *may* take a workspace argument)

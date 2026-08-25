# blackboard-protocol (P2)

**Issues:** TBD  
**Status:** brief **locked** — AI-agnostic KSAR loop + COW workspaces. Extract of [`egao1980/demiurge`](https://github.com/egao1980/demiurge) **core**, not bootstrap.

Sibling: [capability.md](capability.md). **Not** agent-wire. MCP / A2A / AG-UI / `llm-protocol` are optional adapters that post to the board or implement capabilities. Core `.asd` must not depend on them.

Conventions: [API.md](../API.md). Product that composes core + adapters: `egao1980/demiurge`.

```text
write-section → watchers → KSAR → priority agenda → bounded workers
                     │
              fork-workspace (COW) ── requeue-ksar / merge / discard / cancel
```

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `blackboard-protocol` GFs + in-memory/BT2 default |
| **Control** | Path A only: watcher → KSAR → agenda → handler. No eligible-KS scan. No LLM turn loop in core. |
| **KS** | Named, versionable object. Activation is still watcher/KSAR. `ks-precondition` gates the handler; it does not scan the registry every tick. |
| **Continue** | `requeue-ksar` — next step for the same workspace. No trigger-key flicker. |
| **Concurrency** | **Serial-per-workspace** (≤1 running KSAR). Global `max-concurrency` caps parallel *workspaces*. |
| **KSAR** | Carries workspace + handler. Root scheduler must not `get-watcher` on root and miss local watchers. |
| **Workspace** | Named COW branch. Isolation is **sections**, not capabilities or the scheduler. Cap/KS registries shared by pointer (document). |
| **Merge** | `:overwrite` / `:union` / `:fail-on-conflict` — implement all three. |
| **Discard / cancel** | Reclaim overrides + local watchers; unregister. `cancel-workspace` stops further requeues. Optional `:max-steps`. |
| **Nested COW** | `requires` checks use the **read path** (full parent chain). |
| **AI deps** | **Forbidden** in core: `mcp-protocol`, `a2a-protocol`, `ag-ui-protocol`, `llm-protocol`. Allowed: BT2, alexandria, closer-mop, lparallel (or event-protocol later), optional log/schema. |
| **Portable** | No SBCL `invoke-operation` / eql-specializer. |

Do **not** copy Demiurge bugs: `cow-all-requires-present-p` reads parent `blackboard-sections` (breaks nested watchers); agent loop registers watchers on root; `merge` ignores `:strategy`; `discard` is a status flag only.

---

## Inner loop

1. `write-section` commits under lock; `equal` change-detect; optional `merge-fn`.
2. Watcher fires iff `triggered-key ∈ requires` **and** every required key is present (presence, not predicate).
3. KSAR: id, watcher-id, workspace, handler, triggered-key, priority, context snapshot, status `:pending|:running|:completed|:failed`.
4. Priority agenda, FIFO tiebreak. Scheduler claims a slot, runs handler; errors → `:failed` + `:errors` section; loop never dies.
5. `watch` with already-satisfied `requires` immediately enqueues (`triggered-key :initial`). One-shot watchers removed when they fire.
6. Handler may `requeue-ksar` to continue the same workspace.

Demiurge also has an unused sync KS scan (`find-eligible-ks`) and bootstrap `execute-steps`. **Do not ship those as the loop.**

---

## Workspaces

| Op | Semantics |
|----|-----------|
| `fork-workspace` | Empty overrides, empty local watchers, parent-chain reads, **shared root agenda**, shared cap/KS registries, registered on root. |
| `read-section` | Override else parent (full COW chain). |
| `write-section` | Override only; fire **local** watchers; enqueue KSAR on **root** with workspace+handler. |
| `merge-workspace` | Publish overrides to parent (`write-section` retriggers parent watchers). |
| `discard-workspace` | Drop overrides, unwatch locals, unregister. Idempotent. Parent unchanged. |
| `cancel-workspace` | Status + stop requeues. Handler must see cancel before work. |
| Status | `:active` `:completed` `:failed` `:discarded` |

A blackboard workspace is **not** a git tree, MCP resource, or Autolith `workspace:` URI. A capability may take `workspace` to scope cwd/env.

---

## Coding agent (wave-1 done-when)

Core stays AI-agnostic. A **mock** coding-agent KS (no LLM, no MCP) must run a multi-step edit/test loop on this loop. If that test is awkward, fix the protocol — do not add `agent-protocol` in core.

| Need | Lock |
|------|------|
| One step = one KSAR | Handler sees **workspace** BB |
| Continue | `requeue-ksar` |
| No overlapping steps | Serial-per-workspace |
| Cancel / budget | `cancel-workspace` + optional `:max-steps` |
| Child (reviewer / scout) | Nested `fork-workspace`; parent watches child status / `:ks-result` |
| Tools | `invoke-operation` on `:code-editing` / `:compute` / `:version-control` (GFs only). Stub caps in tests. |
| Ingress | KS watches `:pending-task`, forks, requeues first step |
| Transcript | Allowed as COW sections; not required |

**Mock test:** stub `read-file`/`write-file`/`run-command` → fork → write → requeue → “test” → requeue → finish. Assert serial steps; a second workspace interleaves; cancel sticks; discard/merge; nested reviewer child.

LLM / MCP adapters later sit on the same GFs (`:llm-generation` backend, MCP tool projection, A2A → `:pending-task`).

---

## Prior art

| System | Take | Leave |
|--------|------|-------|
| **BB1** (Hayes-Roth 1984) | **KSAR** name/role, agenda | Control blackboard, explain/learn |
| **HEARSAY-II** | Data-directed KS, interrupt not poll | **Levels** / hypotheses / credibility |
| **HEARSAY-III** | Activation records | Scheduling blackboard |
| **GBB / GBBopen** (Corkill; ANSI CL) | Event-on-write; *the* CL prior art | Do **not** import/fork. Spaces/units = P3 |
| **Linda** | — | Tuple spaces |
| **Autolith** | Isolation analogue: RLM frames / `task.run` | LLM tool loop is an **adapter**, not core |
| **Demiurge core** | This extract | Bootstrap supervisor / `:MSG-N` / `cl-mcp-sdk` |

Wave-1 = BB1-lite KSAR loop + GBB-lite event-on-write + COW workspaces. Flat keyword sections.

---

## Protocol surface

```lisp
(defclass blackboard () ())
(defclass workspace () ())
(defclass knowledge-source () ())
(defclass ksar () ())          ; workspace + handler, not just watcher-id

(defgeneric read-section (bb key &key default))
(defgeneric write-section (bb key value &key merge-fn))
(defgeneric watch (bb &key id requires handler priority one-shot))
(defgeneric enqueue-ksar (bb ksar))
(defgeneric requeue-ksar (bb ksar &key workspace))
(defgeneric run-scheduler (bb &key))
(defgeneric fork-workspace (bb name &key parent))
(defgeneric merge-workspace (ws &key strategy))   ; :overwrite :union :fail-on-conflict
(defgeneric discard-workspace (ws))
(defgeneric cancel-workspace (ws &key reason))
(defgeneric ks-precondition (ks blackboard))
(defgeneric ks-execute (ks blackboard))
(defgeneric ks-postcondition (ks blackboard result))
```

---

## Repo layout (target)

| Layer | Repo |
|-------|------|
| Protocol | `egao1980/blackboard-protocol` |
| Default | in-tree memory/BT2 or `blackboard-backend-memory` |

---

## Non-goals (wave-1)

- MCP / A2A / AG-UI / `llm-protocol` as core deps
- `agent-protocol` turn loop in core
- HEARSAY levels, GBBopen import, BB1 control blackboard, Linda
- Autolith live-image / generations
- Trigger-key toggle as the continue API
- Replacing `cl-mcp` tools product

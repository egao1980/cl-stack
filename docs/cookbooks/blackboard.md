# Cookbook: blackboard + capabilities

**Audience:** host an agent loop **without** MCP/A2A/AG-UI/LLM in the core — BB1-lite KSAR + COW workspaces.

| Piece | Package | OCI |
|-------|---------|-----|
| Board (`stack-blackboard`) | [`blackboard-protocol`](https://github.com/egao1980/blackboard-protocol) | **0.1.0** |
| Caps (`stack-capability`) | [`capability-protocol`](https://github.com/egao1980/blackboard-protocol) (colocated) | **0.1.0** |

Briefs: [blackboard.md](../capabilities/blackboard.md) (#193) · [capability.md](../capabilities/capability.md) (#194). **Not** agent-wire. World I/O is **not** `mcp-tool`.

```lisp
(cl-repo:load-system "blackboard-protocol" :version "0.1.0")
(cl-repo:load-system "capability-protocol" :version "0.1.0")
```

---

## 1. Watcher → KSAR

```lisp
(use-package :stack-blackboard)

(let ((bb (make-blackboard :max-concurrency 2)))
  (watch bb :id 'echo :requires '(:ping)
        :handler (lambda (board ksar)
                   (declare (ignore ksar))
                   (write-section board :pong (read-section board :ping))))
  (write-section bb :ping 1)
  (run-scheduler bb :until-empty t)
  (read-section bb :pong))
;; ⇒ 1
```

Watcher fires iff the triggered key is in `requires` **and** every required key is present (presence, not predicate). Already-satisfied `watch` enqueues immediately (`triggered-key :initial`).

---

## 2. COW workspace + `requeue-ksar`

```lisp
(let* ((bb (make-blackboard))
       (ws (fork-workspace bb "job")))
  (watch (workspace-blackboard ws) :id 'steps :requires '(:go)
         :handler (lambda (board ksar)
                    (let ((n (read-section board :n :default 0)))
                      (write-section board :n (1+ n))
                      (when (< n 2)
                        (requeue-ksar board ksar)))))
  (write-section (workspace-blackboard ws) :go t)
  (run-scheduler bb :until-empty t)
  (read-section (workspace-blackboard ws) :n))
;; ⇒ 3
```

| Op | Effect |
|----|--------|
| `fork-workspace` | Empty overrides; parent-chain reads; **shared root agenda**; cap/KS registries by pointer |
| `requeue-ksar` | Next step, same workspace. No trigger-key flicker |
| `merge-workspace` | `:overwrite` / `:union` / `:fail-on-conflict` |
| `discard-workspace` | Drop overrides + local watchers; unregister |
| `cancel-workspace` | Stop further requeues |

Serial-per-workspace (≤1 running KSAR). `max-concurrency` caps parallel **workspaces**.

---

## 3. Stub capabilities (mock coding-agent)

```lisp
(asdf:load-system "capability-protocol")

(defclass mock-edit (stack-capability:code-editing-capability)
  ((files :initform (make-hash-table :test 'equal) :accessor mock-files)))

(defmethod stack-capability:write-file ((cap mock-edit) path content &key)
  (setf (gethash path (mock-files cap)) content))

(let ((bb (make-blackboard)))
  (stack-capability:register-capability bb (make-instance 'mock-edit))
  (stack-capability:invoke-operation
   (stack-capability:get-capability bb :code-editing)
   'stack-capability:write-file "src/foo.lisp" "(+ 1 2)"))
```

Domains (GFs only): `:compute` `:code-editing` `:version-control` `:web-search` `:communication`. `:llm-generation` is a reserved name — no provider here. `invoke-operation` is portable (no SBCL eql-specializer).

Wave-1 proof: mock coding-agent KS (no LLM/MCP) does edit → `requeue-ksar` → “test” → requeue → done. See `blackboard-protocol` `tests/coding-agent-test.lisp`.

---

## What not to do

- Don’t depend on `mcp-protocol` / `a2a-protocol` / `ag-ui-protocol` / `llm-protocol` in this core.
- Don’t add `agent-protocol` as the brain — fix the board if a mock coding-agent test is awkward.
- Don’t scan `find-eligible-ks` every tick — activation is watcher → KSAR.
- Don’t copy Demiurge bugs (nested COW `requires` must use the **read path**; KSAR carries workspace+handler).

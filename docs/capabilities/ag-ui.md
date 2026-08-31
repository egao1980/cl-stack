# ag-ui-protocol (P1)

**Issues:** [#187](https://github.com/egao1980/cl-stack/issues/187)
**Status:** `ag-ui-protocol` **0.3.0** + SSE **0.2.1** + protobuf **0.3.0** + TUI **0.1.0** — typed events, **not** JSON-RPC

[AG-UI](https://docs.ag-ui.com/concepts/events). Agent ↔ UI. Client POSTs `RunAgentInput`; server streams events. All **36** upstream event types decode (`every-upstream-event-type-is-modelled`).

The **agent loop** is [ai-agent.md](ai-agent.md) (`run-ai-agent`). This package owns the **wire GF** `run-agent`.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `schema-protocol` `defschema` events + `run-agent` GF; transports are backends |
| **JSON Schema** | `schema-protocol-json` — draft-07 emit (`ag-ui-json-schema`), validate incoming JSON (`validate-ag-ui-json`), tool `parameters` (`validate-tool-arguments`) |
| **Default backend (A)** | `ag-ui-backend-sse` **0.2.1** — sse-protocol over http-server-protocol |
| **Second backend (B)** | `ag-ui-backend-protobuf` **0.3.0** — JSON-as-WKT (`google.protobuf.Value` via serdes `:wkt`), length-prefixed `application/vnd.ag-ui.event+proto`. **Not** the official `Event` oneof. **Not** JSON octets in SSE. |
| **TUI sink** | `ag-ui-backend-tui` **0.1.0** — fold events into a transcript. Not a wire client. Paint is optional (`/tuition`). |
| **Client reducer** | `ag-ui-protocol/client` — `verify-events` + `apply-event` / `reduce-events`. `STATE_DELTA` via [`json-patch`](https://github.com/egao1980/json-patch) **0.1.0**. |
| **Chunks** | `*_CHUNK` is a producer convenience. `expand-ag-ui-chunks` (or a `chunk-expander`) rewrites to START/CONTENT/END. |
| **Unknown events** | `decode-ag-ui-event` → `unknown-ag-ui-event` (keeps the table, re-encodes verbatim). `:strict t` signals. `validate-ag-ui-json` stays strict. |
| **Interrupts** | `RUN_FINISHED` with `outcome: "interrupt"` + `interrupts[]`. Resume via `RunAgentInput.resume`. `validate-resume`. |
| **Accept** | `make-ag-ui-app` negotiates: proto media type → binary; otherwise SSE. GET on the agent path → `AgentCapabilities`. |
| **Not JSON-RPC** | Do not route through `rpc-protocol-json`. Official HTTP is `POST RunAgentInput` → SSE events. |
| **`:key-style`** | Does **not** inherit. Every event subclass must repeat `(:key-style :camel)`. |

Reasoning / activity / subagent families are **shipped**, not wave-2 non-goals.

---

## Repo layout

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol | [`egao1980/ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) | **0.3.0** |
| Client reducer | `ag-ui-protocol/client` | (same) |
| SSE (A) | [`egao1980/ag-ui-backend-sse`](https://github.com/egao1980/ag-ui-backend-sse) | **0.2.1** |
| Protobuf (B) | [`egao1980/ag-ui-backend-protobuf`](https://github.com/egao1980/ag-ui-backend-protobuf) | **0.3.0** |
| TUI sink | [`egao1980/ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) | **0.1.0** |
| Canary | [`egao1980/ag-ui-parity`](https://github.com/egao1980/ag-ui-parity) | SSE JSON full; WKT Lisp-only |

---

## Protocol surface

```lisp
;; defschema ag-ui-event (:tag event-type :key-style :camel)
;; slot is EVENT-TYPE with wire key "type" (CL:TYPE is package-locked)
(defclass run-agent-input ()
  (thread-id run-id parent-run-id state messages tools context
   forwarded-props resume))
(defclass ag-ui-agent () ())   ; local handler; default = echo last user text
(defclass ag-ui-backend () ())
(defvar *ag-ui-backend* nil)
(defvar *ag-ui-emit* nil)

(defgeneric run-agent (backend input &key on-event))
(defgeneric encode-ag-ui-event (event &key format))   ; :json | :protobuf (WKT)
(defgeneric decode-ag-ui-event (source &key format strict))
(defgeneric serve-ag-ui (backend &key path host port))
(defun make-ag-ui-app (agent &key path event-format))  ; Clack: POST → SSE / proto
(defun expand-ag-ui-chunks (events))
```

`STATE_DELTA` = RFC 6902 JSON Patch (`json-patch` on the client reducer).

---

## Event types (all 36)

| Family | Types |
|--------|--------|
| Run | `RUN_STARTED` `RUN_FINISHED` `RUN_ERROR` |
| Step | `STEP_STARTED` `STEP_FINISHED` |
| Text | `TEXT_MESSAGE_START` `TEXT_MESSAGE_CONTENT` `TEXT_MESSAGE_END` `TEXT_MESSAGE_CHUNK` |
| Tools | `TOOL_CALL_START` `TOOL_CALL_ARGS` `TOOL_CALL_END` `TOOL_CALL_RESULT` `TOOL_CALL_CHUNK` |
| State | `STATE_SNAPSHOT` `STATE_DELTA` `MESSAGES_SNAPSHOT` |
| Activity | `ACTIVITY_SNAPSHOT` `ACTIVITY_DELTA` |
| Subagent | `SUBAGENT_STARTED` `SUBAGENT_FINISHED` `SUBAGENT_ERROR` |
| Reasoning | `REASONING_START` `REASONING_END` `REASONING_MESSAGE_START` `REASONING_MESSAGE_CONTENT` `REASONING_MESSAGE_END` `REASONING_MESSAGE_CHUNK` `REASONING_ENCRYPTED_VALUE` |
| Thinking (deprecated upstream) | `THINKING_START` `THINKING_END` `THINKING_TEXT_MESSAGE_START` `THINKING_TEXT_MESSAGE_CONTENT` `THINKING_TEXT_MESSAGE_END` |
| Ext | `RAW` `CUSTOM` |

Pinned by `every-upstream-event-type-is-modelled`.

---

## Non-goals

- CopilotKit React kit
- Official `Event` oneof proto (WKT Value is the shipped binary)
- Putting `run-ai-agent` in this package

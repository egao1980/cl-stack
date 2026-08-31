# Cookbook: AG-UI (agent ↔ UI events)

**Audience:** CopilotKit `HttpAgent` / `@ag-ui/core` — stream typed events into a UI.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-ag-ui`) | [`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol) | **0.3.0** |
| Client reducer | `ag-ui-protocol/client` | (same) |
| Default backend | [`ag-ui-backend-sse`](https://github.com/egao1980/ag-ui-backend-sse) | **0.2.1** |
| Protobuf (WKT) | [`ag-ui-backend-protobuf`](https://github.com/egao1980/ag-ui-backend-protobuf) | **0.3.0** |
| TUI sink | [`ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) | **0.1.0** |
| JSON Patch | [`json-patch`](https://github.com/egao1980/json-patch) | **0.1.0** |

Brief: [ag-ui.md](../capabilities/ag-ui.md) (#187). **Not JSON-RPC.** Official HTTP is `POST RunAgentInput` → `text/event-stream`. All **36** event types. Loop is `run-ai-agent` — [ai-agent.md](ai-agent.md).

```lisp
(cl-repo:load-system "ag-ui-protocol" :version "0.3.0")
(cl-repo:load-system "ag-ui-backend-sse" :version "0.2.1")
(cl-repo:load-system "http-server-backend-hunchentoot" :version "0.1.0")
```

---

## 1. Local echo (no HTTP)

```lisp
(use-package :stack-ag-ui)

(let ((agent (make-ag-ui-agent)))
  (run-agent agent
             (make-run-agent-input
              :thread-id "thread_123" :run-id "run_456"
              :messages (list (make-ag-ui-message
                               :role "user" :content "Hello, how are you?")))))
;; ⇒ (RUN_STARTED TEXT_MESSAGE_START TEXT_MESSAGE_CONTENT
;;    TEXT_MESSAGE_END RUN_FINISHED)
```

Incremental handlers call `ag-ui-emit` while `*ag-ui-emit*` is bound. A returned event list is `mapc`'d onto `:on-event` if the handler never emits.

```lisp
(make-ag-ui-agent
 :handler (lambda (input)
            (list (make-run-started-event
                   :thread-id (run-agent-input-thread-id input)
                   :run-id (run-agent-input-run-id input))
                  (make-run-finished-event
                   :thread-id (run-agent-input-thread-id input)
                   :run-id (run-agent-input-run-id input)))))
```

`*_CHUNK` → `expand-ag-ui-chunks` (or a `chunk-expander`) so reducers only see START/CONTENT/END. Unknown `type` → `unknown-ag-ui-event` unless `:strict t`.

---

## 2. Serve SSE (stock HttpAgent)

```lisp
(asdf:load-system "ag-ui-backend-sse")
(asdf:load-system "http-server-backend-hunchentoot")

(ag-ui-protocol:serve-ag-ui
 (ag-ui-backend-sse:make-sse-ag-ui-backend
  :agent (ag-ui-protocol:make-ag-ui-agent))
 :host "127.0.0.1" :port 8000 :path "/")
```

```bash
curl -sN -X POST http://127.0.0.1:8000/ \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{
    "threadId": "thread_123",
    "runId": "run_456",
    "messages": [{"id":"msg_1","role":"user","content":"Hello, how are you?"}],
    "tools": [],
    "context": [],
    "forwardedProps": {}
  }'
```

`Accept: application/vnd.ag-ui.event+proto` → length-prefixed WKT `google.protobuf.Value` (not official `Event` oneof). GET on the path → `AgentCapabilities`. Clack app only: `make-ag-ui-app`.

---

## 3. Client consume (async × libuv)

```lisp
(asdf:load-system "ag-ui-backend-sse")
(asdf:load-system "event-backend-libuv")
(asdf:load-system "http-backend-async")

(setf http-backend-async:*event-backend-maker*
      #'event-backend-libuv:make-libuv-backend)
(setf http-protocol:*http-backend*
      (http-backend-async:make-async-backend))

(let ((backend (ag-ui-backend-sse:make-sse-ag-ui-backend
                :url "http://127.0.0.1:8000/")))
  (ag-ui-protocol:run-agent
   backend
   (ag-ui-protocol:make-run-agent-input
    :thread-id "t" :run-id "r"
    :messages (list (ag-ui-protocol:make-ag-ui-message
                     :role "user" :content "hi")))))
```

Or parse a captured stream: `decode-ag-ui-sse-stream`.

Reducer (`json-patch` for `STATE_DELTA`):

```lisp
(asdf:load-system "ag-ui-protocol/client")
(ag-ui-client:reduce-events events)   ; → agent-state
```

---

## 4. Interrupts / resume

`RUN_FINISHED` with `outcome: "interrupt"` + `interrupts[]`. Answer with `RunAgentInput.resume` (`make-resume-entry` / `validate-resume`). Client reducer surfaces `agent-state-status` `:interrupted` + `agent-state-interrupts`.

HITL desk: [`ag-ui-backend-tui`](https://github.com/egao1980/ag-ui-backend-tui) (`AG_UI_TUI_APPROVE=1`). Product glue: [`cl-stack-llm-tui`](https://github.com/egao1980/cl-stack-llm-tui).

---

## 5. TUI sink

Consumes **AG-UI events only** — never `ai-agent-protocol` `:part`. Not a wire client (no `run-agent`).

```lisp
(asdf:load-system "ag-ui-backend-tui")
(let ((tr (ag-ui-backend-tui:make-transcript)))
  (ag-ui-backend-tui:apply-ag-ui-event
   tr (ag-ui-protocol:make-text-message-content-event
       :message-id "m" :delta "hi"))
  (ag-ui-backend-tui:render-transcript tr))
```

Loop ownership when painting: tuition `tui:run` on the main thread; `event-protocol:run` (libuv) on a side thread. Never `http:request` on the tuition thread.

Canary: [`ag-ui-parity`](https://github.com/egao1980/ag-ui-parity) (SSE JSON full; WKT Lisp-only).

---

## Event types

All 36 upstream types, including reasoning / activity / subagent / chunks. Inventory is pinned by `every-upstream-event-type-is-modelled`. See [brief](../capabilities/ag-ui.md).

---

## 6. JSON Schema (`schema-protocol-json`)

```lisp
(ag-ui-json-schema 'ag-ui-event)
(ag-ui-json-schema 'run-agent-input)
(validate-ag-ui-json "{\"type\":\"RUN_STARTED\",\"threadId\":\"t\",\"runId\":\"r\"}")
```

Tool `parameters` is a JSON Schema document — `validate-tool-arguments`.

# Cookbook: SSE (`sse-protocol`)

**Audience:** W3C / WHATWG `text/event-stream` — the framing MCP Streamable HTTP, A2A `message/stream`, and AG-UI all share.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-sse`) | [`sse-protocol`](https://github.com/egao1980/sse-protocol) | **0.1.0** |
| Client | [`sse-backend-http`](https://github.com/egao1980/sse-backend-http) | **0.1.0** |
| Server | [`sse-backend-clack`](https://github.com/egao1980/sse-backend-clack) | **0.1.0** |

Brief: [sse.md](../capabilities/sse.md) (#184). SSE is **framing**, not a serdes format. `data:` is already-encoded JSON (JSON-RPC, AG-UI events, …).

```lisp
(cl-repo:load-system "sse-protocol" :version "0.1.0")
```

---

## 1. Framing (no HTTP)

```lisp
(use-package :stack-sse)

(let ((ev (make-sse-event :id "1" :event "ping" :data "hi")))
  (decode-sse-block (encode-sse-event ev)))

(with-input-from-string (in (encode-sse-event (make-sse-event :data "hi")))
  (collect-sse-events in))
```

Multi-line `data:` is concatenated with `U+000A`. Empty `event:` is the default message type — do not dispatch empty-data as a named event. Comments (`: comment`) are keepalives / ignored.

Wire:

```
id: 1
event: ping
data: hi

```

---

## 2. Serve (Clack)

```lisp
(asdf:load-system "sse-backend-clack")
(asdf:load-system "http-server-backend-hunchentoot")

(sse-backend-clack:use-clack-sse-backend)
(http-server-backend-hunchentoot:use-hunchentoot-backend)

(http-server-protocol:with-server
    (s (sse-backend-clack:make-sse-app
        (list (sse-protocol:make-sse-event :id "1" :data "hi"))
        :path "/sse")
       :host "127.0.0.1" :port 8080)
  ...)
```

Handler may be a list of events, a single event, or `(lambda (env) → events)`. `Last-Event-ID` is `sse-backend-clack:request-last-event-id`.

`sse-protocol:serve-sse` is the same path via `*sse-backend*`.

---

## 3. Consume (http-protocol)

```lisp
(asdf:load-system "sse-backend-http")
(asdf:load-system "http-backend-dexador")

(sse-backend-http:use-http-sse-backend)
(setf http-protocol:*http-backend*
      (http-backend-dexador:make-dexador-backend))

(let ((conn (sse-protocol:open-sse "http://127.0.0.1:8080/sse")))
  (unwind-protect (sse-protocol:collect-sse-events conn)
    (sse-protocol:close-sse conn)))
```

`open-sse` also takes `:method :post`, `:content`, `:headers`, `:last-event-id`, `:timeout` (AG-UI / MCP POST-that-returns-SSE).

---

## 4. Keepalives (independent of object streams)

Default: comment `: ping` every 15s (`*sse-keepalive-interval*`). Style `:comment` | `:event`. `read-sse-event` skips them unless `:include-keepalives t`.

```lisp
(let ((ka (sse-protocol:make-sse-keepalive stream :interval 15)))
  ;; starts unless :start nil
  ;; …write events; note-sse-activity after each write…
  (sse-protocol:stop-sse-keepalive ka))
```

Do not fold the timer into the object-stream wrapper.

---

## 5. Object streams (`io-protocol`)

```lisp
(let ((out (sse-protocol:make-sse-output-stream stream)))
  (io-protocol:write-object out (sse-protocol:make-sse-event :data "hi")))

(let ((in (sse-protocol:make-sse-input-stream stream)))
  (io-protocol:read-object in)) ; → sse-event or :eof
```

Framing, not `prin1`. Canary: [`sse-parity`](https://github.com/egao1980/sse-parity) (Lisp ↔ Node `eventsource` / Python `httpx-sse`). Corpus: `sse-protocol` `tests/fixtures/` (WPT `eventsource/format-*` + rexxars static routes, Lisp-owned sexp).

---

## What not to do

- Don’t treat SSE as a serdes `:format` — payloads are already encoded.
- Don’t put JSON-RPC message types here — [`rpc-protocol`](rpc.md) / [`rpc-backend-sse`](rpc.md).
- Don’t use this for AG-UI protobuf *payload* encoding — that’s `ag-ui-backend-protobuf`.

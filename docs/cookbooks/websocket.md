# Cookbook: WebSocket client (browser / websockets → ws-protocol)

**Audience:** people who know browser `WebSocket` or Python [`websockets`](https://websockets.readthedocs.io/) / [`websocket-client`](https://websocket-client.readthedocs.io/) and want the same recipes on the Lisp stack.

**Packages:**

| Layer | Analogue | Lisp |
|-------|----------|------|
| Protocol / facade | browser `WebSocket` | [`ws-protocol`](https://github.com/egao1980/ws-protocol) (`ws` nick) |
| H1 Upgrade backend | websocket-client | [`ws-backend-websocket-driver`](https://github.com/egao1980/ws-backend-websocket-driver) · [`http-backend-winhttp`](https://github.com/egao1980/http-backend-winhttp) |
| H2 Extended CONNECT | (rare in Python) | [`http-backend-async`](https://github.com/egao1980/http-backend-async) **0.2.3+** |

Capability brief (RFCs, CLOS transport split): [ws-protocol.md](../capabilities/ws-protocol.md). Pins: [QUICKSTART](../QUICKSTART.md).

```lisp
(cl-repo:load-system "ws-protocol" :version "0.2.2")
;; H1 Upgrade (cross-platform driver):
(cl-repo:load-system "ws-backend-websocket-driver" :version "0.2.2")
;; or Windows native:
;; (cl-repo:load-system "http-backend-winhttp" :version "0.1.3")
;; H2 Extended CONNECT (event-loop):
;; (cl-repo:load-system "http-backend-async" :version "0.2.4")
```

---

## Quickstart map

| Browser / Python | ws-protocol | Notes |
|------------------|-------------|--------|
| `new WebSocket(url)` | `(ws:connect url)` / `ws:with-connection` | blocking; bind `*ws-backend*` or pass `:backend` |
| `ws.send(text)` | `(ws:send conn text)` | `:type :binary` for octets |
| `ws.onmessage` | `(ws:on conn :message fn)` | also `:open` `:close` `:error` `:pong` |
| `ws.close()` | `(ws:close conn)` | |
| `ws.readyState` | `(ws:ready-state conn)` | `:connecting` `:open` `:closing` `:closed` |
| subprotocols | `:protocols '("chat")` on connect / client | |
| headers / auth | `:headers` / `:auth` | Basic/Bearer via `inject-auth-headers` |
| async connect | `(ws:connect-async url)` | Blackbird promise; **async backend** = event-loop native |
| HTTP/1.1 Upgrade | `:transport :http/1.1` | driver · WinHTTP |
| HTTP/2 Extended CONNECT | `:transport :http/2` | async only; needs peer `ENABLE_CONNECT_PROTOCOL` |
| auto | `:transport :auto` | prefer `:http/2` when backend lists it |

---

## 1. Local echo (H1 Upgrade)

Runnable demo (starts Clack echo + client):

```bash
# from a ws-backend-websocket-driver checkout with deps installed
ros -l scripts/demo.lisp
```

Minimal API shape:

```lisp
(asdf:load-system "ws-backend-websocket-driver")
(let ((backend (ws-backend-websocket-driver:make-websocket-driver-backend)))
  (ws:with-connection (conn "ws://127.0.0.1:19000/echo"
                            :backend backend
                            :transport :http/1.1)
    (ws:on conn :message (lambda (msg) (format t "← ~A~%" msg)))
    (ws:send conn "hi")
    (sleep 0.2)))
```

`wss://` uses cl+ssl; production TLS = `cl-stack-ssl` overlay (see QUICKSTART / `#35` smoke).

---

## 2. Transport preference

CLOS split (mirrors HTTP version on `http-protocol`):

| Preference | Wire |
|------------|------|
| `:http/1.1` | RFC 6455 Upgrade |
| `:http/2` | RFC 8441 Extended CONNECT (`:method CONNECT`, `:protocol websocket`) |
| `:auto` | Prefer `:http/2` if `backend-ws-transports` lists it |

```lisp
(backend-ws-transports backend)           ; e.g. (:http/1.1) or (:http/2)
(backend-supports-ws-transport-p b :auto)
(make-http2-websocket-connect-headers "wss://ex/chat" nil :protocols '("chat"))
```

Wrong transport → `ws-transport-not-available` (e.g. WinHTTP + `:http/2`, async + `:http/1.1`).

---

## 3. Extended CONNECT (async, event-loop)

`http-backend-async` **0.2.3+** runs handshake + DATA on `register-io` (same TLS WANT_* / H2 pump as HTTP). No BT frame reader.

```lisp
(cl-repo:load-system "http-backend-async" :version "0.2.4")
(cl-repo:load-system "event-backend-libuv" :version "0.1.1")

(setf http-backend-async:*event-backend-maker*
      (lambda () (event-backend-libuv:make-libuv-backend)))

(let* ((backend (http-backend-async:make-async-backend))
       (client (ws-protocol:make-ws-client backend :transport :http/2))
       (conn (ws-protocol:connect backend client "wss://example.com/ws"
                                  :transport :http/2)))
  (ws-protocol:on-event conn :message #'print)
  (ws-protocol:send-text conn "hi")
  (ws-protocol:close-connection conn))
```

Prefer **`connect-async`** when you already own an event loop (do **not** call blocking `connect` on the loop thread).

Demo script:

```bash
HTTP_ASYNC_WS_H2_URL=wss://… ros -l scripts/demo-ws.lisp   # in http-backend-async
```

Peer must advertise `SETTINGS_ENABLE_CONNECT_PROTOCOL=1` or you get `ws-transport-not-available` (acceptable for smoke).

Live gates: `HTTP_ASYNC_WS_H2_LIVE=1` / `:http-async-ws-h2-live` via `feature-or-env-enabled-p`.

---

## 4. WinHTTP (Windows H1)

```lisp
(cl-repo:load-system "http-backend-winhttp" :version "0.1.3")
(let* ((b (http-backend-winhttp:make-winhttp-backend))
       (c (ws-protocol:make-ws-client b :transport :http/1.1)))
  (ws-protocol:connect b c "wss://echo.websocket.events/"))
```

Live: `WINHTTP_WS_LIVE=1`. Upgrade-only — not RFC 8441.

---

## 5. Events & errors

| Event | Handler args (typical) |
|-------|-------------------------|
| `:open` | none |
| `:message` | text string or binary octets |
| `:pong` | payload octets |
| `:close` | `&key code reason` |
| `:error` | condition |

| Condition | When |
|-----------|------|
| `ws-handshake-error` | bad Upgrade / CONNECT status |
| `ws-connection-error` | I/O / TLS |
| `ws-transport-not-available` | backend/transport mismatch or no ENABLE_CONNECT |
| `unsupported-operation` | e.g. WinHTTP ping, proxy P2 |

---

## 6. Out of scope (for now)

- WebSocket **server**
- permessage-deflate (P2)
- Proxy for Extended CONNECT (P2)
- Multiplexed app protocols (JSON-RPC, STOMP, …) — sit above `ws-protocol`

---

## Demos

| Script | Repo | What |
|--------|------|------|
| `scripts/demo.lisp` | [ws-backend-websocket-driver](https://github.com/egao1980/ws-backend-websocket-driver) | Local H1 echo round-trip |
| `scripts/demo-ws.lisp` | [http-backend-async](https://github.com/egao1980/http-backend-async) | Extended CONNECT open (env URL) |

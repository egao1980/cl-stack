# ws-protocol (wave-1)

**Issues:** [#4](https://github.com/egao1980/cl-stack/issues/4) · [#33](https://github.com/egao1980/cl-stack/issues/33) · [#34](https://github.com/egao1980/cl-stack/issues/34) · [#35](https://github.com/egao1980/cl-stack/issues/35)  
**Status:** wave-1 **complete** ([#4](https://github.com/egao1980/cl-stack/issues/4) closed) — brief `#33`; [`egao1980/ws-protocol`](https://github.com/egao1980/ws-protocol) cleartext `#34` + WSS/`cl-stack-ssl` `#35`; hub corpus `tests/corpus/ws/echo-frames/`

WebSocket **client** facade (RFC 6455). Separate from `http-protocol` (API.md) — Java puts WS on `HttpClient`; we keep a dedicated protocol so HTTP backends stay thin.

Conventions: [API.md](../API.md). Event DX: [event-protocol.md](event-protocol.md). TLS overlays: [overlays.md](../overlays.md). Pins: [pins.md](../pins.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **DX target** | **websockets** / browser `WebSocket` shape | Familiar connect / send / on-message / close; httpx has no first-class WS |
| **Wave-1 backend** | **[`websocket-driver`](https://github.com/fukamachi/websocket-driver)** (`websocket-driver-client`) | De-facto CL client; usocket + cl+ssl; BSD-2; Clack ecosystem |
| **Async DX** | **Promises** (same as event/http facades) | `connect-async` → promise of connection; handlers stay callbacks; compose with HTTP |
| **Event loop** | Prefer ops schedulable on `event-protocol` | Driver wave-1 may use BT threads internally; facade must not block the loop thread on `send`/`close` without documenting affinity |
| **TLS / WSS** | **cl+ssl** + `cl-stack-ssl` overlay | Same as HTTPS (#12 / #35); no second TLS stack |
| **Windows** | **Primary** | usocket path; no libev/Woo required for client |
| **Server** | **H1 Upgrade shipped** (`accept` / `make-ws-server` `:transport`) | Protocol **0.4.0** takes `:auto` / `:http/1.1` / `:http/2`. Driver **0.3.0** is H1; H2 Extended CONNECT server = PRs in flight |
| **Extensions** | **permessage-deflate** = **P2** | RFC 7692; ship only if backend exposes it cheaply |
| **Subprotocols** | Pass-through `:protocols` list | Negotiate via handshake headers |

Selection DX: ASDF + `*ws-backend*` (no plugin registry) — same as http/event.

---

## Normative RFCs

| RFC | Role |
|-----|------|
| **[RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.html)** | WebSocket protocol (HTTP/1.1 Upgrade) |
| **[RFC 8441](https://www.rfc-editor.org/rfc/rfc8441.html)** | Bootstrapping WebSockets with HTTP/2 (Extended CONNECT) |
| **[RFC 7692](https://www.rfc-editor.org/rfc/rfc7692.html)** | permessage-deflate — **P2** |
| **[RFC 2818](https://www.rfc-editor.org/rfc/rfc2818.html)** | TLS for `wss://` |

---

## Transport preference (0.2.0+)

CLOS split (mirrors `http-protocol` HTTP version):

| Layer | Owns |
|-------|------|
| **ws-protocol** | `:transport` preference (`:auto` / `:http/1.1` / `:http/2`), `backend-ws-transports` / `backend-supports-ws-transport-p`, RFC 8441 header policy (`make-http2-websocket-connect-headers`) |
| **backends** | Wire: RFC 6455 Upgrade **or** H2 Extended CONNECT + RFC 6455 framing on the stream |

| Keyword | Meaning |
|---------|---------|
| `:http/1.1` | RFC 6455 Upgrade (`websocket-driver`, WinHTTP `WinHttpWebSocket*`) |
| `:http/2` | RFC 8441 Extended CONNECT (`:method CONNECT`, `:protocol websocket`) |
| `:auto` | Prefer `:http/2` when backend lists it, else `:http/1.1` |

| Backend | Transports | Notes |
|---------|------------|-------|
| [`ws-backend-websocket-driver`](https://github.com/egao1980/ws-backend-websocket-driver) | `:http/1.1` | Wave-1 driver (own repo) |
| `http-backend-winhttp` **0.1.3+** | `:http/1.1` | Native WinHTTP WebSocket upgrade; live `WINHTTP_WS_LIVE` |
| `http-backend-async` **0.2.3+** | `:http/2` | RFC 8441 Extended CONNECT + `fast-websocket` framing; live `HTTP_ASYNC_WS_H2_LIVE` |

`ws-protocol` **0.2.2+**: `feature-or-env-enabled-p` for live/smoke gates (`*features*` ∪ truthy env). Cookbook: [websocket.md](../cookbooks/websocket.md); demos `ws-backend-websocket-driver/scripts/demo.lisp`, `http-backend-async/scripts/demo-ws.lisp`.

---

## Protocol surface

### Types

| Type | Role |
|------|------|
| `ws-backend` | Backend marker (websocket-driver wrapper) |
| `ws-client` | Defaults: headers, protocols, proxy, verify, cookie-jar (optional) |
| `ws-connection` | Open socket; ready-state; close code/reason |
| `ws-message` | Text or binary payload (+ optional opcode) |

### Generics / ops

```lisp
(defgeneric connect (backend client url &key))          ; → ws-connection (blocking)
(defgeneric connect-async (backend client url &key callback error-callback))
(defgeneric send-text (connection text &key))
(defgeneric send-binary (connection octets &key))
(defgeneric ping (connection &optional payload &key))
(defgeneric close-connection (connection &key code reason))
(defgeneric on-event (connection event handler))        ; :open :message :close :error :pong
```

`EVENT` keywords mirror websocket-driver: `:open`, `:message`, `:close`, `:error` (+ `:pong` when available).

### Facade sketch (`ws` package)

```lisp
(ws:connect url &key protocols headers auth proxy verify cookie-jar backend client)
(ws:connect-async url &key …)          ; → promise of connection

(ws:send conn message &key type)       ; :text | :binary
(ws:ping conn &optional payload)
(ws:close conn &key code reason)

(ws:on conn :message (lambda (msg) …))
(ws:on conn :close (lambda (&key code reason) …))

(ws:with-connection ((conn url &key …)) …)   ; unwind-protect close
```

`:auth` reuses http-protocol shapes where useful (`(:basic u p)` / `(:bearer tok)` → handshake headers).

### Conditions

| Condition | When |
|-----------|------|
| `ws-error` | Base |
| `ws-handshake-error` | Non-101 / bad Upgrade |
| `ws-connection-error` | TCP / TLS failure |
| `ws-timeout-error` | Connect / idle policy |
| `ws-protocol-error` | Framing / unexpected close |
| `unsupported-operation` | Backend stub (e.g. deflate P2) |

---

## Backpressure

Wave-1 **minimum:**

1. `send` may signal or reject the promise when the socket write buffer is full / driver signals congestion.
2. Document whether `send` is synchronous to the wire or queued.
3. No full reactive streams API in wave-1 — apps throttle via promise chaining / pause reading if the driver exposes it.

P2: high-water marks, explicit `drain` / `pause` / `resume` mirroring Node `stream` / browser backpressure.

---

## Backend plan

| Layer | Repo | Notes |
|-------|------|-------|
| Protocol | [`egao1980/ws-protocol`](https://github.com/egao1980/ws-protocol) | generics + conditions + `ws` facade |
| Client backend | [`egao1980/ws-backend-websocket-driver`](https://github.com/egao1980/ws-backend-websocket-driver) | wraps `websocket-driver-client` |
| TLS | `cl-stack-ssl` | `#35` WSS Done-when |

---

## Relationship to HTTP / event

- Handshake is HTTP/1.1 Upgrade — **not** routed through `http-protocol` `send` (driver owns the Upgrade). Shared concerns: URI (`quri`/`cl-idna`), cookies, TLS verify, proxy (P2 if driver gaps).
- Async composition uses the same **promise** DX as `http:*-async`. Running beside `event-protocol` loops: do not call blocking `connect` on the loop thread; use `connect-async` / `defer`.

---

## Implementation order

1. `#33` — this brief — **done**
2. `#34` — `ws-protocol` + websocket-driver backend + cleartext `ws://` Rove tests — **done**
3. `#35` — `wss://` via `cl-stack-ssl` overlay — **done** (linux/amd64 `wss-openssl` CI; `scripts/smoke-wss-clean-container.sh`; windows matrix P2)
4. Corpus slice under `tests/corpus/ws/` (MIT synthetic echo vectors) + PROVENANCE — **done** (`ws/echo-frames` + `cl-stack/corpus-smoke`)

---

## Out of scope (wave-1)

- WebSocket **server**
- Multiplexed subprotocol frameworks (JSON-RPC, STOMP, …) — app layer
- Browser cookie ITP edge cases
- permessage-deflate (unless free with driver)

## Extended CONNECT status

- **Done** in `http-backend-async` **0.2.3** (event-loop I/O: TLS WANT_* + `async-h2-pump-stream` + `register-io`; `connect-async` primary).
- WinHTTP stays Upgrade-only (OS API); H2 WS = async backend.

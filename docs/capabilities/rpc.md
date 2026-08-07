# rpc-protocol (P2)

**Issues:** [#170](https://github.com/egao1980/cl-stack/issues/170) · related [#106](https://github.com/egao1980/cl-stack/issues/106)  
**Status:** brief **locked** — CLOS protocol + transports; **codecs via serdes**

Request/response (and later notify) over a **transport**. Transports are pluggable: in-process, **subprocess stdio** ([process-protocol](process.md)), TCP, HTTP. Payloads encoded with [`serdes-protocol`](serdes.md) (`:sexp` / `:json`).

Shape targets: Python `xmlrpc`/`jsonrpc` simplicity, Java gRPC *service* feel without requiring HTTP/2 for wave-1, JSON-RPC 2.0 message model.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separation** | RPC ≠ process | Process owns OS; RPC owns framing + dispatch |
| **Message model** | JSON-RPC 2.0–shaped (id / method / params / result / error) | Widely understood; maps to sexp easily |
| **Codec** | serdes `:json` + `:sexp` | No private encoder |
| **Default transport (A)** | In-process loopback | Tests + same-image services |
| **Transport (B)** | Subprocess stdio line/length-prefixed | Language-server energy; needs process-protocol |
| **Transport (C)** | HTTP POST (single request) | Easy ops; reuse http-protocol |
| **gRPC / protobuf** | Watchlist | Needs protobuf stack; not wave-1 |
| **Async** | Promises on event-protocol for streaming transports | Match http-protocol DX |

```lisp
(defclass rpc-transport () ())
(defclass rpc-codec () ())   ; thin over serdes format keyword

(defgeneric rpc-call (transport method params &key timeout id))
(defgeneric rpc-notify (transport method params))
(defgeneric rpc-serve (transport handler &key))  ; handler(method params) → result | signal

;; Errors → condition rpc-error with code/message/data (JSON-RPC codes)
```

Framing for byte streams (stdio/TCP): **netstring** or **uint32be length + body** — pick length-prefix in impl; document in cookbook.

---

## Relationship

```text
app ── rpc-call ──► rpc-protocol ──► transport ──► process-protocol / http / socket
                         │
                      serdes encode/decode
```

---

## Non-goals (wave-1)

- Full gRPC compatibility
- Bidirectional streaming RPC product
- Service discovery / IDL compiler

---

## Implementation tasks

- [ ] Brief lock — this doc
- [ ] Issue + `rpc-protocol` + in-process + stdio transports
- [ ] Cookbook: Lisp parent ↔ child worker over stdio
- [ ] Depends on: serdes (done), process-protocol, optionally http-protocol

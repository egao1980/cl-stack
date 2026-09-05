# grpc-protocol (P1)

**Status:** brief **locked** — CLOS channel/call/stream; Windows path = HTTP/2, not C-core

gRPC **wire** (channel / status / connect). App-facing call shapes live on [`rpc-protocol`](rpc.md); the adapter is [`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc). A2A’s protobuf binding is `a2a-backend-grpc` calling through that.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backends | Match http-protocol (client) energy |
| **Default backend (A)** | `grpc-backend-http2` **0.3.1** (Windows + portable unary **+ interleaved bidi** + gzip/deflate frames) | `http-body-pipe` as request `:content` + `:want-stream`; `grpc-send` `:end` half-closes |
| **Unix C-core** | `grpc-backend-native` | qitab/grpc fork + linux/darwin overlay; Windows stays `:unimplemented` |
| **Codec** | [protobuf-protocol](protobuf.md) | Messages are proto objects |
| **HTTP/2** | `http-protocol` + backend | Frame in Lisp (flag+u32be+octets). Do **not** vcpkg/MSVC overlay C++ grpc |
| **Compression** | http2: `:gzip` / `:deflate` via `encode/decode-content-coding` | `grpc-encoding` + flag 1. **Not** HTTP `Content-Encoding`. Native ignores it |
| **h2c / `:insecure`** | http2 backend: TLS only | `http-protocol` rejects `:http/2` on `http://`. Native still does cleartext |
| **ABCL** | later `grpc-backend-java` | Same pattern as event-backend-nio |

## Repo layout

| Layer | Repo |
|-------|------|
| Wire protocol | [`egao1980/grpc-protocol`](https://github.com/egao1980/grpc-protocol) |
| rpc-protocol binding | [`egao1980/rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc) |
| HTTP/2 backend | [`egao1980/grpc-backend-http2`](https://github.com/egao1980/grpc-backend-http2) |
| Native backend | [`egao1980/grpc-backend-native`](https://github.com/egao1980/grpc-backend-native) |

`egao1980/grpc` stays the C++/CFFI fork (unix). Do not re-fork. Do not overlay it for Windows.

## Protocol surface

```lisp
(defclass grpc-backend () ())
(defclass grpc-channel () ())
(defclass grpc-call () ())
(defvar *grpc-backend* nil)

(defgeneric backend-grpc-connect (backend target &key credentials metadata))
(defgeneric backend-grpc-call (channel method request &key timeout metadata))
(defgeneric backend-grpc-stream (channel method &key metadata))
(defgeneric grpc-send (stream message &key))
(defgeneric grpc-recv (stream &key timeout))
(defgeneric grpc-close (channel-or-stream &key))

(defun grpc-connect (target &key credentials metadata compression (backend *grpc-backend*)) …)
(defun grpc-call (channel method request &key timeout metadata compression) …)
```

`:compression` is `:gzip` / `:deflate` / `nil` (also metadata `:compression`). http2 sets `grpc-encoding` and frame flag 1; codecs are `http-protocol` content-coding (`http-encoding-chipz`). Native C-core ignores it.

Conditions: `grpc-error` with status code / details.

## Non-goals

- JSON-RPC-over-gRPC
- Replacing qitab/grpc internals
- vcpkg/MSVC overlay of `egao1980/grpc`
- Reflection / codegen product (use cl-protobufs protoc as today)

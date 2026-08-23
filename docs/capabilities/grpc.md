# grpc-protocol (P1)

**Status:** brief **locked** — CLOS channel/call/stream; native backend = egao1980/grpc

gRPC is **not** an [`rpc-protocol`](rpc.md) transport. JSON-RPC 2.0 and gRPC do not share a message model. A2A’s protobuf binding is `a2a-backend-grpc` calling this protocol.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backends | Match http-protocol (client) energy |
| **Default backend (A)** | `grpc-backend-native` | qitab/grpc fork + existing native overlay |
| **Codec** | [protobuf-protocol](protobuf.md) | Messages are proto objects |
| **HTTP/2** | Backend / C++ stack | Do not reimplement H2 in Lisp for wave-1 |
| **ABCL** | later `grpc-backend-java` | Same pattern as event-backend-nio |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol | [`egao1980/grpc-protocol`](https://github.com/egao1980/grpc-protocol) |
| Native backend | [`egao1980/grpc-backend-native`](https://github.com/egao1980/grpc-backend-native) |

`egao1980/grpc` stays the C++/CFFI fork. The backend is a thin CLOS adapter — do not re-fork.

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

(defun grpc-connect (target &key credentials metadata (backend *grpc-backend*)) …)
(defun grpc-call (channel method request &key timeout metadata) …)
```

Conditions: `grpc-error` with status code / details.

## Non-goals

- JSON-RPC-over-gRPC
- Replacing qitab/grpc internals
- Reflection / codegen product (use cl-protobufs protoc as today)

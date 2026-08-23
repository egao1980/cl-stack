# protobuf-protocol (P1)

**Status:** brief **locked** — serdes implementor + CLOS message GFs; backend = cl-protobufs

Binary protobuf encode/decode. Required for A2A’s official gRPC binding and AG-UI’s optional protobuf transport.

This is the **format** layer. gRPC *calls* live in [`grpc-protocol`](grpc.md).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | Implements [serdes-protocol](serdes.md) `:protobuf` | Brief already reserved protobuf as a serdes implementor |
| **Default backend (A)** | `protobuf-backend-cl-protobufs` | egao1980 fork of qitab/cl-protobufs; overlay/protoc story exists |
| **Second backend** | none wave-1 | ABCL/Java protobuf later if needed |
| **Values** | CLOS proto messages (cl-protobufs classes) | Don’t invent a parallel DOM |
| **Octets first** | `encode-to-octets` / `decode-octets` | SSE/gRPC want bytes, not UTF-8 strings |

## Repo layout

| Layer | Repo |
|-------|------|
| Protocol (serdes register + GFs) | [`egao1980/protobuf-protocol`](https://github.com/egao1980/protobuf-protocol) |
| Default backend | [`egao1980/protobuf-backend-cl-protobufs`](https://github.com/egao1980/protobuf-backend-cl-protobufs) |

## Protocol surface

```lisp
(defclass protobuf-backend (serdes:serdes-backend) ())
(defvar *protobuf-backend* nil)

(defgeneric encode-message (backend message &key))
(defgeneric decode-message (backend octets message-class &key))
(defgeneric load-schema (backend source &key))   ; .proto / proto-descriptor

;; serdes
(serdes:register-format :protobuf (make-instance 'protobuf-backend))
```

Schema compile (protoc / cl-protobufs ASDF) stays in the backend. Protocol does not shell out.

## Non-goals

- Shipping a new protoc
- gRPC stubs (grpc-protocol)
- Replacing cl-protobufs’ generated classes

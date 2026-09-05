# messagepack-protocol (P2)

**Status:** **shipped** — [`egao1980/messagepack-protocol`](https://github.com/egao1980/messagepack-protocol) OCI **0.1.0** (`stack-messagepack`)

MessagePack. Same Lisp mapping as [`json-protocol`](json-protocol.md), plus `bin` and `ext`. **Implements** [`serdes-protocol`](serdes.md) `:messagepack` and `:msgpack` (binary, `application/msgpack`). Soft-hooks `http-protocol`.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Format stack implements serdes |
| **Canonical keyword** | `:messagepack` (media-type lookup); `:msgpack` is an alias |
| **Null / false** | `:null` → 0xc0; Lisp `nil` → false (0xc2) |
| **Timestamp** | ext type `-1` → `msgpack-timestamp` |
| **Floats** | SBCL in 0.1.0 |

## Non-goals

- wrapping `cl-messagepack`

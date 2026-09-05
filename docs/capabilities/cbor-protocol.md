# cbor-protocol (P2)

**Status:** **shipped** — [`egao1980/cbor-protocol`](https://github.com/egao1980/cbor-protocol) OCI **0.1.0** (`stack-cbor`)

RFC 8949 CBOR. Same Lisp mapping as [`json-protocol`](json-protocol.md), plus byte strings and tags. **Implements** [`serdes-protocol`](serdes.md) `:cbor` (binary, `application/cbor`). Soft-hooks `http-protocol` `:cbor`.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Format stack implements serdes |
| **Mapping** | object → equal hash-table (string keys); array → vector; null → `:null`; false → `nil`; true → `t` |
| **Bytes** | `(vector (unsigned-byte 8))` |
| **Tags** | `cbor-tag`; tags 2/3 decode to bignums |
| **Lengths** | definite encode; indefinite decode |
| **Floats** | SBCL in 0.1.0 |

## Non-goals

- CDDL
- wrapping a QL CBOR library

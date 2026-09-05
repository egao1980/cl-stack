# avro-protocol (P2)

**Status:** **shipped** — [`egao1980/avro-protocol`](https://github.com/egao1980/avro-protocol) OCI **0.1.0** (`stack-avro`) + `schema-protocol-avro` **0.1.1**

Avro **binary** encoding. Writer schema required; optional reader schema (resolution + defaults). **Implements** [`serdes-protocol`](serdes.md) `:avro` (`application/avro`, `avro/binary`). `schema-protocol-avro` registers [`schema-protocol`](schema.md) `:avro` (`emit-schema` / `parse-schema`; `avro-schema` wraps emit). Soft-hooks `http-protocol` `:avro`.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Format stack implements serdes; schema emit is a sibling system |
| **Schema** | JSON string / hash-table / compiled `avro-schema` |
| **Serdes** | bind `*avro-schema*` or pass `(:schema SCH :octets OCTETS)` |
| **Mapping** | same as json-protocol; unions pick the first matching branch |
| **Floats** | SBCL in 0.1.0 |

## Non-goals

- Avro JSON encoding
- object-container files
- wrapping a QL Avro library

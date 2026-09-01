# arrow-protocol

**Status:** wave-1 **shipped** — native Lisp Arrow IPC + Parquet; serdes `:arrow` / `:parquet`

CLOS Apache Arrow / Parquet. **Not** a CFFI wrap of Arrow C++.

```text
serdes-protocol
       ▲
arrow-protocol   (schema/table + IPC + parquet)
       ▲ registers
:arrow    IPC file (encode) / IPC stream (stream-*-value)
:parquet  parquet file (encode only)

schema-protocol-arrow   defschema → arrow-schema + table↔objects
```

Cookbook: [serdes.md](../cookbooks/serdes.md). Schema emit: [schema.md](schema.md).

---

## Repos

| Layer | Repo | OCI |
|-------|------|-----|
| Codec + serdes (`stack-arrow`) | [`arrow-protocol`](https://github.com/egao1980/arrow-protocol) | **0.1.0** (first publish pending) |
| Schema emit (`stack-schema-arrow`) | [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) | **0.1.0** (first publish pending) |

## Surface

Types: scalars (`:int8`–`:64`, `:utf8`, `:bool`, dates/times, `(:decimal p s)`), `(:list)`, `(:struct)`, `(:map)`. Missing = `:null`.

```lisp
(stack-arrow:table-from-rows rows :schema schema)
(stack-arrow:encode table :format :arrow)     ; IPC file
(stack-arrow:encode table :format :parquet)   ; snappy+dict if loaded
(stack-arrow:decode octets :format :parquet)
```

Parquet write: compliant 3-level LIST; read compliant **and** Spark 2-level bag. Soft compressors: `cl-stack-snappy` / zstd / brotli / gzip. Encryption: `AES_GCM_V1` via `crypto-protocol` (`:footer-key`).

## Non-goals

- `arrow-backend-*` / nanoarrow / Arrow C++ / Flight / C Data Interface / compute
- `AES_GCM_CTR_V1`, KMS, INTERVAL
- Arrow schema → `defschema` compile

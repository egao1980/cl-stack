# openapi-protocol (P2)

**Status:** **shipped** — [`egao1980/openapi-protocol`](https://github.com/egao1980/openapi-protocol) OCI **0.1.0** (`stack-openapi`).

OpenAPI 3.1 document emit. Schemas via [`schema-protocol-json`](schema-protocol.md) (`oneOf` + `discriminator`; `$defs` hoisted to `components.schemas`). Envelope via [`json-protocol`](json-protocol.md) / `yaml-protocol`. App contract stays Clack (`http-server-protocol`) — `document-app` / `wrap-app` only.

YAML **extends** JSON (`yaml-backend` ⊆ `json-backend`, same repo). JSON ⊂ YAML at the document level. `json-protocol` does not depend on YAML.

Wave-1: emit only. No codegen, no request validation (`schema-protocol`).

# csv-protocol (P1)

**Status:** implemented — [`egao1980/csv-protocol`](https://github.com/egao1980/csv-protocol) `0.1.0` (`stack-csv`). Not on GHCR until tagged publish.  
**Cookbook:** [csv.md](../cookbooks/csv.md)

CLOS encode/decode for CSV (RFC 4180 dialects). **Implements** [`serdes-protocol`](serdes.md) `:csv` and `:tsv`. First-party codec — no `cl-csv`.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Format stack implements serdes (not a `serdes-backend-csv` shim) |
| **Codec** | First-party incremental RFC 4180 (quoted newlines). Not line-based. |
| **Document** | Vector of rows |
| **Row (`:header t`)** | hash-table (`equal`), **string** keys |
| **Row (`:header nil`)** | vector of strings |
| **Field** | string; `:quoting :nonnumeric` may yield numbers on decode |
| **Empty field** | `""` |
| **Dialect** | `csv-dialect` CLOS object (Python `csv.Dialect` shape). **Not** `sql-query-csv:csv-dialect` (SQL catalog). |
| **Presets** | `:rfc4180` (default), `:excel`, `:excel-tab` / `:tsv`, `:excel-eu` (`;`), `:unix` |
| **Slots** | `delimiter` `quote-char` `escape-char` `double-quote` `skip-initial-space` `line-terminator` `quoting` (`:minimal` `:all` `:nonnumeric` `:none`) |
| **`:header`** | Reader option, not a dialect field |
| **Serdes extras** | Façade does not forward kwargs — use `*csv-dialect*`, a configured backend, or `:format :tsv` |
| **Streams** | Specialize `stream-*-value` (not default `read-line`) |
| **Events** | `:header` `:begin-row` `:field` `:end-row` |
| **Errors** | `csv-error` / `csv-encode-error` / `csv-parse-error`; restarts `use-value` / `continue` |

---

## Non-goals

- Migrating `sql-query-csv` onto this codec
- Excel dialect zoo beyond the presets
- Global number-coerce flag
- `cl-csv` backend
- XML

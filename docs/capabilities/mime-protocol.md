# mime-protocol (P2)

**Status:** **shipped** — [`egao1980/mime-protocol`](https://github.com/egao1980/mime-protocol) OCI **0.1.0** (`stack-mime`)

CLOS media-type / Content-Disposition / CTE / multipart. **Implements** [`serdes-protocol`](serdes.md) `:mime` and `:multipart`. Soft-hooks `http-protocol` `*data-serializers*` when that package is loaded.

**Not** HTTP `Content-Encoding` (gzip/br/zstd) — that stays on [`http-protocol`](http-protocol.md). CTE bytes use [`encoding-protocol`](encoding-protocol.md). **Not** the LGPL `cl-mime` email fork.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Format stack implements serdes (not a `serdes-backend-mime` shim) |
| **`:mime`** | Whole RFC 2045 entity ↔ `mime-entity` |
| **`:multipart`** | alist / hash-table ↔ `multipart/form-data` |
| **CTE** | `decode-content` / `encode-content` — 7bit / 8bit / binary / base64 / quoted-printable |
| **HTTP forms** | `http-protocol` still owns `:form-data` / `:files` streaming multipart |
| **HTTP `:data`** | `:mime` / `:multipart` via hooks; `:auto` uses them when registered |

## Non-goals

- Wrapping `cl-mime`
- HTTP Content-Encoding
- email MUA / IMAP

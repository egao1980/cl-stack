# mime-protocol (P2)

**Status:** **shipped** — [`egao1980/mime-protocol`](https://github.com/egao1980/mime-protocol) OCI **0.3.1** (`stack-mime`)

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
| **Multipart** | Any subtype, nested (`mixed(alternative(text, html), attachment)`); the CRLF before a delimiter is the delimiter's (RFC 2046 §5.1.1), so print and parse round-trip (0.3.0) |
| **Header names** | Stored lowercase, looked up case-insensitively, printed by `canonical-header-name` (`MIME-Version`, `Message-ID`) (0.3.0) |
| **Form-data names** | A header field that is valid UTF-8 is read as UTF-8, else ISO-8859-1; in a `form-data` disposition `name` / `filename` take a literal backslash and decode `%22 %0D %0A`, as browsers write them (RFC 7578, HTML form encoding); everything else keeps RFC 822 quoted-pairs (0.3.1) |

## Non-goals

- Wrapping `cl-mime`
- HTTP Content-Encoding
- email MUA / IMAP

## Open

- [mime-protocol#12](https://github.com/egao1980/mime-protocol/issues/12): `set-header` / `print-mime` accept CR or LF in a header value (header injection; Python's `EmailMessage` raises `ValueError`)
- [mime-protocol#13](https://github.com/egao1980/mime-protocol/issues/13): a part with no `Content-Type` parses with `mime-content-type` `NIL`, not the RFC 2045 default `text/plain`

Demo: [cl-stack-demos `harness/mime-multipart`](https://github.com/egao1980/cl-stack-demos/tree/main/harness/mime-multipart) (0.3.0, with a cross-read by Python's `email` package).

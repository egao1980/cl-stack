# mime-protocol (P2)

**Status:** **shipped** — [`egao1980/mime-protocol`](https://github.com/egao1980/mime-protocol) OCI **0.3.3** (`stack-mime`)

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
| **Header fields** | `set-header` refuses CR, LF or NUL in a value and a name that is not RFC 5322 ftext: `mime-header-error` (a `mime-encode-error`; restart `use-value`), as Python's `EmailMessage` refuses them; `print-mime` checks every field again before it writes. A line over `:max-line-length` octets (default 998) folds before a space, so unfolding gives the value back (0.3.2) |
| **Header text** | `print-mime` writes one character per octet, header text as UTF-8 (RFC 6532), so `parse-mime` reads back any header text; `print-mime-octets` (0.3.2) |
| **RFC 2047** | `encode-header-text` (only the words that need it) / `encode-encoded-words` (a whole display name) / `decode-header-text` (B and Q, any charset encoding-protocol knows) (0.3.2) |
| **Boundaries** | Default multipart boundary: 96 OS-random bits; a part holding its own delimiter line is refused (`mime-boundary-error`, restart `use-value` takes another boundary) (0.3.2) |
| **Continuations** | A long `filename*` goes out as RFC 2231 continuations outside form-data; `parse-content-disposition` joins them, as Python and Thunderbird write them (0.3.3) |
| **Relay** | A parsed field that was not UTF-8 is printed back as its octets (0.3.3) |
| **Serdes** | `:mime` / `:multipart` are binary formats: `encode` returns `print-mime-octets` (0.3.3) |

## Non-goals

- Wrapping `cl-mime`
- HTTP Content-Encoding
- email MUA / IMAP

## Open

- [mime-protocol#13](https://github.com/egao1980/mime-protocol/issues/13): a part with no `Content-Type` parses with `mime-content-type` `NIL`, not the RFC 2045 default `text/plain`
- [mime-protocol#11](https://github.com/egao1980/mime-protocol/issues/11): `disposition-filename` decodes `filename*` lazily, so an unsupported charset signals `mime-parse-error` when it is read, not when the header is parsed

Demo: [cl-stack-demos `harness/mime-multipart`](https://github.com/egao1980/cl-stack-demos/tree/main/harness/mime-multipart) (0.3.0, with a cross-read by Python's `email` package).

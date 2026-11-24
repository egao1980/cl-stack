# encoding-protocol (P2)

**Status:** **shipped** — [`egao1980/encoding-protocol`](https://github.com/egao1980/encoding-protocol) OCI **0.3.0** (`stack-encoding`)

RFC 4648 (Base16/32/64), RFC 2045 quoted-printable, classic byte RLE, RFC 3986 percent-encoding (0.3.0), strict UTF-8 decoding (0.3.0). Core depends only on Babel. Load `encoding-protocol/serdes` to register [`serdes-protocol`](serdes.md) `:base64` / `:base64url` / `:base32` / `:base32hex` / `:base16` (`:hex`) / `:quoted-printable` / `:rle`.

**Not** HTTP `Content-Encoding` (gzip/br/zstd/snappy) — that stays on [`http-protocol`](http-protocol.md). **Not** MIME parse/print — [`mime-protocol`](mime-protocol.md) uses this for CTE. First-party consumers (http / ws / mime / secrets / jwt / oauth2 / arrow / http-parity) use this instead of `cl-base64`.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | Own `encode` / `decode`; optional serdes implementor system |
| **Pad** | `:pad t` is RFC-canonical; decode ignores `SP` / `HT` / `CR` / `LF` unless `:strict t` |
| **QP / MIME CTE** | `:columns 76` on encode |
| **RLE** | count,value pairs (count 1–255). Parquet hybrid RLE stays in [`arrow-protocol`](arrow.md) |
| **Percent-encoding** | `percent-encode` / `percent-decode` / `percent-decode-octets`: RFC 3986 §2.1 over UTF-8 octets, ASCII unreserved set, upper-case hex, `:safe` extra characters, optional `+` for space; a malformed escape or non-ASCII input is an `encoding-decode-error` (0.3.0) |
| **Strict UTF-8** | `decode-utf-8-strict` (and `decode … :strict t` for `:utf-8`): overlong forms, surrogates, code points above U+10FFFF, stray continuation bytes and truncated sequences are an `encoding-decode-error` (RFC 3629) (0.3.0) |
| **Errors** | `encoding-decode-error` with `continue` (skip) / `use-value` |

## Non-goals

- HTTP Content-Encoding
- wrapping `cl-base64` / `cl-qprint`
- URI parsing (quri)
- email MUA

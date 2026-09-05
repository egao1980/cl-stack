# encoding-protocol (P2)

**Status:** **shipped** — [`egao1980/encoding-protocol`](https://github.com/egao1980/encoding-protocol) OCI **0.1.2** (`stack-encoding`)

RFC 4648 (Base16/32/64), RFC 2045 quoted-printable, classic byte RLE. Core depends only on Babel. Load `encoding-protocol/serdes` to register [`serdes-protocol`](serdes.md) `:base64` / `:base64url` / `:base32` / `:base32hex` / `:base16` (`:hex`) / `:quoted-printable` / `:rle`.

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
| **Errors** | `encoding-decode-error` with `continue` (skip) / `use-value` |

## Non-goals

- HTTP Content-Encoding
- wrapping `cl-base64` / `cl-qprint`
- URI percent-encoding (quri)
- email MUA

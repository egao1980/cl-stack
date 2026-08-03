# Corpus provenance

Record every non-original test vector or vendored fixture.
Synthetic / regenerated files under this tree are **MIT** (original).

| Path | Source URL | Commit/tag | SPDX | Notes |
|------|------------|------------|------|-------|
| `http/redirect-policy/vectors.lisp` | _(original)_ | — | MIT | Synthetic redirect follow policy table for http-protocol / backends |
| `http/ce-roundtrip/plaintext.txt` | _(original)_ | — | MIT | Synthetic plaintext for CE round-trips |
| `http/ce-roundtrip/plaintext.gz` | _(original)_ | — | MIT | `gzip.compress` regenerated (mtime=0); not copied from upstream |
| `http/ce-roundtrip/plaintext.zlib` | _(original)_ | — | MIT | `zlib.compress` regenerated; zlib-wrapped deflate |
| `http/ce-roundtrip/manifest.lisp` | _(original)_ | — | MIT | SHA-256 index for the CE binaries |
| `ws/echo-frames/vectors.lisp` | _(original)_ | — | MIT | Synthetic WS echo/framing table for ws-protocol |
| `ws/echo-frames/README.md` | _(original)_ | — | MIT | Slice note |

Allowlist: MIT, BSD-2/3, Apache-2.0, Unlicense, 0BSD, CC0. No GPL/AGPL/LGPL in this tree.

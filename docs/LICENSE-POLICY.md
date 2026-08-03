# License policy

**Project license: MIT** for all original cl-stack code, docs, and test ports.

## Inbound allowlist

| Kind | Allowed | Reject / isolate |
|------|---------|------------------|
| Runtime deps | MIT, BSD-2/3, Apache-2.0, Unlicense, 0BSD, CC0, public domain | GPL, AGPL in default pin set |
| LGPL native `.so`/`.dylib` | Overlay + `NOTICE` only; Lisp stays MIT | Static link without review |
| Test corpus from Py/Java/C++ | Same allowlist + provenance | GPL/AGPL/LGPL suites; unclear license |
| Dual-licensed | Take MIT/BSD/Apache option only | — |

## Provenance

Any vendored or ported foreign test material needs an entry in [`tests/corpus/PROVENANCE.md`](../tests/corpus/PROVENANCE.md): source URL, commit/tag, SPDX.

Layout conventions: [`tests/corpus/README.md`](../tests/corpus/README.md).
Smoke suite: `asdf:test-system "cl-stack/corpus-smoke"`.

Prefer **regenerate / re-express under MIT** over copying copyrighted test sources.

## Corpus license CI

[`scripts/check-corpus-license.py`](../scripts/check-corpus-license.py) runs in [`.github/workflows/corpus-license.yml`](../.github/workflows/corpus-license.yml):

1. Every fixture under `tests/corpus/<domain>/<slice>/` has a `PROVENANCE.md` row.
2. Provenance SPDX is on the allowlist above.
3. Fixture contents must not carry strong GPL/AGPL/LGPL markers
   (`SPDX-License-Identifier: …GPL…`, `GNU … General Public License`, `GPL-N`, `License: GPL`).
4. `--self-test` injects deliberate bad fixtures and asserts the scanner fails them.

```bash
python3 scripts/check-corpus-license.py
python3 scripts/check-corpus-license.py --self-test
```

### False positives

- Policy docs saying “No GPL” are not scanned (only `<domain>/<slice>/` fixtures).
- Bare word `GPL` in a reject-policy vector is not enough to fail; use strong markers above.
- If a fixture must embed a strong marker (rare): add the relative path to
  [`tests/corpus/LICENSE-SCAN-EXCEPTIONS`](../tests/corpus/LICENSE-SCAN-EXCEPTIONS) with a one-line reason comment,
  keep the PROVENANCE row, and note the exception in the PR.

## Forks

Third-party forks keep **upstream license**. Original facades remain MIT.

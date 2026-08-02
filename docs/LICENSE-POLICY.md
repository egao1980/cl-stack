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

Prefer **regenerate / re-express under MIT** over copying copyrighted test sources.

## Forks

Third-party forks keep **upstream license**. Original facades remain MIT.

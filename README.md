# cl-stack

MIT-licensed, Anaconda-style curated Common Lisp stack: coherent libraries for modern personal and small-business apps across SBCL / ECL / ABCL.

**This repo is the backlog and docs hub.** Implementation lives in sibling libraries under `egao1980`. Distribution: [`egao1980/cl-repository`](https://github.com/egao1980/cl-repository) (OCI + platform overlays). TLS natives: [`egao1980/cl-stack-ssl`](https://github.com/egao1980/cl-stack-ssl) (OpenSSL overlays + stock cl+ssl).

## Tracking

- GitHub Project: **CL Stack** (user `egao1980`)
- Issues here = capabilities, epics, corpus/license, Rove gaps
- Lib PRs link back with `Refs` / `Closes egao1980/cl-stack#N`

## Docs

| Doc | Role |
|-----|------|
| [docs/STDLIB-GAP.md](docs/STDLIB-GAP.md) | ANSI/CDR/CL21 vs Python/Java structural matrix |
| [docs/API.md](docs/API.md) | Protocol / facade / backend conventions |
| [docs/capabilities/event-protocol.md](docs/capabilities/event-protocol.md) | Event loop protocol brief + backend picks (libuv/libev) |
| [docs/overlays.md](docs/overlays.md) | Wave-1 platform matrix + GHCR overlay naming |
| [docs/overlay-ci.md](docs/overlay-ci.md) | Multi-arch publish CI prior art + Windows runners |
| [docs/LICENSE-POLICY.md](docs/LICENSE-POLICY.md) | MIT + inbound allowlist |
| [docs/ROVE-GAPS.md](docs/ROVE-GAPS.md) | Test-runner dogfood vs pytest/JUnit |
| [tests/corpus/README.md](tests/corpus/README.md) | Corpus layout + PROVENANCE rules |

## Corpus smoke

```bash
qlot install
qlot exec ros -e '(asdf:test-system "cl-stack/corpus-smoke")'
```

License allowlist: `python3 scripts/check-corpus-license.py`.

## OCI corpus consumer

GHA workflow `OCI corpus consumer` installs `http-protocol` / `http-encoding-chipz` /
`http-backend-dexador` from `ghcr.io/egao1980/cl-systems` and runs `cl-stack/oci-corpus`
(CE decode + redirect-policy vectors against a local fixture). Cleartext only (no
`cl-stack-ssl` overlay).

## License

MIT — see [LICENSE](LICENSE).

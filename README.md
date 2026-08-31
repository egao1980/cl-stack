# cl-stack

MIT-licensed, Anaconda-style curated Common Lisp stack: coherent libraries for modern personal and small-business apps across SBCL / ECL / ABCL.

**This repo is the backlog, docs hub, pin files, and metapackage.** Implementation lives in sibling libraries under `egao1980`. Distribution: [`egao1980/cl-repository`](https://github.com/egao1980/cl-repository) (OCI + platform overlays). TLS natives: [`egao1980/cl-stack-ssl`](https://github.com/egao1980/cl-stack-ssl).

## Metapackage (`cl-stack/meta`)

ASDF umbrella over the stable channel roots (HTTP facade + backends, event, WS, encodings, pathlib, OAuth2/JWT). Versions come from [`pins/stable.pins`](pins/stable.pins).

```bash
# after bootstrapping cl-repository-client (see docs/QUICKSTART.md)
export CL_SOURCE_REGISTRY="$PWD//:$CLIENT_DIR//:"
ros -e '(asdf:load-system "cl-stack/pins")' \
    -e '(cl-stack:apply-pins #p"pins/stable.pins")' \
    -e '(asdf:load-system "cl-stack/meta")' -q
```

E2E CI: workflow **Metapackage E2E** (issues `#21` / `#22`) — clean runner, oras client, apply pins, load meta (no grovel).

## Tracking

- GitHub Project: **CL Stack** (user `egao1980`)
- Issues here = capabilities, epics, corpus/license, Rove gaps
- Lib PRs link back with `Refs` / `Closes egao1980/cl-stack#N`

## Docs

| Doc | Role |
|-----|------|
| **[docs/QUICKSTART.md](docs/QUICKSTART.md)** | **Start here** — cl-repository bootstrap + current pins + minimal HTTP/event |
| [docs/STDLIB-GAP.md](docs/STDLIB-GAP.md) | ANSI/CDR/CL21 vs Python/Java structural matrix |
| [docs/API.md](docs/API.md) | Protocol / facade / backend conventions |
| [docs/capabilities/event-protocol.md](docs/capabilities/event-protocol.md) | Event loop protocol brief + backend picks (libuv/libev) |
| [docs/capabilities/http-protocol.md](docs/capabilities/http-protocol.md) | HTTP client facade brief |
| [docs/cookbooks/http-client.md](docs/cookbooks/http-client.md) | requests/httpx → `cl-stack-http` cookbook (+ OAuth2/JWT packages) |
| [docs/cookbooks/llm.md](docs/cookbooks/llm.md) · [ai-agent.md](docs/cookbooks/ai-agent.md) · [mcp.md](docs/cookbooks/mcp.md) · [a2a.md](docs/cookbooks/a2a.md) · [ag-ui.md](docs/cookbooks/ag-ui.md) | AI: LLM turns · agent loop · MCP · A2A · AG-UI |
| [docs/capabilities/ws-protocol.md](docs/capabilities/ws-protocol.md) | WebSocket client brief (`ws-backend-websocket-driver`) |
| [docs/capabilities/json-protocol.md](docs/capabilities/json-protocol.md) | JSON encode/decode — jzon default, yason alternate |
| [docs/pins.md](docs/pins.md) | Pin file format + stable/edge channels |
| [docs/overlays.md](docs/overlays.md) | Wave-1 platform matrix + GHCR overlay naming |
| [docs/multi-impl.md](docs/multi-impl.md) | SBCL / ECL / ABCL CI matrix + local smoke notes (#42) |
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

GHA workflow `OCI corpus consumer` installs a cleartext HTTP slice from GHCR and runs
`cl-stack/oci-corpus`. Full-stack install = **Metapackage E2E**.

## License

MIT — see [LICENSE](LICENSE).

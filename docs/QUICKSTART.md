# cl-stack + cl-repository quickstart

**Living doc.** Update this file when a wave feature ships (new package, pin bump, or user-facing API). Cookbooks stay task-deep; this page stays the 5‑minute path.

| Piece | Role |
|-------|------|
| [`cl-repository`](https://github.com/egao1980/cl-repository) | Install transport — OCI packages on GHCR + platform overlays (native libs, grovel cache) |
| [`cl-stack`](https://github.com/egao1980/cl-stack) (this repo) | Curated stack hub — briefs, cookbooks, pins, issues |
| `ghcr.io/egao1980/cl-systems/*` | Published systems you load with `cl-repo:load-system` |

Layering: **protocol** (generics) → **backend** (wire/OS) → **facade** (`cl-stack-*`, Python-grade DX). See [API.md](API.md).

---

## 0. Prerequisites

| Tool | Notes |
|------|--------|
| [Roswell](https://roswell.github.io/) + SBCL | `ros install sbcl-bin` |
| Quicklisp | only to bootstrap the **client** |
| [oras](https://oras.land/) | preferred way to pull `cl-repository-client` |

No C toolchain needed for consumer installs — natives ship in overlays.

---

## 1. Bootstrap `cl-repository-client`

Prefer the **`cl-repository/`** GHCR namespace (not the old `cl-systems/cl-repository-client` mirror).

```bash
CLIENT_VER=0.10.0   # or: latest
DEST="${HOME}/.local/share/cl-repository-client"
rm -rf /tmp/cl-repo-pull "$DEST"
mkdir -p /tmp/cl-repo-pull "$DEST"
oras pull "ghcr.io/egao1980/cl-repository/cl-repository-client:${CLIENT_VER}" -o /tmp/cl-repo-pull
for f in /tmp/cl-repo-pull/*.tar.gz; do tar -xzf "$f" -C "$DEST"; done
CLIENT_DIR="$(find "$DEST" -maxdepth 1 -type d -name 'cl-oci-*' | head -1)"
echo "Client tree: $CLIENT_DIR"
```

One-time QL deps for the **client only** (not your app):

```bash
ros -e '(ql:quickload '("yason" "ironclad" "babel" "dexador" "quri" "chipz"
                        "flexi-streams" "cl-ppcre" "cl-base64" "trivial-features"
                        "salza2" "archive") :silent t)' -q
```

Then in Lisp (set `*client-dir*` to the `cl-oci-*` path printed above):

```lisp
(defparameter *client-dir*
  #P"/Users/you/.local/share/cl-repository-client/cl-oci-…/") ; ← paste path

(asdf:initialize-source-registry
 `(:source-registry
   (:tree ,*client-dir*)
   :inherit-configuration))
(asdf:load-system "cl-repository-client")
(cl-repo:add-registry "https://ghcr.io"
                      :namespace "egao1980/cl-systems"
                      :priority :prepend)
```

`cl-repo:load-system` pulls the OCI package (and matching overlay), installs deps, then `asdf:load-system`.

**CI pattern:** same bootstrap via `oras` in the job; `actions/checkout` **only** the repo under test — never sibling-checkout deps. See any first-party `scripts/ci-install.lisp`.

---

## 2. Current stack pins (bump when publishing)

| System | OCI tag | Notes |
|--------|---------|--------|
| `cl-repository-client` | **0.10.0** | bootstrap from `ghcr.io/egao1980/cl-repository/…` |
| `http-protocol` | **0.3.0** | wire client; `:http-version` / H2 header policy |
| `cl-stack-http` | **0.1.6** | requests-like facade (`stack-http`) |
| `http-backend-async` | **0.2.0** | async + **HTTP/2** (ALPN + framing) |
| `http-backend-dexador` | **0.1.2** | sync HTTP/1.1 |
| `http-backend-winhttp` | **0.1.2** | Windows; HTTP/2 via WinHTTP |
| `event-protocol` | **0.1.1** | event-loop generics |
| `event-backend-libuv` | **0.1.1** | default (Windows-primary) |
| `event-backend-libev` | **0.1.2** | Unix second backend |
| `cffi` | **0.24.1** | via cl-stack-systems import |

Channel / pin-file format: [pins.md](pins.md). Overlay platforms: [overlays.md](overlays.md).

---

## 3. Minimal HTTP (facade)

```lisp
(cl-repo:load-system "cl-stack-http" :version "0.1.6")
;; optional CE codecs: http-encoding-chipz / -brotli / -zstd

(defpackage #:demo (:use #:cl) (:local-nicknames (#:http #:cl-stack-http)))
(in-package #:demo)

;; :auto picks a backend (async/libuv preferred; winhttp on Windows)
(http:ensure-http-backend :auto)

(let ((r (http:get "https://httpbin.org/get" :params '(("q" . "1")))))
  (format t "~a ~a~%" (http:response-status r) (http:response-http-version r))
  (princ (http:response-text r)))
```

### HTTP/2 preference (`http-protocol` 0.3.0+)

```lisp
(cl-repo:load-system "http-protocol" :version "0.3.0")
(cl-repo:load-system "http-backend-async" :version "0.2.0")
(cl-repo:load-system "event-backend-libuv" :version "0.1.1")

(setf http-backend-async:*event-backend-maker*
      (lambda () (event-backend-libuv:make-libuv-backend)))

(let* ((backend (http-backend-async:make-async-backend))
       (client (http-protocol:make-http-client backend :http-version :http/2))
       (req (http-protocol:make-http-request
             :url "https://nghttp2.org/" :http-version :http/2))
       (res (http-protocol:send backend client req)))
  (format t "~a ~a~%"
          (http-protocol:response-status res)
          (http-protocol:response-http-version res)))
```

| Preference | Meaning |
|------------|---------|
| `:auto` | Prefer H2 when backend + peer allow (ALPN) |
| `:http/1.1` | Force 1.1 |
| `:http/2` | Require H2 or signal `http-version-not-available` |

CLOS split: protocol owns preference / ALPN helpers / H2 header policy; backends own wire (or WinHTTP). Brief: [capabilities/http-protocol.md](capabilities/http-protocol.md). Recipes: [cookbooks/http-client.md](cookbooks/http-client.md).

---

## 4. Event loop (promises)

```lisp
(cl-repo:load-system "event-protocol" :version "0.1.1")
(cl-repo:load-system "event-backend-libuv" :version "0.1.1")

(let* ((eb (event-backend-libuv:make-libuv-backend))
       (el (event-protocol:make-event-loop eb)))
  (event-protocol:with-event-backend (eb)
    (event-protocol:with-event-loop-var (el)
      ;; defer / sleep* / register-io — see capability brief
      )))
```

Default backend = **libuv** (Windows-primary). Unix second = **libev**. Brief: [capabilities/event-protocol.md](capabilities/event-protocol.md).

---

## 5. Consumer CI skeleton

```yaml
# checkout ONLY this repo
- uses: actions/checkout@v4
- uses: oras-project/setup-oras@v1
- run: |
    oras pull ghcr.io/egao1980/cl-repository/cl-repository-client:0.10.0 -o /tmp/cl-repo-pull
    # extract → CL_SOURCE_REGISTRY includes client tree + $(pwd)//:
    ros -l scripts/ci-install.lisp   # cl-repo:add-registry + install pins
    ros -l scripts/ci-test.lisp
```

Rules (non-negotiable):

- Deps from **GHCR via cl-repo**, not sibling git checkouts.
- Unforked third-party → [`cl-stack-systems`](https://github.com/egao1980/cl-stack-systems) import → republish into `cl-systems`.
- Never require `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` for correctness.

---

## 6. Where next

| Want | Go |
|------|----|
| requests/httpx recipes | [cookbooks/http-client.md](cookbooks/http-client.md) |
| Protocol decisions / RFCs | [capabilities/](capabilities/) |
| Overlay platforms | [overlays.md](overlays.md) |
| Pin channels | [pins.md](pins.md) |
| cl-repository deep dive | [egao1980/cl-repository](https://github.com/egao1980/cl-repository) |
| macOS protobuf/grpc note | [lisp-workspace QUICKSTART-MAC](https://github.com/egao1980/lisp-workspace/blob/main/docs/QUICKSTART-MAC.md) (agent workspace) |

---

## Maintaining this doc

When you **merge + publish** a user-visible feature:

1. Bump the row in [§2 Current stack pins](#2-current-stack-pins-bump-when-publishing).
2. Add or adjust a minimal snippet in §3–4 if the DX entry point changed.
3. Link any new cookbook under [cookbooks/README.md](cookbooks/README.md).
4. Keep capability briefs for design depth — do not dump RFCs here.

Agents: treat an outdated pin table as a bug. Prefer editing this file in the same PR that publishes the OCI tag.

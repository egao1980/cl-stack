# serdes-protocol (P2)

**Issues:** [#132](https://github.com/egao1980/cl-stack/issues/132) · impl [#133](https://github.com/egao1980/cl-stack/issues/133)  
**Status:** brief **locked** — CLOS protocol + format backends

Generic **ser**ialize / **des**erialize of Lisp values ↔ string or octets. **Not** a replacement for [`json-protocol`](json-protocol.md) — JSON keeps its RFC 8259 value mapping (`:null`, string keys, …). Serdes is the **format-dispatch** layer used by logging layouts, HTTP body helpers, and cookbooks that need “encode this plist as JSON **or** SEXP.”

Conventions: [API.md](../API.md).

---

## Why (not just json-protocol)

| Need | json-protocol alone? | serdes-protocol |
|------|----------------------|-----------------|
| HTTP JSON bodies | ✅ already | thin `serdes-backend-json` → json-protocol |
| Structured logs as **JSON lines** | possible but couples log→json | ✅ `:format :json` |
| Structured logs as **SEXP** | ❌ wrong layer | ✅ `:format :sexp` |
| `cl-stack-http` `:data-type :sexp` | ad-hoc today | converge on serdes |
| Future msgpack / edn / CBOR | would bloat json-* | new backend |

**Verdict:** yes — ship a small serdes protocol. Keep `json-protocol` as the JSON specialist; add `serdes-backend-sexp` for Lisp-native wire.

---

## Prior art

| Ecosystem | Analogue |
|-----------|----------|
| **Java** | Jackson `ObjectMapper` + format modules; Java serialization (we do **not** copy Java native ser) |
| **Python** | `json` / `pickle` / `msgpack` behind one app helper; pydantic serdes |
| **Rust** | `serde` (format backends) — closest naming/shape |
| **CL** | `cl:print`/`read`; json-protocol; cl-store (binary object graph — **out of scope**) |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + format backends | Same stack rule as json/log |
| **DX** | `(serdes:encode value :format :json)` / `(serdes:decode source :format :sexp)` | Keyword format; optional `*serdes-format*` |
| **JSON backend** | Delegates to **`json-protocol`** (default jzon) | No second JSON stack |
| **SEXP backend** | CL `prin1` / `read` with **locked policies** | Lisp-native structured logs + HTTP sexp |
| **SEXP policies** | `*package*` = `CL-USER` (or dedicated `STACK-SEXP`) on encode; `*read-eval* nil` on decode; circularity = error | Safe-ish logs/IPC; not a security boundary alone |
| **SEXP value subset** | Prefer json-protocol-shaped data: hash-tables / vectors / numbers / strings / `t`/`nil`/`:null` | Round-trip parity with JSON logs |
| **Octets** | UTF-8 via Babel for string formats | Align with json-protocol |
| **Not wave-1** | msgpack, edn, yaml, cl-store, protobuf | Watchlist |
| **Not in serdes** | Schema validation, migrations | App layer |
| **Selection** | ASDF + `*serdes-backend*` **or** `:format` keyword selecting backend | Load `serdes-backend-json` / `serdes-backend-sexp` |

---

## Repo layout

| Layer | System / repo |
|-------|----------------|
| Protocol | `egao1980/serdes-protocol` (nick `stack-serdes`) |
| JSON backend | `serdes-backend-json` → depends on `json-protocol` |
| SEXP backend | `serdes-backend-sexp` |

Colocate in one repo for MVP OK (json-protocol precedent).

---

## Protocol surface

```lisp
(defvar *serdes-format* :json)          ; default format keyword
(defvar *serdes-backend* nil)           ; optional explicit backend object

(defgeneric backend-encode (backend value &key stream))
(defgeneric backend-decode (backend source &key))

(defun encode (value &key (format *serdes-format*) stream backend)
  "→ string, or write to STREAM.")
(defun decode (source &key (format *serdes-format*) backend)
  "SOURCE = string | octets | stream → Lisp value.")

(defun encode-to-octets (value &key format))
(defun decode-octets (octets &key format))
```

Format → backend map (protocol table): `:json` → json backend; `:sexp` → sexp backend.

### Conditions

```text
serdes-error
├── serdes-encode-error
├── serdes-decode-error
└── serdes-unsupported-format
```

---

## Relationship to other protocols

```text
json-protocol          ← RFC 8259 value rules (owned there)
    ↑
serdes-backend-json
    ↑
serdes-protocol        ← format dispatch
    ↑
log-protocol           ← :text layout | :structured → serdes
cl-stack-http          ← :json / :sexp body helpers (migrate)
```

---

## Non-goals

- Binary object graphs (cl-store)  
- Pretty-printer as API (use `encode` + optional `:pretty` later)  
- Absorbing TOML/YAML config — stays [`cl-stack-config`](config.md)  

---

## Implementation tasks

- [ ] Brief lock (this doc)
- [ ] `serdes-protocol` + json + sexp backends + OCI + pins
- [ ] Wire `log-protocol` structured layouts through serdes
- [ ] Optional: migrate `cl-stack-http` sexp path onto serdes

Ship **with or just before** logging structured layouts (#124) so log doesn’t invent a private encoder.

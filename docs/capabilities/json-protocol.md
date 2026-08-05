# json-protocol (wave-2 data)

**Issues:** [#91](https://github.com/egao1980/cl-stack/issues/91) · [#96](https://github.com/egao1980/cl-stack/issues/96) · [#97](https://github.com/egao1980/cl-stack/issues/97)  
**Status:** brief **locked** (#96); implementation `#97` **done** — [`egao1980/json-protocol`](https://github.com/egao1980/json-protocol) `0.1.0` + backends on GHCR

CLOS encode/decode contract for JSON (RFC 8259). One app DX; swappable backends. CSV/XML stay out of scope.

Conventions: [API.md](../API.md). Pins: [pins.md](../pins.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md) (JSON / CSV / XML → protocol + pin).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **DX target** | Python `json` / httpx `r.json()` shape | `encode` / `decode`; cookbooks teach one API |
| **Default pin (backend A)** | **[com.inuoe.jzon](https://github.com/Zulu-Inuoe/jzon)** (ASDF `com.inuoe.jzon`) — OCI `1.1.4` via [`cl-stack-systems`](https://github.com/egao1980/cl-stack-systems) | RFC 8259-first, MIT, call-site options (no ambient specials), parse depth limits, strong JSONTestSuite / review scores |
| **Alternate (backend B)** | **[yason](https://github.com/phmarek/yason)** | Already wired in [`cl-stack-http`](https://github.com/egao1980/cl-stack-http); keep as escape hatch + migration path |
| **Not default** | **jonathan** | Fast on tiny payloads; weak on large JSON + safety-0 history — unsuitable as stack default |
| **Also considered** | **shasht** | Strong modern contender (symmetry); revisit if jzon pin friction appears — not wave-2 dual-default |
| **Object type** | **hash-table**, keys = **strings** | Matches jzon defaults + current `cl-stack-http` decode (`:object-as :hash-table`) |
| **Array type** | **vector** | Protocol normalizes; backends map lists↔vectors as needed |
| **`null`** | Keyword **`:null`** | Distinct from `nil` / false; backends map to/from library-native null |
| **`false` / `true`** | **`nil` / `t`** | JSON boolean false ≠ empty list; encoders must not emit `null` for boolean false |
| **Numbers** | CL reals; prefer **double-float** for JSON floats | Set `*read-default-float-format*` to `double-float` in backend decode path where relevant |
| **Symbols on encode** | Object keys: symbol-name **downcase**; values: error unless backend documents coercion | Avoid silent keyword/`null` footguns |
| **Streaming** | **Wave-2 optional / P2** | Push/pull parsers later; wave-2 ships whole-value encode/decode only |
| **Errors** | Conditions (`json-error` tree), not bare `error` | Parse / encode / type / limit |
| **HTTP integration** | Protocol owns codecs; `http-protocol` `*json-encoder*` / `*json-decoder*` bind to them | `cl-stack-http` migrates off direct yason calls |

Selection DX: ASDF + `*json-backend*` (no plugin registry) — same as http/event.

---

## Bakeoff scorecard (#96)

Scores: **1** (poor) … **5** (excellent) for cl-stack needs. Sources: [Sabra Crolleton JSON review](https://sabracrolleton.github.io/json-review) (2023-05), jzon README / JSONTestSuite notes, stack usage.

| Criterion | yason | jzon | jonathan | shasht |
|-----------|-------|------|----------|--------|
| RFC 8259 / test-suite posture | **4** | **5** | **2** | **5** |
| null / false / nil distinction | **3** (tunable) | **5** | **3** | **5** |
| Safety (depth limits, hostile input) | **3** | **5** | **1** | **4** |
| Call-site purity (no ambient specials) | **2** | **5** | **2** | **3** |
| Perf (typical API JSON) | **3** | **4** | **3**† | **4** |
| License | BSD | **MIT** | MIT | MIT |
| Already in stack | **5** (`cl-stack-http`) | **2** | **1** | **1** |
| Maintenance / liveliness | **3** | **4** | **2** | **4** |
| **Wave-2 role** | **Alternate (B)** | **Default (A)** | reject | watchlist |

† jonathan: excellent on &lt;~200 B; collapses on large documents — disqualifies as default.

**Verdict:** default pin = **jzon**. Keep **yason** as backend B so `cl-stack-http` can switch via protocol without a big-bang rewrite. Do **not** pin jonathan.

---

## Repo layout (locked)

| Layer | Repo |
|-------|------|
| Protocol + shared tests | `egao1980/json-protocol` |
| Default backend A | `egao1980/json-backend-jzon` (or colocated `json-protocol/jzon` **only if** publish story stays simple — prefer separate repo matching event/http) |
| Alternate backend B | `egao1980/json-backend-yason` (thin; may start inside `json-protocol` as secondary system) |

Prefer **separate repos per layer** (event/http precedent) once A ships. Wave-2 MVP may ship `json-protocol` + `json-backend-jzon` systems in one repo with two ASDF systems if that accelerates `#97`; split before metapackage pin if CI/publish aches.

---

## Protocol surface

Package nick: `json` (system `json-protocol`).

### Value mapping (normative)

| JSON | Lisp (decode) | Encode accepts |
|------|---------------|----------------|
| object | hash-table (test `equal`), string keys | hash-table; alist of string/symbol keys |
| array | vector | vector or proper list |
| string | string | string |
| number | integer or float | integer / float / ratio (ratio → float) |
| `true` | `t` | `t` |
| `false` | `nil` | `nil` **as boolean** (see below) |
| `null` | `:null` | `:null` |

**Boolean false vs empty:** Encoding `(encode nil)` is **ambiguous** in CL. Locked rule:

- `(encode nil :false-nil t)` or dedicated `(encode-false)` — **prefer** keyword arg on encode: `:null-nil` default **nil** meaning `nil` → JSON `false`; pass `:null` for JSON null.
- Decoding never maps `null` → `nil`.

### Generics / functions

```lisp
;; Primary DX (functions or generics — impl choice in #97; keep call shape stable)
(json:encode value &key stream false-nil)   ; → string, or write to stream
(json:decode source &key)                  ; source = string | octet-vector | stream
                                            ; → Lisp value per table above

;; Backend selection
(defvar *json-backend*)                     ; keyword or backend object
(defgeneric json:backend-encode (backend value &key stream false-nil))
(defgeneric json:backend-decode (backend source &key))

;; Predicates / helpers
(json:null-p object)                        ; eq :null
(json:true-p object) (json:false-p object)  ; for decoded values
```

Facade may also expose `encode-to-octets` / `decode-octets` (UTF-8 via Babel) for HTTP bodies.

### Conditions

```text
json-error
├── json-parse-error          ; malformed / truncated / depth
├── json-encode-error         ; unencodable Lisp value
└── json-limit-error          ; depth / size cap exceeded
```

Restarts: `use-value` where cheap; otherwise signal and let callers handle.

### Non-goals (this capability)

- JSON Schema / JSON Pointer / JSON Patch
- CLOS mop→JSON automatic mapping (json-mop etc. = app layer)
- CSV / XML
- Streaming parsers (P2)
- ICU / i18n

---

## HTTP / stack integration

1. `json-protocol` + `json-backend-jzon` publish to GHCR; add to `pins/stable.pins`.
2. `cl-stack-http` `encode-json` / `decode-json` become thin wrappers over `json:encode` / `json:decode` (default backend jzon).
3. `http-protocol` `*json-encoder*` / `*json-decoder*` set from json-protocol install hook (same shape as today’s yason install).
4. Apps that need yason semantics load `json-backend-yason` and bind `*json-backend*`.

---

## Implementation tasks

- [x] #96 Brief + bakeoff (this doc)
- [x] #97 Implement protocol + jzon backend + GHCR pin (+ yason alternate)

## Cookbook (follow-on)

Minimal slice in `docs/cookbooks/` once `#97` lands: encode alist → POST JSON; `response` body → `json:decode`.

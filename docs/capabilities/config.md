# Config facade (env + TOML)

**Issues:** [#92](https://github.com/egao1980/cl-stack/issues/92) · [#98](https://github.com/egao1980/cl-stack/issues/98) · [#99](https://github.com/egao1980/cl-stack/issues/99)  
**Status:** **done** — [`egao1980/cl-stack-config`](https://github.com/egao1980/cl-stack-config) `0.1.0` + tomlet on GHCR; cookbook [config.md](../cookbooks/config.md)

One app DX for configuration: structured file + environment overlay + explicit overrides. Avoid N× envy / ad-hoc `uiop:getenv` stacks.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md) (Config → facade).

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **System name** | **`cl-stack-config`** (nick `stack-config`) | Matches `cl-stack-http` / pathlib facade naming |
| **File format (default)** | **TOML** | Human-friendly for service config; maps cleanly to hash-tables/vectors (same shape as `json-protocol`) |
| **Parser pin** | **[tomlet](https://github.com/fukamachi/tomlet)** | TOML **v1.0.0** compliance (official suite), MIT, **pure Lisp** (only `cl-ppcre`) — no native overlay |
| **Not default** | **YAML** (`cl-yaml` / libyaml) | Needs **libyaml** CFFI + overlays; YAML 1.1 footguns; heavier than config needs |
| **Also considered** | **cl-toml** (cxxxr) | On QL; older / esrap-based; weaker compliance story vs tomlet |
| **Env library** | **Facade-owned** (thin `uiop:getenv`) — not envy | envy = named config *profiles* in Lisp source; we want **file + env overlay**, not `defconfig` tables |
| **Value tree** | hash-table (`equal`) + vectors; TOML tables → nested hash-tables | Aligns with `json-protocol` / tomlet JSON-compatible output |
| **Key path** | Dot-separated strings (`"database.host"`) or list `("database" "host")` | Cookbook teaches dots; list form for programmatic |
| **Precedence** | **file < env < explicit** | Explicit = `with-config` / `config-set` / load keywords |
| **Env naming** | Prefix + `__` nesting: `APP_DATABASE__HOST` → `database.host` | Double-underscore = table separator (12-factor-ish); prefix configurable (default from `load`) |
| **Types** | Typed getters coerce strings from env; file values keep TOML types | `get-integer`, `get-boolean`, `get-string`, `get-list` |
| **Missing keys** | Signal `config-missing-error` **or** return default when `:default` supplied | No silent `nil` for required keys |
| **Reload** | Explicit `load` / `reload` — no file watch in wave-2 | Keep MVP small |
| **Secrets** | Out of scope (see crypto/secrets P2) | Env may carry secrets; no vault |

Selection: ASDF load `cl-stack-config` (depends on tomlet). No backend registry — one format for the pin set. Escape hatch: apps may still parse YAML themselves; not curated.

---

## Bakeoff scorecard (#98)

Scores: **1** (poor) … **5** (excellent) for cl-stack needs.

| Criterion | TOML + tomlet | YAML + cl-yaml | envy alone |
|-----------|---------------|----------------|------------|
| File readability (ops / services) | **5** | **4** | **1** (no file) |
| Spec compliance / test suite | **5** (tomlet 734/734) | **3** | n/a |
| Pure Lisp / no native overlay | **5** | **1** (libyaml) | **5** |
| Env overlay story | **4** (facade) | **4** (facade) | **3** (profiles only) |
| Aligns with json-protocol values | **5** | **3** | **2** |
| Windows / consumer install cost | **5** | **2** | **5** |
| Already in stack | **2** | **1** | **1** |
| **Wave-2 role** | **Default** | reject as pin | reject as primary |

**Verdict:** default = **TOML via tomlet**. Do **not** pin YAML. envy is not a substitute for file+env.

---

## Repo layout (locked)

| Layer | Repo |
|-------|------|
| Facade | `egao1980/cl-stack-config` |
| Parser pin | tomlet via `cl-stack-systems` import → GHCR |

No separate `config-protocol` unless a second format becomes first-class later.

---

## Protocol surface

Package nick: `stack-config`.

### Load / bind

```lisp
;; Load TOML file into a config object (hash-table tree + metadata).
(config:load #p"config.toml"
             :prefix "APP"          ; env prefix; NIL = no env overlay
             :env t                 ; apply getenv overlay
             :overrides '(("debug" . t)))  ; explicit; highest precedence

(defvar *config*)                   ; optional dynamic default
(config:with-config (cfg) …)        ; bind *config*
```

### Access

```lisp
(config:get cfg "database.host")              ; → string / error
(config:get cfg "database.host" :default "localhost")
(config:get cfg '("database" "host"))

(config:get-string cfg "database.host")
(config:get-integer cfg "database.port")
(config:get-boolean cfg "database.enabled")
(config:get-list cfg "features")              ; vector → list optional

(config:section cfg "database")               ; sub-table as config or hash-table
```

### Env overlay rules

Given `:prefix "APP"`:

| Env | Maps to |
|-----|---------|
| `APP_DEBUG=true` | `debug` (boolean coerce for typed getters / `true|false|1|0|yes|no`) |
| `APP_DATABASE__HOST=db` | `database.host` |
| `APP_FEATURES__0=auth` | optional list index — **P2**; MVP may only support scalar/table env |

Unprefixed raw `uiop:getenv` remains available; facade does not steal the process env.

### Conditions

```text
config-error
├── config-parse-error       ; TOML syntax
├── config-missing-error     ; required key absent
├── config-type-error        ; typed getter coercion failed
└── config-file-error        ; missing / unreadable file
```

---

## Non-goals

- Spring-style profiles / multi-document YAML
- Hot reload / file watchers
- JSON/EDN as second curated format (use `json-protocol` directly)
- Secret stores / KMS
- Schema validation (optional follow-on)

---

## Implementation tasks

- [x] #98 Brief + TOML vs YAML bakeoff (this doc)
- [x] #99 Implement `cl-stack-config` + tomlet import + GHCR + cookbook + Rove (env overlay)

## Cookbook (with #99)

Small service: `config.toml` + `APP_DATABASE__HOST` override + typed getters.

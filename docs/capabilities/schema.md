# schema-protocol (P2)

**Status:** wave-1 **shipped** — CLOS interchange models (`defschema` / `defenum` / `:tag` unions). JSON Schema emit/parse is a **format implementor**, not this package. Cookbook: [schema.md](../cookbooks/schema.md)

Python Pydantic is the **feature checklist**. It is **not** the API.

```text
schema-protocol            ← metaclass + parse / validate / dump
schema-protocol-json       ← draft-07 emit / compile / OpenAPI discriminator
schema-protocol-xsd        ← XSD 1.0/1.1 emit / compile / instance validate
schema-protocol-arrow      ← Arrow schema emit + table↔objects
        │
serdes-protocol / json-protocol / arrow-protocol   ← bytes when :format is set
```

**Not** [`sql-orm`](sql.md) `defmodel` (persistence). **Not** [`cl-stack-config`](config.md) (env/TOML settings). Use `defschema` for API / RPC / tool payloads.

Conventions: [API.md](../API.md). Used by [ag-ui.md](ag-ui.md), [llm.md](llm.md), [mcp.md](mcp.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `schema-class` metaclass + `defschema`. Lisp type specifiers on slots. |
| **Null** | JSON null = `:null` (same as `json-protocol`). Lisp `nil` is JSON **false**. |
| **Coercion** | Opt-in (`:coerce t`) + `coerce-field` methods. |
| **Extras** | `:extra :forbid` (default) / `:ignore` / `:allow` (bag in `schema-extras`). **Inherited** (`nil` → parent). |
| **Key style** | `:key-style :downcase` (default) / `:kebab` / `:snake` / `:camel` / `:preserve`. **Not inherited** — omit → `:downcase`. |
| **Unions** | CLOS subclasses + `:tag` slot. Not a parallel tagged-union DSL. |
| **Enums** | `defenum` with proto-style aliases (name / `TYPE_MEMBER` / number / `allow_alias`). |
| **Pattern** | Function designator, not a regex string. |
| **JSON Schema** | [`schema-protocol-json`](https://github.com/egao1980/schema-protocol-json) — `json-schema` GF on the protocol; `emit` / `compile-schema` in the format package. |
| **XSD** | [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) — `xsd-schema` GF; 1.0 default, `:version :1.1` for alternatives / openContent / assert. Closed XPath subset. |
| **Arrow** | [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) — `arrow-schema` GF; `emit` / `table-from-objects` / `objects-from-table`. Bytes stay in [`arrow-protocol`](arrow.md). |
| **Wire** | Default parse/dump speak hash-tables / plists / alists. `:format` goes through `serdes-protocol` when loaded. |
| **Restarts** | Per field, while that field is being parsed: `use-value`, `skip-field`, `use-default`. `schema-fail` signals immediately (restart still live). `schema-issue` collects; `%raise-issues` fires after. |

---

## Repos

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol (`stack-schema`) | [`schema-protocol`](https://github.com/egao1980/schema-protocol) | **0.1.2** |
| JSON Schema (`stack-schema-json`) | [`schema-protocol-json`](https://github.com/egao1980/schema-protocol-json) | **0.1.1** |
| XSD (`stack-schema-xsd`) | [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) | **0.1.1** |
| Arrow (`stack-schema-arrow`) | [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) | **0.1.0** (first publish pending) |

---

## Protocol surface

```lisp
(defgeneric schema-of (designator))
(defgeneric validate (schema value &key coerce extra format))
(defun validp (schema value &key coerce extra format))
(defgeneric parse (schema source &key coerce extra format))
(defgeneric dump (object &key as include-computed format))
(defgeneric json-schema (schema &key draft))   ; method in schema-protocol-json
(defgeneric xsd-schema (schema &key version))  ; method in schema-protocol-xsd (:1.0 / :1.1)
(defgeneric arrow-schema (schema &key))        ; method in schema-protocol-arrow
(defgeneric validate-object (object))
(defgeneric validate-field (schema-name slot-name value))
(defgeneric coerce-field (schema-name slot-name value))
(defun schema-issue (path message &key value slot))   ; collect
(defun schema-fail (path message &key value slot))    ; signal now
```

Conditions: `schema-error` → `schema-validation-error` (`schema-validation-error-issues`), `schema-unknown`.

---

## Non-goals (0.1.0)

- Pydantic `model_validate` / decorator API
- Implicit coercion default
- Settings/env overlay
- ORM / tables
- Full JSON Schema meta-schema / remote `$ref`

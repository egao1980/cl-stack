# schema-protocol (P2)

**Status:** wave-1 **shipped** — CLOS interchange models (`defschema` / `defenum` / `:tag` unions). JSON Schema emit/parse is a **format implementor**, not this package. Cookbook: [schema.md](../cookbooks/schema.md)

Python Pydantic is the **feature checklist**. It is **not** the API.

```text
schema-protocol            ← metaclass + parse / validate / dump
                           ← emit-schema / parse-schema (:format :json/:xsd/:arrow/:avro)
schema-protocol-json       ← registers :json
schema-protocol-xsd        ← registers :xsd
schema-protocol-arrow      ← registers :arrow (emit; parse not yet)
schema-protocol-avro       ← registers :avro
        │
serdes-protocol / json-protocol / xml-protocol / arrow-protocol / avro-protocol   ← instance bytes
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
| **Schema documents** | `emit-schema` / `parse-schema` + `register-schema-format` (same shape as serdes). Default `*schema-format*` is `:json`. Unknown format → `schema-unknown-format`. |
| **JSON Schema** | [`schema-protocol-json`](https://github.com/egao1980/schema-protocol-json) **0.1.2** — `:json` backend. `json-schema` wraps `(emit-schema … :format :json)`. |
| **XSD** | [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) **0.1.3** — `:xsd` backend; trees are `xml-protocol` `xml-element`; `decode-validating` = decode then `validate-instance`. 1.0 default, `:version :1.1` for alternatives / openContent / assert. Closed XPath subset. |
| **Arrow** | [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) **0.1.1** — `:arrow` backend (emit). `parse-schema` for `:arrow` is not implemented. Bytes stay in [`arrow-protocol`](arrow.md). |
| **Avro** | [`schema-protocol-avro`](https://github.com/egao1980/avro-protocol) **0.1.1** — `:avro` backend (`defschema` ↔ Avro JSON tree). Binary codec is [`avro-protocol`](avro-protocol.md) (`avro-protocol:parse-schema` is the writer schema, not this). |
| **Wire** | Default parse/dump speak hash-tables / plists / alists. `parse`/`dump` `:format` goes through `serdes-protocol` when loaded (instance values). Distinct from `emit-schema`/`parse-schema` `:format`. |
| **Restarts** | Per field, while that field is being parsed: `use-value`, `skip-field`, `use-default`. `schema-fail` signals immediately (restart still live). `schema-issue` collects; `%raise-issues` fires after. |

---

## Repos

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol (`stack-schema`) | [`schema-protocol`](https://github.com/egao1980/schema-protocol) | **0.2.0** |
| JSON Schema (`stack-schema-json`) | [`schema-protocol-json`](https://github.com/egao1980/schema-protocol-json) | **0.1.2** |
| XSD (`stack-schema-xsd`) | [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) | **0.1.3** |
| Arrow (`stack-schema-arrow`) | [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) | **0.1.1** |
| Avro (`stack-schema-avro`) | [`schema-protocol-avro`](https://github.com/egao1980/avro-protocol) | **0.1.1** |

---

## Protocol surface

```lisp
(defgeneric schema-of (designator))
(defgeneric validate (schema value &key coerce extra format))
(defun validp (schema value &key coerce extra format))
(defgeneric parse (schema source &key coerce extra format))   ; instance values
(defgeneric dump (object &key as include-computed format))
(defun emit-schema (schema &key format …))     ; schema document
(defun parse-schema (source &key format …))    ; document → schema-class
(defgeneric json-schema (schema &key draft))   ; (emit-schema schema :format :json)
(defgeneric xsd-schema (schema &key version))
(defgeneric arrow-schema (schema &key))
(defgeneric avro-schema (schema &key))
(defgeneric validate-object (object))
(defgeneric validate-field (schema-name slot-name value))
(defgeneric coerce-field (schema-name slot-name value))
(defun schema-issue (path message &key value slot))   ; collect
(defun schema-fail (path message &key value slot))    ; signal now
```

Conditions: `schema-error` → `schema-validation-error` (`schema-validation-error-issues`), `schema-unknown`, `schema-unknown-format`.

---

## Non-goals (0.1.0)

- Pydantic `model_validate` / decorator API
- Implicit coercion default
- Settings/env overlay
- ORM / tables
- Full JSON Schema meta-schema / remote `$ref`

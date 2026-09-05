# Cookbook: CLOS schemas

**Audience:** Pydantic / dataclass people who want interchange models, not an ORM.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol (`stack-schema`) | [`schema-protocol`](https://github.com/egao1980/schema-protocol) | **0.2.0** |
| JSON Schema (`stack-schema-json`) | [`schema-protocol-json`](https://github.com/egao1980/schema-protocol-json) | **0.1.2** |
| XSD (`stack-schema-xsd`) | [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) | **0.1.3** |
| Arrow (`stack-schema-arrow`) | [`schema-protocol-arrow`](https://github.com/egao1980/schema-protocol-arrow) | **0.1.1** |
| Avro (`stack-schema-avro`) | [`schema-protocol-avro`](https://github.com/egao1980/avro-protocol) | **0.1.1** |

Brief: [schema.md](../capabilities/schema.md). Persistence → [sql.md](sql.md). Settings → [config.md](config.md). Field recoveries → [conditions.md](conditions.md).

```lisp
(cl-repo:load-system "schema-protocol" :version "0.2.0")
(cl-repo:load-system "schema-protocol-json" :version "0.1.2")  ; optional :json
(cl-repo:load-system "schema-protocol-xsd" :version "0.1.3")   ; optional :xsd
(cl-repo:load-system "schema-protocol-arrow" :version "0.1.1") ; optional :arrow
(cl-repo:load-system "schema-protocol-avro" :version "0.1.1")  ; optional :avro
```

---

## 1. `defschema` / parse / dump

Default slot accessor is the slot name. `:default` implies `:optional t`. JSON null is `:null`; Lisp `nil` is JSON **false**. Coercion is opt-in (`:coerce t`).

```lisp
(stack-schema:defschema address ()
  (city string)
  (country string :default "GB"))

(stack-schema:defschema user ()
  "API user."
  (name string :min-length 1)
  (age (integer 0) :optional t)
  (email string :format :email :optional t)
  (address address)
  (tags (vector string))
  (:compute display-name (self)
    (format nil "~A" (name self)))
  (:extra :forbid))

(let ((u (stack-schema:parse 'user '(:name "Ada"
                                     :address (:city "London")
                                     :tags #("lisp" "clos")))))
  (stack-schema:dump u))
```

`:extra` is inherited (`nil` on the subclass → parent, else `:forbid`). `:key-style` is **not** inherited — omitted means `:downcase`.

---

## 2. Enums + tagged unions

```lisp
(stack-schema:defenum color
  (:red 1)
  (:blue 2)
  (:azure 2))                       ; proto allow_alias — number 2 still maps to :blue

(stack-schema:defschema shape ()
  (kind color)
  (:tag kind)
  (:key-style :camel))              ; repeat on every subclass that needs camel

(stack-schema:defschema circ (shape)
  (kind (eql :red) :default :red)
  (r number)
  (:key-style :camel))

(stack-schema:parse 'shape '(:kind "COLOR_RED" :r 1.5))  ; => circ
```

Wire accepts keyword, symbol-name (any case), proto `COLOR_RED`, and the integer.

---

## 3. Schema documents (`emit-schema` / `parse-schema`)

Same dispatch as serdes. Load a format implementor, then:

```lisp
(stack-schema:emit-schema 'user :format :json)
(stack-schema:emit-schema 'user :format :xsd :version :1.1)
(stack-schema:emit-schema 'user :format :arrow)
(stack-schema:emit-schema 'user :format :avro)

(stack-schema:parse-schema json-schema-ht :format :json)   ; → schema-class
(stack-schema:parse-schema xsd-string :format :xsd)
(stack-schema:parse-schema avro-json :format :avro)
```

`json-schema` / `xsd-schema` / `arrow-schema` / `avro-schema` wrap `emit-schema`. `parse` / `dump` `:format` is still **instance** serdes, not schema documents.

```lisp
(asdf:load-system "schema-protocol-json")
(stack-schema:emit-schema 'user :format :json)   ; draft-07
(stack-schema:json-schema 'user)                 ; same
(stack-schema-json:compile-schema
 '(:type "object" :required #("name")
   :properties (:name (:type "string"))))
```

Wave-1: local `$ref` (`#/$defs/…`) only. JSON Schema `pattern` strings are ignored on compile (protocol `:pattern` is a function designator).

---

## 4. XSD

`xsd-schema` GF lives on the protocol; methods are in `schema-protocol-xsd`. Trees are `xml-protocol` `xml-element` (`xml-elem` is gone). Default emit is XSD 1.0; `:version :1.1` writes `xs:alternative` / `xs:openContent` / `vc:minVersion`. Parse and `validate-instance` accept 1.1 (`xs:assert`, closed XPath subset). `decode-validating` = well-formed decode then `validate-instance`. No cxml / libxml2. Streaming content-model validator is later.

```lisp
(asdf:load-system "schema-protocol-xsd")   ; pulls xml-protocol + xml-backend-native
(stack-schema:xsd-schema 'user)                 ; 1.0 XML string
(stack-schema-xsd:emit 'user :version :1.1)
(stack-schema-xsd:compile-schema xml)            ; → schema-class
(stack-schema-xsd:validate-instance schema ht-or-xml-document)
(stack-schema-xsd:decode-validating "<person/>" schema)
```

---

## 5. Field restarts

Restarts are established **around each field** inside `parse`. They are live when something **signals** during that field (`schema-fail` in `:validate-field`). Collected `schema-issue` / type failures raise `schema-validation-error` **after** the field `restart-case` exits — `use-value` is gone by then.

```lisp
(stack-schema:defschema person ()
  (name string)
  (:validate-field name (value)
    (if (equal value "bad")
        (stack-schema:schema-fail 'name "bad")
        value)))

(handler-bind ((schema-validation-error
                (lambda (c)
                  (declare (ignore c))
                  (invoke-restart 'use-value "ada"))))
  (stack-schema:parse 'person '(:name "bad")))
```

Also: `skip-field`, `use-default`.

---

## What not to do

- Don't clone Pydantic `BaseModel` / `model_validate`.
- Don't use `defschema` for tables — that's `sql-orm:defmodel`.
- Don't treat Lisp `nil` as JSON null.
- Don't expect `:key-style` to inherit onto subclasses.
- Don't `handler-bind` `use-value` on a collected `schema-validation-error` from `schema-issue` — that restart is already gone.

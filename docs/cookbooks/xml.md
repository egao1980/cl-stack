# Cookbook: XML (Infoset / events / writer)

**Audience:** well-formed XML 1.0 + Namespaces. Not XSD — that's [schema](schema.md).

**Packages:**

| Layer | Role | OCI |
|-------|------|-----|
| [`xml-protocol`](https://github.com/egao1980/xml-protocol) (`stack-xml`) | Infoset, encode/decode, writer GFs, serdes `:xml` | **0.1.0** |
| `xml-backend-native` | Default — Lisp pull parser + sink (XXE-safe) | **0.1.0** |

Brief: [xml-protocol.md](../capabilities/xml-protocol.md). Generic façade: [serdes](serdes.md).

```lisp
(cl-repo:load-system "xml-backend-native" :version "0.1.0")
;; nick: stack-xml — also registers serdes :xml
```

`:xml` is well-formed only. No `:schema` on `xml-protocol:decode`.

---

## 1. Document round-trip

```lisp
(asdf:load-system "xml-backend-native")

(let* ((doc (stack-xml:decode "<root xmlns='urn:x'><n a='1'>hi</n></root>"))
       (n (stack-xml:xml-child (stack-xml:document-root-element doc) "n")))
  (list (stack-xml:xml-element-text n)
        (stack-xml:xml-attr n "a")))
;; => ("hi" "1")

(stack-xml:encode (stack-xml:make-xml-element "n" '(("a" . "1")) "hi")
                  :pretty nil :declaration nil)
(stack-serdes:encode doc :format :xml)
```

Helpers XSD uses: `make-xml-element`, `xml-qname`, `xml-local-name`, `xml-attr`, `xml-child`, `xml-children-named`, `xml-element-text`, `xml-named-p`, `document-root-element`.

---

## 2. Pull events

Klacks-shaped: `:start-document` `:end-document` `:dtd` `:start-element` `:end-element` `:characters` `:comment` `:processing-instruction`. CDATA arrives as `xml-cdata` on `:characters`.

```lisp
(let ((p (stack-serdes:make-event-parser "<a><b>x</b></a>" :format :xml)))
  (loop
    (multiple-value-bind (ev val) (stack-serdes:parse-next-event p)
      (unless ev (return))
      (print (list ev val)))))

(stack-serdes:parse-next-element
 (stack-serdes:make-event-parser "<!--c--><root><n>z</n></root>" :format :xml))
```

---

## 3. Event writer

```lisp
(with-output-to-string (s)
  (stack-xml:with-event-writer (w s :pretty nil)
    (let ((a (stack-xml:make-xml-element "a" nil)))
      (stack-xml:write-event w :start-document)
      (stack-xml:write-event w :start-element a)
      (stack-xml:write-event w :characters "hi")
      (stack-xml:write-event w :end-element a)
      (stack-xml:write-event w :end-document))))
```

---

## 4. Validating compose

Layer 2 is [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) **0.1.2**. `decode-validating` = well-formed decode then `validate-instance`. Streaming content-model validator is later.

```lisp
(asdf:load-system "schema-protocol-xsd")
(stack-schema-xsd:decode-validating "<person><msg>ok</msg></person>" schema)
```

XXE-safe: no external subset / general entities. Predefined + numeric refs only. `continue` skips a bad decl.

## What not to do

- Don't pass `:schema` to `xml-protocol:decode`.
- Don't expect XSD on `parse-next-event`.
- Don't treat this as CXML / libxml2 / plump.

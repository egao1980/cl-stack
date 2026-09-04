# xml-protocol (wave-2 data)

**Status:** **done** — [`egao1980/xml-protocol`](https://github.com/egao1980/xml-protocol) `0.1.0` + `xml-backend-native` `0.1.0` on GHCR; cookbook [xml.md](../cookbooks/xml.md)

CLOS **XML Infoset** + pull events + streaming writer. Hard-implements [`serdes-protocol`](serdes.md) `:xml`. Well-formed syntax only — XSD is [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) **0.1.2** (`decode-validating` = decode then `validate-instance`).

Conventions: [API.md](../API.md). Pins: [pins.md](../pins.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Backend** | First-party `xml-backend-native` (Lisp). No CXML / libxml2. Windows-primary. |
| **XSD** | Zero XSD dep on `xml-protocol`. No `:schema` on `decode`. |
| **`:xml` serdes** | Well-formed only. |
| **Writer GFs** | Stay on `xml-protocol` (do not bump serdes-protocol). |
| **XXE** | No external DTD / general entities. Predefined + numeric refs only. `continue` skips a bad decl. |
| **Events** | Klacks-shaped: `:start-document` `:end-document` `:dtd` `:start-element` `:end-element` `:characters` `:comment` `:processing-instruction`. CDATA = `xml-cdata` on `:characters`. |
| **Streaming XSD** | Later. Do not stub a content-model validator on `parse-next-event`. |

## Repos

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol (`stack-xml`) | [`xml-protocol`](https://github.com/egao1980/xml-protocol) | **0.1.0** |
| Native backend | same repo (`xml-backend-native`) | **0.1.0** |
| XSD compose | [`schema-protocol-xsd`](https://github.com/egao1980/schema-protocol-xsd) | **0.1.2** |

# unicode-protocol

**Status:** protocol surface **locked** (wave-1 scaffold) · OCI TBD  
**Repos:** [`egao1980/unicode-protocol`](https://github.com/egao1980/unicode-protocol) (`stack-unicode`)  
**Related:** Babel octets↔string — [text-unicode.md](text-unicode.md); i18n/l10n — [i18n.md](i18n.md) / [l10n.md](l10n.md); [#151](https://github.com/egao1980/cl-stack/issues/151)

ICU-shaped **CLOS** Unicode: properties, Normalizer2, root case, IDNA/UTS#46, BreakIterator, UnicodeSet. **Not** a cl-unicode API mirror. **Not** MessageFormat / collation / number format.

---

## Prior art

| Ecosystem | Analogue |
|-----------|----------|
| **ICU4C/J** | `uchar` / `UCharacter`, `Normalizer2`, `IDNA`, `BreakIterator`, `UnicodeSet` |
| **Python** | `unicodedata` + `idna` (separate) |
| **Java SE** | `Character` + `Normalizer` + `IDN` (IDNA2003!) + `BreakIterator` |

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Shape | Protocol GFs + `*unicode-backend*` + capability keywords |
| Property API | `binary-property-p` / `int-property` (ICU `hasBinaryProperty` / `getIntPropertyValue`) + sugar predicates |
| Property names | Keywords ≈ PropertyAliases long names (`:alphabetic`, `:general-category`) |
| Normalize forms | `:nfc` `:nfd` `:nfkc` `:nfkd` + optional `:nfkc-casefold` |
| Case | Locale-**independent** here; locale case → `l10n-protocol` |
| IDNA | Full UTS#46 / IDNA2008 in this protocol; `cl-idna` rearranges later |
| Breaks | `:grapheme` `:word` `:line` `:sentence` |
| Octets↔string | **Out** — Babel (#94) |
| MF2 / locale / collate / numfmt | **Out** — i18n / l10n protocols |

---

## Layering

```text
babel                 ← octets ↔ string (UTF-8)
unicode-protocol      ← UCD + normalize + case + IDNA + breaks + UnicodeSet
i18n-protocol         ← locale + MF2 templating + plural + catalogs
l10n-protocol         ← collate + number/date/currency/list + locale case
```

---

## Backends (planned)

| Backend | Role |
|---------|------|
| `unicode-backend-icu` | ICU4C overlays (ceiling) |
| `unicode-backend-cl-unicode` | Portable tables (reworked compressed data) |
| `unicode-backend-sbcl` | `sb-unicode` (no `:idna`) |

---

## DX

```lisp
(stack-unicode:normalize "é" :form :nfc)
(stack-unicode:alphabetic-p #\A)
(stack-unicode:idna-name-to-ascii "bücher.de")
(stack-unicode:map-breaks (lambda (a b) …) "🏳️‍🌈" :kind :grapheme)
```

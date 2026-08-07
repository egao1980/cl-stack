# unicode-protocol

**Status:** protocol surface **locked** · backend wave-1 **shipped** (cl-unicode) · OCI TBD  
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
| IDNA | Full UTS#46 / IDNA2008 in protocol; stack facade = [`cl-stack-idna`](https://github.com/egao1980/cl-stack-idna) — **do not** mutate Ultralisp [`cl-idna`](https://github.com/egao1980/cl-idna) |
| Breaks | `:grapheme` `:word` `:line` `:sentence` |
| Octets↔string | **Out** — Babel (#94) |
| MF2 / locale / collate / numfmt | **Out** — i18n / l10n protocols |

---

## Layering

```text
babel                 ← octets ↔ string (UTF-8)
unicode-protocol      ← UCD + normalize + case + IDNA + breaks + UnicodeSet
cl-stack-idna         ← to-ascii / to-unicode facade (stack apps)
i18n-protocol         ← locale + MF2 templating + plural + catalogs
l10n-protocol         ← collate + number/date/currency/list + locale case
```

---

## Backends

| Backend | Role |
|---------|------|
| [`unicode-backend-cl-unicode`](https://github.com/egao1980/unicode-backend-cl-unicode) | Portable tables — **wave-1 shipped** |
| [`unicode-backend-icu`](https://github.com/egao1980/unicode-backend-icu) | ICU4C overlays — scaffold |
| `unicode-backend-sbcl` | `sb-unicode` (no `:idna`) — TBD |

---

## DX

```lisp
(asdf:load-system "unicode-backend-cl-unicode")
(stack-unicode:normalize "é" :form :nfc)
(stack-unicode:alphabetic-p #\A)

(asdf:load-system "cl-stack-idna")
(stack-idna:to-ascii "bücher.de")
```

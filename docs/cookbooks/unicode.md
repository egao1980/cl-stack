# Cookbook: Unicode / i18n / l10n

**Audience:** people who know ICU / Python `unicodedata`+`babel` / Java `Character`+`Normalizer`.

| Want | Package | Nick |
|------|---------|------|
| UCD / normalize / case / IDNA / breaks / UnicodeSet | [`unicode-protocol`](https://github.com/egao1980/unicode-protocol) | `stack-unicode` |
| Locale + MF2 + plural + catalogs | [`i18n-protocol`](https://github.com/egao1980/i18n-protocol) | `stack-i18n` |
| Collate / number / date / currency / list / locale case | [`l10n-protocol`](https://github.com/egao1980/l10n-protocol) | `stack-l10n` |
| IDNA facade only | [`cl-stack-idna`](https://github.com/egao1980/cl-stack-idna) | `stack-idna` |
| Octets ↔ string | `babel` | — |

Briefs: [unicode-protocol](../capabilities/unicode-protocol.md) · [i18n](../capabilities/i18n.md) · [l10n](../capabilities/l10n.md) · [text-unicode](../capabilities/text-unicode.md).

**Do not** mutate Ultralisp [`cl-idna`](https://github.com/egao1980/cl-idna) — stack apps use `cl-stack-idna`.

---

## Pick a backend

| Impl / need | Load |
|-------------|------|
| Portable default | `unicode-backend-cl-unicode` **0.1.0** |
| SBCL built-in (no IDNA) | `unicode-backend-sbcl` **0.1.0** |
| ICU4C (CFFI + overlays) | `unicode-backend-icu` **0.1.1** (+ `cl-stack-icu` **78.1.3**) |
| ABCL / JVM | `unicode-backend-icu4j` **0.1.2** (+ `cl-stack-icu4j` **78.1.3**) — auto-binds on `#+abcl` |
| i18n / l10n ICU4C | `i18n-backend-icu` / `l10n-backend-icu` **0.1.1** |
| i18n / l10n ABCL | `i18n-backend-icu4j` **0.1.1** / `l10n-backend-icu4j` **0.1.2** — auto-binds on `#+abcl` |

```lisp
(cl-repo:load-system "unicode-backend-cl-unicode" :version "0.1.0")
;; or on SBCL:
;; (cl-repo:load-system "unicode-backend-sbcl" :version "0.1.0")
```

ABCL: prefer ICU4J backends over CFFI ICU4C. Loading `*-backend-icu4j` installs the backend on `#+abcl`.

---

## 1. Properties / names

```lisp
(use-package :stack-unicode)

(general-category #\A)          ; => :LU
(alphabetic-p #\A)              ; => T
(script #\A)                    ; => :LATIN
(unicode-name #\A)              ; => "LATIN CAPITAL LETTER A"
(lookup-name "LATIN CAPITAL LETTER A") ; => 65
```

---

## 2. Normalize + case

```lisp
(normalize "é" :form :nfc)     ; composed é
(normalize "ﬁ" :form :nfkc)    ; => "fi"
(casefold "Straße")             ; => "strasse"
(downcase "AbC") (upcase "AbC")
```

Root case only here — locale case (`I`→`ı` in Turkish) is `l10n-protocol`.

---

## 3. IDNA

```lisp
;; Via unicode backend that implements :idna (cl-unicode / ICU / ICU4J)
(idna-name-to-ascii "bücher.de")     ; => "xn--bcher-kva.de"

;; Or stack facade
(cl-repo:load-system "cl-stack-idna")
(stack-idna:to-ascii "bücher.de")
```

`unicode-backend-sbcl` has **no** `:idna` — pair with `cl-stack-idna` / cl-unicode / ICU.

---

## 4. i18n (MF2) + l10n formatters

```lisp
(cl-repo:load-system "i18n-backend-icu" :version "0.1.1")
(cl-repo:load-system "l10n-backend-icu" :version "0.1.1")

(stack-i18n:format-message "Hello {$name}!" '(("name" . "Ada")) :locale "en")
(stack-l10n:format-currency 12.5 "EUR" :locale "de-DE")
(stack-l10n:locale-downcase "I" :locale "tr")
```

---

## 5. Conformance

Backends can run the shared suite:

```lisp
(asdf:load-system "unicode-protocol/conformance") ; ≥ 0.1.2
(setf unicode-protocol/conformance:*test-backend-maker*
      (lambda () *unicode-backend*))
(rove:run (asdf:find-system "unicode-protocol/conformance"))
```

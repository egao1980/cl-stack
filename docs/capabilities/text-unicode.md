# Text / Unicode (Babel pin)

**Issues:** [#94](https://github.com/egao1980/cl-stack/issues/94)  
**Status:** policy **locked**; Babel on GHCR via [`cl-stack-systems`](https://github.com/egao1980/cl-stack-systems)

Stack policy for **octets ↔ string** only. Character properties / normalize / IDNA → [`unicode-protocol`](unicode-protocol.md). Locales / MF2 / catalogs → [`i18n`](i18n.md). Collation / numfmt → [`l10n`](l10n.md) ([#151](https://github.com/egao1980/cl-stack/issues/151)).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Default encoding | **UTF-8** |
| Encode/decode pin | **[Babel](https://github.com/cl-babel/babel)** — OCI `babel:0.5.0` |
| Unicode properties / IDNA | **[`unicode-protocol`](unicode-protocol.md)** (backends: ICU / cl-unicode / sb-unicode); transitional pin remains cl-unicode for `cl-idna` until rearrange |
| Streams | flexi-streams where needed; prefer Babel for whole-buffer conversion |
| Non-goal (this brief) | ICU wrap, collation, gettext / MF2, locale-aware formatting — see unicode / i18n / l10n protocols |

---

## Follow-on: i18n / l10n

Text/Unicode (#94) locked UTF-8 + Babel only. Protocol split under [#151](https://github.com/egao1980/cl-stack/issues/151):

- [`unicode-protocol`](unicode-protocol.md) — UCD, normalize, case, IDNA, breaks, UnicodeSet  
- [`i18n-protocol`](i18n.md) — locale, MessageFormat 2 templating, plural, catalogs  
- [`l10n-protocol`](l10n.md) — collation, number/date/currency/list, locale case  

---

## DX

```lisp
(babel:string-to-octets s :encoding :utf-8)
(babel:octets-to-string octets :encoding :utf-8)
```

HTTP / JSON paths already assume UTF-8 (`json-protocol:encode-to-octets`, `stack-http:response-text`).

---

## Dual-load caveat

Loading Babel from both OCI and Quicklisp in one image can trip `defconstant` clashes (`sb-ext:defconstant-uneql`). Prefer **one** source — GHCR pin via `cl-repo` — and continue past uneql in CI only as a last resort (see meta-e2e).

Pins: [`pins/stable.pins`](../../pins/stable.pins) · Import: `cl-stack-systems/imports/babel`.

# Text / Unicode (Babel pin)

**Issues:** [#94](https://github.com/egao1980/cl-stack/issues/94)  
**Status:** policy **locked**; Babel on GHCR via [`cl-stack-systems`](https://github.com/egao1980/cl-stack-systems)

Stack policy for octets ↔ string. **Not** ICU / locale / gettext — those need a separate **i18n planning** pass ([#151](https://github.com/egao1980/cl-stack/issues/151)).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Default encoding | **UTF-8** |
| Encode/decode pin | **[Babel](https://github.com/cl-babel/babel)** — OCI `babel:0.5.0` |
| Unicode properties / IDNA | **cl-unicode** (already used by `cl-idna`) — not a second encode/decode path |
| Streams | flexi-streams where needed; prefer Babel for whole-buffer conversion |
| Non-goal (this brief) | ICU4C wrap, collation, gettext / message catalogs, locale-aware formatting |

---

## Follow-on: i18n planning

Text/Unicode (#94) locked UTF-8 + Babel only. Full **i18n** (locales, message catalogs, plural rules, collation, date/number formats, CLDR) is a different capability — do **not** bolt gettext onto Babel ad hoc. Track: [#151](https://github.com/egao1980/cl-stack/issues/151).

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

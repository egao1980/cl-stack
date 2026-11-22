# CSS: css-protocol, css-backend-lass, engels (H4h-0b)

**Status:** **planned**, locked 2026-11-22. Slice group **H4h-0b** (the canvas theme) of [canvas.md](canvas.md).

| System | Repo | Role | Slice |
|--------|------|------|-------|
| `css-protocol` (nick `stack-css`) | [`egao1980/css-protocol`](https://github.com/egao1980/css-protocol) | CLOS stylesheet model, pretty / minified serializer with escaping, custom-property themes, `scope-stylesheet`, `used-rules`, `compile-stylesheet` / `write-stylesheet` GFs | **H4h-0b-0** → 0.1.0 |
| `css-backend-lass` | [`egao1980/css-backend-lass`](https://github.com/egao1980/css-backend-lass) | LASS S-expressions → css-protocol model; classie's extensions (units, colours, `:let*`, `:include`, `ceil`); ASDF `:lass-stylesheet` component | **H4h-0b-1** → 0.1.0 |
| `lass` (third party) | [cl-stack-systems `imports/lass`](https://github.com/egao1980/cl-stack-systems/tree/main/imports/lass) | Shinmera's LASS **0.6.0**, unmodified (codeberg `d28499f`, zlib) | **done** (cl-stack-systems#71, OCI `lass:0.6.0`) |
| `engels` | [`egao1980/engels`](https://github.com/egao1980/engels) | Classless theme: LASS port of [Marx](https://github.com/mblode/marx) (MIT) | **H4h-0b-2** → 0.2.0 |
| `canvas-protocol` minor | [`egao1980/canvas-protocol`](https://github.com/egao1980/canvas-protocol) | Default asset `canvas.css` becomes engels | **H4h-0b-3** |
| `css-backend-parse` | later | CSS text → model, for vendored CSS | **later** |

[`egao1980/classie`](https://github.com/egao1980/classie) is **superseded** by `css-backend-lass` and stays untouched (no archive, no PR). Its README examples become css-backend-lass tests; its own `tests/main.lisp` is a placeholder (`(= 1 1)`), so nothing else ports.

**html-protocol is unchanged:** CSS stays opaque text there ([html-protocol.md](html-protocol.md)). css-protocol reads html-protocol trees (for `used-rules`); html-protocol never depends on css-protocol.

---

## Why

Canvases ([canvas.md](canvas.md), H4h) emit classless semantic HTML and ship one stylesheet asset, `canvas.css`, which freeze inlines into `<style>`. The default theme is engels, which today is LASS files compiled through classie and Quicklisp at ASDF load. To ship it on the stack the CSS needs:

1. a model the stack can test and transform (scope a frozen canvas, prune it to the rules a page uses, add light/dark custom properties), not a string;
2. a serializer that is safe inside an HTML `<style>` element (no `</style` can come out of any value);
3. LASS from cl-repo (OCI), not Quicklisp, and classie's helpers in an owned, tested backend.

---

## Prior art

| Prior art | Take | Leave |
|-----------|------|-------|
| **LASS** (Shinmera) | The S-expression syntax, its compiler (`lass:compile-sheet`: nesting, `:let`, property functions, special blocks, vendor prefixes), its ASDF component idea | Writing CSS straight to text (`write-sheet`), so nothing can transform it; global state in `lass:*vars*` is kept only inside the backend |
| **css-lite**, **cl-css** (CL) | Plain Lisp lists for rules (cl-css) | String concatenation output with no escaping or model; macros as the only interface (css-lite) |
| **SCSS / LESS** | Variables, `@include`/`@import` of partials, colour functions (`darken`, `lighten`, `fade-in`/`fade-out`, `mix`), unit arithmetic — through classie, in the LASS backend | Mixins, `@extend`, control flow (Lisp already has them), a second syntax |
| **Marx**, **Pico**, **Water.css** (classless) | Style semantic elements, never classes; custom properties for colours; `prefers-color-scheme` light/dark (Pico, Water.css) | Class-based components (Pico's `.container`, grid classes); CDN delivery |
| **lightningcss** / **cssom** (W3C CSSOM) | A typed rule tree + one serializer with pretty and minified modes; CSSOM's "serialize an identifier" and "serialize a string" algorithms, exactly | A full CSS parser and value grammar in 0.1.0 (parsing is the later `css-backend-parse`); browser targets and prefixing (LASS already prefixes); source maps |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | "Usual cl-stack shape": protocol repo with no backend inside + backend repos. `compile-stylesheet` dispatches to a `css-backend` (`*css-backend*`), like html-protocol's `parse` | One model, many sources (LASS now, CSS text later) |
| **Dependencies** | css-protocol depends on **html-protocol only** (itself dependency-free). Pure Lisp, no natives, no regex library | `used-rules` reads html-protocol trees; everything else is string work |
| **Model** | CLOS classes, built by `make-*` constructors that validate. Declaration values, media queries and supports conditions are **validated, whitespace-normalised text**, not parsed values | A value grammar is large and not needed to serialize safely; validation is what keeps output well-formed |
| **Selectors** | **Parsed structures with canonical text.** `parse-selector-list` turns text into `selector` objects (one per comma-separated complex selector); each holds compounds and combinators. A compound keeps its type, ids and classes (unescaped) and keeps attribute selectors, pseudo-classes and pseudo-elements as verbatim text (`compound-others`). The serializer rebuilds text from the parts | `used-rules` and `scope-stylesheet` need ids, classes, types and the leading compound; validated strings alone would mean re-parsing in each. Verbatim "others" keep `:not(…)`, `:is(…)`, `[…]` exact without a full Selectors-4 grammar |
| **Selector subset (0.1.0)** | Type, `*`, `#id`, `.class`, `[…]`, `:pseudo`, `:pseudo(…)`, `::pseudo-element`, combinators descendant / `>` / `+` / `~`, comma lists, CSS escapes in identifiers. **Refused** (`css-invalid-selector`): namespaces (`svg\|rect`), nesting `&`, relative selectors (`> a`), `>>`, anything with `{` `}` `;` or `<` outside strings | Covers what classless themes and canvases use; refusing is safer than guessing |
| **`declaration` name** | The class is **`css-declaration`** (constructor `make-declaration`, readers `declaration-*`) | `cl:declaration` is a COMMON-LISP symbol; defining a class on it is undefined (SBCL package lock) |
| **At-rules** | `media-rule`, `supports-rule`, `layer-rule` (statement or block), `font-face-rule`, `keyframes-rule` + `keyframe`, `import-rule`, `scope-rule`. All subclasses of `at-rule` | The locked list plus `@scope`, which `scope-stylesheet` emits. `@page`, `@namespace`, `@charset`, `@container`, `@property` are later minors |
| **No nesting in the model** | Style rules hold declarations only; CSS nesting is flattened by the source (LASS already flattens) | Simpler serializer and pruning; nesting output can come later as a serializer option |
| **Custom properties** | A declaration whose property starts with `--`; name kept case-sensitive; standard properties are lowercased | Themes are custom-property maps |
| **Serializer** | `write-stylesheet` GF, `:pretty t` (default) or `nil` (minified). Exact format below; tests are golden strings | Byte-stable output: freeze must be byte-identical for the same input |
| **Escaping** | CSSOM "serialize an identifier" and "serialize a string", plus **`<` → `\3c `** in strings; `url()` always quoted. Values, preludes and selectors containing `</` are refused | Output is inlined into HTML `<style>`; only `</style` can end it, and no path can produce `</` |
| **Errors** | Root `css-error`; syntax errors carry the offending input. Every validating constructor offers **`use-value`** (replacement is validated again) and **`skip-invalid`** (constructor returns NIL; containers drop NIL children). `compile-stylesheet` with no backend signals **`css-no-backend`** with `use-value` (a stylesheet) and `use-backend` (retry) | CLHS restart names first; skipping one bad rule is the common recovery when compiling a whole theme |
| **Themes** | `css-theme`: light and dark custom-property maps → `:root` + `@media (prefers-color-scheme: dark)`, optional attribute toggle (`data-theme`), `color-scheme` declared | Pico / Water.css pattern; the toggle lets a page force a mode without JS in the cascade |
| **Naming vs canvas-protocol** | css-protocol's theme functions are `make-css-theme` / `css-theme-stylesheet` | canvas-protocol already owns `theme-stylesheet` (its asset GF) |
| **LASS compile path** | css-backend-lass calls **`lass:compile-sheet`** and **walks its compiled form** (the `:block` / `:superblock` / `:property` tree documented in LASS `writer.lisp`) into the model. Selector constraint trees are rendered with LASS's own `write-sheet-object` (minified) and re-parsed by `parse-selector-list`. Not text re-parsing, not walking raw LASS forms | Walking raw LASS forms would re-implement LASS's compiler (nesting, `:let`, property functions, special blocks) and drift from it. Compiling to text then parsing needs a CSS parser that does not exist yet and loses nothing LASS's tree does not already give. The compiled tree is LASS's stable internal contract with its own writer (unchanged since 2015) |
| **LASS** | Imported unmodified at `d28499f` (0.6.0) — the last commit before 2026-05's binary-build work put `#-no-dependencies` reader conditionals into `lass.asd` | Third-party, unmodified ⇒ cl-stack-systems import; no fork |
| **classie** | Superseded; repo untouched. Features re-implemented in css-backend-lass with their own tests; **no** `cl-colors`, `dufy`, `physical-quantities`, `parse-float`, `cl-fad` | Those are Quicklisp-only deps for small jobs (hex/HSL maths, 4 units, float parsing) |

---

## css-protocol 0.1.0 (H4h-0b-0)

### Surface

```lisp
;; conditions + restarts
css-error (error)                    css-error-message
  css-syntax-error                   css-error-input        ; the offending text
    css-invalid-selector css-invalid-property css-invalid-value
    css-invalid-identifier css-invalid-prelude
  css-no-backend                     css-no-backend-source
(skip-invalid &optional condition)   ; invoke SKIP-INVALID
(use-backend backend &optional condition)
;; + CL:USE-VALUE on every syntax error and on css-no-backend

;; backends
*css-backend*  css-backend
(backend-compile-stylesheet backend source &key)       ; GF, backends specialise
(compile-stylesheet source &key backend) → stylesheet  ; GF; stylesheet → itself
(write-stylesheet node &key stream (pretty t)) → string | NIL   ; GF
(write-css-node node stream pretty depth)              ; GF, extension point

;; model
css-node
stylesheet     (make-stylesheet rules)  stylesheet-rules  (merge-stylesheets &rest sheets)
rule           (make-rule selectors declarations)  rule-selectors rule-declarations
css-declaration (make-declaration property value &key important)
               declaration-property declaration-value declaration-important-p custom-property-p
selector       (parse-selector-list string) → (selector …)
               (selector-text selector &key (pretty t))  selector-compounds
compound-selector compound-type compound-ids compound-classes compound-others
at-rule        at-rule-name at-rule-rules
media-rule     (make-media-rule query rules)           media-rule-query
supports-rule  (make-supports-rule condition rules)    supports-rule-condition
layer-rule     (make-layer-rule names &optional rules) layer-rule-names layer-rule-statement-p
font-face-rule (make-font-face-rule declarations)
keyframes-rule (make-keyframes-rule name keyframes)    keyframes-rule-name keyframes-rule-keyframes
keyframe       (make-keyframe selectors declarations)  keyframe-selectors
import-rule    (make-import-rule url &key layer supports media)
               import-rule-url import-rule-layer import-rule-supports import-rule-media
scope-rule     (make-scope-rule start rules &key end)  scope-rule-start scope-rule-end

;; values
(css-ident string) (css-string string) (css-url string) (css-var name &optional fallback)

;; themes and transforms
css-theme  (make-css-theme &key light dark (selector ":root") toggle-attribute)
           css-theme-light css-theme-dark css-theme-selector css-theme-toggle-attribute
           (css-theme-stylesheet theme) → stylesheet
(scope-stylesheet stylesheet scope &key (method :prefix)) → stylesheet  ; :prefix | :scope-rule
(used-rules stylesheet tree) → stylesheet
```

`rule-declarations` also reads `font-face-rule` and `keyframe`. Constructors accept a selector argument as a string (comma lists allowed), a `selector`, or a list of those. Containers accept lists and drop NILs (a skipped child); any other non-node child is a `type-error`. Transforms never mutate their input.

### Validation

- **Property:** `--` followed by one or more name characters (custom, case kept), or an identifier `-?[A-Za-z_][A-Za-z0-9_-]*` (lowercased). Else `css-invalid-property`.
- **Value:** string or real (integers as decimals; floats and ratios in plain decimal without exponent, trailing zeros dropped: `2.0` → `2`, `1/4` → `0.25`). Other types → `type-error`. Text: comments outside strings removed, whitespace runs outside strings collapsed to one space, trimmed. `css-invalid-value` when the result is empty, has an unterminated string / comment / escape, a raw newline in a string, unbalanced `()[]{}`, a `;` or `!` outside strings and brackets (importance is `:important t`), or `</` anywhere.
- **Preludes** (media query, supports condition, import `supports` / `media`): same text rules as values → `css-invalid-prelude`.
- **Identifiers** (`css-ident`, keyframes names, layer name segments): any non-empty string; serialized with `css-ident`. Empty → `css-invalid-identifier`.
- **Keyframe selectors:** `from`, `to` (case-insensitive, lowercased) or a percentage `N%` / `N.N%`; else `css-invalid-selector`.
- **Selectors:** the subset above; `css-error-input` is the whole text given.

### Serializer format

Pretty: two-space indent per level; `selector-list {` … `}`; one declaration per line as `property: value;` or `property: value !important;`; sibling rules separated by **one blank line** at every level; an empty block is `{}` on the opening line; the sheet ends with one newline; an empty sheet is `""`. Selector lists join with `", "`, combinators print as `" > "`, `" + "`, `" ~ "`, `" "`.

Minified: no newlines or indent; `,` between selectors; `>` `+` `~` without spaces; `property:value` joined by `;` with no trailing `;`; `!important` without a space; no space before `{`. Values and preludes print as normalised, in both modes.

```css
/* pretty */
a, b > c {
  color: red;
  margin: 0 auto !important;
}

@media print {
  a {
    color: black;
  }
}
```

```css
/* minified */
a,b>c{color:red;margin:0 auto!important}@media print{a{color:black}}
```

At-rules: `@media Q {`, `@supports C {`, `@layer a.b {` / `@layer {` (anonymous) / statement `@layer a, b;` (minified `@layer a,b;`), `@font-face {`, `@keyframes NAME {` (keyframe selectors `0%, 50%`), `@import url("U") layer | layer(N) supports(C) MEDIA;` (same in both modes), `@scope (START) to (END) {` (selectors in the mode's form). A `write-stylesheet` of a non-stylesheet node prints it as a one-item sheet.

### Escaping

- `css-ident`: CSSOM *serialize an identifier*: NUL → U+FFFD; U+0001–U+001F, U+007F, a leading digit, or a digit after a leading `-` → `\` + lowercase hex + space; a lone `-` → `\-`; `-`, `_`, ASCII alphanumerics and anything ≥ U+0080 stay; every other character → `\` + the character. `(css-ident "1st")` → `\31 st`, `(css-ident "a b")` → `a\ b`.
- `css-string`: CSSOM *serialize a string* in double quotes (NUL → U+FFFD; controls → hex escape; `"` and `\` backslashed) **plus `<` → `\3c `**. `(css-string "</style>")` → `"\3c /style>"`.
- `css-url`: `url(` + `css-string` + `)`. `css-var`: `var(--name)` / `var(--name, fallback)`, the name through `css-ident` (a leading `--` in the argument is accepted).

### Themes

```lisp
(css-theme-stylesheet
  (make-css-theme :light '(("bg" . "#fff") ("fg" . "#111"))
                  :dark  '(("bg" . "#111") ("fg" . "#eee"))
                  :toggle-attribute "data-theme"))
```

```css
:root {
  color-scheme: light dark;
  --bg: #fff;
  --fg: #111;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #111;
    --fg: #eee;
  }
}

:root[data-theme="dark"] {
  color-scheme: dark;
  --bg: #111;
  --fg: #eee;
}

:root[data-theme="light"] {
  color-scheme: light;
}
```

Keys are strings (with or without `--`) or symbols (downcased); values go through `make-declaration`. Without `:toggle-attribute`, the media rule selects `:root` and the two attribute rules are absent. Without `:dark`, the sheet is the `:root` rule with no `color-scheme`. `:selector` replaces `:root` everywhere.

### scope-stylesheet

For frozen canvases (several canvases on one page, or a canvas embedded in a larger document).

- `:prefix` (default): every complex selector becomes `SCOPE SELECTOR`, except when its first compound is `html`, `body` or contains `:root`: then that type / `:root` is replaced by the scope and the rest of the compound kept (`:root:not([x])` → `#c:not([x])`, `body > p` → `#c > p`). Recurses into `@media`, `@supports`, `@layer` blocks; a `@scope` rule's start selector is prefixed and its children left alone. `@font-face`, `@keyframes`, `@import`, `@layer` statements are unchanged.
- `:scope-rule`: wraps each run of consecutive style rules / `@media` / `@supports` / `@scope` into one `@scope (SCOPE) { … }`, with leading `html` / `body` / `:root` replaced by `:scope`. `@import`, `@font-face`, `@keyframes`, `@layer` statements stay where they are (source order kept); `@layer` blocks stay outside and their children are wrapped the same way.

### used-rules

Freeze calls it to ship only the rules a page can use. A complex selector **may match** when every compound in it is satisfied by **some single element** of the tree: its type (case-insensitive; `*` or none = any), all its ids and all its classes (case-sensitive; `class` split on ASCII whitespace) on that one element. Combinators are ignored and attribute selectors, pseudo-classes and pseudo-elements in `compound-others` count as satisfied (**conservative**: anything it cannot decide is kept). A compound with type `html` or `body`, or containing `:root`, is always satisfied (a canvas fragment has no `html` / `body`, the frozen page does).

A rule is kept, **unchanged** (whole selector list), when any of its selectors may match. Grouping rules (`@media`, `@supports`, `@layer` block, `@scope`) keep their kept children and are dropped when none remain. `@font-face`, `@keyframes`, `@import` and `@layer` statements are always kept. The tree is an `html-document`, an `html-element`, or a list of nodes.

### Tests (contract)

`css-protocol/tests` (Rove; contract [css-protocol#1](https://github.com/egao1980/css-protocol/pull/1), 95 deftests), one file per area: `serialize-test` (golden pretty + minified for every construct, number and whitespace normalisation), `escape-test` (identifiers, strings, url, hostile inputs, no `</` in any output), `selector-test` (parse structure, canonical text, every refused form), `theme-test`, `scope-test`, `used-rules-test` (html-protocol trees built with `make-html-element`, including every conservative-keep case), `condition-test` (each invalid input → its condition, `use-value` re-validated, `skip-invalid` dropping, type errors), `backend-test` (`compile-stylesheet` with no backend → `css-no-backend` and its restarts; a test backend through `*css-backend*` and `:backend`).

---

## css-backend-lass 0.1.0 (H4h-0b-1)

Depends on `css-protocol` and `lass` (OCI). Loading it sets nothing global except LASS's own property-function and special-block tables (which LASS keeps global).

```lisp
lass-backend  *lass-backend*               ; instance; *css-backend* is not changed on load
(backend-compile-stylesheet (b lass-backend) forms &key variables pathname)
(compile-lass forms &key variables pathname) → stylesheet       ; = compile-stylesheet with the backend
(compile-lass-file pathname &key variables) → stylesheet
lass-stylesheet                            ; ASDF component, keyword :lass-stylesheet
```

- **Path:** `(apply #'lass:compile-sheet forms)` with `lass:*vars*` rebound to a fresh table seeded from `:variables` (alist), then a walk of the result: `(:block selector props…)` → `rule` (selector text from `lass:write-sheet-object` with `lass:*pretty*` nil, parsed by `parse-selector-list`); `:property` → `make-declaration` (a trailing ` !important` becomes `:important t`); `(:superblock "media"|"supports" …)` → `media-rule` / `supports-rule`; `"keyframes"` → `keyframes-rule` + `keyframe`s; a block whose selector is `@font-face` → `font-face-rule`; a top-level `@import …` property → `import-rule`; `:text` → `css-invalid-value` (raw text is not modelled). The backend adds `:layer` and `:scope` special blocks. Unknown superblocks (`document`, `page`, `namespace`, `charset`) signal `css-invalid-prelude` with the usual restarts.
- **classie features, re-implemented** as LASS property functions / special blocks in this package: unit arithmetic `+ - * /` over `px pt in %` and unitless numbers (percent rules: `(* 85% "800px")` → `680px`; two percents stay percent), `ceil` (on the shown value: `49.5%` → `50%`) and `ceiling` (on the fraction: `49.5%` → `100%`), `values` (space-joined), colours `darken` / `lighten` (HSL lightness ± amount), `fade-in` / `fade-out` (alpha ± amount → `rgba(…)`), `mix` (weighted RGB, default 0.5); `(:let* bindings body…)` (sequential, like CL); `(:include "file.lass")` relative to the including file, bindings visible. Hex parsing, HSL and float printing are local code. Number format: two decimals as classie (`14.00px`, `9.08in`) — kept for engels parity and recorded in the tests.
- **Tests ported from classie** (its README examples, the only real ones): `(a :background (ceil (* 0.85 "16px")))` → `14.00px`; `(div :width (+ 2in (ceil (* 85% "800px"))))` → `9.08in`; `(div :background (darken "#fff" 20%))` → `#CCCCCC`; plus each colour function, `:let*` shadowing, `:include` with a nested include and a relative path, `ceil` vs `ceiling` at 49.5%.
- **ASDF component:** `(:lass-stylesheet "engels" :output "../css/engels.css" :pretty nil)` compiles at `compile-op` through the model and `write-stylesheet`; `load-op` does nothing. Class `css-backend-lass:lass-stylesheet`, smuggled into `asdf/interface` like LASS's `lass-file` so `:defsystem-depends-on ("css-backend-lass")` works.

---

## engels 0.2.0 on the stack (H4h-0b-2)

In `egao1980/engels` (default branch `master`), branch `agent/engels-stack-*`. Skeleton now; the full PR after css-backend-lass 0.1.0 is published.

- `.asd`: `:version "0.2.0"`, `:defsystem-depends-on ("css-backend-lass")`, `:depends-on ("css-protocol" "css-backend-lass")` (no `lass`, `classie`, `alexandria` from Quicklisp), `:lass-stylesheet` component, `engels/tests` (Rove). Canned `test.yml` (ubuntu, macOS, Windows) + `publish-checkout.yml`.
- Light and dark through `make-css-theme` custom properties (`--engels-*`): colours from `src/engels.lass`'s `:let*` move into a light map and a new dark map; rules use `(css-var …)`. `prefers-color-scheme` plus the `data-theme` toggle.
- Covers canvas-protocol's closed `data-*` vocabulary (`data-layout`, `data-gap`, `data-columns`, `data-align`, `data-badge`) and the `aria-*` states it emits, so it can replace the placeholder theme without visual loss.
- No `url(` and no `@import` in the output (canvas freeze must stay offline).
- API: `(engels:stylesheet)` → css-protocol stylesheet; `(engels:css-string &key (pretty nil))` → string; `(engels:css-octets)` → UTF-8 octets; `css/engels.css` stays as the committed build artefact.
- **Licence:** engels stays MIT; add Marx's MIT notice (Copyright (c) Matthew Blode) to `LICENSE` and the CSS header comment, since engels is a port of Marx. Drop the stray `src/marx.css` from the source tree (keep it as reference under `docs/` with its notice) and the duplicate README.
- Tests: the compiled sheet parses through the model, has `:root` light + dark media rule, no `url(` / `@import`, golden checksum of `css/engels.css`.

## canvas-protocol switch (H4h-0b-3)

canvas-protocol minor: `theme-stylesheet` `(eql :engels)` method returning `(engels:css-octets)`, `*canvas-theme*` default `:engels`; asset name `canvas.css` and the API unchanged; the placeholder stays for zero-dependency use. Freeze may call `used-rules` + `scope-stylesheet` on the theme (decided in that slice).

## Later: css-backend-parse

A CSS text parser backend (CSS Syntax 3 tokenizer → the model; unknown at-rules kept or refused by policy) for vendored CSS such as a third-party theme. Not needed for engels.

---

## Non-goals (0.1.0)

- Cascade, specificity, computed values, a value grammar, colour or unit types in css-protocol (units and colours are LASS-backend functions).
- CSS nesting output, `@container`, `@property`, `@page`, `@namespace`, source maps, vendor prefixing.
- Parsing CSS text (css-backend-parse).

## Checklist

- [x] LASS 0.6.0 imported unmodified (cl-stack-systems#71), OCI `lass:0.6.0`
- [x] `egao1980/css-protocol`, `egao1980/css-backend-lass` created; both and `engels` in the workspace `repos.manifest`
- [ ] **H4h-0b-0** css-protocol 0.1.0 — contract [css-protocol#1](https://github.com/egao1980/css-protocol/pull/1) (draft; 95 deftests / 332 assertions), then team-solve
- [ ] **H4h-0b-1** css-backend-lass 0.1.0 — classie features + tests, `:lass-stylesheet`
- [ ] **H4h-0b-2** engels 0.2.0 — skeleton branch now, PR after css-backend-lass is published
- [ ] **H4h-0b-3** canvas-protocol default asset → engels
- [ ] Later: css-backend-parse

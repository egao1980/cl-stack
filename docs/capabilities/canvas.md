# Canvas (H4h) — live HTML views from a session image

**Repos:** new [`egao1980/canvas-protocol`](https://github.com/egao1980/canvas-protocol) (nicks `stack-canvas`, `canvas`) · new [`egao1980/canvas-backend-svg`](https://github.com/egao1980/canvas-backend-svg) · new [`egao1980/rpc-backend-htmx`](https://github.com/egao1980/rpc-backend-htmx) · later [`egao1980/engels`](https://github.com/egao1980/engels) theme (H4h-0b) · server in [`egao1980/cl-stack-code`](https://github.com/egao1980/cl-stack-code) (H4h-2, with H8d-1)
**Builds on:** [html-protocol](html-protocol.md) 0.1.0 (trees, serialize, escaping) · [sse-protocol](sse.md) 0.1.1 (event blocks) · [encoding-protocol](encoding-protocol.md) 0.2.0 (UTF-8) · [rpc-protocol](rpc.md) 0.2.0 (modes, codec; H4h-1b) · [http-server-protocol](http-server.md) 0.1.0 (Clack apps; H4h-1b) · [crypto-protocol](crypto.md) (tests only: asset checksums)
**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md) row H4h; the web view is H8d-1 ([cl-stack-code.md § H8d](cl-stack-code.md#h8d--locked), "Web page")
**Status:** decisions **locked** (below). **H4h-0** contract on branch `agent/h4h0-contract-9e4a` of canvas-protocol ([draft PR #1](https://github.com/egao1980/canvas-protocol/pull/1), stubs `%h4h0-pending`). H4h-0b, H4h-1, H4h-1b, H4h-2: decisions locked here; contracts written when each run starts. Implementation via **team-solve**.

An agent (or a user at the REPL) wants to *show* something richer than text — a sortable table of test results, a form that edits image state, a chart of benchmark timings — and keep it **live**: the page is the image's state, re-rendered per request. A canvas is a **plain CL function** in the session image: keyword arguments in (request parameters as strings), an html-protocol tree out. Interactivity is **htmx** attributes pointing at other canvas functions; live updates are **SSE** through the htmx SSE extension. `freeze` turns a canvas call into one self-contained static `.html`.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| **Claude artifacts** / **ChatGPT canvas** | A rendered view next to the conversation; a **freeze to a file** you can share; strict sandboxing of what the page may load | The page is client-side JS the model writes (React / HTML blobs) with no link back to live state; every view is a new document. Here the image renders and the page stays thin |
| **Jupyter** (rich display, ipywidgets) | Objects render themselves (`_repr_html_` ≈ our `render` GF); a live kernel behind the view; export to static HTML | A websocket comm protocol and a JS widget runtime per widget type; notebook files as the unit |
| **marimo** | Reactive cells; the app *is* code; `marimo export html` freezes; UI elements post values back as plain values | The dataflow graph — state here is ordinary image state, and a canvas is just a function |
| **Observable** (Plot, Framework) | Chart model = marks + scales + axes, sensible defaults (nice ticks, colour-blind palette); static build output | The client-side reactive runtime and JS-authored charts |
| **CLOG** (Lisp GUI over websockets) | The Lisp image owns the UI; plain Lisp functions build it | A persistent websocket and a JS bridge that evaluates commands in the browser (needs `unsafe-eval`, breaks a strict CSP); per-connection object trees |
| **htmx** (docs, `htmx.config`, SSE extension, [CSP notes](https://htmx.org/docs/#security)) | Hypermedia: the server returns HTML fragments; `hx-get/post/target/swap/trigger`; `HX-*` request and response headers; `htmx-config` meta (`allowEval:false`, `selfRequestsOnly`, `includeIndicatorStyles:false`, `historyCacheSize:0`) | `hx-on:*`, trigger filters `[…]`, `js:` vals and `hx-vars` (all need eval); CDN loading; htmx 4 (released 2026-08, still the npm `next` tag; attribute inheritance and SSE changed) |

---

## Decisions (locked, all slices)

| Decision | Choice |
|----------|--------|
| **A canvas is a function** | `(defun people (&key sort page) …)` in any package → anything `render` accepts. No canvas object, no registry, no `defcanvas`. State is image state. The URL names the function (`<package>::<name>`); which functions may be called is the server's allowlist (H4h-1b handler table, H4h-2 policy), never "every fbound symbol" |
| **Trees are html-protocol** | Output is html-protocol nodes; serialization and escaping are html-protocol's. Components render *into* those nodes and accept raw nodes as children; raw nodes pass through `render` unchanged |
| **`render` GF** | `(render object)` → node, list of nodes, or NIL. Methods: `html-node` (itself), string / number (escaped text), list (flattened), `component`, `canvas-coercion-error` (inline error fragment), `chart` (through `*chart-backend*`). Users add methods for their own classes (Jupyter `_repr_html_`) |
| **Classless semantic HTML** | Components emit plain semantic elements so a classless stylesheet (engels, H4h-0b) styles them unchanged: `table/caption/thead/tbody/th scope=col`, `form/label/input/select/textarea/fieldset/legend/button`, `figure/figcaption`, `nav`, `section`, `article/header/footer`, `details/summary`, `dl/dt/dd`, `pre/code`, `small role=alert`. **No `class` attributes are emitted.** Where semantics cannot say it: `aria-*` first (`aria-sort`, `aria-selected`, `aria-invalid`, `aria-describedby`, `aria-live`, `role=tablist/tab/tabpanel`), then this closed `data-*` vocabulary: `data-layout` (`stack` `row` `grid`), `data-gap` (`none` `s` `l`; `m` is the default and omitted), `data-columns` (1–6), `data-align` (`start` `center` `end`), `data-badge` (`neutral` `info` `ok` `warn` `error`), `data-language` (code blocks), `data-chart` (chart figures), `data-canvas-frozen` (frozen `<body>`). Adding to it is a minor version |
| **CSP-ready output** | H8d-1 serves with `script-src 'self'` (no `unsafe-inline`, no `unsafe-eval`). Generated HTML never contains inline `<script>` content, `on*` attributes, `hx-on*`, `javascript:` URLs, trigger filters (`[`), `js:` / `hx-vars`, or `style` attributes. `el` refuses `script` / `iframe` / `object` / `embed` tags and `on*` / `hx-on*` attributes (`canvas-csp-error`); `csp-violations` scans any tree; `page` refuses a violating tree (restart `strip-violations`). htmx itself loads from `'self'` with eval off via the `htmx-config` meta |
| **Attributes** | Plists `(:hx-get "/…" :hx-target "#t")`. Value: string as is, integer decimal, T → `""` (boolean attribute), NIL → omitted. Output order is the order given; components put `id` first, then their own attributes, then the caller's `:attrs`. Deterministic: no generated ids, no hash-table order, no timestamps |
| **URLs: a resolver GF** | `(resolve-canvas-url resolver symbol params)` and `(resolve-asset-url resolver name)` on `*canvas-resolver*`. Params arrive normalized: an alist of lowercase name → string, NIL values dropped, in the given order (later duplicates override earlier ones in place). `canvas-link` (symbol + params) is the unit components carry; `canvas-url` / `link-url` resolve it. canvas-protocol ships `path-resolver` (`<prefix><PACKAGE>::<NAME>?k=v`, RFC 3986 percent-encoding, the H8d-1 shape with `prefix` = `/canvas/<session>/`) and `freeze-resolver` (always NIL). rpc-backend-htmx supplies the server's resolver (H4h-1b), tests use a fake. No resolver → `canvas-no-resolver`. A NIL URL makes every hx helper return NIL: the element renders inert |
| **htmx helpers** | `hx-get` / `hx-post` return attribute plists in a fixed key order (`hx-get|post target swap trigger select include vals push-url confirm indicator`). Swap styles are keywords validated against htmx's set (`:inner-html` → `innerHTML` …), optionally followed by modifiers in a string. `:vals` is a flat plist, normalized to an alist of strings and encoded with json-protocol (`stack-json:encode`, default backend json-backend-jzon). There is no private JSON encoder, and the same goes for the `HX-Trigger` object form and the `htmx-config` meta. Byte determinism comes from json-protocol itself: alist key order and compact output ([json-protocol#23](https://github.com/egao1980/json-protocol/issues/23)). The attribute value is HTML-escaped by html-protocol |
| **Response headers are data** | `(htmx-response-headers &key trigger trigger-after-settle trigger-after-swap redirect refresh location push-url replace-url retarget reswap reselect)` → alist of `("HX-…" . value)` sorted by header name. `:trigger` takes an event name, a list of names (`"a, b"`), or a plist (JSON object of string details, via json-protocol). CR/LF in any value → `canvas-error`. The codec (H4h-1b) turns this into real headers; canvas-protocol never touches a server |
| **SSE** | `sse-connect` (link → `(:hx-ext "sse" :sse-connect url)`), `sse-swap`, `sse-close`, the `live-region` component, and `fragment-event` (event name + tree → `stack-sse:sse-event` whose data is the serialized fragment). Event names are `[A-Za-z0-9_.:-]+` (newline injection into the event stream is refused) |
| **Forms** | Values arrive as strings. `(coerce-param value type &key field default required min max choices)` for `:string :integer :float :boolean :date :choice`; never the Lisp reader. Failure signals `canvas-coercion-error` (field, value, expected, detail) with restarts `use-value` and `use-default`. `coerce-form` coerces a param plist against specs, records each error and takes `use-default`, → `(values coerced-plist errors)`. An error renders as `<small id="<field>-error" role="alert">` and the input gets `aria-invalid` + `aria-describedby` |
| **Tables** | Columns: header, accessor (function or plist key), `:name` (the sort param value), `:sortable`, `:format`, `:align`. Sort param `"name"` / `"-name"`; page param 1-based; both strings from the request, invalid values ignored (never an error). `sort-rows` (stable, fresh copy, lists and vectors), `page-rows` → `(values rows page page-count)`, `parse-sort`, `value<` (NIL first, numbers, then strings, else printed). A table with a `:link` re-renders itself: header buttons and the pager `hx-get` the same canvas with `sort`/`page`, target the table's `id`, `outerHTML` |
| **Page** | `page` wraps a body in a full document: charset, viewport, `htmx-config` meta, title, the stylesheet `<link>`, `<script src>` for htmx and the SSE extension, all from `resolve-asset-url`. Whether a request gets a fragment or a page is the server's call (H4h-1b: `HX-Request` present → fragment) |
| **Vendored htmx** | **htmx 2.0.11** (npm `latest`, 2026-09-22) and **htmx-ext-sse 2.2.4** (2025-10-18), both **0BSD**, minified builds stored under `assets/` with their licences, the npm tarball `sha512` integrity and each file's SHA-256 (`assets/SHA256SUMS`). Served only as bytes by `asset-bytes` (+ `asset-content-type`, `asset-sha256`, `asset-info`, `asset-license`). No CDN, ever. Upgrades are a deliberate minor bump with new sums |
| **Stylesheet** | Asset `canvas.css` (stable name), produced by `(theme-stylesheet *canvas-theme*)`, default theme `:placeholder`: a minimal classless sheet (light/dark via `prefers-color-scheme`, readable tables, the `data-*` vocabulary). H4h-0b adds the engels theme as another `theme-stylesheet` method and makes it the default — **no API change**. No `url(` / `@import` (freeze must stay offline) |
| **`freeze`** | `(freeze fn &key args title)` calls the canvas under `freeze-resolver` and returns one HTML document string. **htmx is dropped, not disabled:** a frozen file has no server, so links could only fail; the file needs no JS and so no CSP exceptions. Freeze inlines the theme stylesheet in `<style>`, strips every `hx-*` / `data-hx-*` / `sse-*` attribute, `<script>`, `<link>`, `<iframe>` / `<object>` / `<embed>`, the caller's own `<style>`, `on*` / `style` attributes, and every `src` / `href` / `action` / `formaction` / `srcset` / `poster` / `xlink:href` value that is not `#…` or `data:`; `<body data-canvas-frozen>`. Charts stay inline SVG. Same function + args + state → byte-identical output |
| **Charts** | A backend-neutral model: `chart` (kind `:line :bar :scatter :histogram`, series, x/y `axis`, title, description, legend, width/height, histogram `bins`), `series` (name, points, colour, tooltip labels), `axis` (label, scale `:linear :log :time`, min/max, ticks, format). `make-chart` validates (`invalid-chart` field + reason). `(render-chart backend chart &key)` GF on a **chart backend**; NIL backend → `chart-backend-missing` (restarts `use-value`, and in `render` also `use-placeholder`). `*chart-palette*` = Okabe–Ito (colour-blind safe), shared by backends. Later backends (vega-lite, …) just add methods |
| **Pure Lisp** | No CFFI, no JS build. SBCL, CCL and ECL via the canned CI; three OSes |
| **Package** | canvas-protocol never depends on rpc-backend-htmx or any server; rpc-backend-htmx depends on canvas-protocol only in its `rpc-backend-htmx/canvas` system (the resolver) |

---

## API sketch (canvas-protocol 0.1.0)

```lisp
;; trees
(render object) → node | list | nil              (to-html object) → string (documents with doctype)
(el tag attrs &rest children)                     ; (el :p nil "hi") ; tag keyword/string
component component-id component-attrs
;; layout
(stack children &key gap direction id attrs)      (grid children &key columns gap id attrs)
(card children &key title footer id attrs)        (details summary children &key open id attrs)
(fieldset children &key legend id attrs)          (tabs tabs &key id active link content attrs)
(code-block text &key language id attrs)          (kv-list pairs &key id attrs)
(badge text &key status id attrs)                 (live-region link event &key id content swap attrs)
;; tables
(column header accessor &key name sortable format align)
(table rows columns &key id link sort page page-size caption empty attrs)
(sort-rows rows columns sort) (page-rows rows page page-size) → (values rows page count)
(parse-sort sort columns) → (values column descending-p)   (value< a b)
;; forms
(form children &key link id target swap attrs)
(text-input name &key label value placeholder required error id attrs)   ; also number-input
(date-input …) (checkbox name &key label checked value error) (select-input name options &key …)
(textarea name &key label value rows error) (submit-button label &key name value)
(coerce-param value type &key field default required min max choices)
(coerce-form params specs) → (values plist errors)   (find-field-error errors field)
(error-fragment condition)
;; htmx + urls
*canvas-resolver* canvas-resolver (resolve-canvas-url r symbol params) (resolve-asset-url r name)
path-resolver (make-path-resolver &key prefix asset-prefix)  freeze-resolver (make-freeze-resolver)
(canvas-link fn &rest params) canvas-link-function canvas-link-params
(canvas-url fn &rest params) (link-url link &rest params)
(hx-get link &key target swap trigger select include vals push-url confirm indicator)  ; hx-post
(hx-swap-value :outer-html) → "outerHTML"
(htmx-response-headers &key …) → (("HX-Retarget" . "#e") …)
;; sse
(sse-connect link) (sse-swap event &key swap target) (sse-close event)
(fragment-event event tree &key id) → stack-sse:sse-event
;; page, csp, freeze
(page body &key title lang stylesheet htmx) → html-document   +htmx-config+
(csp-violations tree) → list of (:kind k :element name :attribute a)
(neutralize tree) (freeze fn &key args title) → string
;; assets
+htmx-version+ +htmx-sse-version+ (asset-names) (asset-bytes name) (asset-content-type name)
(asset-sha256 name) (asset-info name) (asset-license name)
*canvas-theme* (theme-stylesheet theme) → octets   (canvas-stylesheet) → string
;; charts
(make-chart kind &key series x-axis y-axis title description legend width height bins)
(make-series name points &key color labels) (make-axis &key label scale min max ticks format)
(validate-chart c) chart-backend *chart-backend* (render-chart backend chart &key) (chart-node c &key backend)
*chart-palette* +chart-kinds+ +axis-scales+
;; conditions
canvas-error canvas-no-resolver canvas-csp-error canvas-coercion-error canvas-asset-not-found
invalid-chart chart-backend-missing     ; restarts use-default strip-violations use-placeholder
```

---

## The split (each its own team-solve run)

| Run | Repo · version | Delivers | Needs |
|-----|----------------|----------|-------|
| **H4h-0** | canvas-protocol **0.1.0** | components, htmx helpers, resolver GFs + path/freeze resolvers, response headers, SSE helpers, forms + coercion, tables, page, CSP scan, freeze, vendored assets, placeholder theme, chart model + `render-chart` GF | — |
| **H4h-0b** | lass import in cl-stack-systems; **new** css-protocol + css-backend-lass; engels minor | LASS imported (third party, unmodified); `css-protocol` (stylesheet values, units, colour functions) with `css-backend-lass` absorbing classie's unit arithmetic, colour functions and `:include`; engels (a LASS port of the Marx classless framework, built with classie) modernised with `.asd` `:cl-repo` metadata and canned CI; canvas-protocol minor: an `:engels` `theme-stylesheet` method, made the default | H4h-0 published |
| **H4h-1** | **new** canvas-backend-svg **0.1.0** | pure-Lisp SVG `render-chart` for all four kinds | H4h-0 published |
| **H4h-1b** | **new** rpc-backend-htmx **0.1.0** | htmx as an rpc-protocol transport + codec, Clack server, test client; `rpc-backend-htmx/canvas` resolver | rpc-protocol 0.2.0 (core); H4h-0 published (only the `/canvas` system) |
| **H4h-2** | cl-stack-code minor (with H8d-1) | the session's canvas server: rpc-backend-htmx mounted on the H8d-1 web server, handlers forwarding to the session image through repl-protocol, `canvas_open` / `canvas_freeze` / `canvas_snapshot` / `canvas_list` tools, CSP header, per-run token | H4h-0, H4h-1b, H8d-1 |

H4h-0b, H4h-1 and H4h-1b are independent of each other.

---

## H4h-0 — canvas-protocol 0.1.0 (contract)

Branch `agent/h4h0-contract-9e4a`, [draft PR #1](https://github.com/egao1980/canvas-protocol/pull/1). Stubs `%h4h0-pending` (an `error`, deliberately not a `canvas-error`). Per-function rules: the header comment of each `src/*.lisp`. **Given:** package, conditions, classes + readers + constructors (type checks only), GFs, constants, the asset files, `SHA256SUMS`, the placeholder `canvas.css`. **Stubbed:** every behaviour above.

Tests (`canvas-protocol/tests`, Rove; crypto-backend-ironclad only for checksums):

| File | Covers |
|------|--------|
| `render-test` | `el` (attribute order, T/NIL/integer values, bad tag/attribute names, refused tags and `on*`), `render` on nodes/strings/numbers/lists/NIL, `to-html` of fragments and documents, **hostile text and attributes escaped** (top-level text too) |
| `layout-test` | exact HTML of stack / row / grid / card / details / fieldset / tabs (with and without a link, active tab, missing id) / code-block / kv-list / badge / live-region; invalid options → `canvas-error`; `:id` / `:attrs` placement |
| `table-test` | plain table, caption, `data-align`, format, empty state, sorted + paged golden (header buttons, `aria-sort`, pager bounds), link params kept, invalid sort/page ignored; `sort-rows` (asc, desc, stable, unknown, vector, no mutation), `page-rows` (clamp, count, strings, vectors), `parse-sort`, `value<` |
| `form-test` | exact HTML of each input, select options, checkbox, textarea escaping, submit, form posting to a canvas (with/without id), error rendering; `coerce-param` per type (good values, bad values, required, min/max, choices, the reader never runs), restarts `use-value` / `use-default`, the report text, `coerce-form` collects errors in spec order, `find-field-error` |
| `htmx-test` | `canvas-link` validation, param normalization, `canvas-url` through the fake resolver, `canvas-no-resolver`, `path-resolver` URLs + percent-encoding + asset URLs, `freeze-resolver`, `hx-get`/`hx-post` plists, swap values + modifiers, refused triggers, `:vals` JSON escaping, NIL link → NIL, `htmx-response-headers` (order, trigger forms, CR/LF refused) |
| `sse-test` | `sse-connect` / `sse-swap` / `sse-close` plists, event-name validation, `fragment-event` and its encoded block |
| `page-test` | full-document golden (htmx-config meta, stylesheet link, both scripts), `:htmx nil`, `:stylesheet :inline`, page refuses a violating tree and `strip-violations` removes it |
| `csp-test` | `csp-violations` kinds on raw trees; **a gallery of every component through `page` has no violation and no `<script>` without `src`, no `on*`, no `style=`** |
| `freeze-test` | golden frozen document, determinism, self-contained (no `http:`/`https:`/`//` URL, no `<script>`, no `hx-`/`sse-` attribute) on the gallery, raw hostile nodes neutralised, `neutralize` keeps `#` and `data:` URLs, unknown function → `canvas-error` |
| `assets-test` | names, content types, versions, bytes length + leading bytes, recorded SHA-256 = computed SHA-256 for every asset, the pinned literal sums for htmx and the extension, licences are 0BSD, unknown asset → `canvas-asset-not-found`, the theme GF, stylesheet has light + dark and no `url(` / `@import` |
| `chart-test` | valid charts of each kind, each `invalid-chart` field, defaults, palette, `render-chart` on NIL → `chart-backend-missing`, `use-value` with a test backend, `render` of a chart → `use-placeholder` figure |

105 tests (render 8, layout 11, table 15, form 19, htmx 15, sse 3, page 5, csp 5, freeze 9, assets 8, chart 7). Locally (macOS, SBCL 2.4.11, stubs): 2 pass on given code (constants), 103 fail, every failure on `%h4h0-pending` or on validation not yet written; the system loads with no warnings of its own (only ironclad's `BLOCK-LENGTH` redefinition and ASDF's recursive-operate notice). html-protocol 0.1.0 quirks the implementation must not leak: [html-protocol#3](https://github.com/egao1980/html-protocol/issues/3) (document-level text unescaped, attributes printed in reverse order).

## H4h-0b — theme (locked; contract when the run starts)

| Decision | Choice |
|----------|--------|
| **LASS** | Imported into cl-stack-systems unmodified (third party); no fork |
| **css-protocol** | New `egao1980/css-protocol`: stylesheet values (rules, declarations, media queries), units with arithmetic, colour values and functions (mix, lighten/darken, contrast), `:include` of rule sets, serialize. `css-backend-lass` compiles LASS forms to it. classie's helpers move here; classie becomes a thin consumer or is retired |
| **engels** | `egao1980/engels` gets `.asd` `:cl-repo` metadata and the canned CI, builds its CSS through css-protocol, and ships the sheet as bytes |
| **canvas-protocol minor** | `theme-stylesheet` `(eql :engels)` method (depends on engels), `*canvas-theme*` default `:engels`; asset name `canvas.css` and the function API unchanged; the placeholder theme stays for zero-dependency use |

## H4h-1 — canvas-backend-svg 0.1.0 (locked; contract when the run starts)

| Decision | Choice |
|----------|--------|
| **Output** | `render-chart` → an html-protocol `<figure data-chart="<kind>">` holding an inline `<svg role="img" aria-labelledby>` with `<title>` + `<desc>` and a `<figcaption>` when titled. `viewBox`, integer-rounded coordinates (fixed decimals), stable element and attribute order: **byte-deterministic** |
| **Scales** | linear, log (base 10; decade ticks), time (universal-time; ticks on calendar units). Nice-number ticks (1-2-5 × 10ⁿ, Heckbert), axis min/max honoured, auto-padded otherwise |
| **Marks** | line (polyline per series), scatter (circles), bar (grouped, categorical x), histogram (`bins` equal-width; counts) |
| **Text** | axis labels, tick labels via `axis-format`, legend when more than one series (or `:legend t`); all text escaped through html-protocol; tooltips as `<title>` on each mark (series labels or `x, y`) |
| **Colour** | `*chart-palette*` in order; series `color` overrides; axes and text in `currentColor` so light/dark themes work without JS |
| **No JS** | no scripts, no event attributes, no `style` attributes (presentation attributes only); passes `csp-violations` |
| **Tests** | golden SVG per kind, tick tables (`nice-ticks`), log/time ticks, escaping of hostile titles/labels, determinism, `role`/`title`/`desc` present, CSP scan clean, freeze keeps the SVG |

## H4h-1b — rpc-backend-htmx 0.1.0 (locked; contract when the run starts)

htmx **is** RPC: a canvas function is a method, an htmx request is a call. So it is an rpc-protocol transport + codec, and the same handler table is reachable over JSON-RPC (`rpc-protocol-json`) for tests, ACP clients and agents checking fragments without a browser. `rpc-backend-http` cannot be reused: it is JSON-RPC over POST only (`rpc-backend-http/src/backend.lisp:129`).

| Decision | Choice |
|----------|--------|
| **Modes** | `hx-get` / `hx-post` → `:call-response`; `hx-swap="none"` + `HX-Trigger` events → `:notify`; the htmx SSE extension → `:call-stream`, one HTML fragment per event, named by its SSE event name |
| **Codec** | `htmx-codec` (`rpc-codec` subclass). Method from the path (`…/<package>::<name>`, percent-decoded); params from the query string or the urlencoded / multipart form, as keyword → string plist. Names are never interned (revised by [rpc-backend-htmx#2](https://github.com/egao1980/rpc-backend-htmx/issues/2), 0.3.0; interning let any client grow the KEYWORD package without bound): a name maps with `find-symbol` in KEYWORD, and must be a key of the handler's key set, which is its lambda list's `&key` names, or `:params` declared in the handler table (`&allow-other-keys`, or `:params t`, takes any key that maps; a name that maps to no keyword is dropped for it). Any other name is a 400. A canvas with no parameters takes none. At most `max-params` fields per request (default 1000; 413). Request metadata: `HX-Request`, `HX-Target`, `HX-Trigger`, `HX-Trigger-Name`, `HX-Current-URL`, `HX-Boosted`. Result: an html-protocol tree (anything `render` accepts once canvas is loaded), serialized with escaping, `text/html; charset=utf-8`. Response metadata (the canvas `htmx-response-headers` alist) → `HX-Trigger`, `HX-Retarget`, `HX-Reswap`, `HX-Redirect` … headers |
| **Errors** | A condition maps to a status code (`rpc-method-not-found` 404, `rpc-invalid-params` / `canvas-coercion-error` 422, others 500) plus `HX-Retarget` / `HX-Reswap` pointing at an error fragment (default target `#canvas-error`, `innerHTML`); the fragment is escaped text of the report, no backtrace |
| **Server** | A Clack app via `backend-rpc-serve` / `backend-rpc-serve-stream` on http-server-protocol. The handler table (method name → function) **is the allowlist**; anything else 404. GET for `:call-response` reads, POST for forms; no CORS; `HX-Request` absent on GET → the fragment wrapped in canvas `page` (with `rpc-backend-htmx/canvas`) |
| **SSE** | `text/event-stream` through sse-protocol in the shape the htmx SSE extension expects (`event: <name>` + `data:` lines of the fragment), keepalives from sse-protocol, close on stream end |
| **Resolver** | `rpc-backend-htmx/canvas` (a separate system, so the core does not wait for canvas-protocol): `htmx-resolver` implementing `resolve-canvas-url` (method → URL under the server's mount prefix) and `resolve-asset-url` (the server's asset route serving `asset-bytes`) |
| **Client (tests)** | `htmx-client`: call a method the way a browser would (GET/POST, `HX-*` request headers, form encoding), returning status, headers and the parsed fragment; read an SSE stream as `(event . fragment)` pairs |
| **Tests** | codec round trips (path → method, query / urlencoded / multipart → params, headers → metadata), each mode end to end through the Clack app with the test client, allowlist 404, error mapping (status + retarget + escaped fragment), response headers from data, SSE framing as htmx expects, page vs fragment by `HX-Request`, the same handlers over JSON-RPC give the same fragments, the canvas resolver round trip (URL it builds → codec → same method + params) |

### rpc-backend-htmx 0.5.0 — visitor sessions and request context (S1, implemented)

Slice S1 of [session.md](session.md#s1-rpc-backend-htmx-050-rpc-backend-htmx19-15) (the decisions are locked there); contract [rpc-backend-htmx#22](https://github.com/egao1980/rpc-backend-htmx/pull/22) (draft). For this brief:

| Decision | Choice |
|----------|--------|
| **Sessions** | `:sessions` on `make-htmx-transport`, `make-canvas-htmx-transport` and `htmx-app`: NIL (the default on both transports, so 0.4.0's responses are unchanged byte for byte), T or a session-protocol `session-manager`. The layer is S0b's `session-handler` on middleware-protocol. Canvases read the visitor's session with `htmx-session` / `htmx-session-value` like any handler |
| **Gate and CSP** | Unchanged rules, fixed order: CSP outermost, then the token gate, then sessions. The gate runs first: an unauthenticated request never begins a session or has its body read. The CSP header is on every response (the gate's 303 and 403, the cross-origin 403, streams, assets) and stays the last header, after a session's Set-Cookie. The gate's cookie (`canvas-token`, SameSite=Strict, the run's secret) and the session cookie (`sid`, SameSite=Lax, the visitor's id) coexist; one name for both is an error at `htmx-app`. The gate and the CSP stay closures until rpc-backend-htmx#20 |
| **Assets** | The asset route gets no session: no store read, no Set-Cookie |
| **CSRF** | With sessions on, an unsafe request from another origin is a 403 (`htmx-cross-origin`), checked with Sec-Fetch-Site and then Origin against Host (Go's `CrossOriginProtection`). htmx requests are same-origin (`selfRequestsOnly`), so canvases are unaffected |
| **Request context** | `htmx-message-client-address` (`:trusted-proxies`, the right-most untrusted `X-Forwarded-For` hop) and `:last-event-id` in the metadata for a reconnecting `:call-stream` |

## H4h-2 — harness server (later, cl-stack-code with H8d-1)

Routing `/canvas/<session>/<package>::<name>` via an rpc-backend-htmx server mounted on the H8d-1 web server; handlers forward to the session image over repl-protocol (the function must be in the session's canvas allowlist); per-run token: the one-time URL carries a single-use bootstrap token, exchanged once (then 403) for a separate session secret from the CSPRNG (secrets-protocol, ≥ 128 bits) in an HttpOnly, SameSite=Strict, Path=/ cookie, never Secure on a plain-http loopback bind, and a 303 to the URL without the token; URLs leak (history, Referer, logs), so the cookie never holds the URL's value (rpc-backend-htmx 0.3.0 `:token`, #4); origin check, loopback bind; headers `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'`. Tools: `canvas_open` (URL for a function + args), `canvas_freeze` (write the frozen file), `canvas_snapshot` (the fragment as text for the model), `canvas_list` (the allowlisted canvases). Same handlers over JSON-RPC for ACP clients.

---

## Not in H4h

- A JS widget runtime, client-side state, websockets (CLOG's route), a notebook format.
- `hx-on`, trigger filters, `js:` values, inline scripts — ever (CSP).
- Server-side `HX-Request` handling in canvas-protocol (it is the codec's).
- Image/file uploads in forms (multipart parsing is H4h-1b; an upload component is later).
- Vega-lite and other chart backends (the GF is open).
- htmx 4 (re-evaluate when it is npm `latest`; the SSE extension semantics change).

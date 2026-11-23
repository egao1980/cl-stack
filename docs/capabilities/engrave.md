# engrave-protocol (P2): rendering scores to SVG, PDF and timemaps (outline)

**Issues:** to be filed
**Status:** **outline**: decisions open until the Verovio spike reports (below). Planned repos: `engrave-protocol`, `engrave-backend-verovio`; later, optionally, `engrave-backend-lilypond`.
**Builds on:** [score-protocol](score.md), [xml-protocol](xml-protocol.md), [html-protocol](html-protocol.md), `browser-protocol` (`print-pdf`), [canvas](canvas.md) (embedding in live pages)

Turns a [score-protocol](score.md) score (or one of its views) into engraved pages, as **SVG whose element ids are the score's element ids**, plus a **timemap** (milliseconds → sounding element ids) for playback cursors, plus PDF. Rendering is done by an engine behind a protocol. The first engine is Verovio (C++, LGPL-3) over CFFI; a pure-Lisp engraver can come later behind the same generics.

---

## Locked so far

| Decision | Choice |
|----------|--------|
| **Shape** | CLOS protocol plus engine backends; the engine is chosen per call or by `*engrave-engine*` |
| **First engine** | `engrave-backend-verovio`: libverovio through CFFI, built as an `asdf-native` overlay (`load-foreign-library` at ASDF load). LGPL-3 native, so it ships as an overlay plus `NOTICE`, per [LICENSE-POLICY](../LICENSE-POLICY.md). Its bundled SMuFL fonts (Leipzig, Bravura; OFL) are drawn into the SVG. |
| **Output** | `svg-page` values: page number, an SVG document **as an xml-protocol tree** (never a raw string), and per-system `(element-id . bbox)` maps |
| **Embedding** | Pages and systems embed into html-protocol / canvas trees **as parsed XML**, so `neutralize` and the CSP scan still apply. There is no raw-markup escape hatch. |
| **PDF** | An HTML page holding the SVG pages, printed by `browser-protocol:print-pdf` (the [doc-extract-render-pdf](https://github.com/egao1980/doc-extract-render-pdf) path); page size and margins as options |
| **Timemap** | `render-timemap` → `(ms on-ids off-ids tempo)` entries over the **unfolded** score, mapped back to source ids |
| **Interactive re-render** | `render-system` re-renders one system after an edit, keeping page breaks stable |

---

## Protocol surface (sketch)

```lisp
(defclass engrave-engine () ())
(defgeneric engine-render-svg (engine score &key view page-size scale parts systems))
(defgeneric engine-render-timemap (engine score &key tempo-scale))
(defgeneric engine-render-system (engine score system-index &key))
(defun render-svg (score &rest options &key engine &allow-other-keys))   ; → list of svg-page
(defun render-timemap (score &key engine))
(defun render-pdf (score destination &key engine page-size margins))
(defun svg-page-node (page))   ; → html-protocol node (parsed via xml-protocol)
```

Conditions: `engrave-error` → `engine-unavailable`, `engine-render-error` (with engine log), `unsupported-view`.

---

## Spike (decides before slice 1)

A time-boxed spike: Verovio loads through CFFI on SBCL (macOS arm64, Linux amd64). It answers:

1. Do MusicXML `id` attributes survive Verovio's importer into SVG `id`s? If not, the backend writes **MEI internally** (Verovio's native input). MEI stays inside the backend, and no MEI repo is created.
2. Latency to re-render one system after a one-note edit (target: interactive, about 100 ms).
3. Verovio's WASM build client-side as a comparison, to keep the option of browser-side rendering open.
4. Embedding Verovio SVG through xml-protocol → html-protocol: size and neutralize cost.

---

## Later

| Item | Note |
|------|------|
| `engrave-backend-lilypond` | Print-quality PDF. LilyPond (GPL) runs **out of process** in a podman sandbox (compute-protocol); its output carries no license obligation. Writing LilyPond source: prior art in cl-lilypond (Apache-2.0). |
| Pure-Lisp engraver | Behind the same generics. Prior art: CMN (permissive; glyph and layout code), Gsharp / Clovetree design notes (LGPL; study only), cloveleaf (MIT; SMuFL metadata reader) |

## Open questions

- The condensed two-staff view: Verovio's own options, or score-protocol's `condensed-view` before rendering?
- Line-breaking stability rules for `render-system`.
- Font subsetting in SVG, for page weight.

## Non-goals

Editing UI; layout attributes in score-protocol; real-time rendering; non-SVG raster output (raster comes from the browser or image-protocol).

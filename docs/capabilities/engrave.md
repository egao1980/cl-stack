# engrave-protocol (P2): scores to SVG pages, timemaps and PDF

**Issues:** follow-ups in [Progress](#progress)
**Status:** EN0 **contract**: [`engrave-protocol`](https://github.com/egao1980/engrave-protocol) 0.1.0, [draft PR #1](https://github.com/egao1980/engrave-protocol/pull/1) (`%en0-pending` stubs; a reference implementation passes all 2229 assertions). EN1 to EN3: decisions below, contracts written when each run starts. The Verovio backend is **feasible** ([EN1 feasibility](#en1-feasibility-verovio-through-a-native-overlay)); its repo is not created yet.
**Repos:** `engrave-protocol` (nick `stack-engrave`) · planned `engrave-backend-verovio` (EN1) · optional `engrave-backend-lilypond` (EN3)
**Builds on:** [score-protocol](score.md) 0.2.0 (model, ids, `condensed-view`, `unfold`), [music-theory](music-theory.md) 0.5.0 (tempo arithmetic), [xml-protocol](xml-protocol.md) + `xml-backend-native`, FSet; [canvas](canvas.md) 0.2.2 (`svg-fragment`, tests only); [browser](browser.md) (`print-pdf`, EN2); `asdf-native` and [platform overlays](../overlays.md) (EN1); compute-protocol (EN3)

Turns a [score-protocol](score.md) score, or one of its views, into engraved pages. The output is:

- **SVG pages as xml-protocol trees**, whose element ids lead back to the score's ids through an **id map**;
- a **timemap** (milliseconds → sounding event ids) for playback cursors;
- **PDF**, through a printer.

An engine behind the protocol does the rendering. The first native engine is Verovio (C++, LGPL-3) over CFFI. `null-engine`, the reference engine inside the protocol, draws deterministic placeholder SVG, so the protocol and its consumers can be tested without a native library. A pure-Lisp engraver can come later behind the same generics.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| Verovio (C++, LGPL-3) | The first engine. MEI input whose `xml:id`s become SVG `id`s; its timemap shape (on / off ids per timestamp); the C toolkit API (`tools/c_wrapper.h`) | Its JS / WASM app; its editor API (cursor-based, a second source of truth); its own MusicXML importer as the id carrier (below) |
| MEI 5 | The engine input of EN1: one `<measure>` across all staves, `<staff>` and `<layer>` cells that carry slice ids, `<sb/>` system breaks | An MEI repo or MEI in score-protocol: MEI stays inside the backend |
| SMuFL fonts (Leipzig, Bravura; OFL) | Glyphs drawn by Verovio; the web font the backend's stylesheet serves | Font subsetting (later) |
| LilyPond (GPL-3) | Print-quality PDF, **out of process** in a container (EN3); `output-attributes` for ids in its SVG | Linking or bundling it |
| cl-lilypond (Apache-2.0) | Prior art for writing LilyPond source | — |
| OpenSheetMusicDisplay, abcjs, VexFlow (JS) | Their published behaviour (cursor follows the timemap; SVG per page) | Client-side rendering: a second score model in JS and `wasm-unsafe-eval` / script in the page |
| CMN (permissive), Gsharp / Clovetree (LGPL; study only), cloveleaf (MIT; SMuFL metadata) | Prior art for a later pure-Lisp engraver | Code (license policy) |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol plus engine backends. An engine is an instance of an `engrave-engine` subclass, and its options (font, spacing) are **slots of the instance**, never render keywords. `render-svg`, `render-timemap` and `render-pdf` take the engine first; NIL stands for `*engrave-engine*` | The protocol's keywords mean the same for every engine |
| **One engine hook** | An engine implements `engine-render-pages engine view layout &key page`. The protocol's methods for `engrave-engine` do the rest: resolving the engine, checking options, computing the view, mapping ids back, selecting pages, the timemap and PDF | A backend writes only what differs between engines |
| **Availability** | `ensure-engine`: NIL → `*engrave-engine*`. No engine, or one whose `engine-available-p` is false (its native library did not load), signals `engine-unavailable` inside `use-value`. The restart's value is checked again | A missing native library is a recoverable condition, not a load failure |
| **Views** | `engrave-view score &key view parts`. `:choral` is the score as notated: every part on its own staves, which for an open choral score means one staff per part. `:condensed` is score-protocol's `condensed-view` (up to four voices on two staves). `:parts` first restricts the score to some parts and keeps the spanners inside them. The engine gets the view as a score | This settles the outline's open question: the view comes from score-protocol before rendering, so every engine draws it the same way |
| **Pages** | `svg-page` values: number, an **xml-protocol document** (never a string), and `systems` (measure ids per system). The root is `svg` in the SVG namespace with `viewBox`, and `width` / `height` in millimetres. **Every element** is in the SVG namespace, because canvas-protocol's `svg-fragment` refuses others | Pages embed as they are and print at their real size |
| **Id map** | An FSet map from the **score's** element ids to `((page . svg-id) …)`, the drawings of each element over the whole rendering (also with `:page`). `()` means not drawn. Elements a view made (the condensed part and staves) are not keys | Click-to-select, page lookup for an element, highlighting across systems |
| **SVG ids** | ASCII XML NCNames, unique over all pages of a rendering. An element drawn once as an object of its own carries **its own id**. Slice ids (`m-3.v-8`) name staff and layer cells. Ids an engine makes up must be neither element ids nor slice ids: the null engine writes `system.<n>`, and Verovio's generated ids have no hyphen | Ids pass through verbatim: no translation table in the common case |
| **Layout** | `make-layout`: page size (`:a4` … or millimetres), margins, scale (1–1000 %), system breaks (`:auto` or measure ids). Lengths are rationals in whole tenths of a millimetre, the unit engines draw in | Exact. A rendering's `systems` fed back as breaks reproduce its lines (the break plan round trip) |
| **Timemap** | It comes **from the model**, not from an engine. `score-timemap`: events (notes, chords, rests; grace notes excluded) by `absolute-offset`, exact milliseconds over the tempo marks (the default is ♩ = 120, as in MIDI; text-only marks change nothing). `render-timemap` unfolds by default with score-protocol's `unfold` and maps copies back to source ids | Every engine reports the same timemap, consistent with `unfold` and the MIDI export. An engine that realises ornaments may specialize it |
| **PDF** | `render-pdf` → octets, through a **printer** (`print-pages printer pages layout`, `*pdf-printer*`). No printer → `printer-unavailable` (`use-value`) **before** rendering. Output that does not start with `%PDF-` is an `engine-render-error`. An engine with its own PDF output (LilyPond) specializes `render-pdf` | PDF is a separate concern from engraving. The browser printer is EN2 |
| **Embedding** | Pages embed into html-protocol / canvas trees through canvas-protocol's `svg-fragment` (the allowlist), so `neutralize` and the CSP scan apply. The protocol has no `svg-page-node`. There is no raw-markup escape hatch | The protocol depends on neither html nor canvas |
| **Conformance** | `check-engraving` (10 issue kinds: page numbers, SVG root, namespaces, id syntax, duplicates, missing / unknown / undrawn elements, dangling refs, system coverage) and `check-timemap` (order, unknown ids, counts against `unfold`, off before on) | Engines are tested by these checks, not by golden SVG. A backend's suite runs them on its own output |
| **Reference engine** | `null-engine` ships in the protocol. It draws one `<g id class>` per element, splits pages by documented arithmetic, and refuses classes listed in `:unsupported` | Consumers (editors, canvases, demos) test without a native library |
| **Conditions** | Protocol-owned tree, below. `unsupported-notation` offers **score-protocol's `skip-element`** restart, so one handler serves readers and engines | No backend error dialect |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| `engrave-protocol` | Engines, conditions, layout, views, `svg-page`, the render generics and their default methods, the timemap, the conformance checks, `null-engine` |
| `engrave-backend-verovio` (EN1) | libverovio through CFFI as an `asdf-native` overlay, the MEI writer, the stylesheet and font assets |
| `engrave-backend-lilypond` (EN3, optional) | LilyPond source writer; `lilypond` in a container; `render-pdf` and `render-svg` |
| EN2 printer | A browser printer over `browser-protocol` (`engrave-protocol/pdf` or its own repo, decided in EN2) |

---

## Protocol surface (EN0)

```lisp
(defclass engrave-engine () ())              (defvar *engrave-engine* nil)
(defun ensure-engine (engine))               ; NIL → *engrave-engine*; USE-VALUE
(defgeneric engine-name (engine))            (defgeneric engine-available-p (engine))
(defgeneric engine-render-pages (engine view layout &key page)) ; → pages, id-map (view ids)

(defun make-layout (&key (page-size :a4) (margins 10) (scale 100) (system-breaks :auto)))
(defun ensure-layout (designator))           ; NIL | layout | plist
(defun engrave-view (score &key (view :choral) parts)) ; → view, view→source id map

(defstruct svg-page number document systems)
(defun svg-page-root (page))  (defun svg-page-ids (page))  (defun find-svg-element (page id))
(defun make-svg-element (name &optional attrs &rest children)) ; xml element in the SVG ns
(defun valid-svg-id-p (object))  (defun element-kind (element))

(defgeneric render-svg (engine score &key view page layout parts)) ; → pages, id-map
(defgeneric render-timemap (engine score &key unfold))  ; → timemap-entry list
(defgeneric render-pdf (engine score &key view layout parts printer)) ; → octets
(defgeneric print-pages (printer pages layout))      (defvar *pdf-printer* nil)
(defun score-timemap (score))
(defstruct timemap-entry onset on off tempo)

(defun check-engraving (score pages id-map &key view parts)) ; → engraving-issue list
(defun check-timemap (score timemap &key unfold))
(defclass null-engine (engrave-engine) ())   (defun make-null-engine (&key unsupported))
```

### Conditions

```text
engrave-error (error)                  ; slots: engine, message
├── engine-unavailable                 ; slot: reason — restart use-value (an engine)
│   └── printer-unavailable            ; no printer — restart use-value (a printer)
├── unsupported-notation               ; slots: element-id, kind — restart skip-element
├── engine-render-error                ; slot: log (the engine's own message)
└── invalid-render-option              ; slots: option, value
```

---

## Slices

### EN0: protocol and the reference engine (engrave-protocol 0.1.0)

**Given:** package and exports, the conditions, the engine class and generics, the `svg-page`, `layout`, `timemap-entry` and `engraving-issue` structs, `make-svg-element`, `valid-svg-id-p`, `element-kind`.
**Stubbed:** `ensure-engine`, `make-layout` / `ensure-layout`, `engrave-view`, the `render-svg` / `render-timemap` / `render-pdf` methods, `score-timemap`, `svg-page-ids`, `find-svg-element`, `check-engraving`, `check-timemap`, and the null engine.
**Fixtures:** eleven score-protocol fixtures (MIT), and generated multi-page scores.
**Tests:**
- Every element id is in the id map, and SVG ids are valid and unique across pages.
- The null engine draws one group per element, each nested where it belongs. Exact page splitting for nine layouts; the break plan round trip.
- `skip-element`, and the holders of a skipped element.
- The timemap by hand (three tempos, one mid-bar) and against `unfold`.
- Each conformance issue kind.
- The `svg-fragment` path with a clean CSP scan, `neutralize` unchanged, and ids kept.
- PDF delegation to a fake printer and its conditions.

### EN1: Verovio backend (engrave-backend-verovio 0.1.0)

- **Native:** libverovio (pinned tag) through CFFI, as an `asdf-native` overlay per platform, plus `NOTICE`, the LGPL texts, the patch and the build script ([feasibility](#en1-feasibility-verovio-through-a-native-overlay)). `engine-available-p` is false when the library did not load.
- **Input: MEI**, written by the backend from the model. Every element gets its id, and staff and layer cells get slice ids. A spike found that Verovio's MusicXML importer drops the ids of harmonies, lyrics and directions, keeps only the first part's measure id, and has no staff or layer cell, while MEI input keeps all of them and loads faster. The MEI writer stays inside the backend.
- **SVG and id map:**
  - Verovio's SVG text is parsed with `stack-xml:decode` (xml-protocol#3 makes that linear first), and the root's `width` / `height` are set to the page size in millimetres.
  - The id map is the identity for elements Verovio draws under their own ids. Parts, staves and voices map to their slice ids or label groups. Anything Verovio cannot draw signals `unsupported-notation`.
  - Generated ids are seeded per page (`resetXmlIdSeed`), so output is byte-stable without duplicate ids across pages.
- **Engine options fixed by the backend:**
  - `svgViewBox`, `svgFormatRaw`;
  - `smuflTextFont: none`, since the default embeds a 57 KB base64 font in a `<style>` that embedding drops;
  - header and footer `none` (no engine logo);
  - never `svgHtml5`, which writes `data-id` instead of `id`.
- **Stylesheet:** Verovio's drawing relies on its `<style>` rules (for example `path { stroke: currentColor }`). The backend publishes them, re-scoped, as a small stylesheet asset with the same-origin Leipzig woff2 (OFL).
- **Timemap:** the protocol's. Verovio's own timemap (note ids, not chords; rests only on request) serves as a cross-check in tests.
- **Runtime:**
  - One toolkit per thread.
  - Float traps masked around every toolkit call (as image-backend-stb does).
  - Returned strings copied at once (they belong to the toolkit until its next call).
  - `enableLog(false)`; the log is read into `engine-render-error`.
- **Tests:**
  - `check-engraving` and `check-timemap` over the score-parity corpus in both views.
  - The `svg-fragment` path.
  - The break plan round trip through `<sb/>`.
  - Unsupported notation.
  - A latency budget: a spike measured ≈ 15 ms to load 32 bars × 4 staves of MEI and ≈ 5 ms to render a page.

### EN2: PDF through the browser (printer)

- A printer whose `print-pages` builds one HTML document: each page through `svg-fragment` and `neutralize`, the backend's stylesheet and font, and `@page { size; margin }` from the layout. It prints the document with `browser-protocol:print-pdf`.
- This needs [browser-protocol#5](https://github.com/egao1980/browser-protocol/issues/5): `print-pdf` sends no options today, so Chrome prints on US Letter and ignores `@page`.
- A spike found the route works: headless Chrome printed two A4 pages of SVG as vector PDF with the fonts embedded in ≈ 80 ms, and the text stayed selectable.
- Tests: page count and size from the PDF, the fonts embedded, and `printer-unavailable` when no browser can be launched.

### EN3: LilyPond print backend (optional; engrave-backend-lilypond)

- LilyPond (GPL) runs **out of process** in a podman container (compute-protocol); its output carries no license obligation. The backend writes LilyPond source from the model (prior art: cl-lilypond, Apache-2.0).
- `render-pdf` is specialized to LilyPond's own PDF.
- `render-svg` uses its SVG backend, with each object's `output-attributes` set to the element id, and maps them back through the id map.
- The timemap is the protocol's.

---

## EN1 feasibility: Verovio through a native overlay

**Verdict: feasible, with no blocker.** What follows was checked for this brief on 2026-11-24, with Verovio 6.4.1 (tag `version-6.4.1`), zig 0.17.1 and CMake on one macOS arm64 host with 10 cores. The library was built with `-DBUILD_AS_LIBRARY=ON -DNO_HUMDRUM_SUPPORT=ON -DCMAKE_BUILD_TYPE=Release`, and zig wrapper scripts served as the C/C++ compilers. Humdrum is off because it doubles the build and the backend never reads Humdrum.

| Question | Finding |
|---|---|
| **Can `zig c++` build it for the four targets?** | **Yes.** `linux-amd64` and `linux-arm64` (glibc 2.31 targets), `darwin-arm64` and `windows-amd64` (MinGW) each build in ≈ 1.5 min, all four cross-compiled from the one host. Two small fixes are needed. **Windows:** `src/vrv.cpp` includes an MSVC-only `win_time.h`, which redefines `timeval` against MinGW's; a one-line patch takes `<sys/time.h>` unless `_MSC_VER` (an upstream candidate). **macOS:** zig 0.17.1's bundled headers lose `DBL_DIG` / `NAN` in one include order; `-include __float_float.h` works around it (a toolchain issue, not Verovio's). Linux needed no change. The overlay's build script carries both, following image-backend-stb's `natives.yml` (Linux and Windows cross-built on Ubuntu, darwin on macOS). |
| **Can the C wrapper be loaded with CFFI?** | **Yes.** `tools/c_wrapper.cpp` is built into the shared library and exports 62 plain C functions (`vrvToolkit_*`, `enableLog`): opaque `void*` toolkit, `const char*` in and out, `bool` / `int`. Each zig build was loaded with `dlopen` and called through a C FFI (Python `ctypes` standing in for CFFI): constructor with a resource path, `setOptions`, `loadData` of an MEI file, `renderToSVG`, `renderToTimemap`. This ran on darwin-arm64 natively and on linux-arm64 and linux-amd64 in containers (Debian, glibc 2.36). Every MEI id reached the SVG unchanged, slice ids with a dot (`m-1.v-3`) included. The Windows DLL was not run here (no Windows host); its export table holds the 62 functions. A spike also drove Verovio 6.4.1 from SBCL through CFFI on macOS. |
| **How are the resource files located?** | `vrvToolkit_constructorResourcePath(dir)` takes a directory, read with plain file I/O. Verovio loads **Bravura** first (its glyph table names every code point), then **Leipzig** (the default font), then the **Times metrics** (`text/Times*.xml`, mandatory). Gootville, Leland and Petaluma load only on request. The default path is compiled in as `<install prefix>/share/verovio` and is `thread_local`, so the backend always passes the path. The backend finds the directory **relative to the loaded library**: `asdf-native:library-loaded-path`, then `verovio-data/` beside it. That works the same for the overlay (`native/`), a checkout (`lib/<os>-<arch>/`) and an `$VEROVIO_NATIVE` override with the same layout. The required set is **1.6 MB** in about 1,550 small XML files (0.56 MB gzip); the whole `data/` directory is 3.3 MB. All fonts are OFL. |
| **What size are the binaries?** | Stripped, exporting only the C API: **8.0 MB** (linux-amd64), **7.9 MB** (linux-arm64), **8.9 MB** (darwin-arm64), **6.3 MB** (windows-amd64), and **2.3–2.7 MB** gzip. Each library links libc++ statically, so it depends only on glibc (symbol versions ≤ 2.29), libSystem, or KERNEL32 and the UCRT. Unstripped, with every C++ symbol exported, the Linux library is 110 MB. So the build script strips the library and exports only the C API, through a version script on Linux and a `.def` file on Windows. On macOS, zig's linker ignored `-exported_symbols_list`, so the build uses `-fvisibility=hidden` with the wrapper at default visibility. Exporting only the C API also keeps two statically linked libc++ copies in one image from clashing (with llama-cpp, for example). At 7–9 MB per platform, the libraries are not committed (llama-cpp's way, not image-backend-stb's): the natives workflow builds them, and the overlay publish takes them from its artifacts. |
| **Is the system's libverovio acceptable as a fallback under LICENSE-POLICY?** | **Under the policy, yes:** loading a library the user installed is dynamic linking, and the stack distributes nothing LGPL on that path. **In practice it is unavailable:** Homebrew's `verovio` formula is the command-line tool only (no library, no headers), and Debian trixie has no Verovio package. So the backend keeps no `:system` fallback. `$VEROVIO_NATIVE` (asdf-native's override) serves a self-built library, and the backend refuses a library whose `vrvToolkit_getVersion` is not the pinned major.minor. |

**License route (the policy's "overlay + NOTICE"):**
- libverovio stays a separate shared library, loaded by absolute path at ASDF load. Nothing LGPL is linked statically into anything.
- The overlay carries `NOTICE`, `COPYING` and `COPYING.LESSER`, the pinned source tag, the patch and the build script, so the corresponding source of the distributed binary is published.
- A user can replace the library through `$VEROVIO_NATIVE` (LGPL-3 §4(d)(1), a suitable shared-library mechanism).
- The libc++ linked into the library is Apache-2.0 WITH LLVM-exception. The fonts and metric files are OFL. The backend's Lisp code stays MIT.

---

## Progress

### In progress

| Slice | Package | Notes |
|-------|---------|-------|
| EN0 | engrave-protocol 0.1.0 | contract [engrave-protocol#1](https://github.com/egao1980/engrave-protocol/pull/1) (draft). On the stubs, 134 assertions pass (the given parts) and every other test fails. A reference implementation passes all 2229 assertions, and seven mutations of it are each caught |

### Follow-ups

- [browser-protocol#5](https://github.com/egao1980/browser-protocol/issues/5): `print-pdf` options (paper size, margins, `preferCSSPageSize`). Blocks EN2.
- [xml-protocol#3](https://github.com/egao1980/xml-protocol/issues/3): the native decoder is quadratic on long text and attribute values. Needed before EN1 parses engine SVG.
- [canvas-protocol#8](https://github.com/egao1980/canvas-protocol/issues/8): `csp-violations` does not report `<style>` elements. `svg-fragment` already drops them, so this concerns other trees.

---

## Later

| Item | Note |
|------|------|
| `render-system` | Re-render one system after an edit, with the break plan (each system's measure ids from the last full layout) kept stable. A spike found that a system rendered alone lays out exactly as in the full score with header and footer off, `minLastJustification: 0`, the meter hidden and no staff labels, and that it re-renders in ≈ 5 ms of engine time. A fragment cannot show a tie, slur or lyric extender that crosses into it from the system before |
| Client-side preview | Verovio's WASM build renders the same MEI with the same ids. A spike found it no faster than native (1.0–1.7×), at 2.3 MB gzip, and it needs `wasm-unsafe-eval` in the CSP, so it stays an offline option only |
| Pure-Lisp engraver | Behind the same generics, tested by the same conformance checks |
| Font subsetting | For page weight in SVG and PDF |

## Open questions

- Whether the EN2 printer lives in `engrave-protocol/pdf` or in a repo of its own. It depends on browser-protocol and canvas-protocol, which the protocol does not.
- How LilyPond's `output-attributes` ids cover lyrics and chord symbols (EN3).

## Non-goals

Editing UI; layout attributes in score-protocol; real-time rendering; non-SVG raster output (raster comes from the browser or image-protocol).

# Native desktop UI survey: lessons for a `ui-protocol`

**Target:** no brief yet. This doc is the input for one: a cross-platform desktop UI capability next to [canvas](../capabilities/canvas.md) (htmx views of a live image) and [tui](../capabilities/tui.md) (Elm-style terminal programs).
**Question (user):** "We have our canvas support; shall we explore native cross-platform UI (McCLIM, bindings to existing libs, etc.)?", weighed against LispWorks CAPI (one API, native widgets on Windows, macOS and Linux, plus delivery). Follow-ups: is Flutter alive and can we integrate it; Google's low-level UI stack (Skia, Impeller, Dawn); an rfw backend for canvas.
**Date:** 2026-11-27
**Method:**
- vendor docs, release pages and the GitHub/Codeberg APIs (push dates, releases, asset sizes);
- the python-to-cl [tkinter page](https://github.com/egao1980/python-to-cl/blob/master/tkinter.org) survey table as the starting list;
- **five throwaway spikes on this Mac** (macOS 26.6, arm64, SBCL 2.6.9, `sb-alien` only, no CFFI, nothing installed system-wide except `brew install sdl3`); see §5.

Anything marked **(unverified)** comes from secondary sources or memory and was not checked against primary docs or code. Payload sizes marked **est.** are estimates; sizes marked **measured** were measured here.

---

## Executive summary

1. **Build a `ui-protocol`, not a binding.** It should be an Elm-style program protocol: the init/update/view and command shapes of `tui-protocol`. Its view returns a *declarative widget tree*, which a backend reconciles onto retained native widgets. Model it on BeeWare Toga, which has an interface layer, a private implementation layer per OS and a headless dummy backend. That is the CAPI promise, delivered as a protocol with backends, the way the rest of cl-stack works.
2. **First backend: `ui-backend-webview` over canvas-protocol.**
   - It uses webview/webview: WebView2 on Windows, WKWebView on macOS, WebKitGTK on Linux.
   - It reuses the canvas components, htmx, the CSP rules and `freeze` as they are, and gets accessibility, IME and high-DPI from the browser engine.
   - The macOS native payload is **108 KB (measured)**; the engine is the OS's own.
   - The spike works from SBCL: a window opens, JS → Lisp → JS round-trips, and a non-UI thread posts work through `webview_dispatch`.
   - It is not native widgets. It is the cheapest route to a desktop window that is useful in weeks.
3. **Second backend, the CAPI-like one: `ui-backend-iup`.**
   - It uses the **IUP C library from gen2brain/iup-go** (MIT, v0.40.0 / IUP 4.0.0, 2026-11-19).
   - Real native controls on every overlay target:
     - Win32 or WinUI 3 on Windows
     - Cocoa on macOS
     - GTK3, GTK4 or Qt on Linux
   - Prebuilt libraries are about **1.6 MB per platform (measured, darwin-arm64)** and exist for all four of our overlay targets.
   - The spike drove Cocoa widgets from SBCL, including a cross-thread `IupPostMessage`.
   - `lispnik/iup` (MIT, v0.7.0, 2026-08) is an existing CL binding worth importing or forking.
   - IUP is the only MIT-licensed, maintained, native-widget C API we found that covers all three desktops. It is the closest thing to CAPI that we can own.
4. **Avoid making these the cross-platform default:**
   - **GTK4:** LGPL, about 40–60 MB on Windows (est.), not native on macOS, and the maintained CL bindings are LGPL-3 (cl-gtk4) or Linux-centred.
   - **Qt 6:** no maintained CL binding; LGPL-3 with relinking duties; 25–80 MB (est.). `libqt6c`, an MIT C ABI, makes a binding possible later.
   - **McCLIM:** X11 only in practice; its SDL2 backend is alpha; LGPL source.
   - **libui-ng:** stalled since 2025-03 and "mid-alpha".
   - **Dear ImGui / Nuklear:** no accessibility and weak IME, so tools only.
   - **Lesson for policy:** the LICENSE-POLICY allowlist rules out LGPL/LLGPL *Lisp* libraries as runtime dependencies. That excludes McCLIM, nodgui, cl-gtk4 and LTK, whatever their merits.
5. **Flutter is alive, but integrate it only through server-driven UI, as an experiment.**
   - Status: 3.50 shipped 2026-11-11. Canonical stewards desktop since I/O 2026. Multi-window is still experimental.
   - Writing our own embedder is officially unsupported, and every non-Google desktop embedder (go-flutter, flutter-rs) has died.
   - The credible route is a **prebuilt generic Flutter shell plus Remote Flutter Widgets (`package:rfw` 2.0.0)**, fed by Lisp. The spike's Lisp encoder emits rfw's binary format **byte-identical** to rfw's own Dart encoder (§5.5).
   - But rfw has no text field, checkbox, table or painter, so the shell needs its own widget library in Dart.
   - Other costs: Linux accessibility is weak, and building needs a Flutter SDK plus Xcode in CI.
6. **Google's low-level stack: Impeller's standalone C API is the find.**
   - `impeller.h` is BSD-3, with per-engine-commit prebuilts for darwin, linux and windows on x64/arm64.
   - The spike: SBCL opened an SDL3 window and drew a rectangle and a shaped paragraph through Impeller/Metal. The paragraph mixed Latin, Cyrillic, CJK and right-to-left Arabic, with system-font fallback. Verified by GPU readback.
   - It has **no API stability guarantee**, and the version check rejects any other header version.
   - Good for a **GPU `canvas` drawing backend** (charts, custom painters, editors), not for a widget toolkit.
   - Dawn/WebGPU and Skia (via the SkiaSharp C shim) are viable, but each costs more: Dawn has no 2D or text layer, and SkiaSharp's shim lacks paragraph layout.
7. **Three cross-cutting requirements the spikes surfaced** (they belong in the brief):
   - **On macOS the UI must own SBCL's initial thread.** Starting AppKit elsewhere aborts the process with `NSInternalInconsistencyException`.
   - **SBCL must mask float traps around toolkit calls.** WebKit raised `FLOATING-POINT-INVALID-OPERATION` on the first window.
   - **Apple arm64 varargs** go on the stack, so a binding must avoid or specially wrap variadic C functions (IUP's `IupVbox(…, NULL)`; use `IupVboxv`).

---

## 1. Prior art (intersection, not a clone)

| System | Model | Took | Left |
|---|---|---|---|
| **LispWorks CAPI** (8.1, 2025-03) | One CLOS API; native Win32, Cocoa and GTK3 (+ iOS/Android); interfaces defined by `define-interface`; `deliver` produces a stripped app ([news](https://lispworks.com/news/news42.html)) | One portable API over native widgets; layouts as objects; delivery as part of the product | A closed implementation; GTK on Linux only; the per-seat price (Hobbyist about $750, Professional about $1,800 **(unverified labels)**, [prices](https://www.lispworks.com/buy/prices-1a.html)) |
| **Allegro Common Graphics** (ACL 11) | Native Win32 widgets on Windows; on Linux and macOS, **CG/JS** draws the same API in a browser ([docs](https://franz.com/support/documentation/cg-cgjs.html)) | Validates "native on one OS, web engine elsewhere" as a commercial strategy | Asymmetric fidelity across OSes |
| **Tkinter** | Tk through Tcl; ttk themed widgets | Batteries included, tiny API surface, ttk's native themes | Stringly-typed options; Tcl interpreter in the loop |
| **PyQt6 / PySide6** | Qt Widgets + QML | Model/view, layouts, Designer files | GPLv3 (PyQt) or LGPLv3 (PySide); 30–80 MB runtime (est.) |
| **wxPython** (Phoenix 4.2) | wxWidgets: native widgets per OS | Proof that a native-widget wrapper can be one API | A big C++ library needs a huge generated binding; wxWindows licence (LGPL + exception) |
| **BeeWare Toga** (0.5.7, 2026-10) | `toga-core` interface + per-OS `_impl` (cocoa, winforms, gtk, qt, textual, web) from a platform factory; **toga-dummy** must implement the whole core API with no graphics; a shared testbed with per-backend *probes* ([architecture](https://toga.beeware.org/en/latest/topics/architecture/), [testbed](https://toga.beeware.org/en/latest/topics/internal/testbed/)) | **The layering to copy**: protocol package = interface; backend system = impl; a CLOS generic on a backend object = factory; dummy backend = headless Rove; probes = per-backend test systems | Python entry-point discovery (we select by ASDF/pins) |
| **Flet** (1.1.4, 2026-11; 1.0 in 2026-09) | Python dataclass controls mirror a Dart/Flutter control tree; a **diff** of the tree goes over **MessagePack** to a Flutter renderer, by socket or in-process "dart-bridge" FFI ([1.0](https://flet.dev/blog/introducing-flet-1-0-alpha), [0.86](https://flet.dev/blog/flet-v-0-86-release-announcement)) | **The image owns a declarative tree and ships diffs to a prebuilt renderer**; binary codec; bulk-data side channel | One renderer (Flutter) baked in |
| **Tauri 2** (2.12.7) / **pywebview** (6.2) / **Wails** (v3.1, 2026-11) | System webview (wry/tao, WebView2/WKWebView/WebKitGTK); Tauri uses custom schemes (`tauri://`) and per-window **capability ACLs**; pywebview uses a localhost server | Apps of 3–10 MB (est.) because the engine belongs to the OS; permission ACLs for what the page may call | Client JS frameworks as the app; Tauri's Rust build |
| **SwiftUI** | Value-type view descriptions diffed by the framework; `@State`/`@Observable`; accessibility modifiers on the tree | View = function of state; **a11y data lives on the declarative tree** | Apple-only |
| **Compose Multiplatform** (desktop) | Composables, state hoisting, recomposition; Skia via Skiko; a **semantics tree** used by a11y *and* tests (`composeTestRule`) | One semantics tree for screen readers and test queries | JVM; self-drawn look |
| **CLOG** (2.3) | Lisp image drives a browser page over a websocket; the server pushes JS that the client evals; CLOGFrame is a webview.h exe ([repo](https://github.com/rabbibotton/clog)) | The image owns the UI; desktop through a webview | Eval-based bridge, which needs `unsafe-eval` and so breaks canvas-protocol's strict CSP |

---

## 2. Candidate matrix

Columns: **Native** = real OS widgets. **Win / mac / Linux** = state on that OS. **CL binding** = what exists today. **Licence fit** is against [LICENSE-POLICY](../LICENSE-POLICY.md): MIT/BSD/Apache runtime deps; LGPL only as a separate native lib + NOTICE. **Payload** is per platform.

| # | Candidate | Native | Win / mac / Linux | CL binding (state) | Licence fit | Payload | Maintenance | a11y / IME / hi-DPI | Main-thread & loop | Headless CI |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **McCLIM 1.0** "Koliada" (2026-05-05) | No (own gadgets) | X11 via CLX everywhere; SDL2 backend **alpha** (software, no double buffer); no Cocoa/Win32/Wayland | Is the library; SBCL/CCL/ECL | **LGPL-2.1 Lisp source: not an allowed runtime dep** | SDL2 2–3 MB (est.) | Active (Codeberg, commits to 2026-11-26) | None documented | Own event loop per port | Good: Null/RasterImage backends, Xvfb |
| 2 | **GTK 4** via cl-cffi-gtk4 (MIT, 0.9.0, 2026-08) or cl-gtk4 (LGPL-3, GI, 2025-06) | Linux yes; Windows/macOS GTK-drawn | Linux good; Windows via MSYS2/gvsbuild; macOS Quartz backend, non-native look | Two bindings, low activity; cl-gtk4 is LGPL-3 (**not allowed**) | GTK LGPL-2.1+: overlay + NOTICE | Windows 42 MB bin + 185 MB share untrimmed ([discourse](https://discourse.gnome.org/t/compact-gtk-4-app-on-windows-where-to-put-icons/5826)); 40–60 MB trimmed (est.) | GTK very active | AT-SPI good on Linux; GTK 4.18 AccessKit backend on Win/mac ([GTK blog](https://blog.gtk.org/2025/05/12/an-accessibility-update/)); IME good | One GTK thread; `g_idle_add` marshalling | Xvfb / Broadway |
| 3 | **Qt 6** | Qt-drawn with native styles; best-in-class platform integration | All three, excellent | No living CL binding (CommonQt6 = Smoke, fragile; LQML = ECL+QML only). C ABIs: **miqt**/**libqt6c** (MIT, generated C shims, 2026-11) ([libqt6c](https://github.com/rcalixte/libqt6c)) | LGPL-3 (dynamic + relink); some modules GPL | 25–40 MB widgets, 60–80 MB with QML (est.) | Qt very active | Best a11y, IME, hi-DPI | GUI on main thread | `QT_QPA_PLATFORM=offscreen` |
| 4 | **IUP** (gen2brain/iup-go C lib, IUP 4.0.0, 2026-11-19) + **lispnik/iup** (v0.7.0, 2026-08-30) | **Yes** | Win32 or **WinUI 3**; **Cocoa**; GTK3/**GTK4**/Qt5/6 (+ FLTK, Motif, Android, iOS) ([iup-go](https://github.com/gen2brain/iup-go)) | lispnik/iup loads on our four targets in CI, but against lispnik's tecgraf-iup 3.32 build, not iup-go | **MIT** (fits); the Linux GTK/Qt runtime is system LGPL | **1.6 MB** libiup darwin-arm64 (measured); 1.8–2.3 MB tecgraf-iup archives per OS (measured) | iup-go active (453★, pushed 2026-11-26); Tecgraf upstream 3.32 (2025-01) slow | From native controls, **not verified** (§5.4) | `IupMainLoop` on main thread; `IupPostMessage` is the cross-thread entry (spike) | Linux Xvfb; mac/Win runners |
| 5 | **libui-ng** (MIT) | Yes (Win32, Cocoa, GTK3) | All three, "mid-alpha" | jinwoo/cl-ui, dead since 2016 | MIT | **0.7 MB** universal macOS, stripped (measured) | **Stalled**: last push 2025-03-15, 145 open issues | Weak a11y, weak IME | `uiMain` on main; `uiQueueMain` cross-thread (spike) | Xvfb |
| 6 | **Tk 9** via nodgui (LLGPL, 0.7.6.5) / LTK (stale) | ttk native themes (Aqua, Windows themes) | All three; Tk 9.1 (2026-09 **(unverified)**) adds `tk accessible` (NSAccessibility/MSAA/ATK) and RTL ([man page](https://dyn.manpages.debian.org/experimental/tk9.1-doc/accessible.3tk.en.html)) | nodgui talks to a `wish` subprocess; **LLGPL: not allowed** | Tcl licence (BSD-like) | 5–8 MB with script library (est.) | nodgui active, LTK stale | 9.1 a11y new; IME OK | `wish` owns its loop (subprocess) | Xvfb |
| 7 | **webview/webview** (MIT, 0.12.0, 2024-09; master to 2026-10) | No: system web engine | WebView2 / WKWebView / WebKitGTK 4.1 or 6.0 | mikelevins/lisp-webview (Apache-2.0, tiny); CLOGFrame | **MIT** | **108 KB** macOS stripped (measured); engine from OS; WebKitGTK is a system dependency on Linux | Slow releases; custom-scheme PR #1370 open, Cocoa-only | From the engine: good | `webview_run` on main; `webview_dispatch` cross-thread (spike) | browser-protocol tests the same HTML; WebView2 can expose CDP **(unverified)**; Xvfb |
| 7b | **Saucer** (MIT, v8) | No: system web engine | WebView2 / WKWebView / WebKitGTK (GTK4) | none | MIT | ~1 MB (est.) | Active; API churns between majors | From the engine | Thread-safe per README | Xvfb |
| 7c | **webui** (MIT, 2.5.0-beta) / **CLOG** (BSD-3, 2.3) | No | Browser or webview | cl-webui abandoned; CLOG is a full framework | MIT / BSD | — | webui still beta | From the browser | — | Browser |
| 8 | **Dear ImGui** (MIT, 1.93.1) via cimgui; Nuklear, microui | No (immediate mode) | All, via SDL3/GLFW + GPU | Stale or WIP (claw-imgui, cl-imgui) | MIT | ~1–2 MB + SDL3 (est.) | ImGui very active | **No a11y**; IME candidate position only; hi-DPI improved in 1.92 | Single render thread | Offscreen GL; the ImGui test engine is not MIT **(unverified)** |
| 9 | **Per-OS native**: Win32/WinUI via CFFI, Cocoa via `lispnik/objc` (MIT, LispWorks-compatible ObjC/Cocoa API, 2026-10) ([objc](https://github.com/lispnik/objc)), GTK on Linux | **Yes** | Each OS by its own backend | objc bridge exists (SBCL, ECL); Win32/WinUI none maintained | MIT (ours) | ~0 (OS frameworks) | Ours to maintain | Native, best | Main thread on macOS | Per-OS runners |
| 10a | **Flutter** 3.50 + rfw 2.0.0 (BSD-3) | No (Flutter-drawn, Material/Cupertino) | All three; desktop stewarded by Canonical | None; Lisp → rfw encoder in the spike | BSD-3 | 20–60 MB per OS (est., [app-size](https://docs.flutter.dev/perf/app-size)) | Very active | Win/mac a11y in the official runners; **Linux AT-SPI weak** ([Ubuntu](https://documentation.ubuntu.com/desktop/en/latest/explanation/accessibility-stack)); IME good | The runner owns the main thread; Lisp in another process or via FFI | `flutter test` headless; integration tests need a display |
| 10b | **Impeller** standalone (`impeller.h`, BSD-3) + **SDL3** (zlib) | No (draw API) | Metal / Vulkan / GL; prebuilts for darwin, linux and windows, x64/arm64 | None; the spike's `sb-alien` calls | BSD-3 + zlib (**zlib not yet on the allowlist**) | libimpeller **8.7 MB** stripped darwin-arm64 (measured; the SDK zip is 252 MB with symbols); SDL3 2.5 MB (measured) | Ships with every engine commit | You build it (AccessKit); SDL3 IME events; hi-DPI by hand (spike: 2.0 scale) | Render thread is yours; SDL events on main | Needs a GPU or SwiftShader/lavapipe |
| 10c | **Skia** via SkiaSharp's `libSkiaSharp` C shim (MIT; SkiaSharp 4.157.0, 2026-11-18) | No (draw API) | GL/Metal/D3D/Vulkan (Ganesh); Graphite on Dawn emerging | aw-skia dead (2023, no licence) | MIT shim, BSD-3 Skia | 12–16 MB per OS (measured from NuGet) | Microsoft-maintained shim tracks Skia milestones | Shim has **no paragraph API** ([#1248](https://github.com/mono/SkiaSharp/issues/1248)) | Yours | Software raster backend exists |
| 10d | **Dawn** (BSD-3) / **wgpu-native** (MIT/Apache), `webgpu.h` | No (GPU API only) | Metal/D3D12/Vulkan | None | Fits | Dawn 12 MB macOS, 26 MB Linux, 109 MB Windows tarballs (measured from releases); wgpu-native 14–16 MB zips | Dawn nightly; `webgpu.h` declared stable (core) in Chrome 141 ([post](https://developer.chrome.com/blog/new-in-webgpu-141)) | Nothing: no 2D, no text | Yours | Software adapters |
| 10e | **FLTK 1.4** via cfltk (MIT C API, 2026-11) | No (FLTK-drawn) | All, Wayland too | None living | LGPL-2 + static exception | 1–3 MB (est.) | Active | Weak a11y | Main thread | Xvfb |
| 10f | **wxWidgets** 3.2.11 / 3.3.3 | Yes | All three | wxCL dead; would need our own C shim | wxWindows (LGPL + exception) | 10–20 MB (est.) | Active | Good (native) | Main thread | Xvfb |
| 10g | **Slint** 1.19 | No | All | none | GPLv3 / royalty-free (not embedded) / commercial: **not allowed** | — | Active | AccessKit | — | — |

**Reading the matrix:**
- Only IUP, wxWidgets, per-OS native and (partly) Qt give real native widgets on all three desktops.
- Of those, only **IUP** is MIT-licensed, has a C API small enough to bind with CFFI, ships prebuilt binaries for all four of our overlay targets, and already has a CL binding.
- The webview route trades native widgets for engine-provided accessibility, IME and DPI, at the lowest cost.

---

## 3. Topic notes

### 3.1 Threading: macOS main thread vs `event-protocol`

- **Fact (spike §5.3):** AppKit must start on the process's initial thread. Starting libui-ng from a second SBCL thread aborted the process with `NSInternalInconsistencyException: API misuse: setting the main menu on a non-main thread`. Every in-process macOS backend inherits this (webview, IUP, libui, Impeller via SDL3). In SBCL the main thread is `sb-thread::*initial-thread*`. mikelevins/lisp-webview says the same and recommends a helper process.
- **Every toolkit offers one thread-safe entry**, and the spikes used each from a worker thread: `webview_dispatch`, `IupPostMessage`, `uiQueueMain` (SDL3 has `SDL_RunOnMainThread`). The protocol should expose one GF, `ui-call (backend function)`, implemented with these. It is the UI-thread analogue of event-protocol's `wake-call`.
- **Shape:** `run-ui` blocks the initial thread in the toolkit's loop. event-protocol's libuv loop runs on its own thread, as now. A command such as `(task f)` runs off-thread, and its result message comes back through `ui-call`. This is the same split as tui-protocol's `task` command.
- **REPL:** with the main thread taken, Swank/Slynk must run in another thread. Shinmera's `trivial-main-thread` (zlib, archived on GitHub 2026-05, moved to Codeberg) solves the inverse case: it runs a task loop on thread 0 for code started from a REPL. A `with-ui-main-thread` helper should cover both cases.
- **Out-of-process option:** a separate UI process (Flet, Saucer, CLOGFrame) avoids the constraint entirely, at the cost of IPC. Keep it possible for webview (§4.2).

### 3.2 SBCL-specific FFI findings (spikes)

- **Float traps.** WebKit, AppKit and Impeller execute FP operations that SBCL traps by default. The first webview window died with `FLOATING-POINT-INVALID-OPERATION`. Every backend must wrap the loop and its callbacks in `sb-int:with-float-traps-masked (:invalid :divide-by-zero :overflow :inexact)`, or the portable `float-features:with-float-traps-masked`.
- **Varargs on Apple arm64.** Variadic C functions take their variadic arguments on the stack. A fixed-prototype FFI call silently passes garbage. Bind the array forms (`IupVboxv`, `IupHboxv`), or use CFFI's `foreign-funcall-varargs`.
- **Structs by value.** `sb-alien` cannot pass structs by value. CFFI with libffi can. This matters for wgpu-native (callback-info structs) and some ObjC messages (`CGSize` as an HFA works as two doubles on arm64; `MTLRegion` at 48 bytes goes by reference under AAPCS64). Impeller's C API passes structs by pointer, which makes it the easiest GPU API to bind.
- **Callbacks.** `define-alien-callable` worked for every callback (webview bind, IUP `POSTMESSAGE_CB`, libui `uiQueueMain`). CFFI's `defcallback` is the portable equivalent for CCL/ECL.

### 3.3 Accessibility

- **Engine-provided:** webviews (the browser a11y tree, fed by canvas-protocol's semantic HTML and `aria-*`) and native widgets (each OS's own).
- **Self-drawn:** self-drawn UIs (Impeller, Skia, ImGui) must push their own tree. **AccessKit** (`accesskit-c` 0.23.2, MIT/Apache, push-based `TreeUpdate`s, adapters for UIA/NSAccessibility/AT-SPI; [repo](https://github.com/AccessKit/accesskit-c)) is the only credible library. There is **no linux-arm64 prebuilt**, and the linux-x64 one is 23.7 MB unstripped.
- **Flutter:** good on Windows and macOS, weak on Linux.
- **The spike could not verify IUP's a11y:** an in-process `accessibilityRole` query returns `AXUnknown` even for plain AppKit `NSTextField`/`NSButton` until an assistive client connects (baseline in §5.4). It needs a manual VoiceOver/Accessibility Inspector pass (open question 6).
- **Adopt (Compose, SwiftUI):** a11y fields (role, label, description, live) live on the declarative tree, and tests query the same tree.

### 3.4 High-DPI and IME/i18n

- webview: `devicePixelRatio` came back 2 on Retina (spike).
- IUP: reports `SCREENDPI 144` (spike).
- SDL3: `SDL_GetWindowDisplayScale` gave 2.0, and Impeller then draws in **physical pixels**, so the backend must apply the scale transform itself.
- IME comes from the engine (webview, Flutter), the OS widgets (IUP, native) or SDL3 `SDL_EVENT_TEXT_EDITING` + `SDL_StartTextInputWithProperties` (self-drawn; we would render preedit ourselves).
- Unicode text passed fine through every spike (UTF-8 C strings); i18n/l10n stays in our protocols.

### 3.5 Delivery

- **Image:** `save-lisp-and-die` plus the overlay's native libs. On macOS, a `.app` bundle with the dylibs in `Contents/Frameworks` and `@rpath` (IUP's prebuilt already uses `@rpath/libiup.4.dylib`).
- **Signing:** codesign + notarization. SBCL may need hardened-runtime entitlements (`allow-jit` / `allow-unsigned-executable-memory`) **(unverified; needs a spike)**.
- **Windows:** an installer (WiX, Inno, MSIX; open question). WebView2 is preinstalled on Windows 11, and Microsoft still recommends shipping the 2 MB Evergreen bootstrapper ([distribution](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution)).
- **Linux:** WebKitGTK and GTK are system dependencies, not overlay payload. AppImage/Flatpak is an open question.
- **Tooling:** none of this exists in cl-repo today. It is a separate track, `cl-repo bundle`, after the first backend.

### 3.6 Testability (three OSes, headless)

- **Copy Toga:** a **dummy backend** that records the operations the reconciler emits (create, set-property, insert, remove, destroy) and lets tests inject events. All core behaviour is tested in Rove on every OS with no display.
- **Per-backend probes:**
  - webview reuses canvas-protocol's HTML tests and browser-protocol against headless Chrome;
  - IUP runs on Linux under Xvfb, and on GitHub macOS/Windows runners, which have GUI sessions **(unverified for macOS runners)**;
  - Impeller needs a GPU or a software Vulkan (lavapipe/SwiftShader), so make it opt-in in CI.
- **Self-check, as in tui-protocol:** render, read back, compare (the Impeller spike read the Metal drawable back and checked pixels).

---

## 4. Recommended architecture

### 4.1 Layers

```text
                 app code: (defmethod ui-update ...) (defmethod ui-view ...)  — Elm model, same shape as tui-protocol
                                         │ view returns a widget tree (values, not objects)
                       ┌─────────────────┴──────────────────┐
                  ui-protocol (stack-ui): program GFs, commands, messages, widget-tree values,
                  reconciler (diff old/new tree → ops), ui-call, run-ui, conditions, a11y fields
                       │ ops: create / set / insert / remove / destroy ; events → messages
     ┌────────────┬────┴─────────┬──────────────────┬──────────────────────┬────────────────┐
 ui-backend-dummy  ui-backend-webview  ui-backend-iup     (later) ui-backend-cocoa /  (experimental)
 (Rove, headless)  (canvas-protocol    (native widgets,    -win32 / -gtk           ui-backend-rfw
                   HTML + htmx in a    MIT C lib overlay)  if IUP falls short       (Flutter shell)
                   system webview)
                                         canvas-protocol stays the HTML vocabulary; its chart/draw model
                                         gains a GPU backend: canvas-backend-impeller (SDL3 window)
```

- **`ui-protocol` program GFs mirror `tui-protocol`:**
  - `ui-init`, `ui-update (program model message) → (values model command)`, `ui-view (program model) → tree`.
  - The commands are tui's `:quit`, `tick`, `batch` and `task`, plus `ui-call`.
  - **Recommendation:** factor the program/command/message core out of tui-protocol into a shared `program-protocol` **only when the second consumer is written**. Until then ui-protocol copies the shape and documents the correspondence. Do not block on the refactor.
- **The tree vocabulary is canvas-protocol's components:** `stack`, `grid`, `card`, `details`, `fieldset`, `tabs`, `table` (+ columns), `form`, `text-input`, `number-input`, `date-input`, `checkbox`, `select-input`, `textarea`, `submit-button`, `badge`, `kv-list`, `code-block`, `chart`.
  - These are already CLOS classes ([canvas-protocol/src](https://github.com/egao1980/canvas-protocol)) with `render` → HTML.
  - ui-protocol adds window-level nodes (window, menu, dialog, file dialog, status bar) and gives every node an `on-*` slot holding a **message** (data, not a closure), which is what an Elm loop needs.
  - Native backends map each class to a control. The webview backend renders through canvas-protocol unchanged.
  - **One vocabulary, two event models:** canvas pages stay hypermedia (htmx GETs to canvas functions); ui-protocol apps are message-driven.
- **Reconciler in the protocol, not in backends (Flet, React).** Keyed diff of the previous and next trees → an ordered op list. Backends implement only the ops GFs (`backend-create`, `backend-set`, `backend-insert`, `backend-remove`, `backend-destroy`) and deliver native events as messages. That gives the dummy backend for free, and makes parity tests between backends a comparison of op logs.
- **Rules and enabling logic** (enabled/visible/required, mode-dependent menus) go through the logic family (`policy-protocol` / `logic-protocol`), per workspace rule. They are not `cond` chains in views.

### 4.2 Backend order

| Order | Backend | Why this order | Effort (one senior dev, est.) |
|---|---|---|---|
| U0 | **ui-protocol contract + ui-backend-dummy** | The contract and tests first (team-solve style); every later backend is measured against it | 2–3 weeks |
| U1 | **ui-backend-webview**: webview/webview native overlay (4 targets) + http-server-protocol on `127.0.0.1:0` with a per-window token, Host/Origin checks and canvas-protocol's strict CSP; tree → canvas components → HTML; DOM events → htmx POST → messages; SSE for pushes | Reuses canvas wholesale; engine-grade a11y/IME/DPI; smallest payload; proven from SBCL. A custom scheme would avoid localhost, but webview has none (PR #1370 is open and Cocoa-only); **Saucer** (MIT) has `register_scheme` and is the fallback. SSE needs a real HTTP origin anyway **(inferred)** | 3–4 weeks + overlay CI (Windows needs the WebView2 SDK headers at build time) |
| U2 | **ui-backend-iup**: overlay built from iup-go's C sources (CMake; MIT) per target, with Win32 and WinUI variants on Windows and GTK3/GTK4 on Linux; CFFI binding generated from `iup.h` (+ lispnik/iup's `classes.sexp`, as an import or an egao1980 fork); reconciler ops → `IupSetStrAttribute` / `IupAppend` / `IupMap` / `IupDetach` | The CAPI answer: native controls everywhere, MIT, 1.6 MB, a C API small enough to bind, active upstream | 5–8 weeks |
| U3 | **Delivery**: `.app` bundle + codesign/notarize, Windows installer, Linux packaging; `save-lisp-and-die` recipe with overlays | Needed for "an app", not for live-image tooling | 3–5 weeks |
| U4 | **canvas-backend-impeller** (+ SDL3 window): draw commands for charts, custom painters and editors, in a native window or embedded in IUP/webview as a GPU view | Fills the gap neither HTML nor native widgets cover (fast custom drawing). Pinned to a Flutter engine SHA because the API is unstable | 4–6 weeks |
| U5 | (experimental) **ui-backend-rfw** + prebuilt Flutter shell | Only if mobile or Flutter's widget set becomes a goal (§6) | 4–6 weeks + Flutter/Xcode CI |
| U6 | (conditional) **direct per-OS backends** (Cocoa via `lispnik/objc`, Win32/WinUI, GTK4) | Only where IUP proves insufficient (a11y, missing controls); each is months | 2–3 months each |

### 4.3 What to do with the other candidates

- **Adopt:**
  - Toga's interface/impl/dummy/probe layering;
  - Flet's diff-and-ship model and MessagePack wire format (we have `messagepack-protocol`);
  - Compose/SwiftUI's a11y-on-the-tree;
  - Tauri's capability ACL for what a webview page may call, expressed in `policy-protocol`;
  - McCLIM's *presentations* idea for live-image tooling: an object rendered with its type, so clicking it offers that type's commands. In ui-protocol this is a `presentation` node carrying a Lisp object id plus the commands applicable to it, which a webview or IUP context menu can offer. It is idea-level only; do not import McCLIM.
- **Avoid:**
  - LGPL/LLGPL Lisp libraries as runtime deps: McCLIM, nodgui, cl-gtk4 and LTK (policy);
  - CLOG's eval bridge (CSP);
  - writing a Flutter embedder;
  - ImGui/Nuklear for end-user apps (a11y);
  - libui-ng (stalled; it was a fine spike and works, but IUP supersedes it);
  - Qt until a C-ABI binding (libqt6c) is worth the LGPL and payload.
- **Keep an eye on:**
  - Tk 9.1's new accessibility (if nodgui ever relicensed, or a Tcl/Tk CFFI binding of our own);
  - webview's custom-scheme PR;
  - Impeller's API stability;
  - AccessKit's linux-arm64 builds.

---

## 5. Spikes (throwaway, this Mac)

All spikes live in the session scratch directory (`ui-spike/lisp/*.lisp`). Each is plain `sbcl --non-interactive --load` with `sb-alien`, and each exits by itself.

| # | Spike | Result |
|---|---|---|
| 5.1 | **webview/webview** (master `f244320`, 2026-10-22) built as a dylib with one `clang++` call against WebKit/Cocoa (1.1 s, 143 KB, **108 KB stripped**). SBCL: `webview_create` → title/size → `webview_bind "lispReady"` → `webview_set_html` (Cyrillic/CJK) → `webview_run`; a worker thread calls `webview_dispatch` → `webview_terminate` after 3 s | Window up in 0.23 s; JS called Lisp with `[2, "Mozilla/5.0 (Macintosh…AppleWebKit/"]` (devicePixelRatio 2); `webview_return` resolved the JS promise; the callback ran on the main thread; the cross-thread terminate worked. **First run died on a WebKit float trap** until wrapped in `with-float-traps-masked` |
| 5.2 | **libui-ng** (master `43ba1ef`, 2025-03-15) built with meson/ninja via `uv run` (**0.7 MB** universal, stripped). Window + vbox + label + entry + button; a worker thread `uiQueueMain`s a closure that sets and reads the entry, then `uiQuit` | Native NSTextField/NSButton; UTF-8 text round-tripped; callback on the main thread |
| 5.3 | libui-ng started **from a non-main SBCL thread** | Process aborted: `NSInternalInconsistencyException … setting the main menu on a non-main thread` (§3.1) |
| 5.4 | **IUP 4.0.0** (iup-go's prebuilt `libiup.dylib`, darwin-arm64, **1.6 MB**, depends only on system frameworks). `IupOpen`, `IupLabel`/`IupText`/`IupButton` in `IupVboxv` (array form; varargs avoided), `IupDialog`, `IupShow`; a worker thread `IupPostMessage`s; `POSTMESSAGE_CB` sets and reads the text and returns `IUP_CLOSE` | `DRIVER=Cocoa`, `SCREENDPI=144`; the callback ran on the main thread; text round-tripped. Native classes: `IUPCocoaLabelEventView` wrapping `NSTextField`, `IupCocoaTextField` (an NSTextField subclass), and `IupCocoaFlatButton` (**custom-drawn, not NSButton**). In-process `accessibilityRole` returned `AXUnknown`, but so did plain AppKit controls in a baseline, so the probe is **inconclusive** |
| 5.5 | **rfw from Lisp**: a 60-line Lisp encoder ported from rfw's `_BlobEncoder` (little-endian tagged stream) plus an `.rfwtxt` emitter, for a card/column/text/button screen with `data.*` refs, `state`, `event "canvas.submit" {…}` and `set state.count = 1`. Checked with the **Dart SDK 3.14.1 only** (no Flutter, no Xcode) against rfw 2.0.0's vendored pure-Dart `formats` library | Lisp blob **837 bytes, byte-identical** to `encodeLibraryBlob(parseLibraryFile(lisp-text))`; `decodeLibraryBlob` of the Lisp blob equals the parsed text. **Not done:** rendering in a Flutter app. `flutter build macos` needs full Xcode, and only the Command Line Tools are installed |
| 5.6 | **Impeller standalone** (`impeller_sdk.zip` for engine `4d35714`, Flutter 3.50 stable; darwin-arm64 zip 252 MB, dylib 11.7 MB, **8.7 MB stripped**) + **SDL3 3.4.20** (brew, 2.5 MB). SDL window with `SDL_WINDOW_METAL` → `SDL_Metal_CreateView/GetLayer` → CAMetalLayer configured via `objc_msgSend` → `ImpellerContextCreateMetalNew` → display list (white fill, red rect, a paragraph through `ImpellerTypographyContextNew` / `ParagraphBuilder`) → wrap each `nextDrawable` → draw → present for 3 s → read the drawable back with `getBytes:` | 150+ frames presented; readback: rect pixel `(217 26 26)` = 0.85·255 red, background white; the paragraph "Impeller from SBCL — Привет, 日本語, مرحبا" rendered with correct Arabic shaping and RTL through system-font fallback (inspected the dumped PNG). `ImpellerGetVersion` must equal the header's `IMPELLER_VERSION` (1.4.0) |
| — | **Dawn / wgpu-native** | **Skipped.** The current `webgpu.h` passes callback-info structs by value, which `sb-alien` cannot do without libffi/CFFI, and it adds no 2D or text layer over Impeller. Sizes are from the release pages |
| — | **Screenshot of windows** | `screencapture -l` produced nothing (most likely the screen-recording permission). The GPU readback replaced it for Impeller |

---

## 6. Flutter: alive, and how it could integrate

**Status (2026-11):**
- Flutter 3.50 shipped on 2026-11-11 ([what's new](https://docs.flutter.dev/release/whats-new), [3.50 post](https://flutter.dev/blog/whats-new-in-flutter-3-50)). In 3.50 Material and Cupertino move to the separate `material_ui` / `cupertino_ui` packages.
- At I/O 2026 (Flutter 3.44), **Canonical became lead maintainer and "Strategic Steward" for Flutter desktop**, owning the roadmap and the Windows, macOS and Linux embedders ([3.44](https://flutter.dev/blog/whats-new-in-flutter-3-44), [OMG! Ubuntu](https://www.omgubuntu.co.uk/2026/05/flutter-desktop-canonical-maintained)).
- Multi-window is still **experimental, main channel only** ([2026 roadmap](https://flutter.dev/blog/flutter-darts-2026-roadmap)).
- "Impeller beta on macOS desktop" comes only from a third-party blog **(unverified)**. Officially, desktop Windows and Linux still render with Skia.
- **Reading:** the framework is healthy; desktop is now a partner-maintained second tier.

| Route | What it takes | Verdict |
|---|---|---|
| 1. **Lisp as a custom embedder** (`embedder.h`, stable C ABI) | Renderer surface callbacks (GL/Metal/Vulkan/software), task runners with thread affinity, window metrics, pointer/key events, platform messages, a semantics callback; *plus* everything the official runners do: text input/IME, keyboard maps, clipboard, cursors, a11y mapping to UIA/NSAccessibility/AT-SPI, DPI. The official doc says custom embedders are unsupported where Google or Canonical ship one ([Custom-Flutter-Engine-Embedders](https://github.com/flutter/flutter/blob/main/docs/engine/Custom-Flutter-Engine-Embedders.md)). go-flutter (last commit 2023-02) and flutter-rs (2023-06) are dead; only embedded-Linux embedders (flutter-pi, active) survive | **Avoid.** Person-years, alone, against an upstream that says no |
| 2. **Official runner as host, Lisp in-process** via `dart:ffi` | SBCL as a shared library is maintained: `make-shared-library.sh`, `save-lisp-and-die :callable-exports`, ARM64 fix in 2.5.9 ([NEWS](https://raw.githubusercontent.com/sbcl/sbcl/master/NEWS)); sbcl-librarian generates headers ([repo](https://github.com/quil-lang/sbcl-librarian)); ECL embeds via `cl_boot`. Dart build hooks (`hook/build.dart`) can download prebuilt native assets ([hooks](https://dart.dev/tools/hooks)); whether Flutter desktop enables them by default is **unverified** | Possible. Risks: SBCL signals and GC inside a foreign host, thread registration for Dart isolate threads, macOS hardened runtime. Flet does exactly this for Python (the dart-bridge) |
| 3. **Separate process**: Flutter shell + Lisp server over a websocket or MessagePack | Two processes and a handshake; IPC latency is fine for app UI | **Simplest and safest**; matches http/ws/serdes protocols we already have |
| 4. **Server-driven: Remote Flutter Widgets** (`package:rfw` 2.0.0, flutter.dev, maintained to the 3.50 release) | Lisp emits rfw libraries (text or binary) plus `DynamicContent` data; the shell renders them and returns events (name + args). rfw itself says it cannot define new widgets, is unsuited to custom painters, drag-and-drop and page transitions, and its compatibility is "best effort" ([pub.dev](https://pub.dev/packages/rfw)) | **The route worth an experiment** (with 3 or 2 as transport), because no per-app Dart is written. Spike 5.5 proved the format side |

**Costs:**
- **Toolchain:** a Flutter SDK, plus Xcode for macOS and Visual Studio for Windows, only to build the *generic shell* once per OS and arch. The shell is then a cl-repo overlay like any native lib (inferred; plausible since the shell contains no app code). Linux arm64 needs an arm64 runner.
- **Size:** 20–40 MB on Windows and Linux, 40–60 MB for a universal macOS app **(unverified; measure with `flutter build --analyze-size`)**.
- **Licence:** BSD-3 (fits).
- **Accessibility:** weak on Linux.

### 6.1 Design: canvas → rfw backend (`ui-backend-rfw`)

canvas-protocol has no generic backend GF: components `render` to html-protocol nodes, and only charts dispatch on `*chart-backend*`. So an rfw backend is a **second renderer of the same component classes**. In the ui-protocol architecture it becomes a ui-protocol backend whose reconciler output is an rfw library (screens) plus data blobs (state).

| canvas / ui-protocol node | rfw (core.widgets / material) | Status |
|---|---|---|
| `stack` (`data-layout stack/row`, `gap`) | `Column` / `Row` + `SizedBox` gaps / `Wrap` | Direct |
| `grid` (`columns` 1–6) | `GridView` (core, builder) | Direct |
| `card` (title, footer) | `Card` + `Column` + `Text` | Direct |
| `details` | — (`ExpansionTile` is not in rfw's material set) | **Shell widget** |
| `tabs` | — (no `TabBar`) | **Shell widget** |
| `badge`, `kv-list`, `code-block` | `Container` + `Text`; `Column` of `Row`s; `Text` in a monospace `DefaultTextStyle` | Direct (no syntax highlight) |
| `table` (sortable, paged) | — (no `DataTable`) | **Shell widget**; sort/page clicks are events |
| `form`, `submit-button` | `Column`; `ElevatedButton(onPressed: event "canvas.submit" {...})` | Direct; form values must be collected by the shell |
| `text-input`, `number-input`, `date-input`, `textarea` | — (**no `TextField`**) | **Shell widget** with an `onChanged` / `onSubmitted` event |
| `checkbox` | — (no `Checkbox` / `Switch`) | **Shell widget** |
| `select-input` | `DropdownButton` (material) | Direct |
| `chart` | — (no `CustomPaint`) | **Shell widget** painting a draw-command list (the same list `canvas-backend-impeller` takes) |
| `live-region` / SSE `fragment-event` | New `DynamicContent` data or a new library blob pushed over the socket | Direct (data updates are cheap) |
| `hx-get` links / sort / page | `event "canvas.get" { fn: "pkg::name", params: {...} }` | Direct |
| focus, keyboard shortcuts, `aria-*` | `Semantics` is not in rfw's core set | **Shell widget** (`semantics` wrapper) |

- **Shell:** one Flutter app per OS, `cl-stack-shell`, containing:
  - `createCoreWidgets` + `createMaterialWidgets`;
  - a local library `canvas` with about 10 widgets (text field, checkbox, data table, tabs, expansion, chart painter, semantics wrapper, file picker);
  - a transport: a websocket to the image, carrying rfw binary blobs and data blobs.

  It is MessagePack-free because rfw's own blob format already carries both. Events go back as small JSON or MessagePack frames.
- **Lisp side:** an encoder (spike-proven, about 100 lines), the component → rfw mapping above, and the event → message mapping.
- **Overlay:** the shell is built in CI per OS and arch and published as an overlay. It is a version-locked pair with the `canvas` local widget library version that the Lisp side checks at handshake.
- **Missing or hard:**
  - custom painters beyond the chart list;
  - drag-and-drop;
  - rich text editing;
  - per-app custom widgets, which always need Dart and a shell rebuild;
  - rfw's "best effort" compatibility, which means pinning the shell's rfw version.

---

## 7. Google's low-level stack: a GPU canvas backend

**Idea:** canvas-protocol's chart model (and a future draw-command list: rect, path, text run, image, clip, transform) rendered natively in a window, for the cases HTML/SVG is too slow for: big plots, waveforms, score engraving previews, node editors. This is "Lisp draws", the way Flutter, Compose/Skiko and Avalonia do, but scoped to a **canvas surface, not a widget toolkit**. A widget toolkit on a self-drawn stack is about a year of work (layout, focus, text editing with IME and selection, menus, theming, a11y via AccessKit) for a non-native look.

| | **Impeller standalone** | **Skia via libSkiaSharp** | **Dawn / wgpu-native (webgpu.h)** |
|---|---|---|---|
| C API | `impeller.h`, single header, opaque handles, structs by pointer; **no stability guarantee**; exact version match enforced ([README](https://github.com/flutter/flutter/blob/master/engine/src/flutter/impeller/toolkit/interop/README.md), [API](https://api.flutter.dev/impeller/impeller_8h.html)) | `sk_*.h` C shim (about 45 headers) maintained by Microsoft; tracks Skia milestones (SkiaSharp 4.157.0) ([releases](https://github.com/mono/SkiaSharp/releases)) | `webgpu.h` core declared stable ([Chrome 141](https://developer.chrome.com/blog/new-in-webgpu-141)); wgpu-native lagged the stable header **(unverified now)** |
| Prebuilts for our 4 targets | **Yes**: `impeller_sdk.zip` for darwin-arm64, linux-x64, linux-arm64, windows-x64 (all HTTP 200 for engine `4d35714`; 252 / 23 / 22.5 / 108 MB zips with symbols) | Yes (NuGet native assets): linux-x64 12.3 MB, linux-arm64 12.2 MB, osx universal 16.0 MB, win-x64 13.0 MB | Dawn tarballs 12 / 26 / 109 MB; wgpu-native zips 14–16 MB |
| Text | **Built in**: typography context, paragraph builder (SkParagraph + ICU underneath); spike rendered CJK and RTL Arabic | **No paragraph API** in the shim; HarfBuzzSharp for shaping only; a custom build with skparagraph means owning a gn/ninja build ×4 | None |
| GPU backends | Metal, Vulkan, OpenGL (ES) | GL, Metal, D3D, Vulkan (Ganesh); Graphite headers appearing | Metal, D3D12, Vulkan |
| Window/surface | Bring your own: SDL3 (spike) or GLFW (upstream examples) | Bring your own | Bring your own |
| Licence | BSD-3 (bundle LICENSE points to the Flutter engine's `sky_engine` LICENSE, which includes third-party notices) | MIT shim + BSD-3 Skia | BSD-3 / MIT-Apache |
| Binding effort | Low: ~300 functions, pointer-only; the spike needed ~25 | Medium: generated from ~45 headers, 3–5 weeks | Medium-high, plus a 2D layer of our own |
| Verdict | **First choice for `canvas-backend-impeller`**, pinned per engine SHA, with a parity test against `canvas-backend-svg` (rasterised SVG vs readback) | Fallback if Impeller's churn hurts | Not for 2D UI; only if we want compute or 3D |

- **Window layer:** SDL3 (zlib; 3.4.20; IME via `SDL_StartTextInputWithProperties`, display scale, `SDL_RunOnMainThread`; CL bindings `aiffc/cl-sdl3` and others, MIT, immature) beats GLFW, which has no IME preedit API. **The zlib licence is not on our allowlist yet** (open question 4).
- **Accessibility:** a canvas surface exposes one a11y node with a description (like a `figure` with `figcaption`) unless it adopts AccessKit later.

---

## 8. Risks

1. **macOS main-thread ownership vs the live-image workflow.** The UI loop takes thread 0; SLIME/Sly, the event loop and agents must live elsewhere. Getting this wrong crashes the image (spike 5.3).
2. **IUP depends on one maintainer** (gen2brain) for the modern drivers. Tecgraf upstream is slow (3.32, 2025-01). Mitigations: we build the C library from tagged source in our overlay CI (MIT, so forkable); the WinUI and GTK4 drivers are new.
3. **IUP's accessibility and look on macOS are unverified.** The spike showed its button is a custom `IupCocoaFlatButton`, not `NSButton`.
4. **webview/webview's release cadence** (last tag 2024-09) and its missing custom scheme. Saucer is the fallback.
5. **Impeller's unstable API** forces a rebuild and re-pin on each engine roll, and each SDK zip is tied to one engine SHA.
6. **Flutter desktop's future** now rests on Canonical; Linux a11y is weak; rfw compatibility is "best effort".
7. **Delivery** (codesign, notarization with SBCL's executable memory, installers) is unbuilt and may need entitlements we have not tested.
8. **Linux system dependencies** (WebKitGTK, GTK) are outside cl-repo overlays, so "no C toolchain" holds but "no system packages" does not.
9. **Evidence is thin** for payload estimates marked est., Tk 9.1's release, GTK on macOS quality, and CI GUI sessions on GitHub macOS runners.

---

## 9. Open questions for the user

1. **Goal:** is the target (a) live-image tooling windows (inspectors, canvases, agents' views), (b) shippable end-user apps à la CAPI, or (c) both? (a) is served by webview + Impeller in weeks; (b) needs IUP plus delivery tooling.
2. **Native look requirement:** is "engine-drawn but accessible" (webview) acceptable for v1, with native widgets (IUP) as v2? Or must v1 be native?
3. **One vocabulary:** may ui-protocol reuse canvas-protocol's component classes (adding message slots and window-level nodes), or should ui-protocol own a separate widget-tree vocabulary that canvas renders?
4. **Licence policy:** add **zlib** (SDL3, trivial-main-thread, cocoas, Clay) to the runtime allowlist? It is permissive and OSI-approved, but not listed today.
5. **Imports:** import `lispnik/iup` (MIT) into cl-stack-systems, fork it to retarget iup-go's IUP 4 library, or write our own generated binding?
6. **Manual a11y check:** can someone run VoiceOver/Accessibility Inspector on the IUP and webview spikes (and NVDA on Windows)? An in-process probe cannot answer this.
7. **Flutter/rfw:** worth a U5 experiment (it needs full Xcode on the Mac and Flutter in CI), or park it until mobile is on the table?
8. **Delivery scope:** should `cl-repo` grow a `bundle` command (.app/.msi/AppImage), or is delivery per-app?
9. **CAPI compatibility:** worth offering a CAPI-flavoured facade (`define-interface`-like) over ui-protocol for people porting LispWorks code? `lispnik/objc` shows the appetite for LispWorks-compatible APIs.

---

## Sources

- Context: [canvas.md](../capabilities/canvas.md), [tui.md](../capabilities/tui.md), [event-protocol.md](../capabilities/event-protocol.md), [overlays.md](../overlays.md), [LICENSE-POLICY.md](../LICENSE-POLICY.md), [API.md](../API.md); [canvas-protocol](https://github.com/egao1980/canvas-protocol) source.
- McCLIM: [1.0.0 announcement](https://mcclim.common-lisp.dev/posts/McCLIM-100-Koliada-release.html), [Codeberg](https://codeberg.org/McCLIM/McCLIM).
- GTK: [cl-gtk4](https://github.com/bohonghuang/cl-gtk4), [cl-cffi-gtk4](https://github.com/crategus/cl-cffi-gtk4), [GTK a11y update](https://blog.gtk.org/2025/05/12/an-accessibility-update/), [Windows bundle size](https://discourse.gnome.org/t/compact-gtk-4-app-on-windows-where-to-put-icons/5826), [gvsbuild](https://github.com/wingtk/Gvsbuild).
- Qt: [CommonQt6](https://github.com/commonqt/commonqt6), [LQML](https://gitlab.com/eql/lqml), [miqt](https://github.com/mappu/miqt), [libqt6c](https://github.com/rcalixte/libqt6c), [DOtherSide](https://github.com/filcuc/DOtherSide).
- IUP: [gen2brain/iup-go](https://github.com/gen2brain/iup-go) (README, `iup/libs/*` prebuilts, release iup/v0.40.0), [lispnik/iup](https://github.com/lispnik/iup), [lispnik/tecgraf-iup v2.1.0](https://github.com/lispnik/tecgraf-iup/releases/tag/v2.1.0), [Tecgraf IUP news](https://sourceforge.net/p/iup/news).
- libui-ng: [repo](https://github.com/libui-ng/libui-ng).
- Tk: [nodgui](https://codeberg.org/cage/nodgui), [LTK](https://github.com/herth/ltk), [Tk 9.1 accessible(3tk)](https://dyn.manpages.debian.org/experimental/tk9.1-doc/accessible.3tk.en.html), [Tk 9.1 report](https://linuxiac.com/tcl-tk-9-1-released-with-screen-reader-support-and-rtl-text/) (secondary).
- Webviews: [webview CHANGELOG](https://github.com/webview/webview/blob/master/CHANGELOG.md), [issue #851](https://github.com/webview/webview/issues/851), [PR #1370](https://github.com/webview/webview/pull/1370), [WebView2 distribution](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution), [lisp-webview](https://github.com/mikelevins/lisp-webview), [Saucer](https://github.com/saucer/saucer), [webui releases](https://github.com/webui-dev/webui/releases), [cl-webui](https://github.com/garlic0x1/cl-webui), [CLOG](https://github.com/rabbibotton/clog), [three web views for CL](https://lisp-journey.gitlab.io/blog/three-web-views-for-common-lisp--cross-platform-guis), [Tauri releases](https://github.com/tauri-apps/tauri/releases), [pywebview releases](https://github.com/r0x0r/pywebview/releases).
- Immediate mode: [Dear ImGui releases](https://github.com/ocornut/imgui/releases), [cl-sdl3](https://github.com/aiffc/cl-sdl3).
- Python prior art: [Toga architecture](https://toga.beeware.org/en/latest/topics/architecture/), [Toga testbed](https://toga.beeware.org/en/latest/topics/internal/testbed/), [Flet 1.0](https://flet.dev/blog/introducing-flet-1-0-alpha), [Flet 0.86](https://flet.dev/blog/flet-v-0-86-release-announcement), [Flet releases](https://github.com/flet-dev/flet/releases).
- Per-OS: [lispnik/objc](https://github.com/lispnik/objc), [trivial-main-thread](https://shinmera.github.io/trivial-main-thread), [cocoas](https://shinmera.github.io/cocoas), [framebuffers](https://codeberg.org/shirakumo/framebuffers), [CCL 1.14](https://github.com/Clozure/ccl/releases/tag/v1.14), [Windows App SDK unpackaged deployment](https://learn.microsoft.com/windows/apps/windows-app-sdk/tutorial-unpackaged-deployment).
- Commercial: [LispWorks 8.1 news](https://lispworks.com/news/news42.html), [LispWorks prices](https://www.lispworks.com/buy/prices-1a.html), [Allegro CG/JS](https://franz.com/support/documentation/cg-cgjs.html).
- Flutter: [what's new](https://docs.flutter.dev/release/whats-new), [3.50](https://flutter.dev/blog/whats-new-in-flutter-3-50), [3.44](https://flutter.dev/blog/whats-new-in-flutter-3-44), [2026 roadmap](https://flutter.dev/blog/flutter-darts-2026-roadmap), [Canonical stewardship](https://www.omgubuntu.co.uk/2026/05/flutter-desktop-canonical-maintained), [custom embedders](https://github.com/flutter/flutter/blob/main/docs/engine/Custom-Flutter-Engine-Embedders.md), [go-flutter](https://github.com/go-flutter-desktop/go-flutter), [rfw on pub.dev](https://pub.dev/packages/rfw), [rfw source](https://github.com/flutter/packages/tree/main/packages/rfw), [createCoreWidgets](https://pub.dev/documentation/rfw/latest/rfw/createCoreWidgets.html), [createMaterialWidgets](https://pub.dev/documentation/rfw/latest/rfw/createMaterialWidgets.html), [Stac](https://github.com/StacDev/stac), [Dart hooks](https://dart.dev/tools/hooks), [app size](https://docs.flutter.dev/perf/app-size), [Ubuntu a11y stack](https://documentation.ubuntu.com/desktop/en/latest/explanation/accessibility-stack), [SBCL NEWS](https://raw.githubusercontent.com/sbcl/sbcl/master/NEWS), [sbcl-librarian](https://github.com/quil-lang/sbcl-librarian).
- GPU/2D: [Impeller interop README](https://github.com/flutter/flutter/blob/master/engine/src/flutter/impeller/toolkit/interop/README.md), [impeller.h API](https://api.flutter.dev/impeller/impeller_8h.html), `https://storage.googleapis.com/flutter_infra_release/flutter/<engine-sha>/<platform-arch>/impeller_sdk.zip`, [SkiaSharp releases](https://github.com/mono/SkiaSharp/releases), [SkiaSharp #1248](https://github.com/mono/SkiaSharp/issues/1248), [SkiaSharp native assets](https://www.nuget.org/packages/SkiaSharp.NativeAssets.Linux), [rust-skia](https://github.com/rust-skia/rust-skia), [Skiko](https://github.com/JetBrains/skiko), [skia-python](https://github.com/kyamagu/skia-python), [aw-skia](https://github.com/borodust/aw-skia), [Skia m158 notes](https://github.com/google/skia/blob/chrome/m158/RELEASE_NOTES.md), [Dawn releases](https://github.com/google/dawn/releases), [Chrome 141 WebGPU](https://developer.chrome.com/blog/new-in-webgpu-141), [SDL releases](https://github.com/libsdl-org/SDL/releases), [SDL_StartTextInputWithProperties](https://wiki.libsdl.org/SDL3/SDL_StartTextInputWithProperties), [GLFW changelog](https://www.glfw.org/changelog.html), [AccessKit](https://github.com/AccessKit/accesskit), [accesskit-c](https://github.com/AccessKit/accesskit-c), [Slint](https://slint.dev) (licence), [FLTK 1.4.5](https://groups.google.com/g/fltkcoredev/c/_oY4fKlTYxw), [cfltk](https://github.com/MoAlyousef/cfltk), [wxWidgets 3.2.11/3.3.3](https://www.wxwidgets.org/news/2026/07/wxwidgets-3.2.11-and-3.3.3-released/).

# terminal-protocol (P2) — terminal emulation

**Issues:** [#264](https://github.com/egao1980/cl-stack/issues/264)
**Status:** brief **locked** — no code yet

A CLOS protocol for a **headless terminal emulator**. You feed it the bytes a program writes, and it keeps the screen state. You query cells, the cursor, modes and the title, and you encode user input (keys, mouse, focus, paste) into the bytes the program expects back.

It covers the emulator only. It does **not** open a PTY, spawn a shell, draw glyphs or load fonts. Those belong to the caller (see [Non-goals](#non-goals)).

Default backend: **[libghostty-vt 1.0](https://mitchellh.com/writing/libghostty-1-0)** (tag `vt-1.0.0`, MIT), a portable C library extracted from Ghostty. Its C ABI is frozen under semver: opaque handles, enum-keyed get/set, size-prefixed structs, `GHOSTTY_UNSUPPORTED` when headers are newer than the library. On ELF the symbols are versioned. The second backend is pure Lisp.

Conventions: [API.md](../API.md). Errors: [conditions.md](conditions.md).

---

## Use cases

| Consumer | Needs |
|----------|-------|
| Agents driving TUIs (`lisp-mcp`, ai-agent tools) | Run `htop` / `vim` / a REPL behind a PTY. Read the screen back as text. Send keys. |
| TUI tests (`cl-stack-llm-tui`, `ag-ui-backend-tui/tuition`) | Feed the app's output and assert on cells and styles, not on escape-sequence soup. |
| Terminal UIs written in Lisp | Frame and dirty rows for a renderer (any toolkit). |
| Session recording and replay | Feed a recording, snapshot it as `:plain` / `:vt` / `:html`. |

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| libghostty-vt 1.0 | Terminal + render-state split. Dirty rows. Effects as callbacks. Key/mouse/focus/paste encoders driven by terminal modes. Formatter (plain/VT/HTML). | Kitty graphics, search and selection in wave-1 (P1). Custom allocators. |
| libvterm (Neovim) | Damage callbacks, screen vs state layers | Callback-only API (we also need pull) |
| xterm.js headless | Headless mode as a first-class product | JS buffer API shape |
| pyte (Python) | A pure-language reference emulator good enough for tests | Its VT coverage as the ceiling |
| alacritty_terminal / wezterm `term` | One owner per terminal; the renderer pulls a snapshot | Rust lock types |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | CLOS protocol + backends | Matches the stack |
| **Default (A)** | **libghostty-vt 1.0** via CFFI | Stable ABI, broad VT coverage (xterm, Kitty keyboard, OSC 8/52/133), creates no threads, CI on linux/macOS/windows/android/wasm |
| **Second (B)** | **`terminal-backend-lisp`** (pure CL) | ECL/ABCL smoke ([multi-impl.md](../multi-impl.md)). Fallback where no native overlay exists. Keeps the protocol from becoming "the ghostty API in Lisp". |
| **Bytes in** | `terminal-feed` takes **octets** | The program's output is bytes. UTF-8 decoding belongs to the emulator; sequences split across reads must resume. |
| **Pull + push** | Pull: frame/cell queries. Push: a **host** object gets effects. | Renderers pull. Bells, titles and DSR replies are events. |
| **Effects** | GFs on a **`terminal-host`**. Default methods do nothing; the default host buffers replies. | Not a closure plist. Methods compose (`:around` for logging). |
| **Input encoding** | Lives in the protocol (`encode-key` …) and reads the terminal's live modes | DECCKM, Kitty flags, bracketed paste and mouse tracking are terminal state. Encoding without it is wrong. |
| **Threads** | One owner thread per terminal. The protocol does **not** lock. | libghostty-vt is not thread-safe per terminal. Locks are policy. |
| **Reentrancy** | `terminal-feed` on the same terminal from inside a host method signals **`terminal-reentrant-feed`** | libghostty-vt doesn't check for this and corrupts the parse. The guard is a special binding in the protocol `:around`. |
| **Non-local exits** | Never through C frames | A condition in a host method is caught in the callback trampoline. The native call finishes, then the condition is re-signalled as `terminal-host-error` with `continue`. |
| **Native shim** | **None.** Bind `ghostty/vt.h` directly. | Unlike `llama.h`, this ABI is frozen. `GHOSTTY_UNSUPPORTED` maps to `terminal-unsupported`. |
| **Wave-1 backends** | ghostty **and** pure Lisp ship together | Parity corpus gates both from day one |
| **Overlays** | `linux/amd64` `linux/arm64` `darwin/arm64` `windows/amd64` — no `darwin/amd64` | Matches other cl-stack natives |
| **Resources** | `with-terminal` / `terminal-close`; a finalizer as backstop only | [API.md](../API.md) rule |

---

## Repo layout

Each repo is its own `egao1980/<name>`, created the day its tree is created (`create-first-party-repo.sh`).

| Repo / system | Role |
|---------------|------|
| [`terminal-protocol`](https://github.com/egao1980/terminal-protocol) (`stack-terminal`) | GFs, value types, conditions, host protocol, reentrancy guard |
| [`ghostty-vt`](https://github.com/egao1980/ghostty-vt) | CFFI bindings + OCI native overlays for libghostty-vt. Not the protocol; usable on its own (same split as `llama-cpp` / `llm-backend-llama-cpp`). |
| [`terminal-backend-ghostty`](https://github.com/egao1980/terminal-backend-ghostty) | `defmethod`s over `ghostty-vt` |
| [`terminal-backend-lisp`](https://github.com/egao1980/terminal-backend-lisp) | Pure-CL emulator for the VT core subset |
| [`terminal-parity`](https://github.com/egao1980/terminal-parity) | Golden corpus (bytes → snapshot) run against every backend, filtered by `backend-supports-p` |

---

## Protocol surface

```lisp
(defclass terminal-backend () ())
(defvar *terminal-backend* nil)
(defgeneric backend-supports-p (backend feature))
;; features: :scrollback :alternate-screen :kitty-keyboard :osc-52 :osc-133
;;           :format-vt :format-html      ; P1: :selection :search :kitty-graphics

;;; Lifecycle
(defgeneric backend-make-terminal (backend &key cols rows host
                                     scrollback-lines palette
                                     foreground background cursor-color))
(defun make-terminal (&rest keys &key (backend *terminal-backend*) &allow-other-keys))
(defgeneric terminal-close (terminal))
(defgeneric terminal-closed-p (terminal))
(defmacro with-terminal ((var &rest keys) &body body))

;;; Program → terminal
(defgeneric terminal-feed (terminal octets &key start end))   ; → nil
(defgeneric terminal-resize (terminal cols rows &key cell-width-px cell-height-px))
(defgeneric terminal-reset (terminal))                         ; RIS

;;; State
(defgeneric terminal-size (terminal))           ; → (values cols rows)
(defgeneric terminal-cursor (terminal))         ; → cursor
(defgeneric terminal-title (terminal))          ; OSC 0/2 → string or nil
(defgeneric terminal-pwd (terminal))            ; OSC 7 → string or nil
(defgeneric terminal-active-screen (terminal))  ; → :primary | :alternate
(defgeneric terminal-mode (terminal mode))      ; mode = (:dec 25) | (:ansi 4) | :bracketed-paste …
(defgeneric (setf terminal-mode) (value terminal mode))
(defgeneric terminal-mouse-tracking (terminal)) ; → :none :x10 :normal :button :any
(defgeneric terminal-scroll-viewport (terminal &key to delta)) ; to = :top | :bottom
(defgeneric terminal-text (terminal &key format region))
;; format = :plain | :vt | :html ; region = :viewport | :screen | :scrollback → string

;;; Frames (pull-based rendering)
(defgeneric make-frame (terminal))              ; reusable snapshot
(defgeneric frame-update (frame))               ; → :none | :partial | :full
(defgeneric frame-size (frame))                 ; → (values cols rows)
(defgeneric frame-cursor (frame))               ; → cursor (viewport coords, or nil if off-screen)
(defgeneric frame-colors (frame))               ; → default fg / bg / cursor + 256-entry palette
(defgeneric frame-row (frame y))                ; → row
(defmacro do-frame-rows ((row frame &key dirty-only) &body body))
(defgeneric row-y (row))
(defgeneric row-dirty-p (row))
(defgeneric (setf row-dirty-p) (value row))
(defgeneric row-cells (row))                    ; → (vector cell)
(defgeneric frame-mark-clean (frame))

;;; Terminal → program: input encoding (reads live modes) → octets, empty if none
(defgeneric encode-key (terminal key &key text modifiers action))
;; key  = :a … :z :enter :tab :escape :backspace :up :f1 … (W3C KeyboardEvent.code names)
;; text = string the key produces (layout-resolved) ; modifiers ⊆ (:shift :ctrl :alt :super)
;; action = :press | :repeat | :release
(defgeneric encode-mouse (terminal button action x y &key modifiers pixel-x pixel-y))
(defgeneric encode-focus (terminal focused-p))
(defgeneric encode-paste (terminal string))     ; honours bracketed paste
(defun paste-safe-p (string))                   ; no ESC / C1 tricks

;;; Host: effects pushed from inside terminal-feed
(defclass terminal-host () ())
(defclass buffering-host (terminal-host) ())    ; default; collects replies
(defgeneric host-write-pty (host terminal octets))     ; DA / DSR / XTVERSION replies
(defgeneric host-bell (host terminal))
(defgeneric host-title-changed (host terminal title))
(defgeneric host-pwd-changed (host terminal pwd))
(defgeneric host-clipboard-write (host terminal clipboard string)) ; OSC 52 ; clipboard = :clipboard | :primary
(defgeneric host-clipboard-read (host terminal clipboard))         ; → string or nil (nil = deny)
(defgeneric host-notify (host terminal title body))                ; OSC 9 / 777
(defgeneric host-color-scheme (host terminal))                     ; → :light | :dark | nil
(defgeneric host-prompt-mark (host terminal kind))                 ; OSC 133 A/B/C/D
(defgeneric terminal-take-replies (terminal))   ; buffering-host only → octets
```

### Value types

| Type | Slots |
|------|-------|
| `cursor` | `x` `y` `visible-p` `style` (`:block` `:bar` `:underline` `:block-hollow`) `blinking-p` `wide-tail-p` |
| `cell` | `text` (grapheme cluster string; `""` empty) · `width` (`:narrow` `:wide` `:spacer`) · `style` |
| `style` | `foreground` `background` `underline-color` · `bold` `faint` `italic` `blink` `inverse` `invisible` `strikethrough` `overline` · `underline` (`nil` `:single` `:double` `:curly` `:dotted` `:dashed`) · `hyperlink` (OSC 8 URI or nil) |
| colour | `:default` · palette index `(integer 0 255)` · `rgb` struct (`r g b` octets). In a frame, cell colours are **resolved** to `rgb` or `:default`. |

Cells and styles in a frame are fresh Lisp values. Nothing aliases native memory, so they outlive `frame-update`.

### Conditions

```text
terminal-error (error)
├── terminal-closed-error
├── terminal-unsupported         ; feature / GHOSTTY_UNSUPPORTED — restart use-value
├── terminal-invalid-argument
├── terminal-out-of-memory       (storage-condition mixin)
├── terminal-reentrant-feed
└── terminal-host-error          ; wraps original; restarts continue, abort-feed
terminal-native-unavailable      ; overlay missing at ASDF load — restart use-value (path)
```

---

## Native libghostty-vt (`ghostty-vt`)

- **Pin:** libghostty-vt **1.0.x**, built from the **signed source tarball + deps tarball**, not a git checkout (a checkout builds the app unless you pass `-Demit-lib-vt`). Needs **Zig 0.17.x**, matched exactly by major.minor. Verify the signatures in CI.
- **Overlays:** `linux/amd64`, `linux/arm64`, `darwin/arm64`, `windows/amd64` shared libraries. The library builds with the GNU ABI on Windows, and that's fine for CFFI. The `.asd` `:cl-repo :overlays` is the inventory.
- **Load:** `load-foreign-library` at ASDF load from the overlay's absolute path. `(asdf:load-system "terminal-backend-ghostty")` is enough.
- **Version check:** at load, compare the `build_info.h` / `version.h` runtime version with the header version the bindings were written for. Refuse a major mismatch with `terminal-native-unavailable`.
- **Bindings:** enum-keyed `ghostty_*_get` / `_set` / `_get_multi` behind typed Lisp accessors. Size-prefixed structs fill `size` from `foreign-type-size`.
- **Callbacks:** one `defcallback` trampoline per effect. `GHOSTTY_TERMINAL_OPT_USERDATA` carries an integer id into a weak table, never a Lisp object. Every trampoline is wrapped in `handler-case` → stash → re-signal after the native call (see Locked decisions).
- **Buffers:** `terminal-feed` pins octets with `cffi:with-pointer-to-vector-data` when the vector is a simple `(unsigned-byte 8)` array. Otherwise it copies into a reused foreign buffer.
- **Render state:** a frame owns one `GhosttyRenderState` plus row/cell iterators, reused across `frame-update`.
- **Float traps:** mask them around native calls, as `llama-cpp` does. SIMD paths otherwise risk `FLOATING-POINT-*` conditions in SBCL.

## Pure-Lisp backend (`terminal-backend-lisp`)

Wave-1 scope is the VT core every TUI uses:

- C0 controls
- CSI cursor movement, ED / EL / ICH / DCH / IL / DL, scroll regions (DECSTBM)
- SGR (16, 256 and truecolor)
- DECSET 1 / 7 / 25 / 1049 / 2004 and mouse modes 1000 / 1002 / 1003 / 1006
- OSC 0 / 2 / 7 / 8
- DA / DSR replies
- UTF-8 with East Asian Width
- Legacy and xterm modifier key encoding

It reports `nil` from `backend-supports-p` for `:kitty-keyboard`, `:osc-133` and `:format-html`.

## Conformance (`terminal-parity`)

- A fixture is `(bytes, cols×rows, expected snapshot)`. The snapshot holds cell text, widths, styles, cursor, title, modes and replies.
- The corpus is **generated once with the ghostty backend as oracle**, reviewed, frozen as S-expressions, and replayed against every backend. Each fixture is tagged with the features it needs and skipped when a backend lacks them.
- Seed sources: vttest-style sequences, recordings of `vim` / `htop` / `less` / the cl-stack TUIs, and split-read fuzzing (the same bytes fed in random chunk sizes must give an identical snapshot).

---

## Example

```lisp
(asdf:load-system "terminal-backend-ghostty")

(stack-terminal:with-terminal (term :cols 80 :rows 24)
  (stack-terminal:terminal-feed
   term (babel:string-to-octets (format nil "Hello, ~C[1;32mworld~C[0m!~C~C"
                                        #\Esc #\Esc #\Return #\Newline)))
  (stack-terminal:terminal-text term :format :plain))
;; ⇒ "Hello, world!"
```

---

## Non-goals

- **PTY / shell spawning.** `process-protocol` excludes PTYs in wave-1. A separate `pty-protocol` brief (forkpty / ConPTY) comes later; the cookbook shows the glue loop.
- Glyph rendering, fonts, shaping, GPU
- Kitty graphics, search and selection (P1; libghostty-vt has them)
- A tmux-like multiplexer or session server
- Locking inside the protocol

---

## Implementation tasks

- [x] Brief lock — this doc ([#264](https://github.com/egao1980/cl-stack/issues/264))
- [ ] `terminal-protocol` + Rove (host protocol, reentrancy guard, value types)
- [ ] `ghostty-vt` — CFFI + overlay build (Zig 0.17, signed tarballs) + `publish-oci.yml`
- [ ] `terminal-backend-ghostty` + Rove
- [ ] `terminal-parity` corpus (ghostty oracle)
- [ ] `terminal-backend-lisp` against the parity corpus
- [ ] Cookbook `cookbooks/terminal.md` (headless TUI test; PTY glue loop)
- [ ] OCI publish

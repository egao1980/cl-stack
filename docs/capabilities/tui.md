# tui-protocol (P2) — terminal user interfaces

**Issues:** [#274](https://github.com/egao1980/cl-stack/issues/274) · terminal [#264](https://github.com/egao1980/cl-stack/issues/264)
**Status:** brief **draft** — no code yet

A CLOS protocol for full-screen terminal programs. The program is a model with `update` and `view` (the Elm architecture, as in bubbletea and [cl-tuition](https://github.com/atgreen/cl-tuition)). `view` returns a **canvas**: a grid of [`terminal-protocol`](terminal.md) cells and styles. A renderer diffs successive canvases into minimal VT output. An input decoder turns the terminal's bytes into key, mouse, paste, focus and resize messages.

Backends are the terminals the program runs on:

| Backend | Terminal | Use |
|---------|----------|-----|
| `tui-backend-terminal` | A `terminal-protocol` emulator (ghostty or pure Lisp), headless | Tests, agents, embedding a TUI in another program, recordings |
| `tui-backend-tty` | The real controlling terminal: raw mode, `SIGWINCH`; Windows console VT mode | Interactive programs |

The headless backend makes the stack check itself. The renderer's VT output goes through a real emulator, and the emulator's snapshot must equal the canvas the program drew. Input is checked the same way: every byte sequence `encode-key` / `encode-mouse` produce must decode back to the same event.

This supersedes `ag-ui-backend-tui`'s "no `tui-protocol`" note. That repo's tuition painter stays, and a `tui-protocol` painter can sit beside it.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| bubbletea / cl-tuition | `init` / `update` / `view`, messages, commands (`tick`, `quit`, async work) | String-concatenation views (we draw on a cell grid) |
| ratatui / tui-rs | Cell buffer + diff rendering, rectangles, layout constraints | Its widget zoo in wave 1 |
| notcurses / crossterm | Input decoding (CSI-u, SGR mouse, bracketed paste), raw-mode handling, synchronized output (DEC 2026) | Planes and multimedia |
| `terminal-protocol` | `cell`, `style`, `rgb`, key names, mode names | — |

---

## Locked decisions (proposed)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Program shape** | Generic functions `tui-init`, `tui-update (program model message) → (values model command)` and `tui-view (program model) → canvas` | Pure functions; easy to test |
| **Drawing** | A `canvas` of `terminal-protocol:cell`s. `draw-text` / `fill-rect` / `draw-box` / sub-canvas regions work with styles, wide characters and graphemes. | One cell model across the stack |
| **Rendering** | Diff the previous canvas against the next, emit the minimal CUP/SGR/text, and wrap the frame in synchronized output (DEC 2026) when the terminal supports it | Flicker-free over slow links |
| **Input** | A pure-Lisp decoder for the bytes a terminal sends: legacy and xterm-modified keys, SS3, CSI-u (Kitty keyboard), SGR / X10 mouse, bracketed paste, focus in/out | The inverse of `encode-key`; round-trips are the test |
| **Messages** | `key-message` (key name, text, modifiers, action), `mouse-message`, `paste-message`, `focus-message`, `resize-message`, `tick-message`, plus user messages sent with `tui-send` | Key names are `terminal-protocol`'s W3C names |
| **Commands** | `:quit`, `(tick seconds)`, `(batch …)`, `(task function)`, where the function runs off the UI thread and its result comes back as a message | As in bubbletea; no callbacks into the view |
| **Loop** | `run-tui (program &key backend)` owns its thread. The backend supplies bytes in, bytes out, size, and modes on start and stop (alt screen, cursor, mouse, bracketed paste). | The backend is only the transport |
| **Errors** | `tui-error` → `tui-backend-error`; a condition in `tui-update` restores the terminal before it propagates | A crash must not leave the tty in raw mode |

---

## Repo layout

| Repo / system | Role |
|---------------|------|
| [`tui-protocol`](https://github.com/egao1980/tui-protocol) (`stack-tui`) | Program GFs, messages, commands, canvas, renderer (diff → VT), input decoder, `run-tui` |
| [`tui-backend-terminal`](https://github.com/egao1980/tui-backend-terminal) | Headless backend on any `terminal-protocol` backend: `make-headless-tui`, `tui-press`, `tui-screen`, `tui-snapshot` |
| [`tui-backend-tty`](https://github.com/egao1980/tui-backend-tty) | Real terminal: termios raw mode + `SIGWINCH` (Unix), console VT mode (Windows), via a small C library cross-built with Zig |

---

## Protocol surface (sketch)

```lisp
;;; Program
(defgeneric tui-init (program))                        ; → (values model command)
(defgeneric tui-update (program model message))        ; → (values model command)
(defgeneric tui-view (program model))                  ; → canvas
(defun run-tui (program &key backend alt-screen mouse)) ; → final model

;;; Canvas
(defun make-canvas (cols rows))
(defun draw-text (canvas x y string &key style clip))  ; → x after the text (wide chars count 2)
(defun fill-rect (canvas x y w h &key char style))
(defun draw-box (canvas x y w h &key style title))
(defun sub-canvas (canvas x y w h))                     ; view into a region, clipped

;;; Rendering and input (pure, usable without a backend)
(defun render-diff (old new &key synchronized))        ; → octets
(defun make-input-decoder ())
(defun decode-input (decoder octets))                  ; → messages; holds partial sequences

;;; Backend
(defclass tui-backend () ())
(defgeneric backend-start (backend &key alt-screen mouse))  ; → (values cols rows)
(defgeneric backend-stop (backend))
(defgeneric backend-read (backend &key timeout))       ; → octets | empty | NIL
(defgeneric backend-write (backend octets))
(defgeneric backend-size (backend))
```

---

## Non-goals (wave 1)

- A widget library beyond boxes, text, lists and progress bars. Widgets compose canvases and can grow later.
- Layout engines (flexbox / constraints), which are P1
- Images in TUIs (Kitty graphics through the canvas), which is P1 once `image-protocol` lands

---

## Implementation tasks

- [ ] Brief lock — this doc
- [ ] `tui-protocol`: canvas, renderer, input decoder, loop, messages, commands + Rove
- [ ] `tui-backend-terminal`: headless driver on `terminal-protocol`; canvas ⇄ emulator snapshot and `encode-*` ⇄ decoder round-trips on both terminal backends
- [ ] `tui-backend-tty`: raw mode / console mode C shim, overlays, a smoke test on a pty (`pty-protocol`)
- [ ] Cookbook `cookbooks/tui.md`

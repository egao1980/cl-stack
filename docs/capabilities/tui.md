# tui-protocol (P2) — terminal user interfaces

**Issues:** [#274](https://github.com/egao1980/cl-stack/issues/274) · terminal [#264](https://github.com/egao1980/cl-stack/issues/264)
**Status:** brief **draft**. Wave 1 shipped: [`tui-protocol`](https://github.com/egao1980/tui-protocol) 0.1.0 (`stack-tui`: init / update / view over a cell canvas) + [`tui-backend-terminal`](https://github.com/egao1980/tui-backend-terminal) 0.1.0 (headless, on any `terminal-protocol` emulator: `make-headless-tui`, `tui-type`, `tui-press`, `tui-wait-for`). No cookbook yet; see the repo READMEs.

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
| [`tui-backend-tty`](https://github.com/egao1980/tui-backend-tty) | Real terminal: termios raw mode + `SIGWINCH` (Unix), console VT mode (Windows), CFFI into libc / kernel32 (locked below) |

---

## `tui-backend-tty` (locked)

Contract: [`egao1980/tui-backend-tty`](https://github.com/egao1980/tui-backend-tty) — skeleton plus the tests that define it (harness plan H1).

### Natives: CFFI into the system libraries (no C shim)

The C shim proposed earlier is dropped. The backend calls libc (Unix) and kernel32 (Windows) through CFFI. The package is source-only: no Zig build, no `:cl-repo` overlays, no `asdf-native`, no cffi-grovel.

Why this has less build risk:

- **Nothing to cross-build or publish per platform.** A shim needs `natives.yml`, four overlays (linux amd64/arm64, darwin arm64, windows amd64), `publish-native-package` and an ABI check. The canned `test-system.yml` / `publish-source.yml` cover the source-only package.
- **No struct layouts.** `struct termios` differs (60 bytes on glibc, 72 on macOS, with different flag values). The backend never reads it: it is an opaque buffer of at least 256 bytes passed to `tcgetattr`, copied, passed to `cfmakeraw` and then `tcsetattr`. `cfmakeraw` exists in glibc, musl and macOS libc.
- **Few constants, all ABI-stable.**

  | Constant | Linux (amd64, arm64) | macOS |
  |----------|----------------------|-------|
  | `TIOCGWINSZ` | `#x5413` | `#x40087468` |
  | `SIGWINCH` | 28 | 28 |
  | `TCSANOW` | 0 | 0 |

  `struct winsize` is four `unsigned short`s (`ws_row`, `ws_col`, …) on both. The Linux values were checked against zig's glibc headers and the macOS ones on macOS 26.
- **The Windows console ABI is fixed:** `CONSOLE_SCREEN_BUFFER_INFO` (22 bytes), `INPUT_RECORD` (20 bytes; `KEY_EVENT_RECORD` holds `bKeyDown`, repeat, vk, scan, `UnicodeChar`, control state).
- **cffi-grovel is rejected** because it needs a C toolchain on the consumer's machine.

### Unix

| Step | Calls |
|------|-------|
| Terminal check | `isatty(input)` first, then `isatty(output)`. A non-terminal signals `tty-not-a-terminal` (`:stream` `:input` / `:output`) before any state changes. |
| Raw mode | Save the termios buffer, then `cfmakeraw` on a copy and `tcsetattr(TCSANOW)`. That gives `-icanon -echo -isig -iexten -opost`, `cs8`, `VMIN=1 VTIME=0`. The renderer positions with CUP, so `-opost` is safe. |
| Size | `ioctl(output, TIOCGWINSZ)` on every `backend-size` call |
| Resize | A `SIGWINCH` handler through the implementation's signal API (SBCL `sb-sys:enable-interrupt sb-unix:sigwinch`). It only sets a flag and wakes the reader. The previous handler is put back on stop. Implementations without a signal API read in slices of 100 ms or less and compare sizes. |
| Read | Wait on the input fd (select(2) on macOS, where poll rejects ttys; SBCL `sb-sys:wait-until-fd-usable` is fine), then `read(2)` up to 4096 bytes. Returns octets, an empty vector on timeout or when a resize woke the wait, and `NIL` at EOF. `EINTR` returns empty. |
| Write | `write(2)` on the output fd until every octet is written, retrying on `EINTR`. No Lisp streams. |

### Windows (10 1809+)

| Step | Calls |
|------|-------|
| Handles | `GetStdHandle(STD_INPUT_HANDLE / STD_OUTPUT_HANDLE)`. When a handle is NULL or `INVALID_HANDLE_VALUE` (as under ConPTY with `STARTF_USESTDHANDLES`), open `CONIN$` / `CONOUT$`. A redirected handle (pipe, file, NUL) fails `GetConsoleMode`, and that signals `tty-not-a-terminal`. |
| Raw mode | Save both console modes and `GetConsoleCP` / `GetConsoleOutputCP`. Input mode: clear `ENABLE_LINE_INPUT` `#x2`, `ENABLE_ECHO_INPUT` `#x4` and `ENABLE_PROCESSED_INPUT` `#x1`; set `ENABLE_VIRTUAL_TERMINAL_INPUT` `#x200` and `ENABLE_WINDOW_INPUT` `#x8`. Output mode: set `ENABLE_VIRTUAL_TERMINAL_PROCESSING` `#x4` and `DISABLE_NEWLINE_AUTO_RETURN` `#x8`. Both code pages become 65001. If VT processing is refused, signal `tty-system-error` (pre-1809). |
| Size | `GetConsoleScreenBufferInfo`, from `srWindow` (not `dwSize`) |
| Read | `WaitForSingleObject(input, timeout)`, then `ReadConsoleInputW`. Key-down `UnicodeChar`s, which carry the VT sequences, are UTF-8 encoded. `WINDOW_BUFFER_SIZE_EVENT` returns empty, so the loop rereads the size. `ReadFile` is not used: it blocks when only non-key records are queued. |
| Write | `WriteFile` on the output handle until every octet is written |

### Restore, resize, errors

- **Restore on any condition.** `run-tui` already calls `backend-stop` in its `unwind-protect`. `backend-stop` restores the saved termios bytes or console modes and code pages exactly. It is idempotent and a no-op when start failed or never ran.
- **Restore on exit.** `backend-start` registers an implementation exit hook (SBCL `sb-ext:*exit-hooks*`) and `backend-stop` removes it. The hook covers an exit that does not unwind `run-tui`'s frame, such as `exit` from another thread. An uncaught error under `--disable-debugger` and SBCL's default `SIGTERM` both unwind and so restore. `SIGKILL` cannot be covered.
- **Resize is a `resize-message`.** The backend wakes `backend-read`. `run-tui` compares `backend-size` after each read and sends `resize-message`. The protocol does not change.
- **Not a tty.** `tty-not-a-terminal` (a `tui-backend-error`) is signalled from `backend-start`, so it propagates out of `run-tui`. `tty-available-p` lets callers pick the headless backend first. No restart is offered: the recovery (choosing another backend) belongs to the caller.
- **OS call failures** signal `tty-system-error` with `:operation` (`:tcsetattr`, `:set-console-mode`, …) and `:code` (errno / `GetLastError`).
- **Out of scope for now:** `SIGTSTP` / `SIGCONT`. Ctrl-Z arrives as a byte, because `-isig`.

### Surface

`tty-backend`, `make-tty-backend &key input output`, `tty-backend-input`, `tty-backend-output`, `tty-backend-active-p`, `tty-available-p`, `tty-not-a-terminal` (`tty-not-a-terminal-stream`), `tty-system-error` (`tty-system-error-operation`, `tty-system-error-code`).

### Tests (CI, no real terminal)

Each test starts a child SBCL (same runtime and core, the source registry of the parent's loaded systems). The child runs `tests/child.lisp` on a pty from `pty-backend-native`: forkpty-style on Linux and macOS, ConPTY on Windows. The terminal state is read with an oracle the backend does not control: `stty -g` / `stty -a` on Unix, `GetConsoleMode` on `CONIN$` / `CONOUT$` on Windows. The checks:

- raw while running, restored exactly on `:quit`
- the first frame reaches the terminal
- a key arrives as a `key-message`
- `pty-resize` gives a `resize-message` and a redraw at the new size
- an error in `tui-update` is restored before the caller's handler runs
- stdin from the null device signals `tty-not-a-terminal :stream :input`
- an uncaught crash that kills the process leaves `stty -g` unchanged. This one runs under `sh` and is **Unix only**.

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
- [x] `tui-backend-tty` contract locked (below): repo, stubs, pty tests
- [ ] `tui-backend-tty` implementation (CFFI raw mode / console mode) passing its pty tests
- [ ] Cookbook `cookbooks/tui.md`

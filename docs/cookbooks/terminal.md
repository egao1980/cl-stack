# Cookbook: headless terminals (`terminal-protocol` + `pty-protocol`)

**Audience:** anyone who wants to drive a terminal program from Lisp: TUI tests, agents that read a screen, recording replay.

| Piece | Package | OCI |
|-------|---------|-----|
| Emulator protocol (`stack-terminal`) | [`terminal-protocol`](https://github.com/egao1980/terminal-protocol) | **0.1.0** |
| Default backend: libghostty-vt 1.0 | [`terminal-backend-ghostty`](https://github.com/egao1980/terminal-backend-ghostty) (+ [`ghostty-vt`](https://github.com/egao1980/ghostty-vt)) | **0.2.0** |
| Pure-Lisp backend | [`terminal-backend-lisp`](https://github.com/egao1980/terminal-backend-lisp) | **0.1.0** |
| PTY protocol (`stack-pty`) | [`pty-protocol`](https://github.com/egao1980/pty-protocol) | **0.1.0** |
| PTY backend: forkpty / ConPTY | [`pty-backend-native`](https://github.com/egao1980/pty-backend-native) | **0.1.0** |

Briefs: [terminal.md](../capabilities/terminal.md) (#264), [pty.md](../capabilities/pty.md) (#270). Every example below runs as written on both terminal backends. They're checked against a real `sh` on a real pty.

```lisp
(asdf:load-system "terminal-backend-ghostty")   ; or "terminal-backend-lisp"
(asdf:load-system "pty-backend-native")         ; only for sections 5–6

(defun utf8 (string) (babel:string-to-octets string :encoding :utf-8))
```

The emulator is fed **octets**, the bytes a program writes, and splits across reads are fine. Nothing here opens a window: the screen is data.

---

## 1. First terminal

```lisp
(stack-terminal:with-terminal (term :cols 40 :rows 5)
  (stack-terminal:terminal-feed term (utf8 (format nil "Hello, ~C[1;32mworld~C[0m!" #\Esc #\Esc)))
  (list (stack-terminal:terminal-text term)
        (stack-terminal:cursor-x (stack-terminal:terminal-cursor term))))
;; ⇒ ("Hello, world!" 13)
```

`terminal-text` gives the viewport as plain text. With the ghostty backend, `:format :vt` or `:html` together with `:region :screen` gives styled output.

## 2. Cells and styles

```lisp
(stack-terminal:with-terminal (term :cols 20 :rows 2)
  (stack-terminal:terminal-feed term (utf8 (format nil "~C[1;31mERR~C[0m ok" #\Esc #\Esc)))
  (let* ((row (aref (getf (stack-terminal:terminal-snapshot term) :cells) 0))
         (style (stack-terminal:cell-style (aref row 0))))
    (list (stack-terminal:style-bold style)        ; ⇒ T
          (stack-terminal:style-foreground style)  ; ⇒ #S(RGB :R 204 :G 102 :B 102)
          (stack-terminal:style-bold (stack-terminal:cell-style (aref row 4))))))  ; ⇒ NIL
```

`terminal-snapshot` returns `:lines`, `:cells` (a vector of rows of `cell`), `:cursor`, `:title`, `:pwd` and `:screen`. All values are plain structs, so `equalp` compares them. Colours are resolved: palette entries come back as `rgb`, and "no colour of its own" is `:default`.

For a renderer, use frames instead (`make-frame`, `frame-update` → `:none` / `:partial` / `:full`, `do-frame-rows … :dirty-only t`, `frame-mark-clean`).

## 3. Testing a TUI without a terminal

Render your program's output into a terminal and assert on the screen, not on escape-sequence soup:

```lisp
(defun draw-box (stream width title)
  (format stream "~C[H+~A+~%" #\Esc (make-string (- width 2) :initial-element #\-))
  (format stream "~C[2;1H|~C[7m~A~C[0m~vT|~%" #\Esc #\Esc title #\Esc width)
  (format stream "~C[3;1H+~A+" #\Esc (make-string (- width 2) :initial-element #\-)))

(rove:deftest box-renders
  (stack-terminal:with-terminal (term :cols 12 :rows 3)
    (stack-terminal:terminal-feed term (utf8 (with-output-to-string (s) (draw-box s 12 "menu"))))
    (let ((snap (stack-terminal:terminal-snapshot term)))
      (rove:ok (equal (first (getf snap :lines)) "+----------+"))
      (rove:ok (stack-terminal:style-inverse          ; the title is reverse video
                (stack-terminal:cell-style (aref (aref (getf snap :cells) 1) 1)))))))
```

To assert on input handling, `encode-key` / `encode-mouse` / `encode-paste` produce the bytes a real terminal would send *in the terminal's current modes*: cursor-key mode, bracketed paste, mouse tracking and format.

## 4. Effects: titles, bells, replies

Programs ask the terminal things (`ESC[6n` = "where is the cursor?") and tell it things (OSC 2 = window title). Those arrive on a **host**:

```lisp
(defclass recording-host (stack-terminal:buffering-host)
  ((titles :initform '() :accessor titles)))

(defmethod stack-terminal:host-title-changed ((host recording-host) term title)
  (push title (titles host)))

(let ((host (make-instance 'recording-host)))
  (stack-terminal:with-terminal (term :host host)
    (stack-terminal:terminal-feed term (utf8 (format nil "~C]2;build: ok~C~C[6n" #\Esc (code-char 7) #\Esc)))
    (list (titles host)                                  ; ⇒ ("build: ok")
          (stack-terminal:terminal-take-replies term)))) ; ⇒ octets of ESC[1;1R
```

The default host is a `buffering-host`, which collects replies for `terminal-take-replies` and ignores everything else. Other effects are `host-bell`, `host-pwd-changed`, `host-clipboard-write` / `-read` (OSC 52; returning NIL denies a read), `host-notify` and `host-prompt-mark` (OSC 133, ghostty only).

**Rules:**
- A host method that signals doesn't unwind through the parser. `terminal-feed` finishes, then signals `terminal-host-error` with a `continue` restart.
- Feeding the *same* terminal from its own host method signals `terminal-reentrant-feed`. Feeding another terminal is fine.

## 5. A real program on a PTY

The emulator parses bytes and the pty carries them. Three small helpers do all the glue:

```lisp
(defun pump (pty term &key (timeout 0.1))
  "Move what PTY has written into TERM and answer TERM's replies.
→ NIL once the program has closed its side."
  (loop
    (let ((chunk (stack-pty:pty-read pty :timeout timeout)))
      (cond ((null chunk) (return nil))             ; EOF
            ((zerop (length chunk)) (return t))     ; nothing new
            (t (stack-terminal:terminal-feed term chunk)
               (let ((replies (stack-terminal:terminal-take-replies term)))
                 (when (plusp (length replies))
                   (stack-pty:pty-write pty replies))))))))

(defun type-keys (pty term &rest keys)
  "Each KEY is a key name (:enter, :arrow-up, …) or a string of text."
  (dolist (key keys)
    (stack-pty:pty-write pty (if (stringp key) (utf8 key) (stack-terminal:encode-key term key)))))

(defun wait-for (pty term needle &key (timeout 5))
  "Pump until NEEDLE is on screen. → T, or NIL on timeout or exit."
  (let ((deadline (+ (get-internal-real-time) (* timeout internal-time-units-per-second))))
    (loop
      (let ((alive (pump pty term)))
        (when (search needle (stack-terminal:terminal-text term)) (return t))
        (when (or (not alive) (> (get-internal-real-time) deadline)) (return nil))))))
```

Then a session reads like a test script:

```lisp
(stack-terminal:with-terminal (term :cols 60 :rows 10)
  (stack-pty:with-pty (pty '("sh" "-c" "printf '\\033[1mready\\033[0m\\n'; read name; echo \"hi $name\"; stty size")
                           :cols 60 :rows 10)
    (wait-for pty term "ready")        ; ⇒ T
    (type-keys pty term "lisp" :enter)
    (wait-for pty term "hi lisp")      ; ⇒ T
    (wait-for pty term "10 60")        ; ⇒ T   the child sees the pty size
    (stack-pty:pty-wait pty :timeout 5)))  ; ⇒ 0
```

`pty-read` returns octets, an empty vector on timeout, or `NIL` at EOF. `pty-wait` returns `(values code signal)`, or `NIL` on timeout. The command is a list of strings, with no shell unless you ask for one. `:environment` is merged over yours, and `TERM` defaults to `xterm-256color`.

## 6. Resizing

Resize both sides, so the program gets `SIGWINCH` and the emulator resizes its grid:

```lisp
(stack-terminal:terminal-resize term 100 30)
(stack-pty:pty-resize pty 100 30)
```

---

## Choosing a backend

| | `terminal-backend-ghostty` | `terminal-backend-lisp` |
|---|---|---|
| Native code | libghostty-vt 1.0 (MIT), via overlays | none |
| Coverage | full xterm, Kitty keyboard, OSC 52/133, VT/HTML text | VT core: everything in the [parity corpus](https://github.com/egao1980/terminal-parity) |
| Platforms | linux amd64/arm64, darwin arm64, windows amd64 | anywhere CL runs |

Both pass the same 101-fixture corpus, generated from libghostty-vt, fed whole and byte by byte. Where the corpus doesn't decide, the Lisp backend differs: no column reflow, invalid UTF-8 becomes U+FFFD, and 8-bit C1 bytes aren't controls.

## Conditions

| Condition | When | Restarts |
|-----------|------|----------|
| `terminal-closed-error` | any call after `terminal-close` | |
| `terminal-invalid-argument` | bad key, mode, size, format | `use-value` |
| `terminal-unsupported` | backend lacks a feature (`backend-supports-p`) | `use-value` |
| `terminal-host-error` | a host method failed during a feed | `continue` |
| `terminal-reentrant-feed` | feed from inside the same terminal's host method | |
| `pty-spawn-error` | command not found, bad directory, … (`pty-spawn-error-code` = errno) | `use-value` (another command) |
| `pty-io-error` | write after the child is gone | `continue` (drop it) |
| `pty-closed-error` | any call after `pty-close` | |

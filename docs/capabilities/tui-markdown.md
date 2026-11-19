# tui-markdown (H1c): markdown and diff rendering for the terminal UI

**Plan:** [HARNESS-PLAN.md](https://github.com/egao1980/cl-workspace/blob/main/docs/HARNESS-PLAN.md), Track H, row H1 ("markdown and diff rendering")
**Status:** milestone **H1c locked**. The contract is in [`egao1980/tui-markdown`](https://github.com/egao1980/tui-markdown) 0.1.0 (`tui-markdown/tests`, Rove). Every function calls `%not-implemented`. It will be implemented through **team-solve**.

H1b ([tui.md](tui.md#h1b--widgets-locked)) gave `tui-protocol/widgets` styled text runs: `text-run`, `wrap-runs`, `runs-width`, `draw-runs`. It called them "the interface a later markdown / diff renderer emits" but had no parser. H1c adds two renderers. Both turn text into **lines of runs** at a width in cells, with wide characters and combining marks handled.

- **Markdown:** `parse-markdown` covers a CommonMark subset plus GFM tables and `~~strike~~`. `render-markdown` lays out lines of runs. A `markdown-stream` re-renders while model text streams in. Completed blocks never change, so they never flicker.
- **Diffs:** `render-diff-lines` takes a [`diff-protocol`](diff.md) 0.2.0 value or unified diff text. It renders file headers with +/− counts, line numbers, +/− colouring, word-level highlighting inside changed lines, wrapping at the width, and an optional side-by-side layout.

A viewport (`(make-instance 'w:viewport :lines lines :wrap nil)`) or `draw-runs` puts the lines on screen. The transcript of `cl-stack-code` (H3) shows assistant text through a `markdown-stream` and tool edits through `render-diff-lines`.

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| **Codex CLI** (`codex-rs/tui`: `markdown_stream.rs`, `diff_render.rs`) | Streaming is gated on newlines: only complete source lines decide what is committed, and a width change re-renders from the one source string. Diff rows are `number sign content` with a gutter as wide as the largest line number, `⋮` between hunks, continuation rows aligned under the content, cell-aware wrapping, tabs as spaces, and a header path with `(+N -M)` | Rendered history committed to terminal scrollback (we keep lines in a viewport). Syntect highlighting built in (we take a hook). Its verbs ("Edited", "Added"), and its fg+bg palette tiers by colour depth |
| **pi** (`pi-tui` `Markdown`, `marked` lexer) | Headings: H1 bold underline, H2 bold, H3+ keep their `###`. Quote bar `│ ` with italic text. Box-drawing tables with bold headers, shrunk to fit and wrapped, with a fallback when too narrow. Links styled, as OSC 8 hyperlinks, with ` (url)` unless the text is the url. Inline code without backticks. A `highlightCode(code, lang)` hook. A partial closing fence is hidden while streaming. Rendered blocks are cached | `marked` (JavaScript). Fences drawn around code. LaTeX, HTML comments, CJK-specific emphasis rules |
| **Claude Code** (Ink, `marked`) | Completed messages are static and only the streaming message re-renders, which became our committed vs live lines. Structured diffs with line numbers and word-level highlighting of changed lines | A React / Ink component tree. Background-colour line fills as the only add/remove cue (our default theme uses the 16-colour foreground plus inverse for words, so it reads on any terminal; a theme can add backgrounds) |
| **opencode v2** (opentui) | Unified or split diff chosen by width (`:auto`, 120 cells) | tree-sitter for markdown and code (not on cl-stack; the Lisp outline exists, other languages later) |
| CommonMark 0.31 spec, GFM spec | Block / inline structure, the delimiter-run emphasis algorithm, code spans, inline links, autolinks, GFM tables | Everything listed under "Not supported" below |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Home** | A new first-party repo, [`egao1980/tui-markdown`](https://github.com/egao1980/tui-markdown) (package `tui-markdown`, nickname `stack-tui-md`), created the same day (`create-first-party-repo.sh`). One system holds both renderers. It depends on `tui-protocol/widgets`, `terminal-protocol` and `diff-protocol` | (1) The diff renderer needs `diff-protocol`. cl-repo maps a secondary system (`tui-protocol/markdown`) to its primary package, so placing the renderer in tui-protocol would add `diff-protocol` to every tui-protocol install. (2) A markdown parser is about 1k lines of content code with its own release pace, not protocol surface. (3) AGENTS.md: a new renderer or backend gets its own repo. (4) Both renderers share the run helpers (`break-runs`, `expand-tabs`), the theme roles and the overlay rule, so they live together. `diff-protocol` has no dependencies, so markdown-only users pay for nothing else |
| **Own markdown parser** | Written in tui-markdown. `doc-extract-protocol:parse-markup` is not reused | The stack's only markdown reader (`doc-extract-protocol`'s `parse-markup`, behind `doc-extract-render`) reads CommonMark blocks into the extracted-document model. It has sections and text blocks, but no inline spans (emphasis, code, links), no source positions and no incremental use, and it brings `schema-protocol`. No egao1980 repo or `cl-stack-systems` import has an inline-level parser. The AST here is plain data, so doc-extract can adopt it later (follow-up issue) |
| **AST** | Plain lists, compared with `EQUAL`: blocks `(:paragraph inlines)`, `(:heading level inlines)`, `(:code-block language lines)`, `(:block-quote blocks)`, `(:bullet-list tight items)`, `(:ordered-list start delimiter tight items)`, `(:table alignments header rows)`, `(:thematic-break)`; inlines are strings, `(:emph …)`, `(:strong …)`, `(:strike …)`, `(:code s)`, `(:link url …)`, `(:soft-break)`, `(:hard-break)`. Adjacent strings are merged | Easy to test exactly, easy to serialize, and nothing to subclass. Renderers walk lists |
| **Subset** | CommonMark blocks and inlines as listed in the contract's `src/markdown.lisp` header, with **no lazy continuation lines, no setext headings, no indented code blocks, no reference links, no HTML, no images, no entities**. Tabs in leading whitespace become spaces (4-column stops) | Models rarely use what was left out. Leaving out laziness, setext headings and reference definitions is what makes streaming exact: a later line can never change an earlier block (see Streaming). Unsupported syntax stays visible as text, so nothing is lost |
| **Output** | A line is a list of `w:text-run`s. A string or a block list goes in and a list of lines comes out. Run boundaries are not part of the contract; tests compare strings and per-character styles | Matches H1b's viewport and `draw-runs`. Implementations stay free to merge or split runs |
| **Styles** | A **theme** is a plist role → `tp:style`, with 22 roles (`+theme-roles+`). Missing roles fall back to `default-theme-style`. Nesting is `overlay-style`: an OVER attribute that is not the default replaces BASE's (colours, true booleans, the underline kind, the hyperlink) | One rule for emphasis in headings, code in links, quoted text, header cells and word highlights. The defaults use only attributes and palette colours 1, 2, 4 and 6, so they work on every terminal (Codex's ANSI-16 tier) |
| **Links** | The text gets `:link` and `(:hyperlink url)`, which the tui-protocol renderer emits as OSC 8. With `:show-urls` (default T), ` (url)` follows in `:link-url` unless the text is the url | Terminals without OSC 8 still show where a link goes. Click-through works where OSC 8 is supported |
| **Code blocks** | No fences shown. The text is indented two cells and broken by cells, not words. Tabs use 4-cell stops. The `:highlight` hook is `(funcall hook language lines)` and returns lines of runs, or NIL for the default `:code-block` style. Highlighting is a hook only | There is no highlighter in the stack yet, and a hook lets `lisp-source-protocol` or any other tokenizer plug in. Breaking by cells keeps code exact, with no reflow |
| **Tables** | Box-drawing tables with natural column widths. When the table is too wide, the widest column (leftmost on ties) gives up one cell at a time, down to min(natural, 3). Cells word-wrap. When even that is too wide, each row becomes ` \| `-joined text | Tables are "best effort" in the plan. pi's layout, with a fallback that never overflows |
| **Streaming** | `markdown-stream` (append / finish / lines / committed-count / width). Completion is decided on **complete lines only**: every top-level block except the last is committed and rendered once. The last block plus the partial line is live and re-rendered on each query. A partial line that could become the closing fence of an open code block is hidden | No completed block ever flickers. A partial line cannot complete a block: on its own, `#` would be an empty heading that ends the paragraph above it, then `#tag` would rejoin that paragraph. Showing the partial line avoids Codex's line-at-a-time feel for long paragraphs. The test feeds a document one character at a time and checks that the committed lines are always a prefix of the final rendering |
| **Diff input** | A `diff-protocol:diff` goes through `(diff:render-diff d :unified nil)` first. A string is read as unified text: `git diff`, `diff -u` or model output | One path for values and text. Text never signals, because model output is often malformed. Hunk bodies are read using the `@@` counts, so a removed `-- x` line is not taken for a header |
| **Diff layout** | Unified: `number sign content`, where the number is old for `-` and new otherwise. The gutter is as wide as the largest number in the file. `⋮` marks the gap between hunks and `@@` lines are hidden. File headers read `path +A -R`, or `old → new` for a rename. Git header lines other than index, rename and similarity are shown faint. Split: ⌊(W−1)/2⌋ \| rest around `│`, with old on the left and new on the right, change rows facing each other, and each side wrapped on its own. `:auto` splits at 120 cells | Codex's rows, with opencode's split view. Line numbers come from the hunk headers, so a value and its unified text render identically |
| **Word diff** | Pairs the i-th `-` row of a change block with its i-th `+` row. Tokens are word runs, whitespace runs and single punctuation characters. Uses a minimal token diff from diff-protocol's Myers text engine (one token per line). A pair is highlighted only when the unchanged text is at least half the longer line; otherwise it is plain | The stack's own diff engine, no second LCS. The threshold keeps rewritten lines from looking like confetti, as in Claude Code |
| **Errors** | Renderers are total. Bad arguments signal `type-error`, and an unrenderable diff value propagates `diff:unsupported-content`. The one condition of our own is `markdown-stream-finished` (a `tui-markdown-error`, slot `stream`), signalled by append after finish | Nothing in rendering can be recovered from. A finished stream is a caller bug that handlers may want to tell apart |
| **Threads** | A `markdown-stream` is not thread-safe. Append and query from one thread (the TUI's update) | The H1b widgets have the same rule. Model chunks arrive as `tui-send` messages |

---

## Surface

```lisp
;;; themes (22 roles; defaults in src/theme.lisp)
+theme-roles+                    (default-theme-style role) → style
(theme-style role &optional theme) → style      (overlay-style base over) → fresh style

;;; markdown
(parse-markdown string) → blocks
(render-markdown markdown width &key theme highlight (show-urls t)) → lines
;; highlight: (lambda (language lines) …) → lines | NIL

;;; streaming
(make-markdown-stream &key (width 80) theme highlight (show-urls t)) → markdown-stream
(markdown-stream-append s text) → s          ; markdown-stream-finished after finish
(markdown-stream-finish s) → s               ; idempotent
(markdown-stream-finished-p s)  (markdown-stream-source s)
(markdown-stream-width s)  (setf (markdown-stream-width s) w)
(markdown-stream-lines s) → lines            ; committed, then live
(markdown-stream-committed-count s) → n      ; leading lines that are final

;;; diffs
(render-diff-lines diff width &key (layout :unified) theme (word-diff t) (split-min-width 120)) → lines
;; diff: diff-protocol:diff | unified text; layout :unified | :split | :auto

;;; helpers (both renderers use them)
(break-runs runs width) → lines                ; by cells, no word breaks
(expand-tabs runs &key (tab-width 4)) → runs   ; stops counted in cells

;;; conditions
tui-markdown-error ← markdown-stream-finished (markdown-stream-finished-stream)
```

### Layout rules (summary; the contract's file headers are exact)

Markdown at width W:

- Blocks are separated by one empty line. Paragraphs use `w:wrap-runs`. Headings 1 and 2 drop their markers; headings 3 to 6 keep `### `.
- List markers are `- `, or `N.` / `N)` right-aligned to the widest marker. Loose lists put empty lines between items.
- Quotes are prefixed `│ `. An empty quoted line is a lone `│`.
- Code is indented two cells. A thematic break is `─` × W.
- Every line fits W cells when W ≥ 10.

Diffs at width W:

- Each file section is a header line, then its git header lines, then rows. Sections are separated by one empty line.
- Rows wrap at W − G − 2. Continuation rows are indented G + 2 cells.
- The split layout pads the left pane to its width.

---

## Tests (the contract)

`tui-markdown/tests` has 58 deftests and about 320 assertions:

- **Model level:** an exact `EQUAL` AST for each block and inline rule (CommonMark spec cases for emphasis, code spans and links). Exact rendered strings, plus per-character style **segments** (`(text . style-keys)` with equal neighbours merged), for paragraphs, inline styles, links, headings, lists, quotes, code (hook, wrapping, tabs), breaks, tables (natural, aligned, shrunk, fallback, wide) and diffs (unified, styles, word pairing and threshold, wrapping, CR / no-newline / counts, diff-protocol text and tree values, split, auto, loose text).
- **Streaming:** the visible partial line, the live last block, completion only on complete lines, the hidden partial fence, no second highlight of a committed block, width changes, finish, and the property that, fed one character at a time at two widths, the committed lines always match the final rendering.
- **End to end:** rendered lines in a `viewport` on `tui-backend-terminal`'s headless driver with the pure-Lisp emulator, where exact screen snapshots check markdown, a table with wide characters, a unified diff and a split diff.
- Every expectation was checked against a throwaway prototype before sealing (the prototype is not committed). Against the stubs, all 58 deftests fail.

---

## Not supported / out of scope

- **Markdown:** indented code blocks, setext headings, lazy continuation lines, HTML blocks and inline HTML, reference links and definitions, images (`!` stays text), entities, footnotes, task-list markers, math, and bare-URL autolinks (terminals detect URLs themselves). All of these render as text.
- A built-in syntax highlighter. The hook stays until the stack has a tokenizer: `lisp-source-protocol` for Lisp first.
- Rendering fenced ```` ```diff ```` blocks with the diff renderer. A highlight hook can call `render-diff-lines` already.
- Word-level diffs beyond token LCS (moved-line detection, character-level diffs inside a token), and intra-line highlighting across unpaired rows.
- Background-filled diff lines in the default theme (a theme can set `:bg`), and colour-depth tiers.
- A markdown widget class (the viewport plus `markdown-stream` covers H3). Incremental parsing is also out: the stream may re-parse its whole source on each query, which is O(n²) over a long reply but fine at transcript sizes. An optimization can parse from the last block's start line without changing the contract.
- Copy-friendly raw output (the transcript can keep the source).

---

## Implementation tasks

- [x] Brief: this document
- [x] Repo `egao1980/tui-markdown` created: skeleton on `main`, CI from the canned `test-system.yml` / `publish-source.yml` workflows
- [x] H1c contract: stubs plus the Rove tests, sealed (`.team-solve/task.md`)
- [ ] Implementation through team-solve, passing `tui-markdown/tests`
- [ ] Publish `tui-markdown` 0.1.0 to GHCR, then update QUICKSTART pins
- [ ] Follow-up issue: let doc-extract adopt this parser's AST

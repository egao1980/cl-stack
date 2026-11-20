# markdown-protocol: a CommonMark-subset parser with a plain-list AST

**Status:** **shipped**. [`egao1980/markdown-protocol`](https://github.com/egao1980/markdown-protocol) OCI **0.1.0** (package `markdown-protocol`, nickname `stack-markdown`). No dependencies.

The parser was written for [tui-markdown](tui-markdown.md) (H1c). It moved to its own repo so that a document-extraction protocol does not depend on a terminal-rendering library ([doc-extract-protocol#1](https://github.com/egao1980/doc-extract-protocol/issues/1)). The AST did not change.

| Consumer | Use |
|----------|-----|
| [`tui-markdown`](https://github.com/egao1980/tui-markdown) | Renders the AST as lines of styled runs and streams it (`markdown-stream`). Re-exports `parse-markdown` |
| [`doc-extract-protocol`](https://github.com/egao1980/doc-extract-protocol) | `parse-markup` maps the AST onto the extracted-document model, with inline spans as `annotation-span`s |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Home** | Its own first-party repo with no dependencies | Both a renderer (`tui-markdown`) and a document model (`doc-extract-protocol`) read markdown. Neither should pull in the other's stack |
| **AST** | Plain lists compared with `EQUAL`. Blocks: `(:paragraph inlines)`, `(:heading level inlines)`, `(:code-block language lines)`, `(:block-quote blocks)`, `(:bullet-list tight items)`, `(:ordered-list start delimiter tight items)`, `(:table alignments header rows)`, `(:thematic-break)`. Inlines: strings, `(:emph …)`, `(:strong …)`, `(:strike …)`, `(:code s)`, `(:link url …)`, `(:soft-break)`, `(:hard-break)`. Adjacent strings merged, empty strings dropped | Easy to test exactly and to serialize. Consumers walk lists, with nothing to subclass |
| **Subset** | CommonMark 0.31 blocks and inlines plus GFM tables and `~~strike~~`. Not supported, so left as text: lazy continuation lines, setext headings, indented code blocks, HTML, link reference definitions, images, entities. The rules are in the header of `src/markdown.lisp` | Without lazy lines, setext headings or reference definitions, a later line never changes an earlier block, so a stream can commit completed blocks. Unsupported syntax stays visible as text |
| **Streaming hook** | `parse-markdown-document` also returns the open fence `(char . length)` of a top-level fenced code block left unclosed | A streaming renderer hides a partial closing fence. This needs the parser's state, not a second parse |
| **Errors** | A non-string signals `type-error`. Any string parses | Markdown from models is often malformed. Nothing in parsing can be recovered from |
| **No source positions** | The AST carries none | Not needed by current consumers. Add them in a new function if a consumer needs them, so the AST stays `EQUAL`-comparable |

---

## Surface

```lisp
(parse-markdown string) → blocks
(parse-markdown-document string) → (values blocks open-fence)   ; open-fence: (char . length) | NIL
```

## Non-goals

- Full CommonMark conformance, HTML output, raw HTML.
- Rendering. That is `tui-markdown` for terminals and `doc-extract-protocol`'s `dump-markup` for documents.

## Checklist

- [x] `markdown-protocol` 0.1.0 with the parser and its tests from tui-markdown 0.1.0
- [x] `tui-markdown` depends on it and re-exports `parse-markdown`
- [x] `doc-extract-protocol` `parse-markup` uses it and keeps inline spans

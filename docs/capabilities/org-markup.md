# org-markup: Org-mode text to the markdown AST

**Status:** **shipped**. [`egao1980/org-markup`](https://github.com/egao1980/org-markup) OCI **0.1.0** (package `org-markup`, nickname `stack-org`). No dependencies.

It parses a subset of Org-mode (org-element 9.x) into [markdown-protocol](markdown.md)'s AST, `:image` included. As a result, [html-markdown](html-markdown.md), [tui-markdown](tui-markdown.md) and [doc-extract-protocol](https://github.com/egao1980/doc-extract-protocol) render Org with no changes. First consumer: [cl-blog](https://github.com/egao1980/cl-blog), where posts may be `.org`.

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **AST** | markdown-protocol's, unchanged. Org-only allowances: a table `header` may be NIL. `_underline_` is `:emph` | One renderer per output, not one per input syntax |
| **Name** | `org-markup`, not `org-protocol` | `org-protocol` is Emacs' URL handler (`org-protocol://`) |
| **Metadata** | `(parse-org s)` → `(values blocks keywords)`. KEYWORDS: `#+KEY: value` lines as an alist in source order, keys downcased; affiliated keywords (`caption`, `name`, `attr_*`, …) dropped | Post metadata (`#+TITLE`, `#+DATE`, `#+FILETAGS`) without a second parse |
| **Subset** | Headings (TODO, priority, tags stripped; `noexport` / COMMENT subtrees dropped), drawers and comments dropped, SRC / EXAMPLE / QUOTE / VERSE / special blocks, fixed width, rules, tables with alignment cookies, lists (description items, counters), Org emphasis rules, `[[link][desc]]`, `[[image.png]]`, plain links. The rules are in the header of `src/org.lisp` | What blog posts and notes use. Anything else stays text |
| **Errors** | A non-string signals `type-error`. Any string parses, in linear time, with nesting capped at 64 | Notes are hand-written and often unfinished |

## Non-goals

- Agenda, babel execution, export options, footnotes, LaTeX, internal links (`[[*Heading]]` stays a plain link).

# html-markdown: the markdown AST as HTML

**Status:** **shipped**. [`egao1980/html-markdown`](https://github.com/egao1980/html-markdown) OCI **0.1.0** (package `html-markdown`, nickname `stack-html-markdown`). Depends on [markdown-protocol](markdown.md) 0.2.0 and [html-protocol](html-protocol.md) 0.1.1.

It is the HTML counterpart of [tui-markdown](tui-markdown.md). It turns the markdown-protocol AST, from markdown or from [org-markup](org-markup.md), into html-protocol nodes. First consumer: the [cl-blog](https://github.com/egao1980/cl-blog) generator.

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Output** | html-protocol nodes (`render-markdown`), or a string (`markdown-html`). CommonMark reference-renderer shapes: a newline after each block, tight items without `<p>`, `class="language-X"` on code | Callers put the nodes in their own trees (pages, canvases) and the serializer does the escaping |
| **Tables** | `align="left/right/center"` attributes, not `style=` | Strict-CSP pages (canvas-protocol) forbid inline styles |
| **URLs** | A `:url` function `(url kind)` → url or NIL. The default `safe-url` reads URLs as a browser does, then drops `javascript:`, `vbscript:`, `file:` and non-image `data:`. NIL renders a link as its text and an image as its alt | Rewriting (site-relative paths, links between posts) and safety are the same hook |
| **Headings** | `:heading-offset` (capped at 6), `:heading-ids` (`heading-slug`, unique per call) | A page's title is its h1; post headings link by anchor |
| **Unknown nodes** | `unknown-markdown-node` with `continue` (render nothing) and `use-value` (nodes instead) | The AST grows (org-markup, later extensions); a caller decides |

## Surface

```lisp
(render-markdown markdown &key heading-offset heading-ids url) → nodes  ; string or blocks
(markdown-html markdown &rest keys) → string
(render-inlines inlines &key url) → nodes
(plain-text inlines) → string
(heading-slug text) → string
(safe-url url kind) → string | NIL
```

# highlight-protocol: build-time syntax highlighting

**Status:** **implemented, publish pending**. [`egao1980/highlight-protocol`](https://github.com/egao1980/highlight-protocol) **0.1.0** (package `highlight-protocol`, nickname `stack-highlight`), PR [highlight-protocol#1](https://github.com/egao1980/highlight-protocol/pull/1). Depends on [html-protocol](html-protocol.md) 0.1.1 and [css-protocol](css.md) 0.1.0.

Lexers turn source text into `(class . text)` tokens whose texts concatenate to exactly the input. The tokens render as HTML spans with a light / dark stylesheet, or as per-line token lists for a styled-run renderer.

- **First consumer:** [cl-blog](https://github.com/egao1980/cl-blog), for `#+begin_src lisp` and ```` ```python ```` blocks.
- **Next:** [tui-markdown](tui-markdown.md)'s code-block `:highlight` hook, so cl-stack-code's transcript highlights code ([tui-markdown#4](https://github.com/egao1980/tui-markdown/issues/4)).

---

## Prior art

| Source | Took | Left |
|--------|------|------|
| **Pygments** / **Chroma** | Lexers registered by name and aliases. A token stream that round-trips the input. `highlight(code, lexer, formatter)` as lexing followed by rendering. Short CSS classes | A token-type hierarchy (`Name.Builtin.Pseudo`), so we use one flat, fixed set. Regex state machines. Guessing the language from content |
| **highlight.js** | `hljs-*`-style prefixed classes. Theme CSS kept apart from the markup. Language aliases as markdown writers type them (`sh`, `yml`, `py`) | Runtime highlighting in the browser (ours runs at build time). Auto-detection |
| **Rouge** | Formatters as a separate layer over one token stream | Ruby |
| **Emacs font-lock** (`lisp-mode`, `sh-mode`) | Highlighting Lisp by operator position: `def…` and `with-…` forms, the defined name, docstrings, `&optional` in the type face. Shell keywords only where a command starts | Regexes over the buffer, which cannot tell data lists from code |
| **colorize** (CL, Quicklisp) | Lisp, Scheme and Emacs Lisp from one scanner | Writing HTML strings directly, with no token API and no stylesheet model |
| **GitHub Primer** syntax colours | The light and dark palettes, checked for 4.5:1 contrast | — |
| **tree-sitter**, **TextMate / Shiki** grammars | — | Not on the stack: native parsers, or Oniguruma and JSON grammars. Far beyond what blog code blocks need |

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Home** | A new first-party repo, `egao1980/highlight-protocol`. One system holds lexers, HTML and CSS. It depends on html-protocol and css-protocol, both small and pure Lisp, and on nothing third-party | Highlighting is its own capability with its own release pace. A secondary system would not save a TUI consumer anything, because cl-repo maps a secondary to its primary package. HTML nodes and a css-protocol stylesheet are what cl-blog builds pages from |
| **Tokens** | A list of conses `(class . text)`. TEXT is never empty, neighbours never share a class, and the texts concatenate to exactly the input | Easy to compare with `EQUAL` in tests. Maps one to one onto spans and onto styled runs. Normalised output keeps golden tests stable |
| **Classes** | A fixed, documented set, `+token-classes+`: `:plain :keyword :builtin :function :type :symbol :variable :constant :string :doc :number :comment :operator :punctuation :meta :property :inserted :deleted :header :hunk`. Each lexer file's header says what it marks with each class | Themes and renderers can be total over a closed set. Twenty classes cover the six languages without a hierarchy |
| **Extending** | `lexer` is a CLOS class with a name and aliases, and `lexer-tokens` is the generic function a subclass implements. `register-lexer` adds it to a registry keyed by lowercase name and alias. There is no `define-lexer` macro | A lexer is a function over a string, not a DSL. `register-lexer` with the same name replaces the old lexer, so reloading works |
| **Lookup** | `find-lexer` matches the designator's **first word**, case-insensitive (`"lisp :results output"`, `"python {.x}"`, `:lisp`). NIL or a blank string means plain text | Org `#+begin_src` and markdown info strings carry more than the language |
| **Unknown languages** | `unknown-language` is signalled with `signal`. It is a condition, not an error, and carries a `use-value` restart that takes a lexer or a name. Unhandled, the text is plain | Unknown fences are common in blog posts and must not break a build. A caller who cares can map `"clojure"` to the Scheme lexer, or log it |
| **Own scanners** | Every lexer is a hand-written single pass over the string, with no regex library. Parsers already on the stack (lisp-source-protocol's Eclector CST, json-protocol, yaml-protocol, diff-protocol) are not used | Highlighting needs lexical classes over the exact text of fragments: truncated, invalid or mixed. The parsers return values, drop whitespace, signal on malformed input, and lisp-source-protocol brings Eclector (third party). No values are produced here, so this is not a second JSON / YAML implementation. A lexer backed by lisp-source-protocol can be registered later without an API change |
| **Robustness** | Every lexer is total on strings: it never signals on content, and unterminated strings, comments, heredocs and `\|…\|` run to the end. Lexing is linear. Nesting is a heap stack, not recursion | Input is hand-written posts and, for the TUI, streaming model output |
| **Lisp heuristics** | Special operators and CL macros are `:keyword`, and CL functions `:builtin`, **only as the first element of a code list**. Both tables come from the `COMMON-LISP` package at load time. Quoted lists, vectors, feature expressions, lambda lists and `defclass` slot lists are data. Definers name their second element (`:function` / `:type` / `:variable`, and `(setf foo)` names `foo`). Docstrings are found by position. Emacs Lisp and Scheme add their own tables, `[ ]`, `?c`, `#t` / `#f` and `#;` | Matches what readers expect from Emacs, without tagging `list` in `(defun f (list) …)` as a function. The 978 CL symbols are fixed by the standard, so the tables need no copy |
| **HTML** | `highlight-nodes` returns html-protocol nodes: a text node for `:plain` and `<span class="hl-CLASS">` for the rest. `highlight-html` serializes them with html-protocol's own writer, which does the escaping. `:prefix` changes `hl-`. `:wrap t` adds `<pre><code class="language-L">` | cl-blog and html-markdown build node trees, so the nodes slot in. No second escaper. Callers usually make the `<pre><code>` themselves |
| **CSS** | `highlight-stylesheet` returns a css-protocol stylesheet: the `--hl-*` custom properties of a `css-theme` (light under `:root`, dark under `prefers-color-scheme`, optional `toggle-attribute`), then one `.hl-CLASS { color: var(--hl-CLASS) }` rule per class. Comments and docs are italic, diff headers bold, inserted and deleted lines get backgrounds. `:theme nil` leaves the properties to the page, and `highlight-palette` returns the colours as alists for the page's own `make-css-theme` | It merges with a site stylesheet (`css:merge-stylesheets`) and prunes with `css:used-rules`, which is how cl-blog builds `style.css`. The fixed `--hl-*` names let a page retheme without touching the rules |
| **Palette** | GitHub Primer syntax colours. Every foreground has at least 4.5:1 contrast on `#f3f3f3` / `#fff` (light) and `#262a31` / `#16181d` (dark). Those are cl-blog's code backgrounds (`--engels-code-bg`) and page colours | Readable in both schemes on the blog as it is |
| **TUI shape** | `token-lines` splits tokens at newlines, and `tokenize-lines lines language` returns one token list per input line: tui-markdown's hook input and output shape. The class → `tp:style` mapping belongs to tui-markdown | The terminal renderer stays a thin mapping, and highlight-protocol does not depend on tui-protocol |
| **Threads** | `tokenize` keeps no global state beyond read-only tables. The registry is a plain hash table: register at load time | Same rule as other stack registries |

---

## Surface

```lisp
;;; tokens
+token-classes+
(tokenize text language) → ((class . text) …)          ; language: lexer | name | alias | NIL
(tokenize-lines lines language) → ((token …) …)        ; one list per input line
(token-lines tokens) → ((token …) …)

;;; lexers
(find-lexer language) → lexer | NIL
(register-lexer lexer) → lexer
(list-lexers) → (lexer …)
(lexer-tokens lexer text) → tokens                     ; GF, one method per lexer class
lexer (lexer-name, lexer-aliases)
plain-lexer  lisp-lexer (lisp-lexer-dialect: :common-lisp :emacs-lisp :scheme)
python-lexer  shell-lexer  console-lexer  json-lexer  yaml-lexer  diff-lexer

;;; HTML
(highlight-nodes text language &key (prefix "hl-")) → html-protocol nodes
(highlight-html text language &key (prefix "hl-") wrap) → string

;;; CSS
(highlight-stylesheet &key (prefix "hl-") (theme t) (selector ":root") toggle-attribute) → css:stylesheet
(highlight-css &key (pretty t) prefix theme selector toggle-attribute) → string
(highlight-theme &key (selector ":root") toggle-attribute) → css:css-theme
(highlight-palette &optional (scheme :light)) → (("hl-keyword" . "#cf222e") …)

;;; conditions
unknown-language (condition; unknown-language-name; restart use-value)
```

| Lexer | Aliases |
|-------|---------|
| `common-lisp` | lisp, cl, commonlisp, asd, lsp |
| `emacs-lisp` | elisp, el |
| `scheme` | scm |
| `python` | py, python3 |
| `shell` | sh, bash, zsh, ksh |
| `console` | shell-session, sh-session (prompts `:meta`, commands as shell, output `:plain`) |
| `json` | jsonc (`//` and `/* */` comments) |
| `yaml` | yml |
| `diff` | patch, udiff (`@@` counts decide which `---` / `+++` lines are changes) |
| `text` | plain, txt, plaintext |

### Dropping it into a site (cl-blog)

```lisp
;; a code block
(html:make-html-element "pre" :children
  (list (html:make-html-element "code"
          :attributes (list (cons "class" (format nil "language-~A" lang)))
          :children (stack-highlight:highlight-nodes code lang))))

;; the stylesheet: theme toggle as the site's
(css:merge-stylesheets (engels:stylesheet)
                       (css:css-theme-stylesheet (blog-theme))
                       (stack-highlight:highlight-stylesheet :toggle-attribute "data-theme")
                       (css-backend-lass:compile-lass-file …))
```

---

## Tests

`highlight-protocol/tests` (Rove, 1107 assertions):

- **Protocol:** the class list, every alias, designator forms, user lexers with normalisation and replacement, `unknown-language` both unhandled and with `use-value`, `token-lines` and `tokenize-lines`.
- **Golden tokens** per lexer: exact token lists and class checks. Lisp covers definitions, docstrings, reader macros, data lists and dialects. Python covers docstrings, decorators and attributes. Shell covers command position, heredocs, `$…` inside strings and console prompts. JSON covers keys. YAML covers keys, block scalars and flow. Diff covers counted hunks and loose snippets.
- **Robustness:** every prefix of every sample through every lexer, malformed fragments, and 400 fuzz strings per lexer. Each run must not signal, must round-trip, and must use known classes. Inputs of 200k characters (deep nesting, unterminated runs, many heredocs) must lex under a time bound; they take about 0.1 s each.
- **Rendering:** exact HTML with escaping, prefix, wrap and an escaped language attribute; nodes; palettes for both schemes; stylesheet rules and options; pruning with `css:used-rules` over a page.

## Not supported (0.1.0)

- Other languages: C, JavaScript / TypeScript, Rust, Go, TOML, HTML / XML, SQL, Clojure, Makefile. These are follow-ups, each one lexer class.
- Language auto-detection, line numbers, highlighting of single lines (`hl_lines`).
- Embedded languages: f-string and `${…}` internals beyond shell variables, heredoc bodies, markdown inside docstrings, `#.` code.
- Semantic highlighting: local functions, macro-defined operators from other packages, Python soft keywords (`match`, `case`, `type`).
- The terminal renderer ([tui-markdown#4](https://github.com/egao1980/tui-markdown/issues/4)).

## Implementation tasks

- [x] Brief: this document
- [x] Repo `egao1980/highlight-protocol`: canned `test.yml` (three OSes) and `publish-checkout.yml`
- [x] 0.1.0: lexers, HTML, CSS, Rove suite ([highlight-protocol#1](https://github.com/egao1980/highlight-protocol/pull/1))
- [ ] Publish `highlight-protocol` 0.1.0 to GHCR, then the QUICKSTART pin
- [ ] cl-blog: highlight code blocks and add the stylesheet
- [ ] tui-markdown: a highlight hook over `tokenize-lines` ([tui-markdown#4](https://github.com/egao1980/tui-markdown/issues/4))

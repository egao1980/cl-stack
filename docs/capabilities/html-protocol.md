# html-protocol (P1)

**Status:** **shipped** — [`egao1980/html-protocol`](https://github.com/egao1980/html-protocol) OCI **0.1.0** (`stack-html`) + `html-backend-plump` **0.1.0** (plump **2.0.0**).

Lenient HTML parse / serialize / tree query. **Not** XML Infoset — that is [`xml-protocol`](xml-protocol.md).

**CSS/JS stay opaque text.** `<style>` / `<script>` / `style=` / `href` / `src` are not interpreted. No cascade, no VM.

```lisp
(asdf:load-system "html-backend-plump")
(let* ((doc (stack-html:parse "<div class='x'><p>hi</p></div>"))
       (p (first (stack-html:select doc "div.x p"))))
  (stack-html:element-text p))
```

`select` subset: `tag`, `#id`, `.class`, descendant, `>`.

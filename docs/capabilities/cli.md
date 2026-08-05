# cli-protocol (P2)

**Issues:** [#103](https://github.com/egao1980/cl-stack/issues/103)  
**Status:** brief **locked** — CLOS protocol + backends (not “pin clingon alone”)

One app DX for command-line tools: define commands/options, parse `argv`, run handlers, emit help/version. Multiple parser backends; cookbooks teach the protocol.

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md) (CLI → protocol + pin).

---

## Prior art (shape targets)

| Ecosystem | Library | What we steal |
|-----------|---------|---------------|
| **Python** | [`argparse`](https://docs.python.org/3/library/argparse.html) | Option/arg typing, help text, exit codes |
| **Python** | [`click`](https://click.palletsprojects.com/) / Typer | Nested **subcommands**, decorator-ish composition, context object |
| **Java** | [picocli](https://picocli.info/) | Subcommands + types + auto-help; annotation → our CLOS defs |
| **Go** | Cobra / urfave/cli | Subcommand trees (same as clingon’s mental model) |

**Not** inventing a second argv grammar. Protocol owns **command tree + run lifecycle**; backends own parse tables / help renderers.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | **CLOS protocol + backends** | Issue #103 said “pin clingon or adopt”; stack rule is protocol → backend when ≥2 real options |
| **DX target** | click/picocli **subcommand tree** + argparse-grade option kinds | Most stack tools will grow `serve` / `migrate` / `version` subcommands |
| **Default backend (A)** | **[clingon](https://github.com/dnaeon/clingon)** | Native subcommands, option kinds, env init, bash/zsh completion, man pages; active; MIT-ish; REPL-friendly `parse-command-line` |
| **Alternate (B)** | **[adopt](https://github.com/sjl/adopt)** | Small argparse/optparse-shaped escape hatch; man pages; MIT; no nested subcommands as first-class |
| **Not default** | **unix-opts** | Fine for tiny scripts; weak subcommand/help story vs clingon |
| **Also considered** | **CLON** (Didier Verna) | Powerful but heavier / less cookbook-friendly; skip wave-1 |
| **Selection DX** | ASDF + `*cli-backend*` | Load `cli-backend-clingon` (default) or `cli-backend-adopt` |
| **Argv source** | Explicit list **or** `uiop:command-line-arguments` | Tests pass unquoted lists; binaries use UIOP |
| **Exit** | Conditions → exit codes via `cli:exit` / `uiop:quit` | Map parse errors → 2; handler errors → 1; success → 0 (sysexits-ish) |
| **Config / logging** | Out of protocol — compose with `cl-stack-config` + `log-protocol` in cookbooks | CLI parses; config loads; logger configures |
| **Windows** | Both A/B are pure Lisp | Primary target; no native overlay |

**Supersedes** #103 disposition “pin only.” We **pin clingon as default backend**, not as the sole app API.

---

## Bakeoff scorecard (#103)

Scores: **1** … **5** for cl-stack needs.

| Criterion | clingon | adopt | unix-opts |
|-----------|---------|-------|-----------|
| Subcommands / nesting | **5** | **2** | **1** |
| Option kinds (int/bool/enum/list) | **5** | **3** | **3** |
| Help / man / completions | **5** | **4** (man) | **2** |
| argparse/click familiarity | **4** | **5** | **3** |
| Pure Lisp / Windows | **5** | **5** | **5** |
| Extensibility (CLOS) | **5** (`make-option` GF) | **4** | **2** |
| Docs / liveliness | **5** | **4** | **3** |
| Size / dep weight | **3** | **5** | **5** |
| **Wave role** | **Default (A)** | **Alternate (B)** | reject as pin |

**Verdict:** protocol + **clingon default**, **adopt second**. unix-opts = scripts outside the pin set.

---

## Repo layout (locked)

| Layer | Repo / system |
|-------|----------------|
| Protocol + shared tests | `egao1980/cli-protocol` (nick `stack-cli`) |
| Default backend A | `cli-backend-clingon` (colocated ASDF OK for MVP) |
| Alternate backend B | `cli-backend-adopt` |
| Optional facade | only if cookbooks need sugar beyond protocol |

**Third-party imports** (`cl-stack-systems`): `clingon` (+ deps), `adopt` (+ bobbin / split-sequence as needed).

---

## Protocol surface

Package nick: `stack-cli` (system `cli-protocol`).

### Value types

```lisp
(defclass cli-backend () ())
(defvar *cli-backend* nil)

;; Command = name + options + optional subcommands + handler
;; Option  = name/short/long + kind + default + required + env + help
;; Result  = parsed options (plist or hash-table) + free arguments (list of string)
```

Backends may wrap native objects (`clingon:command`, adopt interface) behind protocol types — escape hatch: `cli:raw-command`.

### Generics / DX

```lisp
(defgeneric backend-make-command (backend &key name description version
                                      options subcommands handler)
  (:documentation "Build a COMMAND value."))

(defgeneric backend-make-option (backend &key name short long kind
                                     default required env help key)
  (:documentation "KIND ∈ :flag :string :integer :boolean :enum :list :counter …"))

(defgeneric parse (command argv &key)
  (:documentation "→ (values options free-args). Signals cli-parse-error."))

(defgeneric run (command &key argv)
  (:documentation "Parse + invoke handler. Returns handler values."))

(defun main (command &key (argv (uiop:command-line-arguments)))
  "Binary entry: RUN + map conditions to exit codes.")

(defmacro define-command (name-and-options &body body) …)  ; optional sugar later
```

Handler contract: `(lambda (options free-args) …)` or backend-native with protocol adapter.

### Conditions

```lisp
cli-error
├── cli-parse-error          ; unknown option, missing required, bad type
├── cli-usage-error          ; handler rejected args
└── cli-exit                 ; :code slot — intentional exit
```

---

## Cookbook (with impl)

Minimal tool with subcommands:

```lisp
(asdf:load-system "cli-backend-clingon")

(defvar *app*
  (stack-cli:backend-make-command
   stack-cli:*cli-backend*
   :name "demo"
   :version "0.1.0"
   :subcommands
   (list (stack-cli:backend-make-command
          … :name "greet"
            :options (list (stack-cli:backend-make-option … :name :count :kind :integer :default 1))
            :handler (lambda (opts args)
                       (dotimes (i (getf opts :count))
                         (format t "hi ~a~%" (or (first args) "world"))))))))

(stack-cli:main *app*)
```

---

## Non-goals (this wave)

- GUI / TUI frameworks  
- REPL command systems (Lem, etc.)  
- Replacing clingon/adopt option DSLs wholesale inside the protocol  
- i18n of help strings  

---

## Implementation tasks

- [x] Brief lock (this doc) — [#118](https://github.com/egao1980/cl-stack/issues/118)
- [ ] Import clingon + adopt — [#119](https://github.com/egao1980/cl-stack/issues/119)
- [ ] `cli-protocol` + clingon backend — [#120](https://github.com/egao1980/cl-stack/issues/120)
- [ ] adopt backend + cookbook — [#121](https://github.com/egao1980/cl-stack/issues/121)

Child issues under #103. Impl order vs siblings: **CLI → logging → SQL**.

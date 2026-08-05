# cli-protocol (P2)

**Issues:** [#103](https://github.com/egao1980/cl-stack/issues/103)  
**Status:** brief **locked** — CLOS protocol + backends; **Windows / PowerShell option styles required**

One app DX for command-line tools: define commands/options, parse `argv`, run handlers, emit help/version. Multiple parser backends; cookbooks teach the protocol. **Windows is a primary target** — not “POSIX argv only, works if you pass `--flags`.”

Conventions: [API.md](../API.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md) (CLI → protocol + pin). Platform: [overlays.md](../overlays.md) (Windows primary).

---

## Prior art (shape targets)

| Ecosystem | Library | What we steal |
|-----------|---------|---------------|
| **Python** | [`argparse`](https://docs.python.org/3/library/argparse.html) / Click | Option/arg typing, help, exit codes; Click subcommands |
| **Java** | [picocli](https://picocli.info/) | Subcommands + types; picocli’s case-insensitive / Windows-ish modes |
| **PowerShell** | [Command-line syntax](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines) | **Single-dash long names** (`-Verbose`, `-Count 3`), switches, case-insensitive |
| **Windows CMD** | Classic utilities (`ipconfig /all`) | **Slash** options `/Help`, `/Out:file` — still what many Windows users type |
| **Go** | Cobra | Subcommand trees (clingon mental model) |

Upstream **clingon / adopt are POSIX-prefixed** (`-s`, `--long`). Stack rule: **protocol owns dialect normalization** so backends stay stock — do **not** wait for clingon to grow `/flags`.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | **CLOS protocol + backends** | #103 upgraded from pin-only |
| **DX target** | click/picocli **subcommand tree** + argparse-grade option kinds | Tools grow `serve` / `migrate` / `version` |
| **Default backend (A)** | **[clingon](https://github.com/dnaeon/clingon)** | Subcommands, option kinds, env init, man/completions (Unix); REPL `parse-command-line` |
| **Alternate (B)** | **[adopt](https://github.com/sjl/adopt)** | Small argparse escape hatch |
| **Windows primary** | **Required** | Same bar as http-server / event: `windows-latest` CI + idiomatic Windows argv |
| **Option dialects** | Protocol accepts **POSIX ∪ PowerShell ∪ CMD** (see below) | Backends stay POSIX; protocol normalizes argv **before** `backend-parse` |
| **Default dialect policy** | `:auto` — on Windows enable all three; on Unix enable POSIX (+ PowerShell single-dash long for consistency) | CMD `/` stays Windows-on by default (path ambiguity on Unix) |
| **Case folding** | **Case-insensitive** option name match on Windows; sensitive on Unix (POSIX) | PowerShell habit; Unix scripts rely on case |
| **Help text** | Usage lists **platform-relevant** spellings | Windows help shows `-Name` / `/Name` / `--name`; Unix shows `-n` / `--name` |
| **Completions** | Wave-1: clingon bash/zsh on Unix; **PowerShell completer = follow-on** | Don’t block MVP; document as #121+ |
| **Selection DX** | ASDF + `*cli-backend*` | `cli-backend-clingon` default |
| **Argv source** | Explicit list **or** `uiop:command-line-arguments` | Fixture tests for all dialects; binaries use UIOP (SBCL Windows OK) |
| **Exit** | Conditions → exit codes | Parse → 2; handler → 1; success → 0 |
| **Config / logging** | Compose with `cl-stack-config` + `log-protocol` | Out of CLI protocol |

**Supersedes** “Windows = pure Lisp only.” Pure Lisp is necessary but **not sufficient** — dialect support is part of Done-when.

---

## Option dialects (normative)

Canonical option identity in the protocol = **long name** (string, kebab or as defined) + optional **short** char. Wire spellings accepted:

### POSIX (always)

| Wire | Maps to |
|------|---------|
| `-v` | short `v` |
| `--verbose` | long `verbose` |
| `--count=3` / `--count 3` | long `count` + value |
| `--` | end-of-options |

### PowerShell-style (Windows default; Unix optional)

| Wire | Maps to |
|------|---------|
| `-Verbose` / `-verbose` | long `verbose` (case-fold on Windows) |
| `-Count 3` / `-Count:3` | long `count` + value |
| `-Flag` / `-Flag:$true` / `-Flag:$false` | flag/boolean |
| Single-dash **multi-char** token | treated as long name, **not** clustered shorts |

Clustered shorts (`-xyz` = `-x -y -z`) remain POSIX-only. A token matching `-[A-Za-z][A-Za-z0-9_-]+` is **long**, never a cluster.

### CMD slash-style (Windows default; off on Unix unless `:styles` includes `:cmd`)

| Wire | Maps to |
|------|---------|
| `/v` | short `v` if defined, else long |
| `/Verbose` / `/verbose` | long `verbose` |
| `/Count:3` / `/Count 3` | long `count` + value |

### Normalization

```lisp
(defun normalize-argv (argv &key (styles :auto))
  "→ argv in POSIX form for the backend. STYLES = :auto | list of :posix :powershell :cmd")
```

`parse` / `run` / `main` call `normalize-argv` first. Escape hatch: `:styles '(:posix)` for strict GNU-only tools.

---

## Bakeoff scorecard (#103)

Scores: **1** … **5** for cl-stack needs. **Windows dialect** column = stock library without protocol normalizer.

| Criterion | clingon | adopt | unix-opts |
|-----------|---------|-------|-----------|
| Subcommands / nesting | **5** | **2** | **1** |
| Option kinds | **5** | **3** | **3** |
| Help / man / completions | **5** | **4** | **2** |
| **Windows / PowerShell / CMD dialects** | **2**† | **2**† | **1** |
| Pure Lisp (runs on Windows) | **5** | **5** | **5** |
| Extensibility (CLOS) | **5** | **4** | **2** |
| Docs / liveliness | **5** | **4** | **3** |
| **Wave role** | **Default (A)** | **Alternate (B)** | reject |

† Raised to **5** for the **stack** by protocol `normalize-argv` + dual help — not by forking clingon.

**Verdict:** clingon default + adopt second; **protocol owns Windows/PowerShell/CMD wire formats**.

---

## Repo layout (locked)

| Layer | Repo / system |
|-------|----------------|
| Protocol + dialect normalizer + tests | `egao1980/cli-protocol` (nick `stack-cli`) |
| Default backend A | `cli-backend-clingon` |
| Alternate backend B | `cli-backend-adopt` |

**Third-party imports:** `clingon`, `adopt` (+ deps) via `cl-stack-systems`.

---

## Protocol surface

Package nick: `stack-cli` (system `cli-protocol`).

### Value types

```lisp
(defclass cli-backend () ())
(defvar *cli-backend* nil)
(defvar *cli-option-styles* :auto
  ":auto | (:posix) | (:posix :powershell) | (:posix :powershell :cmd) | …")
```

### Generics / DX

```lisp
(defgeneric backend-make-command (backend &key name description version
                                      options subcommands handler))
(defgeneric backend-make-option (backend &key name short long kind
                                     default required env help key)
  (:documentation "LONG = canonical name without -- or / prefix.
KIND ∈ :flag :string :integer :boolean :enum :list :counter …"))

(defun normalize-argv (argv &key (styles *cli-option-styles*))
  "Dialect → POSIX tokens for backends.")

(defgeneric parse (command argv &key styles)
  (:documentation "Normalize then backend-parse → (values options free-args)."))

(defgeneric run (command &key argv styles))
(defun main (command &key (argv (uiop:command-line-arguments))
                       (styles *cli-option-styles*))
  "Binary entry + exit codes.")

(defgeneric format-usage (command &key stream styles)
  (:documentation "Help listing spellings for STYLES / platform."))
```

### Conditions

```lisp
cli-error
├── cli-parse-error          ; unknown option, missing required, bad type
├── cli-usage-error
└── cli-exit                 ; :code slot
```

---

## Cookbook (with impl)

Same command, three wires (all succeed on Windows):

```lisp
(asdf:load-system "cli-backend-clingon")
;; define *app* with option long-name "count", short #\c …

(stack-cli:run *app* :argv '("greet" "--count" "2" "ada"))     ; POSIX
(stack-cli:run *app* :argv '("greet" "-Count" "2" "ada"))      ; PowerShell
(stack-cli:run *app* :argv '("greet" "/Count:2" "ada"))        ; CMD
```

---

## Non-goals (this wave)

- GUI / TUI  
- Full **PowerShell tab-completion** module (follow-on; document stub)  
- Forking clingon/adopt for dialect support  
- i18n of help strings  
- Treating `/` options as default on Unix (path collision)  

---

## Implementation tasks

- [x] Brief lock — [#118](https://github.com/egao1980/cl-stack/issues/118)
- [x] Import clingon + adopt — [#119](https://github.com/egao1980/cl-stack/issues/119) (PR [cl-stack-systems#15](https://github.com/egao1980/cl-stack-systems/pull/15))
- [x] `cli-protocol` + **`normalize-argv`** + clingon backend + dialect Rove fixtures — [#120](https://github.com/egao1980/cl-stack/issues/120) ([egao1980/cli-protocol](https://github.com/egao1980/cli-protocol) `0.1.0`)
- [x] adopt backend + cookbook — [#121](https://github.com/egao1980/cl-stack/issues/121) · [cookbooks/cli.md](../cookbooks/cli.md)

**#120 Done-when addendum:** green on `windows-latest` with PowerShell-style and CMD-style argv fixtures (not only `--posix`).

Child issues under #103. Impl order: **CLI → logging → SQL**.

# Cookbook: CLI (argparse / Click / picocli)

**Audience:** Python argparse/Click or Java picocli users who want one Lisp command tree with Windows-friendly argv.

**Packages:**

| Layer | Role |
|-------|------|
| [`cli-protocol`](https://github.com/egao1980/cli-protocol) (`stack-cli`) | `make-command` / `parse` / `run` / `normalize-argv` |
| `cli-backend-clingon` | **default** — subcommands |
| `cli-backend-adopt` | alternate — flat interface (`use-adopt-backend`) |

Brief: [cli.md](../capabilities/cli.md). Dialects: POSIX ∪ PowerShell ∪ CMD (protocol normalizes before the backend).

```lisp
(cl-repo:load-system "cli-backend-clingon" :version "0.1.0")
;; nick: stack-cli
```

---

## 1. Subcommand tool (clingon)

```lisp
(asdf:load-system "cli-backend-clingon")  ; sets *cli-backend*

(defparameter *greet*
  (stack-cli:make-command
   :name "greet"
   :description "greet someone"
   :options (list (stack-cli:make-option
                   :name "count" :short #\c :long "count"
                   :kind :integer :default 1 :help "times" :key :count))
   :handler (lambda (opts free)
              (dotimes (_ (stack-cli:get-option opts :count 1))
                (format t "hello ~{~a~^ ~}~%" free)))))

(defparameter *app*
  (stack-cli:make-command
   :name "demo"
   :description "demo CLI"
   :version "0.1.0"
   :subcommands (list *greet*)))

;; Same command, three wires (all succeed on Windows):
(stack-cli:run *app* :argv '("greet" "--count" "2" "ada"))   ; POSIX
(stack-cli:run *app* :argv '("greet" "-Count" "2" "ada"))    ; PowerShell
(stack-cli:run *app* :argv '("greet" "/Count:2" "ada"))      ; CMD
```

Binary entry (maps parse → exit 2, handler → 1, ok → 0):

```lisp
(stack-cli:main *app*)  ; uses uiop:command-line-arguments
```

---

## 2. Flat tool (adopt)

```lisp
(asdf:load-system "cli-backend-adopt")
(cli-backend-adopt:use-adopt-backend)

(defparameter *app*
  (stack-cli:make-command
   :name "greet"
   :description "greet"
   :options (list (stack-cli:make-option
                   :name "count" :short #\c :long "count"
                   :kind :integer :default 1 :help "times" :key :count))
   :handler (lambda (opts free)
              (format t "~a × ~s~%" (stack-cli:get-option opts :count) free))))

(stack-cli:run *app* :argv '("-Count" "3" "bob"))
```

Adopt does **not** support nested subcommands — use clingon for trees.

---

## 3. Strict POSIX only

```lisp
(stack-cli:run *app* :argv … :styles '(:posix))
```

Default `:auto` → Windows gets POSIX+PowerShell+CMD; Unix gets POSIX+PowerShell.

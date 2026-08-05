# Cookbook: Config (env + TOML)

**Audience:** apps that need a file + environment overlay (12-factor-ish).

**Package:** [`cl-stack-config`](https://github.com/egao1980/cl-stack-config) (`stack-config`)  
**Brief:** [config.md](../capabilities/config.md)

```lisp
(cl-repo:load-system "cl-stack-config" :version "0.1.0")
```

---

## 1. `config.toml`

```toml
features = ["auth", "cache"]

[database]
host = "localhost"
port = 5432
enabled = true
```

```lisp
(defvar *cfg*
  (stack-config:load #p"config.toml" :prefix "APP"))

(stack-config:get-string *cfg* "database.host")     ; => "localhost"
(stack-config:get-integer *cfg* "database.port")    ; => 5432
(stack-config:get-boolean *cfg* "database.enabled") ; => T
(stack-config:get-list *cfg* "features")            ; => ("auth" "cache")
```

---

## 2. Env overlay

| Env | Path |
|-----|------|
| `APP_DEBUG=true` | `debug` |
| `APP_DATABASE__HOST=db` | `database.host` |

Precedence: **file < env < `:overrides`**.

```lisp
;; APP_DATABASE__HOST=db.example already in the process env:
(stack-config:load #p"config.toml" :prefix "APP" :env t
                   :overrides '(("debug" . t)))
```

---

## 3. Typed defaults / sections

```lisp
(stack-config:get *cfg* "cache.ttl" :default 60)
(let ((db (stack-config:section *cfg* "database")))
  (stack-config:get db "host"))
```

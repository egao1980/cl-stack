# Cookbook: SQL (connectivity / Core / ORM)

**Audience:** people who know SQLAlchemy (Engine / Core / ORM) or JDBC + a query builder, and want the Lisp three-layer stack.

**Packages:**

| Layer | Python / Java | Lisp |
|-------|---------------|------|
| Connectivity | Engine / DB-API / JDBC | [`sql-protocol`](https://github.com/egao1980/sql-protocol) (`stack-sql`) + `sql-backend-*` |
| Query DSL | SQLAlchemy Core / jOOQ | [`sql-query`](https://github.com/egao1980/sql-query) (`stack-sql-query`) + dialect backends |
| ORM | SQLAlchemy ORM | [`sql-orm`](https://github.com/egao1980/sql-orm) (`stack-sql-orm`) — **not** Mito |

Capability brief: [sql.md](../capabilities/sql.md).

```lisp
(cl-repo:load-system "sql-backend-sqlite3" :version "0.1.0")
(cl-repo:load-system "sql-query-sqlite3" :version "0.2.0")   ; pulls sql-query
(cl-repo:load-system "sql-orm" :version "0.1.0")             ; pulls sql-protocol + sql-query
```

Postgres: load `sql-backend-postgres` + `sql-query-postgres` instead of (or as well as) the sqlite3 pair.

---

## 1. Connectivity (`sql-protocol`)

Raw SQL strings + params. No DSL.

```lisp
(asdf:load-system "sql-backend-sqlite3")

(stack-sql:with-connection (c :driver :sqlite3 :database-name ":memory:")
  (stack-sql:execute c "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
  (stack-sql:execute c "INSERT INTO t (name) VALUES (?)" '("ada"))
  (stack-sql:fetch-all (stack-sql:execute c "SELECT * FROM t")))
;; ⇒ ((:ID 1 :NAME "ada"))

(stack-sql:with-transaction (c)
  (stack-sql:execute c "INSERT INTO t (name) VALUES (?)" '("grace")))

(let ((pool (stack-sql:make-pool stack-sql:*sql-backend*
                                 :database-name ":memory:"
                                 :max 4)))
  (stack-sql:with-pool-connection (c pool)
    (stack-sql:ping c)))
```

Postgres:

```lisp
(asdf:load-system "sql-backend-postgres")
(stack-sql:connect :driver :postgres
                   :database-name "app"
                   :username "app"
                   :password "secret")
```

| Want | Call |
|------|------|
| one-shot connect | `with-connection` / `connect` |
| txn | `with-transaction` |
| pool | `make-pool` + `with-pool-connection` |
| escape hatch | `raw-connection` → underlying cl-dbi conn |

---

## 2. Core DSL (`sql-query`)

CLOS AST → SQL string + params. Filters/DDL are objects, not string concat.

```lisp
(asdf:load-system "sql-query-sqlite3")
(asdf:load-system "sql-backend-sqlite3")

(use-package :sql-query)

(multiple-value-bind (sql params)
    (compile-sql
     (select (columns :id (label (count :*) :n))
             (from :users)
             (where (sql-and (:= :active 1)
                             (sql-fragment "created_at > ?" "2020-01-01")))
             (order-by :name)
             (limit 10))
     :dialect (sql-query-sqlite3:make-sqlite3-dialect))
  (list sql params))
```

Execute through protocol (dialect auto via `dialect-for-connection` when backends are loaded):

```lisp
(stack-sql:with-connection (c :driver :sqlite3 :database-name ":memory:")
  (sql-query:execute-query
   c
   (create-table :users
     (column :id :type :integer :primary-key t :autoincrement t)
     (column :name :type :text :not-null t)))
  (sql-query:execute-query
   c
   (insert-into :users (columns :name) (sql-values "ada")))
  (sql-query:fetch-all-query
   c
   (select (columns :id :name) (from :users) (where (:= :name "ada")))))
```

| Want | Call |
|------|------|
| DML | `select` / `insert-into` / `update` / `delete-from` |
| DDL | `create-table` / `alter-table` / `drop-table` / … |
| raw nestable SQL | `sql-fragment` |
| compile only | `compile-sql` |
| run on connection | `execute-query` / `fetch-query` / `fetch-all-query` |
| vendor bits | dialect backends + open `sql-extension` hooks |

---

## 3. ORM (`sql-orm`)

`defmodel` + persistence generics + schema snapshot/diff. Filters are **sql-query** exprs.

```lisp
(asdf:load-system "sql-backend-sqlite3")
(asdf:load-system "sql-query-sqlite3")
(asdf:load-system "sql-orm")

(defmodel user ()
  (id :integer :primary-key t :autoincrement t)
  (name :text :not-null t)
  (email :text)
  (:table users)
  (:has-many posts post :key user-id)
  (:compute label (self)
    (format nil "~A <~A>" (name self) (email self))))

(with-orm-connection (c :driver :sqlite3 :database-name ":memory:")
  (ensure-schema c 'user)
  (let ((u (persist (make-instance 'user :name "ada" :email "a@x"))))
    (label u)                       ; ⇒ "ada <a@x>"
    (find-instance 'user (id u))
    (select-instances 'user :where (:= :name "ada"))
    (destroy u)))
```

### Schema ops (reversible; not a migration runner)

```lisp
(let* ((old (schema-snapshot 'user))
       ;; … redefine model / build a new snapshot …
       (new (schema-snapshot 'user))
       (mig (make-migration old new :name "add-email" :revision "0002")))
  (upgrade-schema c mig)
  (downgrade-schema c mig))
```

| Want | Call |
|------|------|
| define model | `defmodel` (`:table` / `:has-many` / `:belongs-to` / `:compute`) |
| CRUD | `persist` / `destroy` / `refresh` / `find-instance` / `select-instances` |
| create tables from models | `ensure-schema` |
| structural diff | `schema-snapshot` / `diff-schema` → `schema-op` list |
| apply / roll back | `upgrade-schema` / `downgrade-schema` |

No identity map, no Mito façade, no Alembic product — just the op algebra a runner can version.

---

## Layer pick

| You need… | Use |
|-----------|-----|
| execute SQL strings | `sql-protocol` only |
| composable queries / DDL AST | + `sql-query` (+ dialect) |
| models / DAO / schema diff | + `sql-orm` |

Apps pick the highest layer they need. Libs that only execute SQL should depend on **`sql-protocol`**.

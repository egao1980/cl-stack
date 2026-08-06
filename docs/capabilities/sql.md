# SQL stack (P2) — three layers

**Issues:** [#101](https://github.com/egao1980/cl-stack/issues/101)  
**Status:** brief **re-locked** — three layers; **`sql-query` = first-party CLOS DSL** (not a thin SxQL wrapper)

```text
sql-orm              ← ORM (Mito facade)              ~ SQLAlchemy ORM
    │
sql-query            ← CLOS DSL + ANSI dialect        ~ SQLAlchemy Core
sql-query-sqlite3    ← dialect backend                ~ sqlite+pysqlite dialect
sql-query-postgres   ← dialect backend                ~ postgresql dialect
    │
sql-protocol         ← connectivity + pooling         ~ Engine / Connection / Pool / DB-API
sql-backend-*        ← driver backends                ~ DBAPI drivers
```

Apps pick the layer they need. Libs that only execute SQL depend on **`sql-protocol`**. Query builders depend on protocol (+ optionally emit via it). ORM depends on query + protocol (Mito may still speak SxQL internally for wave-1).

Conventions: [API.md](../API.md). Config: [config.md](config.md). Gap: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Prior art

| Layer | Java | Python | CL |
|-------|------|--------|-----|
| **Connectivity** | JDBC `DataSource` / pool | DB-API + SQLAlchemy Engine/Pool | **cl-dbi** + drivers |
| **SQL generation** | **jOOQ** / QueryDSL | **SQLAlchemy Core** | **first-party CLOS DSL** (SxQL = prior art / Mito bridge) |
| **ORM** | JPA / Hibernate | **SQLAlchemy ORM** | **Mito** |

---

## Locked decisions (cross-cutting)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separation** | **Three first-party systems** (separate repos) | Clear deps; no “Mito in the protocol” |
| **Connectivity pin** | **[cl-dbi](https://github.com/fukamachi/cl-dbi)** | Portable DBI; do not reimplement drivers |
| **Default driver (A)** | **SQLite3** (`dbd-sqlite3`) | Windows-primary + CI zero-ops |
| **Second driver (B)** | **PostgreSQL** (`dbd-postgres`) | Prod services |
| **MySQL** | Watchlist dialect | cl-dbi/Mito support; not wave-1 emit target |
| **Postmodern** | Escape hatch only | Postgres-native; not portable default |
| **Query layer** | **First-party CLOS lispy DSL** in `sql-query` | Composable AST, dialects, DDL + DML + procedures, raw fragments — SxQL is too narrow / not CLOS |
| **SxQL** | Prior art + **Mito interop** (imported) | Not the public `sql-query` API; optional bridge helpers OK |
| **ORM pin** | **[Mito](https://github.com/fukamachi/mito)** | AR-shaped; migrations; uses SxQL internally for now |
| **Pooling** | **In `sql-protocol` wave-1** (simple pool) | User-required; not deferred |
| **Row shape** | plist default; optional alist/hash | json-protocol kinship |
| **Config** | DSN-ish keys via `cl-stack-config` | `database.driver`, `database.url`, … |
| **Natives** | SQLite / libpq system or overlay follow-on | Document until overlays |

---

## Layer 1 — `sql-protocol` (connectivity)

**Repo:** [`egao1980/sql-protocol`](https://github.com/egao1980/sql-protocol) · nick **`stack-sql`** · OCI **0.1.0**  
**Backends:** `sql-backend-sqlite3`, `sql-backend-postgres`

Owns: connect / disconnect / ping / execute / fetch* / transactions / **pool**.  
Does **not** own query DSL or DAO macros.

```lisp
(defclass sql-backend () ())
(defvar *sql-backend* nil)
(defvar *sql-connection* nil)

(defclass sql-connection () ())
(defclass sql-pool () ())

(defgeneric backend-connect (backend &key &allow-other-keys) → sql-connection)
(defgeneric disconnect (connection))
(defgeneric ping (connection))

(defgeneric execute (connection sql &optional params)
  (:documentation "SQL string + params. Query objects → sql-query layer."))
(defgeneric fetch (result &key) → plist | nil)
(defgeneric fetch-all (result &key))

(defgeneric make-pool (backend &key min max &allow-other-keys) → sql-pool)
(defgeneric pool-connect (pool) → sql-connection)   ; checkout
(defgeneric pool-release (pool connection))
(defmacro with-pool-connection ((var pool) &body body) …)

(defmacro with-connection ((var &rest connect-keys) &body body) …)
(defmacro with-transaction ((connection) &body body) …)

(defun connect (&key (driver :sqlite3) &allow-other-keys) …)
(defun raw-connection (connection) …)  ; underlying dbi connection for Mito
```

**Pooling (wave-1 minimum):** fixed max size, checkout/release, wait or error when exhausted.  
**Conditions:** `sql-error` → connection / programming / integrity / operational / `sql-pool-timeout`.

---

## Layer 2 — `sql-query` (CLOS SQL DSL / Core)

**Repo:** `egao1980/sql-query` · nick **`stack-sql-query`**  
**Systems:** `sql-query` (ANSI builtin) · `sql-query-sqlite3` · `sql-query-postgres`  
**Depends on:** `sql-protocol` (for execute helpers; compile path has **no** hard driver dep)  
**Issue:** [#148](https://github.com/egao1980/cl-stack/issues/148)

Owns: **composable CLOS AST** with **SQLAlchemy Core feature parity**, **ANSI dialect** (only builtin), compile → `(sql-string . params)`, DX to run on a connection.  
Vendor SQL → **dialect backend systems** (same protocol/backend pattern as `sql-protocol` / `sql-backend-*`).  
Does **not** own connections/pools or ORM.

### Shape (locked)

```text
expression / clause / statement   ← CLOS classes (immutable-ish value objects OK)
        │
   compose (generics + constructors)
        │
   sql-dialect                    ← CLOS; methods specialize emission
        │
   compile-sql → (values string params)
        │
   execute-query / fetch-*-query  ← sql-protocol
```

**Lispy DX** — constructors that return objects (not a giant `macrolet` DSL that hides composition):

```lisp
;; DML
(select (columns :id :name)
        (from :users)
        (where (:= :active t))
        (order-by :name)
        (limit 10))

(insert-into :users
  (columns :name :email)
  (values "ada" "ada@example.com"))

(update :users
  (set (:= :name "grace"))
  (where (:= :id 1)))

(delete-from :users (where (:= :id 1)))

;; DDL
(create-table :users
  (column :id :type :integer :primary-key t :autoincrement t)
  (column :name :type '(:varchar 255) :not-null t)
  (column :email :type '(:varchar 255) :unique t))

(create-index :users-email (on :users) (columns :email))
(alter-table :users (add-column :created-at :type :timestamptz))
(drop-table :users :if-exists t)

;; Procedures — two layers: SQL-shaped PROC-* + lispy BODY macros
(create-procedure :bump_counter
  (params (in :by :integer) (inout :n :integer))
  (body
   (if (:= :n 0)
       (setf :n :by)
       (setf :n (:+ :n :by)))
   (loop :while (:< :n 100) :do (setf :n (:+ :n 1)))))
;; layer 1 (programmatic): (make-body (proc-if …) (proc-setf …))
;; emit: ANSI SQL/PSM · postgres plpgsql · sqlite unsupported

(sql-call :bump_counter :by 1)

;; Raw escape hatch — first-class, composable
(where (:and
        (:= :tenant-id tid)
        (sql-fragment "created_at > now() - interval '? days'" days)))

(select (columns (sql-fragment "count(*) AS c"))
        (from :users))
```

**Composition:** statements/clauses are objects; `merge-query` / `and-where` / appending clauses via generics — no string concat as the public model.

**Dialects (protocol / backend):**

```lisp
;; sql-query — protocol + ANSI only
(defclass sql-dialect () ())
(defclass ansi-dialect (sql-dialect) ())   ; builtin default
(register-sql-dialect :ansi (make-ansi-dialect))

;; sql-query-sqlite3 / sql-query-postgres — separate ASDF systems
(defclass sqlite3-dialect (ansi-dialect) ())
(defclass postgres-dialect (ansi-dialect) ())
(register-sql-dialect :sqlite3 …)
(register-sql-dialect :postgres …)
;; mysql — watchlist backend

(defgeneric dialect-for-connection (connection) → sql-dialect)  ; registry by driver
(defgeneric compile-sql (statement &key dialect) → (values string params))
(defgeneric emit-sql (dialect node stream ctx) …)
```

Default compile dialect = **ANSI**. `execute-query` resolves via `*sql-dialect-registry*` from the connection driver when a backend is loaded. Explicit `:dialect` always allowed.

**Extension registry (types & operators):** SQL types potentially know how to **read/write Lisp values as SQL expressions** — not just DDL names. JSON/BSON/arrays stay out of core; backends register adapters.

```lisp
(register-sql-type :jsonb dialect
  :sql "JSONB"
  :encode #'json-encode          ; Lisp → wire / bind
  :decode #'json-decode          ; wire → Lisp  (sql-type-read)
  :to-expr (lambda (d v) …)      ; Lisp → sql-node (preferred write)
  :emit-value (lambda (d v s ctx) …)) ; or full emit

(typed obj :jsonb)                 ; or (lit obj :jsonb) / (bindparam :x obj :type :jsonb)
(sql-type-write dialect :jsonb obj) ; → expression
(sql-type-read dialect :jsonb db)   ; → Lisp

(register-sql-op :->> :binary dialect :sql "->>")
(ensure-expr '(:->> :payload "name"))
```

Default write without `:to-expr`/`:emit-value` = `CAST(? AS <sql>)` + `:encode`. `sql-query-postgres` seeds `:json`/`:jsonb`/`:array` and common JSONB ops.

**Raw fragments:**

```lisp
(defclass sql-fragment (sql-node)
  ((template :initarg :template)    ; string with ? placeholders
   (args :initarg :args)))          ; bound params, inlined into param vector in order
(defun sql-fragment (template &rest args) …)
```

Fragments are nodes — nestable inside WHERE/SELECT lists/DDL body. **No** silent string interpolation of user values (params only).

**Parameter style:** dialect chooses `?` vs `$1` vs `:name` at emit time; public AST stays positional/named-agnostic (internal binder).

### SQLAlchemy Core parity (target)

Track against SQLAlchemy 2.0 Core expression language + schema/DDL (not ORM).

| Core area | Wave-1 (`sql-query`) | Later |
|-----------|----------------------|-------|
| `select` / DML | `select` `insert-into` `update` `delete-from` + join/group/having/order/limit/offset/returning | `VALUES` selectable as FROM, multi-table UPDATE completeness |
| Distinct / locking | `distinct` `for-update` | `FOR SHARE`, dialect lock strength |
| Set ops | `union` `union-all` `intersect*` `except*` | — |
| CTE / subquery | `cte` `with-cte` `as-cte` `subquery` `exists` | recursive CTE sugar, `LATERAL` |
| Column elements | `:=`… comparisons, `sql-and/or/not`, `sql-in` `sql-between` `sql-like` `sql-is-null`, arithmetic `:+`…, `sql-case` `sql-cast` `sql-func` `count` `coalesce` `label` `bindparam` `lit` `col` `typed` | `within-group`; richer type codecs |
| Extensibility | `register-sql-type` / `register-sql-op` (Lisp↔expr encode/decode/to-expr) | first-party JSON/BSON helper systems |
| `text()` | `sql-fragment` / `sql-raw` | bindparam expanding |
| Schema | `make-sql-table` `table-column` `create-table-from` + DDL stmts | MetaData registry, reflection, FK/CHECK/UNIQUE table constraints, sequences |
| DDL | CREATE/DROP TABLE, INDEX, basic ALTER ADD/DROP COLUMN | partitions, complex ALTER |
| Procedures | `proc-*` (SQL-shaped) + lispy `body`; ANSI SQL/PSM + postgres plpgsql | functions, triggers, handlers |
| Dialects | **ANSI builtin**; **sqlite3** + **postgres** backends | mysql backend |
| Compile / execute | `compile-sql` → `(values string params)`; `execute-query` `fetch-*-query` | Result typing, async |
| Upsert / ON CONFLICT | — | dialect backends |
| Inspector / reflection | — | follow-on |

**Done-when for #148:** wave-1 Core rows green + ANSI/backends split + Rove/CI + OCI publish of the three systems.

### Non-goals (`sql-query`)

- Re-hosting SxQL’s public API as ours  
- LINQ-style deferred ORM identity map (→ `sql-orm` / Mito)  
- Parsing arbitrary SQL → AST  
- Schema migration versioning product (Mito / later tool)

### SxQL relationship

- **Imported** for Mito / migration interop.  
- Optional `sql-query/sxql` helpers may convert *subset* SxQL → our AST or yield-through — **not** required for wave-1 Done-when.  
- Cookbook shows first-party DSL, not SxQL macros.

---

## Layer 3 — `sql-orm` (ORM facade)

**Repo:** `egao1980/sql-orm` · nick **`stack-sql-orm`**  
**Depends on:** `sql-protocol`, `sql-query` (for app-level queries), **mito**  
**Issue:** [#149](https://github.com/egao1980/cl-stack/issues/149)

Owns: model / DAO DX, migrations sketch, wiring `mito:*connection*` to protocol connections.  
Does **not** reimplement `deftable` — Mito keeps macros for wave-1.

```lisp
(asdf:load-system "sql-backend-sqlite3")
(asdf:load-system "sql-orm")

(stack-sql:with-connection (c :driver :sqlite3 :database-name ":memory:")
  (sql-orm:use-connection c)           ; sets mito:*connection*
  (mito:ensure-table-exists 'user)
  (mito:insert-dao (make-instance 'user :name "ada")))
```

Later: prefer `sql-query` for ad-hoc reports; Mito for DAO lifecycle.

---

## Repo layout (locked)

| Layer | Repo / systems |
|-------|----------------|
| Connectivity | `egao1980/sql-protocol` + `sql-backend-*` (**shipped 0.1.0**) |
| Core / query | `egao1980/sql-query` + `sql-query-sqlite3` + `sql-query-postgres` |
| ORM | `egao1980/sql-orm` |

**Imports** (`cl-stack-systems`): `cl-dbi`, `dbd-*`, `sxql`, `mito`, … (already published).

---

## Bakeoff

**cl-dbi** for connectivity; **first-party CLOS DSL** for generation; **Mito** for ORM.  
Postmodern escape hatch; CLSQL reject.  
SxQL remains available under the hood for Mito — not the Core façade.

---

## Cookbooks (with impl)

1. Connectivity: SQLite connect / execute / txn / pool — **done** with `sql-protocol`  
2. Core: composable select/insert + DDL + `sql-fragment` on protocol connection  
3. ORM: Mito CRUD + migration sketch (SQLite CI; Postgres Ubuntu job)

---

## Non-goals (this wave)

- Postmodern as default  
- Full PgBouncer-grade pool product  
- NoSQL  
- Multi-tenant routers  
- Full SQL:2003 / every PG extension  

---

## Implementation tasks

- [x] Brief lock (three-layer) — #101  
- [x] Import cl-dbi / dbd-* / sxql / mito — [#146](https://github.com/egao1980/cl-stack/issues/146)  
- [x] `sql-protocol` + pool + sqlite3/postgres — [#147](https://github.com/egao1980/cl-stack/issues/147)  
- [ ] `sql-query` ANSI Core DSL + dialect backends (SQLAlchemy Core parity wave-1) — [#148](https://github.com/egao1980/cl-stack/issues/148)  
- [ ] `sql-orm` over Mito + cookbook — [#149](https://github.com/egao1980/cl-stack/issues/149)  

**Impl order:** ~~imports → connectivity~~ → **query** → **ORM**.

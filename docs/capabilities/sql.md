# SQL stack (P2) — three layers

**Issues:** [#101](https://github.com/egao1980/cl-stack/issues/101)  
**Status:** three layers **shipped** — `sql-protocol` **0.1.0** · `sql-query{,-postgres,-sqlite3}` **0.2.0** · `sql-orm` **0.1.0** (first-party CLOS; no Mito). Cookbook: [cookbooks/sql.md](../cookbooks/sql.md)

```text
sql-orm              ← first-party CLOS ORM           ~ SQLAlchemy ORM (checklist only)
    │
sql-query            ← CLOS DSL + ANSI dialect        ~ SQLAlchemy Core
sql-query-sqlite3    ← dialect backend                ~ sqlite dialect
sql-query-postgres   ← dialect backend                ~ postgresql dialect
sql-query-csv        ← AST→Lisp over CSV              ~ in-process tabular
    │
sql-protocol         ← connectivity + pooling         ~ Engine / Connection / Pool / DB-API
sql-backend-*        ← driver backends                ~ DBAPI drivers
```

Apps pick the layer they need. Libs that only execute SQL depend on **`sql-protocol`**. Query builders depend on protocol (+ optionally emit via it). ORM depends on query + protocol.

Conventions: [API.md](../API.md). Config: [config.md](config.md). Gap: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Prior art

| Layer | Java | Python | CL |
|-------|------|--------|-----|
| **Connectivity** | JDBC `DataSource` / pool | DB-API + SQLAlchemy Engine/Pool | **cl-dbi** + drivers |
| **SQL generation** | **jOOQ** / QueryDSL | **SQLAlchemy Core** | **first-party CLOS DSL** (`sql-query`; SxQL = prior art only) |
| **ORM** | JPA / Hibernate | **SQLAlchemy ORM** | **first-party `sql-orm`** (`defmodel`; not Mito) |

---

## Locked decisions (cross-cutting)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separation** | **Three first-party systems** (separate repos) | Clear deps; no ORM in the protocol |
| **Connectivity pin** | **[cl-dbi](https://github.com/fukamachi/cl-dbi)** | Portable DBI; do not reimplement drivers |
| **Default driver (A)** | **SQLite3** (`dbd-sqlite3`) | Windows-primary + CI zero-ops |
| **Second driver (B)** | **PostgreSQL** (`dbd-postgres`) | Prod services |
| **MySQL** | Watchlist dialect | cl-dbi support; not wave-1 emit target |
| **Postmodern** | Escape hatch only | Postgres-native; not portable default |
| **Query layer** | **First-party CLOS lispy DSL** in `sql-query` | Composable AST, dialects, DDL + DML + procedures, raw fragments |
| **SxQL** | Prior art only (may stay imported elsewhere) | **Not** the public `sql-query` / `sql-orm` API |
| **ORM** | **First-party lispy CLOS** (`sql-orm`) | `defmodel`, relations, `:compute`, schema-op migrations; SQLAlchemy = feature checklist only |
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
(defun raw-connection (connection) …)  ; underlying dbi connection when needed
```

**Pooling (wave-1 minimum):** fixed max size, checkout/release, wait or error when exhausted.  
**Conditions:** `sql-error` → connection / programming / integrity / operational / `sql-pool-timeout`.

---

## Layer 2 — `sql-query` (CLOS SQL DSL / Core)

**Repo:** [`egao1980/sql-query`](https://github.com/egao1980/sql-query) · nick **`stack-sql-query`** · OCI **0.2.0**  
**Dialects:** [`sql-query-sqlite3`](https://github.com/egao1980/sql-query-sqlite3) · [`sql-query-postgres`](https://github.com/egao1980/sql-query-postgres) · [`sql-query-csv`](https://github.com/egao1980/sql-query-csv)  
**Depends on:** `sql-protocol` (execute helpers; compile path has **no** hard driver dep)  
**Issue:** [#148](https://github.com/egao1980/cl-stack/issues/148)

Owns: **composable CLOS AST**, **ANSI dialect** (only builtin), compile → `(sql-string . params)`, DX to run on a connection.  
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

(sql-call :bump_counter :by 1)

;; Raw escape hatch — first-class, composable
(where (sql-and
        (:= :tenant-id tid)
        (sql-fragment "created_at > now() - interval '? days'" days)))
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

(defgeneric dialect-for-connection (connection) → sql-dialect)
(defgeneric compile-sql (statement &key dialect) → (values string params))
(defgeneric emit-sql (dialect node stream ctx) …)
```

Default compile dialect = **ANSI**. Open dialect hooks: `sql-extension`, `emit-alter-table-action`, `emit-create-type-kind`, `emit-create-table-extra`, `emit-insert-prefix` / `emit-insert-extras`, `emit-trigger-execute`, `register-sql-extension`, …

**Extension registry (types & operators):** SQL types can **read/write Lisp values as SQL expressions** — not just DDL names. JSON/BSON/arrays stay out of core; backends register adapters (`register-sql-type` / `register-sql-op` / `register-sql-func`).

**Literals vs params:** bare values / `lit` always emit SQL literal text. `?` / `$n` only from `bindparam` or `sql-fragment`.

### SQLAlchemy Core parity (shipped vs later)

Track against SQLAlchemy 2.0 Core expression language + schema/DDL (not ORM). Feature checklist only — APIs stay Lisp.

| Core area | Shipped (`sql-query` 0.2.0 + dialect backends) | Later / out of scope |
|-----------|-----------------------------------------------|----------------------|
| `select` / DML | `select` `insert-into` `update` `delete-from` + join/group/having/order/limit/offset; `values` selectable; `merge` / `truncate` | multi-table UPDATE edge cases |
| Distinct / locking | `distinct` (+ `DISTINCT ON` PG); `for-update` / `for-share` / key-share strengths | — |
| Set ops | `union*` `intersect*` `except*` (± ALL) | — |
| CTE / subquery | `cte` `with-cte` `subquery` `exists` `lateral` | — |
| Column elements | comparisons, `sql-and/or/not`, `in`/`between`/`like`(+ESCAPE)/`similar-to`, quantified, window/`over`, `FILTER`/`WITHIN GROUP`, named `WINDOW`, `TABLESAMPLE`, NULLS FIRST/LAST, `rollup`/`cube`/`grouping-sets`, … | richer codecs |
| Extensibility | type/op/func registries + open AST emit hooks | — |
| `text()` | `sql-fragment` / `sql-raw` | — |
| Schema / DDL | tables/indexes/views/schemas/sequences; type/domain; cast; grant/revoke; function/trigger; assertion; collation; CTAS; TABLE LIKE; TEMP; CHECK OPTION; ALTER COLUMN/DOMAIN; generated columns; DEFERRABLE | complex vendor ALTER only |
| Procedures | `proc-*` + lispy `body`; ANSI SQL/PSM + PG plpgsql | richer handlers / SIGNAL |
| Dialects | **ANSI** builtin; **sqlite3** + **postgres** (+ csv) | mysql backend |
| Upsert | PG/SQLite `on-conflict`; SQLite `insert-or` / `replace-into` | — |
| Vendor extras | PG COPY, matviews, partitions; PG ENUM/base TYPE | FDW, RLS, VACUUM/EXPLAIN, embedded SQL |
| Compile / execute | `compile-sql`; `execute-query` `fetch-*-query` | Result typing, async |
| Inspector / reflection | — | follow-on (`sql-orm` schema-ops cover model-side) |

**Done-when for #148:** wave-1 Core rows green + ANSI/backends split + Rove/CI — **met on `main`**. OCI **0.2.0** published (`sql-query`, `sql-query-postgres`, `sql-query-sqlite3`).

### Non-goals (`sql-query`)

- Re-hosting SxQL’s public API as ours  
- ORM identity map (→ `sql-orm`)  
- Parsing arbitrary SQL → AST  
- Vendoring NIST / sqllogictest as the test runner (first-party Rove only)  
- Embedded/module SQL, FDW, RLS, admin utilities (`VACUUM`/`EXPLAIN`, …)

---

## Layer 3 — `sql-orm` (first-party CLOS ORM)

**Repo:** [`egao1980/sql-orm`](https://github.com/egao1980/sql-orm) · nick **`stack-sql-orm`** · OCI **0.1.0**  
**Depends on:** `sql-protocol`, `sql-query` (+ dialect backend for live DB)  
**Issue:** [#149](https://github.com/egao1980/cl-stack/issues/149) · merged PR [#1](https://github.com/egao1980/sql-orm/pull/1)  
**Cookbook:** [cookbooks/sql.md](../cookbooks/sql.md)

Owns: `defmodel`, relations, `:compute`, persistence generics, schema snapshot/diff → reversible `schema-op` → sql-query DDL.  
Does **not** wrap Mito. Filters are **sql-query** expressions.

```lisp
(asdf:load-system "sql-backend-sqlite3")
(asdf:load-system "sql-query-sqlite3")
(asdf:load-system "sql-orm")

(defmodel user ()
  (id :integer :primary-key t :autoincrement t)
  (name :text :not-null t)
  (:table users)
  (:has-many posts post :key user-id)
  (:compute label (self)
    (format nil "~A" (name self))))

(with-orm-connection (c :driver :sqlite3 :database-name ":memory:")
  (ensure-schema c 'user)
  (persist (make-instance 'user :name "ada"))
  (select-instances 'user :where (:= :name "ada")))
```

---

## Repo layout (locked)

| Layer | Repo / systems | Version |
|-------|----------------|---------|
| Connectivity | `egao1980/sql-protocol` + `sql-backend-*` | OCI **0.1.0** |
| Core / query | `egao1980/sql-query` · `sql-query-sqlite3` · `sql-query-postgres` · `sql-query-csv` | OCI **0.2.0** (query + sqlite/pg; csv separate) |
| ORM | `egao1980/sql-orm` | OCI **0.1.0** |

**Imports** (`cl-stack-systems`): `cl-dbi`, `dbd-*`, … as needed. SxQL/Mito are **not** required by the first-party SQL stack.

---

## Bakeoff

**cl-dbi** for connectivity; **first-party CLOS DSL** for generation; **first-party `sql-orm`** for DAO/schema.  
Postmodern escape hatch; CLSQL reject.  
SxQL/Mito = prior art only — not the public façade.

---

## Cookbooks (with impl)

See [cookbooks/sql.md](../cookbooks/sql.md).

1. Connectivity: SQLite connect / execute / txn / pool — **done** with `sql-protocol`  
2. Core: composable select/insert + DDL + `sql-fragment` on protocol connection  
3. ORM: `defmodel` CRUD + schema-op upgrade/downgrade (SQLite CI)

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
- [x] Import cl-dbi / dbd-* — [#146](https://github.com/egao1980/cl-stack/issues/146)  
- [x] `sql-protocol` + pool + sqlite3/postgres — [#147](https://github.com/egao1980/cl-stack/issues/147)  
- [x] `sql-query` ANSI Core DSL + dialect backends (wave-1 on `main`) — [#148](https://github.com/egao1980/cl-stack/issues/148)  
- [x] OCI publish `sql-query{,-sqlite3,-postgres}` **0.2.0**  
- [x] `sql-orm` merge + OCI **0.1.0** + cookbook — [#149](https://github.com/egao1980/cl-stack/issues/149)  

**Impl order:** ~~imports → connectivity → query → ORM~~ — **wave-1 complete**.

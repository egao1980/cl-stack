# SQL stack (P2) — three layers

**Issues:** [#101](https://github.com/egao1980/cl-stack/issues/101)  
**Status:** brief **re-locked** — **three separate layers** (SQLAlchemy-shaped)

```text
sql-orm          ← ORM (Mito facade)          ~ SQLAlchemy ORM
    │
sql-query        ← SQL generation (SxQL)      ~ SQLAlchemy Core
    │
sql-protocol     ← connectivity + pooling     ~ Engine / Connection / Pool / DB-API
    │
driver backends  ← sqlite3 / postgres         ~ DBAPI drivers / dialect
```

Apps pick the layer they need. Libs that only execute SQL depend on **`sql-protocol`**. Query builders depend on protocol (+ optionally emit via it). ORM depends on query + protocol.

Conventions: [API.md](../API.md). Config: [config.md](config.md). Gap: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Prior art

| Layer | Java | Python | CL pin |
|-------|------|--------|--------|
| **Connectivity** | JDBC `DataSource` / pool | DB-API + SQLAlchemy Engine/Pool | **cl-dbi** + drivers |
| **SQL generation** | jOOQ / QueryDSL | **SQLAlchemy Core** | **SxQL** |
| **ORM** | JPA / Hibernate | **SQLAlchemy ORM** | **Mito** |

---

## Locked decisions (cross-cutting)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Separation** | **Three first-party systems** (separate repos preferred) | Clear deps; no “Mito in the protocol” |
| **Connectivity pin** | **[cl-dbi](https://github.com/fukamachi/cl-dbi)** | Portable DBI; do not reimplement drivers |
| **Default driver (A)** | **SQLite3** (`dbd-sqlite3`) | Windows-primary + CI zero-ops |
| **Second driver (B)** | **PostgreSQL** (`dbd-postgres`) | Prod services |
| **MySQL** | Watchlist | cl-dbi/Mito support; not wave-1 |
| **Postmodern** | Escape hatch only | Postgres-native; not portable default |
| **Query pin** | **[SxQL](https://github.com/fukamachi/sxql)** | Shared AST; Core analogue — **not** reimplemented |
| **ORM pin** | **[Mito](https://github.com/fukamachi/mito)** | AR-shaped; migrations; uses SxQL |
| **Pooling** | **In `sql-protocol` wave-1** (simple pool) | User-required; not deferred |
| **Row shape** | plist default; optional alist/hash | json-protocol kinship |
| **Config** | DSN-ish keys via `cl-stack-config` | `database.driver`, `database.url`, … |
| **Natives** | SQLite / libpq system or overlay follow-on | Document until overlays |

---

## Layer 1 — `sql-protocol` (connectivity)

**Repo:** `egao1980/sql-protocol` · nick **`stack-sql`**  
**Backends:** `sql-backend-sqlite3`, `sql-backend-postgres` (colocated ASD systems OK)

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

**Pooling (wave-1 minimum):** fixed max size, checkout/release, wait or error when exhausted, disconnect-on-release optional. Not a full PgBouncer; good enough for HTTP workers.

**Conditions:**

```text
sql-error
├── sql-connection-error
├── sql-programming-error
├── sql-integrity-error
├── sql-operational-error
└── sql-pool-timeout
```

---

## Layer 2 — `sql-query` (SQL generation / Core)

**Repo:** `egao1980/sql-query` · nick **`stack-sql-query`**  
**Depends on:** `sql-protocol`, **sxql**

Owns: building portable SQL ASTs and compiling them to `(sql-string . params)`, plus DX to run them on a connection.  
Does **not** own connections/pools or ORM.

```lisp
;; Thin stack DX over SxQL — do not fork SxQL
(defun select (&rest clauses) …)     ; → sxql statement
(defun insert-into …)
(defun update …)
(defun delete-from …)

(defun compile-sql (query &key (type :mysql/:postgres/:sqlite3))
  "→ (values sql-string params) via sxql:yield")

(defun execute-query (connection query &key)
  "compile-sql + sql-protocol:execute")
(defun fetch-query / fetch-all-query …)
```

Dialect for `yield` comes from the connection/backend (sqlite vs postgres). Raw strings still go straight to `sql-protocol:execute`.

**Non-goals:** inventing a second AST; LINQ-style deferred ORM queries (that's Mito).

---

## Layer 3 — `sql-orm` (ORM facade)

**Repo:** `egao1980/sql-orm` · nick **`stack-sql-orm`** (or `cl-stack-sql` if we prefer facade naming)  
**Depends on:** `sql-protocol`, `sql-query`, **mito**

Owns: model / DAO DX, migrations sketch, wiring `mito:*connection*` to protocol connections.  
Does **not** reimplement `deftable` — Mito keeps macros.

```lisp
(asdf:load-system "sql-backend-sqlite3")
(asdf:load-system "sql-orm")

(stack-sql:with-connection (c :driver :sqlite3 :database-name ":memory:")
  (sql-orm:use-connection c)           ; sets mito:*connection*
  (mito:ensure-table-exists 'user)
  (mito:insert-dao (make-instance 'user :name "ada")))
```

Migrations: Mito tooling in cookbook; protocol stays execution-only.

---

## Repo layout (locked)

| Layer | Repo / systems |
|-------|----------------|
| Connectivity | `egao1980/sql-protocol` + `sql-backend-sqlite3` + `sql-backend-postgres` |
| Core / query | `egao1980/sql-query` |
| ORM | `egao1980/sql-orm` |

**Imports** (`cl-stack-systems`): `cl-dbi`, `dbd-sqlite3`, `dbd-postgres`, `sxql`, `mito` (+ transitive).

---

## Bakeoff (unchanged verdict)

**cl-dbi + SxQL + Mito** default; Postmodern escape hatch; CLSQL reject.  
Difference from prior brief: **pooling in protocol**, and **SxQL/Mito are not stuffed into `sql-protocol`**.

---

## Cookbooks (with impl)

1. Connectivity: SQLite connect / execute / txn / pool checkout  
2. Core: SxQL select/insert via `sql-query` on protocol connection  
3. ORM: Mito CRUD + migration sketch (SQLite CI; Postgres Ubuntu job)

---

## Non-goals (this wave)

- Postmodern as default  
- Full PgBouncer-grade pool product  
- NoSQL  
- Replacing SxQL  
- Multi-tenant routers  

---

## Implementation tasks

- [x] Brief lock (three-layer) — this doc / #101  
- [ ] Import cl-dbi / dbd-* / sxql / mito — [#146](https://github.com/egao1980/cl-stack/issues/146) (supersedes #127)  
- [ ] `sql-protocol` + pool + sqlite3/postgres — [#147](https://github.com/egao1980/cl-stack/issues/147) (supersedes #128/#129 connectivity)  
- [ ] `sql-query` over SxQL — [#148](https://github.com/egao1980/cl-stack/issues/148)  
- [ ] `sql-orm` over Mito + cookbook — [#149](https://github.com/egao1980/cl-stack/issues/149)  

**Impl order:** imports → **connectivity** → **query** → **ORM**.

Old children #127–#129 superseded by the above.

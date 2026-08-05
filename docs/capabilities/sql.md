# sql-protocol (P2)

**Issues:** [#101](https://github.com/egao1980/cl-stack/issues/101)  
**Status:** brief **locked** — CLOS protocol + **driver backends** + Mito/SxQL facade (not “Postmodern-only”, not inventing a second DBI)

One app DX for relational SQL: connect, execute, fetch, transactions. Drivers swap like JDBC. Optional ORM facade for small-business CRUD (ActiveRecord/Django shape).

Conventions: [API.md](../API.md). Config: [config.md](config.md). JSON: [json-protocol.md](json-protocol.md). Gap row: [STDLIB-GAP.md](../STDLIB-GAP.md).

---

## Prior art (shape targets)

| Ecosystem | Library | What we steal |
|-----------|---------|---------------|
| **Java** | [JDBC](https://docs.oracle.com/javase/tutorial/jdbc/) | `Connection` / `PreparedStatement` / `ResultSet`; driver SPI |
| **Java** | JPA / Hibernate | Optional ORM — **not** required for protocol |
| **Python** | [DB-API 2.0](https://peps.python.org/pep-0249/) | `connect` / `cursor` / `execute` / `fetch*` |
| **Python** | [SQLAlchemy](https://www.sqlalchemy.org/) Core + ORM | Core ≈ query builder; ORM ≈ Mito |
| **Ruby** | ActiveRecord | Migrations + timestamps — Mito already mirrors this |

CL already has the JDBC/DB-API analogue: **[cl-dbi](https://github.com/fukamachi/cl-dbi)**. Protocol **thin-wraps** it (conditions, pool hooks, stack DX) — does **not** reimplement drivers.

---

## Locked decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Shape** | **CLOS protocol + driver backends** + optional ORM facade | #101 “cl-dbi + SxQL + Mito”; multi-driver is the backend axis (sqlite / postgres) |
| **Wire / DBI pin** | **[cl-dbi](https://github.com/fukamachi/cl-dbi)** | De-facto portable DBI; drivers load on demand (`dbd-sqlite3`, `dbd-postgres`, `dbd-mysql`) |
| **Query builder** | **[SxQL](https://github.com/fukamachi/sxql)** | Shared SQL AST for Mito + raw queries; not reimplemented |
| **ORM facade (default app DX)** | **[Mito](https://github.com/fukamachi/mito)** | Migrations, relationships, `created_at`/`updated_at`; SQLite + Postgres + MySQL |
| **Default driver (A)** | **SQLite3** (`dbd-sqlite3`) | Windows-primary + zero-ops for cookbooks/CI; file or `:memory:` |
| **Second driver (B)** | **PostgreSQL** (`dbd-postgres`) | Production default for services; overlay/native story via libpq / existing Postgres installs |
| **Not wave default** | **MySQL** | Supported by cl-dbi/Mito; pin later if demand — watchlist |
| **Not stack default** | **[Postmodern](https://github.com/marijnh/Postmodern)** alone | Excellent Postgres-native; skips portable path; escape hatch OK for Postgres specialists |
| **Also considered** | **CLSQL** | Older multi-backend; prefer cl-dbi ecosystem (Mito/SxQL) |
| **Also considered** | **cl-sqlite** direct | Useful escape hatch; cookbooks go through protocol/cl-dbi |
| **Connection config** | DSN-ish keys via `cl-stack-config` | e.g. `database.driver`, `database.name`, `database.url` |
| **Row shape** | **plist** default (cl-dbi); optional alist/hash via keys | Align with json-protocol for API rows |
| **Transactions** | `with-transaction` macro → backend begin/commit/rollback | Conditions → rollback |
| **Pooling** | Protocol hook / follow-on | Wave-1 = single connection + explicit `disconnect`; pool = P2 once HTTP/server apps need it |
| **Migrations** | Mito migration tooling in facade cookbook | Protocol stays SQL-execution; schema DX in Mito layer |
| **Selection DX** | ASDF + `*sql-backend*` **or** connect `:driver` keyword | Load `sql-backend-sqlite3` / `sql-backend-postgres`; connect selects driver |
| **Natives** | SQLite / libpq via system packages or future overlays | Document QL/system deps until overlays exist; Windows SQLite via prebuilt DLL overlay follow-on |

**Supersedes** vague “pin Mito.” **Protocol = DBI lifecycle**; **backends = drivers**; **Mito = facade** (like `cl-stack-http` over `http-protocol`).

---

## Bakeoff scorecard (#101)

Scores: **1** … **5** for cl-stack needs.

| Criterion | cl-dbi+SxQL+Mito | Postmodern | CLSQL | cl-sqlite alone |
|-----------|------------------|------------|-------|-----------------|
| Multi-driver (sqlite→pg) | **5** | **1** | **4** | **1** |
| Windows / SQLite cookbooks | **5** | **1** | **3** | **5** |
| ORM + migrations | **5** (Mito) | **2** | **2** | **1** |
| Query builder | **5** (SxQL) | **3** (S-SQL) | **3** | **1** |
| Ecosystem / Fukamachi stack | **5** | **4** | **2** | **3** |
| Postgres-native power | **3** | **5** | **3** | **1** |
| Overlay / native cost | **3** | **3** | **3** | **4** |
| **Wave role** | **Default stack** | escape hatch | reject | escape hatch |

**Driver sub-score (backends):**

| Criterion | SQLite3 | Postgres | MySQL |
|-----------|---------|----------|-------|
| Dev / CI / Windows | **5** | **3** | **2** |
| Prod services | **2** | **5** | **4** |
| **Wave role** | **Default (A)** | **Second (B)** | watchlist |

**Verdict:** **sql-protocol** over **cl-dbi**; backends **sqlite3** + **postgres**; app facade **Mito + SxQL**. Postmodern documented as Postgres escape hatch, not pin.

---

## Repo layout (locked)

| Layer | Repo / system |
|-------|----------------|
| Protocol + conformance | `egao1980/sql-protocol` (nick `stack-sql`) |
| Driver backend A | `sql-backend-sqlite3` (wraps `dbd-sqlite3`) |
| Driver backend B | `sql-backend-postgres` (wraps `dbd-postgres`) |
| ORM facade | `egao1980/cl-stack-sql` **or** pin Mito directly as facade — prefer thin `cl-stack-sql` only if cookbook DX needs stacking over raw Mito |

**Third-party imports** (`cl-stack-systems`): `cl-dbi`, `dbd-sqlite3`, `dbd-postgres`, `sxql`, `mito` (+ transitive). MySQL driver optional later.

Wave-1 MVP may colocate protocol + sqlite backend; split before metapackage pain.

---

## Protocol surface

Package nick: `stack-sql` (system `sql-protocol`).

### Value types

```lisp
(defclass sql-backend () ())
(defvar *sql-backend* nil)
(defvar *sql-connection* nil)

(defclass sql-connection () ())   ; may wrap dbi:<dbi-connection>
```

### Generics / DX

```lisp
(defgeneric backend-connect (backend &key database-name host port
                                    username password options)
  (:documentation "→ sql-connection. Backend encodes driver-specific keys."))

(defgeneric disconnect (connection))
(defgeneric ping (connection))

(defgeneric execute (connection sql &optional params)
  (:documentation "SQL string or SxQL clause; params = list."))

(defgeneric fetch (query &key)
  (:documentation "Next row as plist, or NIL."))

(defgeneric fetch-all (query &key))

(defmacro with-connection ((var &rest connect-keys) &body body) …)
(defmacro with-transaction ((connection) &body body) …)

;; Convenience
(defun connect (&key (driver :sqlite3) &allow-other-keys)
  "Select backend by driver keyword; bind *sql-connection* optionally.")
```

Escape hatch: `(sql:raw-connection conn)` → underlying `dbi` connection for Mito (`mito:*connection*`).

### ORM facade (Mito)

```lisp
;; Recommended app path (cookbook)
(asdf:load-system "sql-backend-sqlite3")
(asdf:load-system "mito")   ; or cl-stack-sql if we add sugar

(stack-sql:with-connection (c :driver :sqlite3 :database-name #p"app.db")
  (setf mito:*connection* (stack-sql:raw-connection c))
  (mito:ensure-table-exists 'user)
  (mito:insert-dao (make-instance 'user :name "ada")))
```

Protocol does **not** redefine `deftable` — Mito keeps model macros.

### Conditions

```lisp
sql-error
├── sql-connection-error
├── sql-programming-error     ; bad SQL / params
├── sql-integrity-error       ; unique / FK
└── sql-operational-error     ; locked DB, timeout
```

Map from cl-dbi conditions where possible.

---

## Cookbook (with impl)

1. SQLite CRUD with Mito (in-memory CI smoke)  
2. Same models against Postgres (service compose)  
3. Raw SxQL select via protocol `execute` without ORM  

---

## Non-goals (this wave)

- Postmodern as default  
- Full connection pool product (document hook only)  
- NoSQL / Redis  
- Multi-tenant schema routers  
- Replacing SxQL with another query DSL  

---

## Implementation tasks

- [x] Brief lock (this doc) — [#126](https://github.com/egao1980/cl-stack/issues/126)
- [ ] Import cl-dbi / dbd-* / sxql / mito — [#127](https://github.com/egao1980/cl-stack/issues/127)
- [ ] `sql-protocol` + sqlite3 backend — [#128](https://github.com/egao1980/cl-stack/issues/128)
- [ ] postgres backend + Mito cookbook — [#129](https://github.com/egao1980/cl-stack/issues/129)

Child issues under #101. Start after logging wave (#123–#125).

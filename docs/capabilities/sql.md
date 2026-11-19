# SQL stack (P2) — three layers + runner

**Issues:** [#101](https://github.com/egao1980/cl-stack/issues/101)  
**Status:** three layers + runner **shipped** — `sql-protocol` **0.1.0** · `sql-query{,-postgres,-sqlite3}` **0.2.0** · `sql-orm` **0.2.0** · `sql-migrate` **0.1.1** (linear Alembic-style; no second DDL). **S2** (`sql-migrate` 0.2.0 on `revision-protocol` + `diff-protocol`) contract locked — see [sql-migrate 0.2.0 — S2 locked](#sql-migrate-020--s2-locked). Cookbook: [cookbooks/sql.md](../cookbooks/sql.md)

```text
sql-migrate          ← revision runner                ~ Alembic (linear 0.1.0)
    │
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
**0.2.0 (S1, contract locked):** pure snapshot fold, `alter-column-op`, faithful `diff-schema :complete t`, `reflect-schema` (SQLite, PostgreSQL), footprints — see [sql-orm 0.2.0 — S1 locked](#sql-orm-020--s1-locked).  
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

## sql-orm 0.2.0 — S1 locked

**Plan:** workspace `docs/HARNESS-PLAN.md` → R2 detail, milestone **S1** (algebra additions).  
**Contract branch:** [`egao1980/sql-orm` `agent/sql-orm-s1-c7ff`](https://github.com/egao1980/sql-orm/tree/agent/sql-orm-s1-c7ff). Its stubs fail with `orm-error` "… is not implemented yet (sql-orm 0.2.0 S1)", and the new Rove files are the acceptance tests: `tests/s1-fixtures.lisp`, `tests/algebra-test.lisp`, `tests/reflect-test.lisp`.  
**Scope:** `sql-orm` stays the schema algebra. It does **not** depend on `revision-protocol` or `diff-protocol`. Those come in S2 (`sql-migrate` 0.2.0). `sql-migrate` 0.1.x keeps working unchanged.

### Exports added

```lisp
;; ops
(defclass alter-column-op (schema-op) …)        ; :table-name :from :to
(schema-op-from-column op) (schema-op-to-column op) (schema-op-column-name op)
;; algebra (pure)
(apply-ops-to-snapshot snapshot ops) → new snapshot   ; ops: list | schema-op | schema-migration
(diff-schema from to &key drop-tables drop-columns complete dialect)
(schema-snapshot-equal a b &key dialect)
(column-info-equal a b &key dialect)
(canonical-type-sql dialect-key type-sql) → string    ; GF
(schema-dialect-key dialect) → keyword
(schema-op-footprint op) → list of strings            ; GF
;; live database
(reflect-schema connection &key exclude dialect schema) → snapshot
(reflect-schema-using dialect-key connection &key exclude schema)   ; GF
(reflection-query dialect-key kind &key table schema) → (values sql params)   ; GF
(dialect-schema-op-statements dialect-key op direction connection) → DDL AST list   ; GF
;; conditions (all subtypes of orm-error)
invalid-schema-op (invalid-schema-op-op)
snapshot-conflict (snapshot-conflict-op)
reflection-unsupported (reflection-unsupported-dialect)
```

### Snapshot and dialect designators

- A snapshot is unchanged from 0.1: a list of `(table-name . column-infos)`. Model snapshots use keyword table names (`:items`). Reflected snapshots use strings (`"items"`). Column names are strings or symbols. All names compare with `string-equal`.
- A `:dialect` argument is `nil` (ANSI), a keyword registered in `sql-query:*sql-dialect-registry*` (`:sqlite3`, `:postgres`, `:ansi`), or a `sql-dialect` instance.
- `schema-dialect-key`: `nil` → `:ansi`; a keyword → itself; an instance → the key it is registered under, `:ansi` for an unregistered `ansi-dialect`, otherwise `nil`. sql-orm dispatches on this keyword (EQL methods), so it needs neither `sql-query-sqlite3` nor `sql-query-postgres` at load time.

### Equality (locked)

`column-info-equal a b :dialect d` is true when all of these hold:

| Attribute | Rule |
|-----------|------|
| name | `string-equal` |
| type | `string=` of `(canonical-type-sql key (dialect-type-sql d type))`. A string type renders as itself, so reflected `"INTEGER"` equals `:integer` on SQLite, and `:boolean` equals `"INTEGER"` on SQLite |
| primary-key, unique, autoincrement | compared as booleans |
| not-null | `(or not-null primary-key)` on each side, so a primary key is implicitly NOT NULL |
| default | `nil` = no default. Otherwise compare the SQL text the dialect emits: a `sql-node` emits as itself, any other value emits as `(lit value)`. `0` equals `(sql-raw "0")`, `"x"` equals `(sql-raw "'x'")`, and `t` equals `(sql-raw "1")` on SQLite |

`canonical-type-sql` (default method): upcase, trim, collapse runs of whitespace to one space, and drop spaces next to `(` `,` `)`. The `:postgres` method also folds catalog spellings to sql-query's: `character varying(n)`→`VARCHAR(N)`, `character(n)`→`CHAR(N)`, `timestamp with time zone`→`TIMESTAMPTZ`, `timestamp without time zone`→`TIMESTAMP`, `time without time zone`→`TIME`, `int`/`int4`→`INTEGER`, `int8`→`BIGINT`, `int2`→`SMALLINT`, `bool`→`BOOLEAN`, `float8`→`DOUBLE PRECISION`, `float4`→`REAL`.

`schema-snapshot-equal`: the tables match one to one by name, and so do the columns within each table, under `column-info-equal`. **Table order and column order are not significant.** Alembic does not diff column order either, and treating order as significant would turn a reorder into a lossy drop and re-add.

With `:dialect nil`, equality is the ANSI rendering, so `:text`, `:string` and `:varchar` are all `CHARACTER VARYING` and equal. Callers comparing a reflected snapshot must pass the connection's dialect.

### `apply-ops-to-snapshot` (pure)

- The function returns a new snapshot. It does not modify `snapshot` or the ops, and the result shares no `column-info` with either.
- `create-table-op` appends a table and `drop-table-op` removes one. `add-column-op` appends a column and `drop-column-op` removes one. `alter-column-op` replaces the column **in place** with a copy of its `to`.
- The function signals `snapshot-conflict` (slot `op`) on: a create of an existing table; a drop of a missing table; an add of an existing column or to a missing table; a drop or alter of a missing column. It checks presence by name only.

### `diff-schema :complete t` (the faithful diff)

- Law: `(schema-snapshot-equal (apply-ops-to-snapshot a (diff-schema a b :complete t :dialect d)) b :dialect d)`.
- When `:complete` is true, `:drop-tables` and `:drop-columns` are ignored. `:dialect` is the equality used to decide whether a column changed.
- A column present on both sides is handled by what changed:
  - Only type, not-null or default changed: one `alter-column-op` (from, to).
  - primary-key, unique or autoincrement changed: `drop-column-op` then `add-column-op`. This is lossy, and S2 flags it.
- **Op order (locked):** go through tables in TO order. A new table gets `create-table-op`. An existing table gets `drop-column-op`s (removed or re-added columns, in FROM order), then `add-column-op`s (TO order), then `alter-column-op`s (TO order). Last come `drop-table-op`s in FROM order.
- An identical pair, or a pair that differs only in order or name case, gives `nil`.
- **The default (`:complete nil`) is the 0.1 autogenerate policy, unchanged.** It makes no alters, adds before drops per table, and drops tables only with `:drop-tables t`. The corpus test checks the default kinds for every pair. `make-migration` keeps the default.

### `alter-column-op`

- `from` and `to` are complete `column-info`s. They must share name (`string-equal`), primary-key, unique and autoincrement. Otherwise `initialize-instance` signals `invalid-schema-op`.
- `invert-schema-op` swaps `from` and `to` and copies both columns.
- `schema-op-upgrade` and `schema-op-downgrade` return the **portable** form: `alter-table-statement`s with one action per changed attribute. A type change gives `ALTER COLUMN c SET DATA TYPE t`. Nullability gives `SET NOT NULL` or `DROP NOT NULL`. A default gives `SET DEFAULT <lit>` or `DROP DEFAULT`. PostgreSQL accepts this as is. A string default is a literal (`(lit "b")`), not a column reference.
- **SQLite** has no `ALTER COLUMN`. `upgrade-schema` and `downgrade-schema` therefore get each op's statements from `dialect-schema-op-statements` **just before running that op**, after earlier ops have run. The default method returns `schema-op-upgrade` or `schema-op-downgrade`. The `(eql :sqlite3)` method for `alter-column-op` reflects the table on the same connection and rebuilds it:
  1. `CREATE TABLE <t>__sql_orm_rebuild` with the altered column list.
  2. `INSERT INTO … (cols) SELECT cols FROM <t>`.
  3. `DROP TABLE <t>`.
  4. `ALTER TABLE … RENAME TO <t>`.
- The rebuild runs inside the caller's transaction, so a failure leaves the table and no rebuild table. Rows, primary-key values and AUTOINCREMENT continue. SQLite type affinity converts stored values.
- Documented limit: the rebuild recreates only what `column-info` models. Other indexes, triggers and foreign keys on that table are not preserved (sql-orm DDL does not emit them).
- `schema-ops-upgrade` (offline AST) stays portable.

### `schema-op-footprint`

- Table ops (`create-table-op`, `drop-table-op`) return `("table:<t>")`.
- Column ops (`add-column-op`, `drop-column-op`, `alter-column-op`) return `("column:<t>.<c>")`.
- Names are downcased, and each call returns a fresh list. An op and its inverse have the same footprint.
- Consumers (S3 conflict detection) treat `"table:<t>"` as covering every `"column:<t>.<c>"`.

### `reflect-schema`

- Signature: `(reflect-schema connection &key exclude dialect schema)`.
- `dialect` defaults to `(sql-query:dialect-for-connection connection)`. The call dispatches to `reflect-schema-using` on its key. The default method signals `reflection-unsupported` (slot `dialect` = the key) without issuing a query.
- Queries go through `sql-protocol:execute` with the SQL and params from `reflection-query`, and rows come back through `sql-protocol:fetch-all`. No transaction is opened.
- `exclude` is a list of names (`string-equal`) or a predicate on the table-name string.
- The result has string table names in `string<` order and columns in table order. Types are the catalog strings, verbatim. Defaults are `sql-node`s (`sql-raw` of the catalog text).

**SQLite** (tested live, in memory):

- Tables come from `sqlite_master` where `type = 'table'`; `sqlite_%` tables are skipped (`sqlite_sequence` and others).
- Columns come from `pragma_table_info(t)`, which gives `cid, name, type, notnull, dflt_value, pk`:
  - type is the declared type string (empty → `nil`)
  - primary-key = `pk > 0`
  - not-null = `notnull = 1`
  - default = `nil` when NULL, else `(sql-raw dflt_value)` (`0`, `'x'`)
- autoincrement = primary key **and** the table's `sqlite_master.sql` contains `AUTOINCREMENT` (case-insensitive).
- unique comes from `pragma_index_list(t)` rows with `unique = 1` and `origin = 'u'` whose `pragma_index_info` has exactly one column.
- `reflection-query :sqlite3` kinds: `:tables`, `:columns`, `:indexes`, `:index-columns`.

**PostgreSQL** (tested through generated SQL and a canned connection; no server):

- `(reflection-query :postgres :tables &key (schema "public"))`: `SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_type = 'BASE TABLE' ORDER BY table_name`. Params are `(schema)`.
- `(reflection-query :postgres :columns &key (schema "public"))` is one query over every table in the schema:
  - Sources: `pg_catalog.pg_class`, `pg_namespace` and `pg_attribute` (`attnum > 0 AND NOT attisdropped`, `relkind = 'r'`, `nspname = $1`), with `LEFT JOIN pg_attrdef` for defaults.
  - Ordered by table name, then `attnum`. Params are `(schema)`.
  - Column aliases (locked): `table_name`, `column_name`, `data_type` = `format_type(atttypid, atttypmod)`, `not_null` = `attnotnull`, `column_default` = `pg_get_expr(adbin, adrelid)`, `identity` = `attidentity`, `is_primary_key` and `is_unique`. The last two are `EXISTS` over a single-column `pg_index` with `indisprimary`, or with `indisunique AND NOT indisprimary`.
- PostgreSQL reflection issues exactly these two queries, once each.
- Row decoding: the plist keys are upcased (`:TABLE_NAME`, …). SQL NULL arrives as `nil` or `:null`, booleans as `t` or `nil`.
  - type = `data_type` verbatim (`"character varying(64)"`).
  - autoincrement = `identity` ∈ {`"a"`, `"d"`}, or a default that starts with `nextval(`. In the nextval case the default becomes `nil`.
  - Trailing `::type` casts outside quoted literals are stripped from defaults: `'a::b'::character varying` → `'a::b'`.
- `:schema` selects the PostgreSQL schema, and SQLite ignores it.

### Tests (contract)

The suite loads `sql-query-postgres` (no driver; it does not take `*sql-dialect*` from SQLite) and adds it to `:ci :with`.

**Corpus.** `s1-fixtures.lisp` holds 19 snapshot pairs:

- create, drop table, add, add NOT NULL with default, drop column
- type change, set and drop NOT NULL, set, change and drop default, all three at once, varchar length
- unique toggle, primary-key toggle
- a multi-table mix, identity, reorder only, name case

Each pair records its locked complete and default op kinds. 17 pairs are marked live; the unique and primary-key toggles are not, because SQLite cannot `ADD COLUMN` a UNIQUE or PRIMARY KEY column.

**Tests** (`deftest-parametrize` rows are corpus ids):

| Test | Property |
|------|----------|
| `apply-diff-roundtrip/*` (19) | the law above; purity; no shared column-infos |
| `inverse-roundtrip/*` (19) | fold of `migration-downgrade-ops` restores `a`; `apply-ops-to-snapshot` takes a migration |
| `double-inverse/*` (19) | invert∘invert keeps classes, footprints and result |
| `diff-kinds/*` (19) | locked op order for `:complete t`; the default diff is unchanged |
| `reflect-after-create/*` (17) | `reflect-schema` after `upgrade-schema(diff-schema(nil, s))` = `s` (`:sqlite3`) for both sides of each live pair |
| `reflect-after-complete-diff/*` (17) | upgrade `a` → complete diff → reflect = `b` → downgrade → reflect = `a` |
| `alter-column-sqlite-*` (3) | nullability and default end to end with data; type change with affinity and AUTOINCREMENT; a failing rebuild rolls back |
| `postgres-reflection-queries`, `postgres-reflect-canned` | generated SQL and params; decoding; exclude; exactly two queries |
| Remaining tests | conflicts, validation, DDL text, equality table, canonical types, dialect keys, footprints, exclude, the unsupported dialect |

**Counts.** 178 new tests and 7 existing ones. On the contract branch all 178 new tests fail cleanly and all 7 existing ones pass.

### Release

`sql-orm` **0.2.0**: bump `:version` when S1 is green, then publish from the owning repo (skill **pr-merge-publish**). `sql-migrate` needs no change for S1.

---

## sql-migrate 0.2.0 — S2 locked

**Plan:** workspace `docs/HARNESS-PLAN.md` → R2 detail, milestone **S2** (linear graphs on `revision-protocol` + `diff-protocol`). S3 (branches, merge revisions, multi-head version table, footprint conflicts) and S4 (projections, capture, spec replay) come later.
**Contract branch:** [`egao1980/sql-migrate` `agent/sql-migrate-s2-9d73`](https://github.com/egao1980/sql-migrate/tree/agent/sql-migrate-s2-9d73). Its stubs signal an internal `not-implemented` error ("… is not implemented yet (sql-migrate 0.2.0 S2)"). It is deliberately neither a `migrate-error` nor a `revision-error`, so no test can pass by expecting one. The new Rove files are the acceptance tests: `tests/s2-fixtures.lisp`, `engine-test.lisp`, `directory-test.lisp`, `target-test.lisp`, `compat-test.lisp`, `condition-test.lisp`. The 0.1 implementations stay in place on the branch so the 0.1 suite keeps running.
**Dependencies:** `sql-orm` 0.2.0, `revision-protocol` 0.2.0 (local nickname `rev`), `diff-protocol` 0.2.0 (`diff`). The suite also loads `sql-query-postgres` (no driver, for the `:sql` render) and adds it to `:ci :with`. No PostgreSQL server; SQLite in memory.

### Exports added

```lisp
;; conditions
multiple-heads (multiple-heads-heads)          ; subtype of branch-not-supported
;; schema diff engine (diff-protocol)
schema-diff-engine  (make-schema-diff-engine &key dialect)  (schema-engine-dialect e)
schema-diff         (make-schema-diff ops &key engine level) (schema-diff-ops d)
schema-change       (change-schema-op c) (change-lossy-p c)
(diff-lossy-p d) (step-lossy-p step)
;; SQL target (revision-protocol)
sql-target (make-sql-target connection &key directory version-table dialect (check-drift t))
(target-connection tg) (target-directory tg) (target-version-table tg) (target-dialect tg)
(target-check-drift-p tg)
;; runner
(current-revisions connection dir)
```

Every 0.1 export stays: `upgrade`, `downgrade`, `current-revision`, `stamp`, `ensure-version-table`, `history`, `head-revision`, `make-revision`, `register-revision`, `find-revision`, `require-revision`, `make-script-directory`, `directory-version-table`, `script-directory`, and the conditions with their readers.

### Decisions

| Decision | Choice |
|----------|--------|
| **Store** | `script-directory` is a subclass of `stack-rev:in-memory-store`. `make-script-directory &key version-table dialect` makes it with `:primary :delta` and a `schema-diff-engine` of that dialect (default `nil`, ANSI equality). Each registered migration is one revision: id = `:revision`, parents = `(:down-revision)` or none, message = the migration name. |
| **Content** | A revision's content is `(make-schema-diff (migration-upgrade-ops m))`: a `schema-diff`, so the store classifies it as a delta. `revision-delta` returns it as stored (`eq`). `revision-state` folds the deltas from the root with `apply-ops-to-snapshot`. `walk-revisions :footprint` works on the op footprints. |
| **register-revision** | Same checks as 0.1: a non-empty string id (else `migrate-error`), unique (else `migrate-error` with the id). **New:** the down-revision must be `nil` or already registered, else `unknown-revision`, and nothing is stored. Forks are accepted. Merge revisions (a list down-revision) are S3. |
| **find-revision** | Exact id match, returning the `schema-migration` (`eq` to the registered object), or `nil`. No id-prefix matching. `stack-rev:resolve-revision` on the directory keeps R0a's unique-prefix rule. `require-revision` is unchanged: `unknown-revision` with a `use-value` restart. |
| **history** | The migrations in `walk-revisions :topo` order from every head: parents first, root to head on a linear graph. **It never signals `branch-not-supported`.** Empty → `nil`. |
| **head-revision** | The id of the single head, or `nil` when empty. Several heads → `multiple-heads` (heads sorted `string<`) with a `use-value` restart (the id is returned as is). `make-revision` defaults its parent to `head-revision`, so on a fork it signals unless `:down-id` is given. |
| **Fork refusal (S2)** | `plan-transition` on a directory with more than one head signals **`branch-not-supported`** (that class exactly, not `multiple-heads`), whatever the goal, **before reading the target**. `upgrade` / `downgrade` resolve `:head` first (so `upgrade` with the default target signals `multiple-heads`). Every other target form reaches `plan-transition` and gets `branch-not-supported`. They always plan, even when there is nothing to do, so `downgrade :target :base` on a fork is refused too. Nothing is applied or stamped. `branch-not-supported` stays exported and is deprecated. It is the parent of `multiple-heads`, so 0.1 handlers still catch every fork refusal. |
| **Plans** | A `plan-transition` method on `script-directory` (linear graphs). TO is a designator, or `nil` for the empty state (then `plan-goal` is `nil`). Steps go `:down` from the target's revision to the merge-base, then `:up` to TO, one parent edge each (the R0b shape). An `:up` step to R has `step-diff` = `(revision-delta dir R)` (`eq`, the migration's own ops). A `:down` step from R has `(invert-diff (revision-delta dir R))`. What runs is the script, not a re-diff of states, as in 0.1. Every step is `step-reversible-p`: drops are lossy, not irreversible. A target with several stamps → `revision-error`, and an unknown TO → `revision-not-found` (both R0b). Planning is pure. `describe-plan` is R0b's. |
| **Lossy** | `change-lossy-p` is true for every `:remove` change (drop table, drop column). An inverse change is lossy when the change it inverts is lossy, or when the inverse itself is a `:remove`. So the inverse of a drop is lossy: it re-creates the schema, not the data. The double inverse of an add is lossy too, because the add's data went with the drop. `diff-lossy-p` = some change lossy; `step-lossy-p` = `diff-lossy-p` of `step-diff`. Lossy steps are data for approval (H5). `upgrade` / `downgrade` do not refuse them (0.1 behaviour). |
| **Conditions** | `migrate-error` becomes a subtype of `stack-rev:revision-error`. `migrate-error-message` and `revision-error-message` return the same string. `unknown-revision` inherits `migrate-error` **and** `stack-rev:revision-not-found`, with designator = the id. `branch-not-supported` ⊂ `migrate-error`. `multiple-heads` ⊂ `branch-not-supported`. Handlers for `revision-error` / `revision-not-found` catch sql-migrate's conditions. |
| **0.1 runner** | `upgrade` / `downgrade` keep their 0.1 lambda lists, defaults (`:head`, `:count 1`), `:target` / `:count` exclusivity, direction errors (`migrate-error` "use downgrade" / "use upgrade") and return values (the `schema-migration`s applied, in application order). They resolve the goal along `history`, check that the stamp is known (an unknown stamp → `unknown-revision`, as 0.1), call `plan-transition`, and run `execute-plan` on `(make-sql-target connection :directory dir :check-drift nil)`. **0.1 never checked drift, and neither do they.** |
| **Step failure in the runner** | When a step fails, `upgrade` / `downgrade` first re-`signal` its cause (the driver's condition), so a 0.1 handler on, say, `sqlite:sqlite-error` still fires. If no handler takes it, `step-failed` keeps propagating with `execute-plan`'s restarts (`retry-step`, `skip-step`, `rollback-to-start`) available to the caller. Unhandled, the database keeps the last completed step (the 0.1.1 guarantee). |
| **current-revision / stamp** | `current-revision` returns one id or `nil`. Several version-table rows → `multiple-heads` (the rows, sorted) with `use-value`. `current-revisions` = `target-revisions` (sorted). **`stamp` now checks first:** an unknown id signals `unknown-revision` and the version table is unchanged (0.1 deleted the row first). `stamp nil` clears. `ensure-version-table` is unchanged. |

### Schema diff engine

A `diff-protocol` engine whose states are sql-orm snapshots. `engine-name` → `:schema`.

- **`compute-diff e a b &key level`** returns a `schema-diff` with one `schema-change` per op of `(diff-schema a b :complete t :dialect (schema-engine-dialect e))`, in that op order (sql-orm S1's locked order). This holds at every level: a schema op is already a leaf. `diff-level` records the level asked for, and `diff-engine` is `e`. Equal states (also when they differ only in order or name case) → an empty diff.
- **Change shape** by op:

  | Op | Kind | Path | Before | After |
  |----|------|------|--------|-------|
  | `create-table-op` | `:add` | `("<t>")` | `nil` | the table entry `(name . column-infos)` |
  | `drop-table-op` | `:remove` | `("<t>")` | the table entry | `nil` |
  | `add-column-op` | `:add` | `("<t>" "<c>")` | `nil` | the column-info |
  | `drop-column-op` | `:remove` | `("<t>" "<c>")` | the column-info | `nil` |
  | `alter-column-op` | `:modify` | `("<t>" "<c>")` | from | to |

  Names in paths are downcased strings. `change-footprint` = `schema-op-footprint`. `diff-footprint` is the sorted union. `change-schema-op` is the op, and `schema-diff-ops` lists the ops in apply order.
- **`make-schema-diff ops &key engine level`** wraps given ops (a list, one op, or a `schema-migration`) the same way. Engine default: a fresh ANSI engine. Level default: `:changes`.
- **`state-equal`** = `schema-snapshot-equal :dialect`.
- **`apply-diff state d`** is pure: `apply-ops-to-snapshot` per change, in order. An op that does not fit signals `diff:apply-conflict`, reason `:exists` (create / add of an existing name) or `:missing` (otherwise), with `diff-error-change` = the change. Restarts: `skip-change` (that change goes into the second value) and `abort` (`(values state :aborted)`, the original state).
- **`invert-diff`** inverts each op (`invert-schema-op`), reverses the order and swaps the kinds. It returns a `schema-diff` and never signals `irreversible-change`. **`compose-diffs`** of two schema diffs is their concatenation (a `schema-diff`).
- **`render-diff d :sql stream`** writes offline DDL in the engine's dialect: a keyword is the instance registered in `sql-query:*sql-dialect-registry*`, and `nil` is `(sql-query:make-ansi-dialect)`, never `*sql-dialect*`. Each change contributes the statements of `schema-op-upgrade` compiled with `sql-query:compile-sql`, each on its own line ending in `;`. `nil` dialect → ANSI. An empty diff → `""`. Stream `nil` → string; `t` → `*standard-output*`, returns `nil`. A stream → written, returns `nil`. An `alter-column-op` on `:sqlite3` signals `diff:unsupported-content`, because SQLite needs a live table rebuild and the offline form is S4. `:summary` is diff-protocol's (`A table:widgets`). `:sexp`, `parse-diff`, `three-way-diff` and `rebase-diff` are S3+.
- Laws (corpus of 19 pairs, every level): apply round trip, inverse round trip, double inverse, self-diff empty, compose (there-and-back, associativity).

### SQL target

`(make-sql-target connection &key directory version-table dialect (check-drift t))`. `version-table` defaults to the directory's, else `"sql_migrate_version"`. `dialect` defaults to `(sql-query:dialect-for-connection connection)` and is resolved when the target is made, so `target-dialect` is never `nil`.

| GF | `sql-target` |
|----|--------------|
| `target-revisions` | Version-table ids, sorted `string<`. Creates the table when it is missing (as 0.1's `current-revision`). |
| `target-stamp` | `DELETE` every row, then `INSERT` each id, revisions or ids, deduped, in order. Returns the ids. No store check and no transaction of its own (atomic inside `with-target-transaction`). |
| `target-state` | `(reflect-schema connection :exclude (list version-table) :dialect dialect)`. |
| `(setf target-state)` | `revision-error` in S2. |
| `target-drift tg store` | `nil` when the stamped revision's `revision-state` (`nil` unstamped) is `schema-snapshot-equal` to `target-state` **under the target's dialect** (reflected `"TEXT"` = `:text` on SQLite). Otherwise the `schema-diff` (a `schema-diff-engine` of that dialect) from the stamped state to the actual one. Several stamps → `revision-error`. |
| `target-fidelities` | `nil`: projections are S4. |
| `target-transactional-p` | True for dialect keys `:sqlite3` and `:postgres`. |
| `call-with-target-transaction` | `sql-protocol:with-transaction`: a non-local exit rolls back DDL and stamp. Not transactional → `revision-error`, thunk not called. |
| `execute-plan` | The R0b contract. For each step, one transaction runs the step's DDL (`upgrade-schema connection (schema-diff-ops (step-diff s)) :transaction nil`, so dialect rebuilds see earlier ops) **and** stamps `(step-to)`. A non-transactional target runs DDL then stamp. Any error inside the step rolls its transaction back; then `step-failed` (cause = that error, attempt from 1) is signalled **after** the rollback, with `retry-step`, `skip-step` (no change, no stamp, second value) and `rollback-to-start` (one transaction runs the inverses of the steps this call completed, restamps `plan-start`, returns `nil`). Unhandled, the stamp names the last completed step. Resume and the foreign-stamp `revision-error` are R0b's. With `target-check-drift-p`, drift before the first step signals `target-drift-detected` with `discard-drift` (one transaction runs the complete diff from the actual schema back to the stamped one, then the plan) and `abort` (return `nil`, nothing changed). `capture-and-continue` is not offered in S2 (`capture-revision` is S4). |

### Behaviour changes from 0.1 (locked)

1. `history` on a fork lists it instead of signalling `branch-not-supported`. The refusal moved to planning, and `head-revision` signals `multiple-heads`, a `branch-not-supported`. The 0.1 test `branch-not-supported` is the one 0.1 test changed.
2. `register-revision` refuses an unregistered down-revision (`unknown-revision`).
3. `stamp` checks before deleting.
4. `current-revision` signals `multiple-heads` for several version rows (0.1 returned an arbitrary one).
5. A failing step signals `step-failed` after re-signalling the driver's condition. 0.1 signalled only the driver's condition.

### Tests (contract)

| File | Covers |
|------|--------|
| `s2-fixtures` | Snapshot builders, a 19-pair corpus (sql-orm S1's rows with the change kinds and lossy flags the engine must give), linear and forked directories, an in-memory target, an `untouchable-target` (no methods), SQLite helpers |
| `engine-test` | `deftest-parametrize` over the corpus: apply / inverse / double-inverse round trips at three levels, self-diff, compose, change shapes (kinds, ops, footprints, lossy, inverse lossy). Paths, before / after, dialect equality, `make-schema-diff`, `apply-conflict` restarts, `:summary`, `:sql` text on SQLite / PostgreSQL / ANSI, the SQLite alter refusal, stream designators |
| `directory-test` | Store shape, content = the op list, folded states, `walk :footprint`, `make-revision` state, unknown parent, exact `find-revision`, forks (topological history, `multiple-heads` + `use-value`, `make-revision` on a fork, `plan-transition` refusal before reading the target), plan shapes up / down / partial / no-op, `describe-plan`, `step-lossy-p`, purity |
| `target-test` | Defaults, stamps, reflected state, drift (column, unstamped table, several stamps), transaction rollback and refusal, `execute-plan` up and down (law 5), DDL + stamp atomic per step, `step-failed` after rollback with `retry-step` / `skip-step` / `rollback-to-start`, drift blocking with `abort` / `discard-drift` (no `capture-and-continue`), resume, foreign stamp |
| `compat-test` | 0.1 entry points agree with the target; drift ignored by `upgrade`; `current-revisions`; `multiple-heads` from `current-revision`; `stamp` checks first; cause re-signalled then `step-failed`; `retry-step` from outside `upgrade`; fork refusals touch nothing; unknown stamp |
| `condition-test` | Subtype tree; messages agree; `revision-error` / `revision-not-found` handlers catch duplicates, unknown ids (designator, `use-value`), unknown upgrade targets and fork refusals |

**Counts.** 151 new tests (including parametrized rows: 5 corpus laws × 19 pairs) and 10 in `runner-test`. On the contract branch all 151 new tests fail cleanly (stubs), the 9 unchanged 0.1 tests pass, and the rewritten `branch-not-supported` fails until `history` stops signalling.

### Release

`sql-migrate` **0.2.0**: the contract branch already sets `:version "0.2.0"` and the dependency floors. Publish from the owning repo when S2 is green (skill **pr-merge-publish**).

---

## Repo layout (locked)

| Layer | Repo / systems | Version |
|-------|----------------|---------|
| Connectivity | `egao1980/sql-protocol` + `sql-backend-*` | OCI **0.1.0** |
| Core / query | `egao1980/sql-query` · `sql-query-sqlite3` · `sql-query-postgres` · `sql-query-csv` | OCI **0.2.0** (query + sqlite/pg; csv separate) |
| ORM | `egao1980/sql-orm` | OCI **0.1.0** |
| Migrate | `egao1980/sql-migrate` | OCI **0.1.0** |

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
4. Migrate: `sql-migrate` linear `upgrade` / `downgrade` / `stamp` on those ops

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
- [x] `sql-migrate` **0.1.0** linear runner + OCI — [sql-migrate#1](https://github.com/egao1980/sql-migrate/pull/1)  
- [x] S2 contract: `sql-migrate` 0.2.0 brief section, skeleton and Rove suites on `agent/sql-migrate-s2-9d73`  
- [ ] S2 implementation through team-solve (`.team-solve/task.md` in the worktree), then OCI publish 0.2.0  
- [ ] S3 branches / merges / multi-head version table; S4 projections, drift capture, spec replay

**Impl order:** ~~imports → connectivity → query → ORM → migrate~~ — **wave-1 complete**. OpenAPI next.

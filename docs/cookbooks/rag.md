# Cookbook: RAG ingest / retrieve

**Audience:** chunk text, embed via `llm-protocol`, store vectors, retrieve top-k. **Not** conversation memory.

| Piece | Package | OCI |
|-------|---------|-----|
| Protocol + mock (`stack-rag`) | [`rag-protocol`](https://github.com/egao1980/rag-protocol) | **0.1.0** |
| In-process cosine store | [`rag-backend-memory`](https://github.com/egao1980/rag-backend-memory) | **0.1.0** |
| SQL persist + Lisp cosine | [`rag-backend-sql`](https://github.com/egao1980/rag-backend-sql) | **0.1.0** |
| Postgres ANN (pgvector) | [`rag-backend-pgvector`](https://github.com/egao1980/rag-backend-pgvector) | **0.1.0** |
| Recursive character splitter | [`rag-backend-text`](https://github.com/egao1980/rag-backend-text) | **0.1.0** |
| Embeddings | [`llm-protocol`](https://github.com/egao1980/llm-protocol) | **0.2.0** |

Brief: [rag.md](../capabilities/rag.md). Embeddings stay on an `llm-backend` — [llm cookbook](llm.md).

```lisp
(cl-repo:load-system "rag-protocol" :version "0.1.0")
(cl-repo:load-system "rag-backend-memory" :version "0.1.0")
(cl-repo:load-system "rag-backend-text" :version "0.1.0")

(let* ((store (rag-backend-memory:make-memory-vector-store))
       (chunker (rag-backend-text:make-recursive-character-chunker
                 :size 400 :overlap 80))
       (embedder (stack-llm:make-mock-llm-backend))
       (pipe (stack-rag:make-rag-pipeline
              :store store :chunker chunker :embedder embedder)))
  (stack-rag:ingest pipe
                    (list (stack-rag:make-rag-document :id "a" :text "alpha …")
                          (stack-rag:make-rag-document :id "b" :text "beta …")))
  (stack-rag:retrieve pipe "alpha" :top-k 5))
```

Swap the mock embedder for OpenAI / llama.cpp — same `embed` / `embed-query` GFs. Store-only path (precomputed vectors):

```lisp
(rag-backend-memory:use-memory-vector-store)
(stack-rag:upsert stack-rag:*rag-store*
                  (stack-rag:make-rag-chunk
                   :id "a:0" :text "alpha" :embedding #(1.0 0.0)))
(stack-rag:query-store stack-rag:*rag-store* #(1.0 0.0) :top-k 5)
```

SQL (SQLite here; same GFs on a `sql-protocol` connection):

```lisp
(cl-repo:load-system "sql-backend-sqlite3" :version "0.1.0")
(cl-repo:load-system "rag-backend-sql" :version "0.1.0")
(let ((store (rag-backend-sql:make-sql-vector-store
              :driver :sqlite3 :database-name "rag.sqlite")))
  (stack-rag:upsert store
                    (stack-rag:make-rag-chunk
                     :id "a:0" :text "alpha" :embedding #(1.0 0.0)))
  (stack-rag:query-store store #(1.0 0.0) :top-k 5)
  (rag-backend-sql:close-sql-vector-store store))
```

Postgres + pgvector (`<=>` ANN; score is `1 - distance`):

```lisp
(cl-repo:load-system "sql-backend-postgres" :version "0.1.0")
(cl-repo:load-system "rag-backend-pgvector" :version "0.1.0")
(let ((store (rag-backend-pgvector:make-pgvector-store
              :host "localhost" :database-name "postgres"
              :username "postgres" :password "postgres"
              :dimension 2)))
  (stack-rag:upsert store
                    (stack-rag:make-rag-chunk
                     :id "a:0" :text "alpha" :embedding #(1.0 0.0)))
  (stack-rag:query-store store #(1.0 0.0) :top-k 5)
  (rag-backend-pgvector:close-pgvector-store store))
```


Default `rerank` is identity (score desc). Missing store / embedder: `rag-missing-backend` + `use-value`. Dim mismatch: `continue` skips the chunk; `use-value` supplies a vector. Unknown ids on `delete-ids`: `rag-not-found` + `continue`.

## What not to do

- Don’t put RAG GFs on `llm-protocol`.
- Don’t treat conversation memory as this protocol.
- Don’t expect hybrid BM25 / a cross-encoder in 0.1.0. `rag-backend-sql` is Lisp cosine; ANN is `rag-backend-pgvector`.

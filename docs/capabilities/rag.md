# rag-protocol (P1)

**Status:** `rag-protocol` **0.1.0** + memory **0.1.0** + text **0.1.0** + [`rag-backend-sql`](https://github.com/egao1980/rag-backend-sql) **0.1.0** · cookbook [rag.md](../cookbooks/rag.md)

CLOS chunk / store / rerank / retrieve. **Not** stuffed into `llm-protocol`. Embeddings stay `embed` / `embed-query` on an `llm-backend`.

Conversation memory is a **different** gap (`prepare-agent-turns` only).

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| LlamaIndex / LangChain retrievers | `ingest` = chunk → embed → upsert; `retrieve` = embed → query → rerank | Graph / agents / query engines |
| LangChain `RecursiveCharacterTextSplitter` | size + overlap + separator cascade | Token splitters, semantic chunkers |
| LangChain4j / Spring `VectorStore` | `upsert` / `delete-ids` / `query-store`; SQL persistence via `sql-protocol` | pgvector / Pinecone / hosted ANN |
| Cross-encoders | `rerank` GF | No model backend in 0.1.0 (identity default) |

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `rag-vector-store` + `rag-chunker` + `rag-reranker` + `rag-pipeline` |
| **GFs** | `chunk` / `upsert` / `delete-ids` / `query-store` / `rerank` / `ingest` / `retrieve` |
| **Embed** | Not here. Pipeline calls `llm-protocol:embed` / `embed-query`. Store takes float vectors. |
| **Types** | `rag-document` `rag-chunk` `rag-hit` `rag-query` |
| **Default rerank** | Identity (score desc, truncate `top-k`) |
| **Default chunker on ingest** | Protocol passthrough (one chunk / doc) unless a `rag-chunker` is bound |
| **In-tree mock** | `mock-vector-store` for protocol tests |
| **First store** | `rag-backend-memory` — brute-force cosine, dim fixed on first upsert |
| **SQL store** | `rag-backend-sql` — persist via `sql-protocol`; cosine still in Lisp. Not pgvector. |
| **First chunker** | `rag-backend-text` — recursive character splitter (CL characters) |
| **Not here** | Conversation memory, pgvector, hybrid BM25, rerank models, token splitters |

---

## Protocol surface

Package nick: `stack-rag`.

```lisp
(defclass rag-vector-store () ())
(defclass rag-chunker () ())
(defclass rag-reranker () ())
(defclass rag-pipeline () ())

(defgeneric chunk (chunker document &key size overlap))
(defgeneric upsert (store chunks))
(defgeneric delete-ids (store ids))
(defgeneric query-store (store query &key top-k filter))
(defgeneric rerank (reranker query hits &key top-k))
(defgeneric ingest (pipeline documents &key model dimensions))
(defgeneric retrieve (pipeline query &key top-k model dimensions))
```

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol + mock | [`egao1980/rag-protocol`](https://github.com/egao1980/rag-protocol) | **0.1.0** |
| Memory store | [`egao1980/rag-backend-memory`](https://github.com/egao1980/rag-backend-memory) | **0.1.0** |
| SQL store | [`egao1980/rag-backend-sql`](https://github.com/egao1980/rag-backend-sql) | **0.1.0** |
| Text chunker | [`egao1980/rag-backend-text`](https://github.com/egao1980/rag-backend-text) | **0.1.0** |

Conditions: `rag-error` / `rag-missing-backend` (`use-value`) / `rag-dimension-mismatch` (`continue` / `use-value`) / `rag-not-found` (`continue`).

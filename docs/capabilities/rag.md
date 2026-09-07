# rag-protocol (P1)

**Status:** `rag-protocol` **0.1.2** + memory / sql / pgvector / hybrid **0.1.1** / tsvector / splade / cross-encoder / text **0.1.0** · cookbook [rag.md](../cookbooks/rag.md)

CLOS chunk / store / rerank / retrieve. **Not** stuffed into `llm-protocol`. Embeddings stay `embed` / `embed-query` on an `llm-backend`.

Conversation memory is a **different** protocol — [conversation.md](../cookbooks/conversation.md).

---

## Prior art (intersection, not a clone)

| Source | Took | Left |
|--------|------|------|
| LlamaIndex / LangChain retrievers | `ingest` = chunk → embed → upsert; `retrieve` = embed → query → rerank | Graph / agents / query engines |
| LangChain `RecursiveCharacterTextSplitter` | size + overlap + separator cascade | Token splitters, semantic chunkers |
| LangChain4j / Spring `VectorStore` | `upsert` / `delete-ids` / `query-store`; SQL persist + pgvector ANN | Pinecone / other hosted stores |
| Cross-encoders | `rerank` GF | `rag-backend-cross-encoder` (`:score-fn` / `:batch-fn`; default is token overlap) |

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| **Shape** | `rag-vector-store` + `rag-chunker` + `rag-reranker` + `rag-pipeline` |
| **GFs** | `chunk` / `upsert` / `delete-ids` / `query-store` / `rerank` / `ingest` / `retrieve` / `analyze` / `fuse` / `encode-sparse` |
| **Embed** | Not here. Pipeline calls `llm-protocol:embed` / `embed-query`. Store takes float vectors. |
| **Types** | `rag-document` `rag-chunk` `rag-hit` `rag-query` |
| **Default rerank** | Identity (score desc, truncate `top-k`) |
| **Default chunker on ingest** | Protocol passthrough (one chunk / doc) unless a `rag-chunker` is bound |
| **In-tree mock** | `mock-vector-store` for protocol tests |
| **First store** | `rag-backend-memory` — brute-force cosine, dim fixed on first upsert |
| **SQL store** | `rag-backend-sql` — persist via `sql-protocol`; cosine still in Lisp |
| **pgvector store** | `rag-backend-pgvector` — `<=>` ANN, text `'[1,0]'::vector` wire, optional HNSW |
| **Hybrid** | `rag-backend-hybrid` — Okapi BM25 + RRF / linear over a vector store. Persist lexical via `:lexical-store`. |
| **FTS / sparse / CE** | `rag-backend-tsvector`, `rag-backend-splade`, `rag-backend-cross-encoder` |
| **First chunker** | `rag-backend-text` — recursive character splitter (CL characters) |
| **Not here** | Conversation memory, token splitters, shipped BERT/CE weights |

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
(defgeneric analyze (analyzer text))
(defgeneric fuse (fusion hit-lists &key top-k))
(defgeneric encode-sparse (encoder text))
```

| Layer | Repo | OCI |
|-------|------|-----|
| Protocol + mock | [`egao1980/rag-protocol`](https://github.com/egao1980/rag-protocol) | **0.1.2** |
| Memory store | [`egao1980/rag-backend-memory`](https://github.com/egao1980/rag-backend-memory) | **0.1.0** |
| SQL store | [`egao1980/rag-backend-sql`](https://github.com/egao1980/rag-backend-sql) | **0.1.0** |
| pgvector store | [`egao1980/rag-backend-pgvector`](https://github.com/egao1980/rag-backend-pgvector) | **0.1.0** |
| Hybrid BM25 + RRF | [`egao1980/rag-backend-hybrid`](https://github.com/egao1980/rag-backend-hybrid) | **0.1.1** |
| Postgres FTS | [`egao1980/rag-backend-tsvector`](https://github.com/egao1980/rag-backend-tsvector) | **0.1.0** |
| Sparse / SPLADE | [`egao1980/rag-backend-splade`](https://github.com/egao1980/rag-backend-splade) | **0.1.0** |
| Cross-encoder | [`egao1980/rag-backend-cross-encoder`](https://github.com/egao1980/rag-backend-cross-encoder) | **0.1.0** |
| Text chunker | [`egao1980/rag-backend-text`](https://github.com/egao1980/rag-backend-text) | **0.1.0** |

Conditions: `rag-error` / `rag-missing-backend` (`use-value`) / `rag-dimension-mismatch` (`continue` / `use-value`) / `rag-not-found` (`continue`).

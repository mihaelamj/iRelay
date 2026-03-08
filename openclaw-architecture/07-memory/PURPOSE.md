# Memory — Purpose

## Why This System Exists

Memory gives the agent **long-term recall** beyond the current conversation. It stores information from past sessions and user-provided documents as searchable vector embeddings, so the agent can retrieve relevant context when needed.

## The Problem It Solves

1. **Beyond the context window**: LLMs can only see what's in their current context. Memory lets the agent search across all past conversations and documents to find relevant information, even from weeks ago.

2. **Semantic search**: Traditional keyword search misses meaning. Vector embeddings capture semantic similarity — searching for "deployment process" finds content about "how we ship code" even if those exact words aren't used.

3. **Provider flexibility**: Not everyone has the same embedding API. Memory supports 6 providers (OpenAI, Gemini, Voyage, Mistral, Ollama, local) with automatic fallback, and degrades gracefully to text-only search when no embedding provider is available.

4. **Diversity in results**: The MMR (Maximal Marginal Relevance) algorithm ensures search results aren't all near-duplicates. Combined with temporal decay (recent memories rank higher), the agent gets a diverse, relevant set of results.

## What SwiftClaw Needs from This

SwiftClaw already uses GRDB/SQLite, which is perfect for this. The key algorithms to replicate are: file chunking (line-based with overlap), hybrid search (0.7 × vector + 0.3 × text), MMR re-ranking (greedy selection with Jaccard similarity penalty), and temporal decay (exponential with configurable half-life). The sync system (hash-based change detection, atomic reindex) keeps the index fresh.

## Key Insight for Replication

Memory is fundamentally a **search engine** built on SQLite. It has two indexes: a vector index (cosine similarity) for semantic search and an FTS5 index for keyword search. The hybrid merge combines both, and MMR adds diversity. Everything else (chunking, syncing, caching) exists to keep those indexes populated and efficient.

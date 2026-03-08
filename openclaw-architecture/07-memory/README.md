# 07 — Memory & Embeddings

The Memory system gives OpenClaw **long-term recall**. It stores information as vector embeddings in a local SQLite database and retrieves relevant memories when the agent needs context beyond the current conversation.

Think of it as the agent's notebook — it writes down important things and can search through them later.

## How Memory Works (Big Picture)

1. You create markdown files in your agent's workspace (`MEMORY.md`, `memory/*.md`)
2. OpenClaw **chunks** the markdown into smaller pieces
3. Each chunk is **embedded** — converted into a vector (a list of numbers) using an AI model
4. The vectors are stored in a **SQLite database** with a vector extension
5. When the agent needs to recall something, it **searches** by embedding the query and finding similar vectors
6. The most relevant chunks are injected into the agent's context

## Memory Sources

Memory content comes from two sources:

### 1. Memory Files (manually curated)

```
~/.openclaw/workspace/MEMORY.md           # Main memory file
~/.openclaw/workspace/memory/             # Topic-specific memory files
~/.openclaw/workspace/memory/projects.md
~/.openclaw/workspace/memory/2026-03-08.md  # Date-specific memories
```

These files are the primary source. You write them (or the agent writes them), and OpenClaw indexes them.

### 2. Session Transcripts (automatic)

Active conversation transcripts can also be indexed as a secondary source. This lets the agent recall things from previous conversations.

## The Embedding Pipeline

### Step 1: File Discovery

OpenClaw scans for markdown files:
- `MEMORY.md` (always)
- `memory/*.md` (all files in the memory directory)
- Extra configured directories

### Step 2: Chunking

Each file is split into chunks using **markdown-aware chunking**:

- Splits on headings (# , ## , ### , etc.)
- Preserves code blocks (never splits inside a code fence)
- Each chunk records: `startLine`, `endLine`, `text`, `hash` (SHA-256)

### Step 3: Change Detection

Before re-embedding, OpenClaw checks if a chunk has changed:
- Compare SHA-256 hash of chunk text against stored hash
- Skip chunks that haven't changed (saves API calls and money)

### Step 4: Embedding

Each new/changed chunk is sent to an embedding provider:

```
"The quarterly report shows revenue increased 15%"
    ↓ embedding model
[0.023, -0.145, 0.892, 0.034, ..., -0.567]  (768-1536 dimensions)
```

### Step 5: Storage

Embedded chunks are stored in SQLite with three tables:
- `chunks`: The text, metadata, and embedding
- `chunks_vec`: The vector for similarity search (sqlite-vec extension)
- `chunks_fts`: Full-text search index (FTS5)

### Step 6: Search

When the agent queries memory:
1. Embed the query text
2. Find the most similar vectors (cosine similarity)
3. Also search full-text index (keyword matching)
4. Combine results (hybrid search)
5. Apply diversity re-ranking (MMR) and temporal decay
6. Return top K results

## Embedding Providers

OpenClaw supports 6 embedding providers, listed here in priority order for auto-selection:

### 1. OpenAI

- **Model**: `text-embedding-3-small` (default)
- **API**: `https://api.openai.com/v1/embeddings`
- **Auth**: `OPENAI_API_KEY`
- **Batch**: Yes (up to 8,000 tokens per request)
- **Cost**: ~$0.02 per 1M tokens

### 2. Google Gemini

- **Model**: `text-embedding-004` (default)
- **API**: Google AI / Vertex AI
- **Auth**: Google API key
- **Batch**: Yes
- **Task types**: `RETRIEVAL_QUERY`, `RETRIEVAL_DOCUMENT`, `SEMANTIC_SIMILARITY`, etc.

### 3. Voyage AI

- **Model**: `voyage-3-lite` (default)
- **API**: `https://api.voyageai.com/v1/embeddings`
- **Auth**: Voyage API key
- **Batch**: Yes (custom polling-based)

### 4. Mistral

- **Model**: `mistral-embed` (default)
- **API**: `https://api.mistral.ai/v1/embeddings`
- **Auth**: Mistral API key
- **Batch**: No (sequential only)

### 5. Ollama (Local)

- **Model**: Configurable (e.g., `nomic-embed-text`)
- **API**: `http://localhost:11434/api/embed`
- **Auth**: None (local)
- **Batch**: No (sequential)
- **Setup**: `ollama pull nomic-embed-text`

### 6. Local (node-llama-cpp)

- **Model**: `embeddinggemma-300m-qat-Q8_0.gguf` (default, auto-downloaded)
- **API**: In-process inference
- **Auth**: None
- **Batch**: No
- **Fully offline**: No API calls needed

### Auto-Selection

When `provider: "auto"`:
1. Try local embedding (if valid model file exists)
2. Try remote providers in order: OpenAI → Gemini → Voyage → Mistral
3. Skip any provider missing an API key
4. Fall back to FTS-only (keyword search without vectors)

## Vector Storage (SQLite)

### Database Location

```
~/.openclaw/state/agents/{agentId}/memory.db
```

### Schema

**`meta` table** — Stores metadata:
```sql
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
-- Stores: vectorDims (dimension count of embeddings)
```

**`files` table** — Tracks source files:
```sql
CREATE TABLE files (
  path TEXT PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'memory',
  hash TEXT NOT NULL,
  mtime INTEGER NOT NULL,
  size INTEGER NOT NULL
);
```

**`chunks` table** — The main content store:
```sql
CREATE TABLE chunks (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'memory',
  start_line INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  hash TEXT NOT NULL,
  model TEXT NOT NULL,
  text TEXT NOT NULL,
  embedding TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

**`chunks_vec` table** — Vector index (via sqlite-vec extension):
```sql
CREATE TABLE chunks_vec (
  id TEXT PRIMARY KEY,
  embedding BLOB  -- Float32Array buffer
);
```

**`chunks_fts` table** — Full-text search index (FTS5):
```sql
CREATE VIRTUAL TABLE chunks_fts USING fts5(
  text,
  id UNINDEXED,
  path UNINDEXED,
  source UNINDEXED,
  model UNINDEXED,
  start_line UNINDEXED,
  end_line UNINDEXED
);
```

**`embedding_cache` table** — Avoids re-embedding unchanged text:
```sql
CREATE TABLE embedding_cache (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  provider_key TEXT NOT NULL,
  hash TEXT NOT NULL,
  embedding TEXT NOT NULL,
  dims INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (provider, model, provider_key, hash)
);
```

## Search Architecture

### Hybrid Search

OpenClaw combines two search methods for best results:

1. **Vector search** (semantic): "What's conceptually similar?"
   - Embed the query
   - Find nearest vectors by cosine similarity
   - Understands meaning, not just keywords

2. **FTS search** (keyword): "What contains these exact words?"
   - Use SQLite FTS5 with BM25 ranking
   - Fast and precise for specific terms

Results are merged with configurable weights:
- **Vector weight**: 0.7 (default) — semantic similarity dominates
- **Text weight**: 0.3 (default) — keyword matching supplements

### Query Expansion

For FTS queries, OpenClaw expands the query:
- Extract keywords from conversational text
- Remove 100+ English stop words
- Handle CJK (Chinese, Japanese, Korean) via Unicode categories
- Build FTS5 query: `"keyword1" AND "keyword2"`

### Temporal Decay

Optional re-ranking that prefers recent content:

```
score = original_score * exp(-lambda * age_in_days)
lambda = ln(2) / halfLifeDays
```

- **Default half-life**: Configurable (e.g., 30 days)
- **Dated files** (`memory/2026-03-08.md`): Age calculated from filename
- **Evergreen files** (`MEMORY.md`, `memory/projects.md`): No decay applied

### Maximal Marginal Relevance (MMR)

Prevents redundant results:
- Iteratively selects results that are relevant to the query but **dissimilar** to already-selected results
- Controlled by `lambda` parameter (balance relevance vs diversity)
- Reduces duplication in the result set

## Search Flow (Complete)

1. **Warm session** if configured (pre-sync on session start)
2. **Trigger async sync** if files have changed
3. **Clean query text** (normalize whitespace, etc.)
4. **Determine search mode**: Vector + FTS (hybrid) or FTS-only
5. **Run searches in parallel**:
   - Vector: Embed query → cosine similarity → top 200 candidates
   - FTS: Build FTS query → BM25 ranking → top candidates
6. **Merge results**: Combine scores, deduplicate by chunk ID
7. **Apply MMR**: Diversity re-ranking
8. **Apply temporal decay**: Prefer recent memories
9. **Filter by minimum score** (default 0.2)
10. **Truncate snippets** to 700 characters
11. **Return top K** results (default 10)

### Search Result Format

```
MemorySearchResult:
  path: string         # Source file path
  startLine: number    # Where the chunk starts
  endLine: number      # Where the chunk ends
  score: number        # Relevance score (0-1)
  snippet: string      # Truncated text preview (max 700 chars)
  source: string       # "memory" or "sessions"
  citation: string     # Optional citation reference
```

## Configuration

```json
{
  "memory": {
    "provider": "auto",
    "fallback": "openai",
    "model": "text-embedding-3-small",

    "remote": {
      "baseUrl": "https://api.openai.com",
      "apiKey": { "env": "OPENAI_API_KEY" }
    },

    "local": {
      "modelPath": "/path/to/model.gguf",
      "modelCacheDir": "~/.cache/node-llama/"
    },

    "store": {
      "fts": { "enabled": true },
      "vector": {
        "enabled": true,
        "extensionPath": "/path/to/sqlite-vec.so"
      }
    },

    "query": {
      "maxResults": 10,
      "minScore": 0.2,
      "hybrid": {
        "enabled": true,
        "vectorWeight": 0.7,
        "textWeight": 0.3,
        "candidateMultiplier": 5,
        "mmr": { "enabled": true, "lambda": 0.7 },
        "temporalDecay": { "enabled": false, "halfLifeDays": 30 }
      }
    },

    "sync": {
      "onSessionStart": true,
      "onSearch": true,
      "interval": 300000
    },

    "cache": {
      "enabled": true,
      "maxEntries": 10000
    }
  }
}
```

## Embedding Normalization

Before storage, embeddings are cleaned up:
- Invalid values (NaN, Infinity) replaced with 0
- L2 normalized to unit length (for cosine similarity)
- Stored as `Float32Array` buffer in SQLite

## Batch Processing

For efficiency, embeddings are processed in batches:

```
Batch Configuration:
  enabled: boolean
  wait: boolean              # Wait for async completion
  concurrency: number        # Parallel batch limit
  pollIntervalMs: number     # Poll interval for async batches
  timeoutMs: number          # Batch timeout
```

Batch failure tracking:
- Max 2 consecutive failures triggers fallback
- Failures per provider tracked separately
- On failure: fall back to sequential embedding

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/memory/` | Main memory module (100+ files) |
| `src/memory/embeddings-openai.ts` | OpenAI embedding provider |
| `src/memory/embeddings-gemini.ts` | Gemini embedding provider |
| `src/memory/embeddings-voyage.ts` | Voyage embedding provider |
| `src/memory/embeddings-mistral.ts` | Mistral embedding provider |
| `src/memory/embeddings-ollama.ts` | Ollama embedding provider |
| `src/memory/query-expansion.ts` | FTS query expansion |
| `src/memory/temporal-decay.ts` | Time-based score decay |
| `src/memory/mmr.ts` | Maximal Marginal Relevance |

## Swift Replication Notes

1. **SQLite**: Use GRDB (already in SwiftClaw) for all database operations
2. **sqlite-vec**: There's a C library that works with Swift — or implement cosine similarity in pure Swift
3. **FTS5**: GRDB supports FTS5 natively
4. **Embedding providers**: URLSession-based async API calls
5. **Chunking**: Port the markdown-aware chunker
6. **Hybrid search**: Run vector + FTS in parallel, merge with weighted scores
7. **Local embeddings**: Consider using CoreML models or llama.cpp Swift bindings

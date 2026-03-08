# Memory — Technical Implementation Details

## Embedding Pipeline

### File Chunking

Files are split into chunks using a greedy line-based algorithm:

```
chunkFile(content, maxTokens=1024, overlapTokens=128):
  maxChars = maxTokens × 4        # ~4 chars per token
  overlapChars = overlapTokens × 4
  lines = content.split("\n")
  chunks = []
  currentLines = []
  currentChars = 0

  for (lineNum, line) in enumerate(lines):
    lineChars = line.length + 1    # +1 for newline

    # Handle individual lines longer than maxChars
    if (lineChars > maxChars):
      # Flush current chunk
      if (currentLines.length > 0):
        chunks.push(makeChunk(currentLines, startLine, lineNum))
        currentLines = []
        currentChars = 0

      # Split long line at maxChars boundaries
      for segment in splitAtBoundary(line, maxChars):
        chunks.push(makeChunk([segment], lineNum, lineNum))
      continue

    # Would adding this line exceed the limit?
    if (currentChars + lineChars > maxChars and currentLines.length > 0):
      chunks.push(makeChunk(currentLines, startLine, lineNum - 1))

      # Carryover overlap lines
      overlapLines = takeLastLines(currentLines, overlapChars)
      currentLines = overlapLines
      currentChars = sum(line.length for line in overlapLines)
      startLine = lineNum - overlapLines.length

    currentLines.push(line)
    currentChars += lineChars

  # Flush remaining
  if (currentLines.length > 0):
    chunks.push(makeChunk(currentLines, startLine, lines.length))

  return chunks

makeChunk(lines, startLine, endLine):
  text = lines.join("\n")
  return {
    text,
    startLine,       # 1-indexed
    endLine,         # 1-indexed
    hash: sha256(text)
  }
```

### Embedding Process

```
embedChunks(chunks, provider):
  # 1. Check embedding cache
  cached = []
  uncached = []
  for chunk in chunks:
    cacheKey = { provider: provider.id, model: provider.model, hash: chunk.hash }
    embedding = lookupCache(cacheKey)
    if (embedding):
      cached.push({ chunk, embedding })
    else:
      uncached.push(chunk)

  # 2. Batch uncached chunks (max 8000 tokens per batch)
  batches = groupByTokenLimit(uncached, maxBatchTokens=8000)

  # 3. Embed each batch with retry
  for batch in batches:
    texts = batch.map(c => c.text)
    embeddings = await retryWithBackoff(
      () => provider.embedBatch(texts),
      { maxAttempts: 3, baseMs: 500, maxMs: 8000 }
    )

    # 4. L2-normalize all embeddings
    for (i, embedding) in enumerate(embeddings):
      normalized = l2Normalize(embedding)
      cached.push({ chunk: batch[i], embedding: normalized })

      # 5. Store in cache
      storeCache(cacheKey, normalized)

  return cached

l2Normalize(vector):
  magnitude = sqrt(sum(v × v for v in vector))
  if (magnitude === 0): return vector
  return vector.map(v => v / magnitude)
```

### Storage

```
storeChunks(db, chunks):
  for chunk in chunks:
    # Main table
    db.run("INSERT INTO chunks (id, path, source, start_line, end_line, hash, model, text, embedding, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [uuid(), chunk.path, chunk.source, chunk.startLine, chunk.endLine,
       chunk.hash, chunk.model, chunk.text, JSON.stringify(chunk.embedding),
       Date.now()])

    # Vector table (binary blob for sqlite-vec)
    db.run("INSERT INTO chunks_vec (id, embedding) VALUES (?, ?)",
      [chunk.id, float32ArrayToBlob(chunk.embedding)])

    # FTS table
    db.run("INSERT INTO chunks_fts (text, id, path, source, model, start_line, end_line) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [chunk.text, chunk.id, chunk.path, chunk.source, chunk.model,
       chunk.startLine, chunk.endLine])
```

## Vector Search

### Cosine Similarity with sqlite-vec

```
vectorSearch(db, queryEmbedding, topK=20):
  queryBlob = float32ArrayToBlob(queryEmbedding)

  results = db.all("""
    SELECT c.id, c.path, c.source, c.start_line, c.end_line, c.text,
           vec_distance_cosine(v.embedding, ?) AS distance
    FROM chunks_vec v
    JOIN chunks c ON c.id = v.id
    ORDER BY distance ASC
    LIMIT ?
  """, [queryBlob, topK])

  # Convert distance to score: score = 1 - distance
  return results.map(r => ({
    ...r,
    vectorScore: 1 - r.distance    # range [0, 1], higher = better
  }))
```

### Fallback (No sqlite-vec Extension)

```
vectorSearchFallback(db, queryEmbedding, topK=20):
  # Load all chunks into memory
  allChunks = db.all("SELECT id, path, text, embedding FROM chunks")

  # Compute cosine similarity in JavaScript
  scored = allChunks.map(chunk => ({
    ...chunk,
    vectorScore: cosineSimilarity(
      queryEmbedding,
      JSON.parse(chunk.embedding)
    )
  }))

  # Sort and take top-K
  scored.sort((a, b) => b.vectorScore - a.vectorScore)
  return scored.slice(0, topK)
```

### Cosine Similarity Formula

```
cosineSimilarity(a, b):
  dotProduct = sum(a[i] × b[i] for i in range(len(a)))
  magnitudeA = sqrt(sum(a[i]² for i in range(len(a))))
  magnitudeB = sqrt(sum(b[i]² for i in range(len(b))))

  if (magnitudeA === 0 or magnitudeB === 0): return 0
  return dotProduct / (magnitudeA × magnitudeB)

  # Range: [-1, 1] for general vectors
  # Range: [0, 1] for L2-normalized vectors (which OpenClaw uses)
```

## FTS5 Full-Text Search

### Query Construction

```
buildFtsQuery(rawQuery):
  # 1. Extract tokens using Unicode-aware regex
  tokens = rawQuery.match(/[\p{L}\p{N}_]+/gu)    # letters, numbers, underscores

  # 2. Quote each token for FTS5
  quoted = tokens.map(t => '"' + t + '"')

  # 3. Join with AND
  return quoted.join(" AND ")

  # Example: "how does config work" → '"how" AND "does" AND "config" AND "work"'
```

### BM25 Score Conversion

```
ftsSearch(db, query, topK=20):
  ftsQuery = buildFtsQuery(query)

  results = db.all("""
    SELECT id, path, source, start_line, end_line, text,
           rank AS bm25_rank
    FROM chunks_fts
    WHERE chunks_fts MATCH ?
    ORDER BY rank
    LIMIT ?
  """, [ftsQuery, topK])

  # Convert BM25 rank to [0, 1] score
  return results.map(r => ({
    ...r,
    textScore: bm25RankToScore(r.bm25_rank)
  }))

bm25RankToScore(rank):
  # FTS5 returns negative ranks (more negative = better match)
  return Math.abs(rank) / (1 + Math.abs(rank))
  # Range: [0, 1) where 1 = perfect match
```

## Hybrid Search

### Merge Algorithm

```
hybridSearch(db, query, opts):
  vectorWeight = opts.vectorWeight ?? 0.7
  textWeight = opts.textWeight ?? 0.3
  topK = opts.topK ?? 10
  minScore = opts.minScore ?? 0.0

  # 1. Embed query
  queryEmbedding = await provider.embedQuery(query)

  # 2. Run both searches in parallel
  [vectorResults, ftsResults] = await Promise.all([
    vectorSearch(db, queryEmbedding, topK × 2),
    ftsSearch(db, query, topK × 2)
  ])

  # 3. Merge by chunk ID
  merged = new Map()

  for result in vectorResults:
    merged.set(result.id, {
      ...result,
      vectorScore: result.vectorScore,
      textScore: 0
    })

  for result in ftsResults:
    if (merged.has(result.id)):
      existing = merged.get(result.id)
      existing.textScore = Math.max(existing.textScore, result.textScore)
    else:
      merged.set(result.id, {
        ...result,
        vectorScore: 0,
        textScore: result.textScore
      })

  # 4. Compute final scores
  for entry in merged.values():
    entry.score = vectorWeight × entry.vectorScore +
                  textWeight × entry.textScore

  # 5. Apply temporal decay (if enabled)
  if (opts.temporalDecay):
    for entry in merged.values():
      entry.score × = computeTemporalDecay(entry, opts.halfLifeDays)

  # 6. Apply MMR re-ranking (if enabled)
  if (opts.mmr):
    entries = mmrRerank(merged.values(), opts.mmrLambda)
  else:
    entries = merged.values().sortBy(score descending)

  # 7. Filter and limit
  return entries
    .filter(e => e.score >= minScore)
    .slice(0, topK)
```

### FTS-Only Mode (No Embedding Provider)

```
ftsOnlySearch(db, query, topK):
  # Conversational queries like "that thing we discussed" need keyword extraction
  keywords = extractKeywords(query)

  if (keywords.length > 0):
    # Search with each keyword separately, merge results
    allResults = new Map()
    for keyword in keywords:
      results = ftsSearch(db, keyword, topK)
      for result in results:
        if (allResults.has(result.id)):
          existing = allResults.get(result.id)
          existing.textScore = Math.max(existing.textScore, result.textScore)
        else:
          allResults.set(result.id, result)

    return allResults.values().sortBy(textScore descending).slice(0, topK)

  else:
    return ftsSearch(db, query, topK)
```

## Maximal Marginal Relevance (MMR)

### Algorithm

MMR re-ranks results to balance relevance and diversity:

```
mmrRerank(items, lambda=0.7):
  # 1. Normalize scores to [0, 1]
  maxScore = max(item.score for item in items)
  minScore = min(item.score for item in items)
  for item in items:
    item.normalizedScore = (item.score - minScore) / (maxScore - minScore)

  # 2. Pre-tokenize all snippets
  for item in items:
    item.tokens = tokenize(item.text.toLowerCase())
    # tokens = set of alphanumeric words

  # 3. Greedy selection
  selected = []
  remaining = list(items)

  while (remaining.length > 0):
    bestItem = null
    bestMmrScore = -Infinity

    for candidate in remaining:
      relevance = candidate.normalizedScore

      # Max similarity to any already-selected item
      maxSim = 0
      for sel in selected:
        sim = jaccardSimilarity(candidate.tokens, sel.tokens)
        maxSim = max(maxSim, sim)

      mmrScore = lambda × relevance - (1 - lambda) × maxSim

      if (mmrScore > bestMmrScore):
        bestMmrScore = mmrScore
        bestItem = candidate

    selected.push(bestItem)
    remaining.remove(bestItem)

  return selected
```

### Jaccard Similarity

```
jaccardSimilarity(setA, setB):
  intersection = setA.intersect(setB).size
  union = setA.union(setB).size
  if (union === 0): return 0
  return intersection / union

  # Range: [0, 1] where 1 = identical token sets
```

**Lambda parameter:**
- `0.0` = maximum diversity (ignores relevance)
- `1.0` = maximum relevance (ignores diversity, same as regular sort)
- `0.7` = default (favors relevance but penalizes near-duplicates)

## Temporal Decay

### Date Extraction

```
extractTimestamp(chunk):
  # 1. Try path-based date: memory/2026-03-08.md
  dateMatch = chunk.path.match(/(\d{4}-\d{2}-\d{2})/)
  if (dateMatch):
    return Date.parse(dateMatch[1])

  # 2. Fall back to file mtime
  stat = fs.stat(chunk.path)
  return stat.mtimeMs

  # 3. Evergreen files (no decay)
  EVERGREEN = ["MEMORY.md", "memory/*.md" without dates]
  if (chunk.path matches EVERGREEN pattern):
    return null    # no decay applied
```

### Decay Formula

```
computeTemporalDecay(chunk, halfLifeDays=30):
  timestamp = extractTimestamp(chunk)
  if (timestamp === null): return 1.0    # evergreen, no decay

  ageInDays = (Date.now() - timestamp) / (24 × 60 × 60 × 1000)
  lambda = Math.LN2 / halfLifeDays

  decayMultiplier = Math.exp(-lambda × ageInDays)
  return decayMultiplier

  # Examples with halfLifeDays=30:
  # age=0:   multiplier = 1.000 (full score)
  # age=15:  multiplier = 0.707
  # age=30:  multiplier = 0.500 (half-life)
  # age=60:  multiplier = 0.250
  # age=90:  multiplier = 0.125
  # age=365: multiplier = 0.000047 (nearly zero)
```

## Sync & Re-Indexing

### Sync Triggers

```
1. File Watch:    debounced 1000ms after file change detected
2. Session:       debounced 5000ms after session transcript update
3. Interval:      periodic timer (configurable, e.g., every 5 min)
4. Search:        on-demand before each search if dirty flag set
5. Session Start: warm index at beginning of new session
```

### Incremental Sync

```
syncMemoryFiles(db, config):
  # 1. List all tracked files in DB
  dbFiles = db.all("SELECT path, hash, mtime, size FROM files")

  # 2. List all files in memory directories
  diskFiles = scanMemoryDirectories(config.sources)

  # 3. Compare
  for file in diskFiles:
    dbEntry = dbFiles.get(file.path)

    if (not dbEntry):
      # New file: chunk and embed
      chunks = chunkFile(readFile(file.path))
      embeddings = await embedChunks(chunks, provider)
      storeChunks(db, embeddings)
      db.run("INSERT INTO files VALUES (?)", [file])

    else if (dbEntry.hash !== sha256(readFile(file.path))):
      # Changed file: re-chunk and re-embed
      db.run("DELETE FROM chunks WHERE path = ?", [file.path])
      db.run("DELETE FROM chunks_vec WHERE id IN (SELECT id FROM chunks WHERE path = ?)", [file.path])
      db.run("DELETE FROM chunks_fts WHERE path = ?", [file.path])

      chunks = chunkFile(readFile(file.path))
      embeddings = await embedChunks(chunks, provider)
      storeChunks(db, embeddings)
      db.run("UPDATE files SET hash=?, mtime=?, size=? WHERE path=?", [file])

  # 4. Remove stale entries
  for dbFile in dbFiles:
    if (not diskFiles.has(dbFile.path)):
      db.run("DELETE FROM chunks WHERE path = ?", [dbFile.path])
      db.run("DELETE FROM chunks_vec WHERE id IN (...)", [dbFile.path])
      db.run("DELETE FROM chunks_fts WHERE path = ?", [dbFile.path])
      db.run("DELETE FROM files WHERE path = ?", [dbFile.path])
```

### Full Reindex (Atomic)

```
runSafeReindex(dbPath, config, provider):
  tempPath = dbPath + ".tmp"
  backupPath = dbPath + ".backup"

  # 1. Create temp database
  tempDb = createDatabase(tempPath)
  createSchema(tempDb)

  # 2. Copy embedding cache (reuse cached embeddings)
  copyTable(db, tempDb, "embedding_cache")

  # 3. Index all files (4 concurrent)
  files = listAllFiles(config.sources)
  await parallelMap(files, 4, async (file) => {
    chunks = chunkFile(readFile(file.path))
    embeddings = await embedChunks(chunks, provider)
    storeChunks(tempDb, embeddings)
    tempDb.run("INSERT INTO files VALUES (?)", [file])
  })

  # 4. Atomic swap
  rename(dbPath, backupPath)
  rename(tempPath, dbPath)

  # 5. Cleanup
  rm(backupPath)

  # On failure: restore from backup
  catch:
    if (exists(backupPath)):
      rename(backupPath, dbPath)
    rm(tempPath, { force: true })
    throw
```

### Reindex Triggers

Full reindex happens when metadata changes:

```
needsFullReindex(db, config, provider):
  meta = db.all("SELECT key, value FROM meta")

  if (meta.provider !== provider.id): return true
  if (meta.model !== provider.model): return true
  if (meta.chunkSize !== config.chunkSize): return true
  if (meta.overlapSize !== config.overlapSize): return true
  if (meta.vectorDims !== provider.dimensions): return true
  if (meta.sources !== JSON.stringify(config.sources)): return true

  return false
```

## Embedding Providers

### Provider Interface

```
EmbeddingProvider:
  id: string              # "openai", "local", "gemini", etc.
  model: string           # model identifier
  dimensions: number      # embedding vector length
  maxInputTokens: number  # per-text token limit

  embedQuery(text): Promise<number[]>
  embedBatch(texts): Promise<number[][]>
```

### Provider Details

**Local (node-llama-cpp):**
- Model: EmbeddingGemma-300M (GGML format)
- Downloads and caches model on first use
- No API key needed
- Runs in-process

**OpenAI:**
- Models: text-embedding-3-large (3072 dims), text-embedding-3-small (1536 dims)
- Batch API: async file upload → poll → retrieve results
- Completion window: 24 hours

**Google Gemini:**
- Model: text-embedding-004
- Direct API calls (no batch)

**Voyage AI:**
- Model: voyage-3
- Batch API support

**Mistral:**
- Model: mistral-embed
- Direct API only

**Ollama:**
- Local inference server
- Configurable model

### Provider Selection

```
"auto" mode:
  1. Try local provider (node-llama-cpp)
  2. If unavailable: try remote providers in config order
  3. If all fail: fall back to FTS-only (no vectors)
```

## Embedding Cache

### Cache Schema

```sql
CREATE TABLE embedding_cache (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  provider_key TEXT NOT NULL,
  hash TEXT NOT NULL,           -- SHA-256 of input text
  embedding TEXT NOT NULL,       -- JSON array of floats
  dims INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (provider, model, provider_key, hash)
);
```

### Cache Behavior

```
Cache hit: same provider + model + provider_key + text hash
  → Return stored embedding immediately (no API call)

Cache miss: compute embedding via provider
  → Store in cache with current timestamp

Invalidation:
  - Provider/model change → cache entries for old provider abandoned
  - Different provider_key (e.g., API key change) → different cache partition
  - LRU eviction when exceeding max entries (configurable)
```

## Query Expansion (FTS-Only Mode)

### Keyword Extraction

```
extractKeywords(query):
  # Language-aware tokenization
  tokens = []

  for segment in query:
    if (isEnglish): split on whitespace/punctuation
    if (isChinese): character n-grams (unigrams + bigrams)
    if (isJapanese): script-aware tokenization
    if (isKorean): jamo splitting + particle stripping

  # Filter stop words (multilingual)
  stopWords = loadStopWords("en", "es", "pt", "ar", "zh", "ko", "ja")
  keywords = tokens.filter(t =>
    t.length > 0 and
    not stopWords.has(t.toLowerCase()) and
    not isPureNumber(t) and
    not isAllPunctuation(t)
  )

  return deduplicate(keywords)
```

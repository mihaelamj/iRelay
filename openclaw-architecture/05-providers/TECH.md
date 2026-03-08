# Providers — Technical Implementation Details

## SSE Stream Parsing

### Server-Sent Events Format

SSE frames follow the format:
```
data: {"json":"payload"}\n\n
```

The final frame is:
```
data: [DONE]\n\n
```

### SSE Writing (Server Side)

```
writeSse(res, data):
  res.write("data: " + JSON.stringify(data) + "\n\n")

writeDone(res):
  res.write("data: [DONE]\n\n")

setSseHeaders(res):
  res.statusCode = 200
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8")
  res.setHeader("Cache-Control", "no-cache")
  res.setHeader("Connection", "keep-alive")
  res.flushHeaders()
```

### NDJSON Streaming (Ollama)

Ollama uses NDJSON (Newline-Delimited JSON) instead of SSE. The parser buffers incomplete lines:

```
parseNdjsonStream(reader):
  decoder = new TextDecoder()
  buffer = ""

  while true:
    { done, value } = await reader.read()
    if (done): break

    buffer += decoder.decode(value, { stream: true })
    lines = buffer.split("\n")
    buffer = lines.pop() ?? ""         # keep incomplete last line

    for line in lines:
      trimmed = line.trim()
      if (trimmed is empty): continue

      try:
        yield parseJsonPreservingUnsafeIntegers(trimmed)
      catch:
        log.warn("Skipping malformed NDJSON line")

  # Handle trailing incomplete line
  if (buffer.trim() is not empty):
    yield parseJsonPreservingUnsafeIntegers(buffer.trim())
```

Key details:
- Buffers incomplete lines until a newline is encountered
- Skips empty lines gracefully
- Uses `TextDecoder` with `stream: true` for proper multi-byte UTF-8
- Preserves unsafe JavaScript integers via quoting transformation

## HTTP Request Construction

### General Pattern

All providers follow the same request-building pattern:

```
buildProviderRequest(model, context, options):
  # 1. Convert messages to provider format
  messages = convertMessages(context.messages, context.systemPrompt)

  # 2. Extract tools if any
  tools = extractTools(context.tools)

  # 3. Build provider-specific options
  providerOptions = buildOptions(model, options)

  # 4. Construct body
  body = {
    model: model.id,
    messages,
    stream: true,
    tools: tools.length > 0 ? tools : null,
    ...providerOptions
  }

  # 5. Set headers
  headers = {
    "Content-Type": "application/json",
    ...defaultHeaders,
    ...options.headers
  }

  # 6. Add auth
  if (options.apiKey and not isNonSecretApiKeyMarker(options.apiKey)):
    headers.Authorization = "Bearer " + options.apiKey

  # 7. Send
  response = await fetch(endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: options.signal           # AbortController for cancellation
  })
```

### Ollama-Specific

```
createOllamaStreamFn(baseUrl, defaultHeaders):
  chatUrl = resolveOllamaChatUrl(baseUrl)     # {baseUrl}/api/chat

  return (model, context, options) => {
    ollamaOptions = {
      num_ctx: model.contextWindow ?? 65536   # context window size
    }
    if (options.temperature):
      ollamaOptions.temperature = options.temperature
    if (options.maxTokens):
      ollamaOptions.num_predict = options.maxTokens

    body = {
      model: model.id,
      messages: convertToOllamaMessages(context),
      stream: true,
      tools: extractOllamaTools(context.tools),
      options: ollamaOptions
    }

    return fetch(chatUrl, { method: "POST", headers, body: JSON.stringify(body) })
  }
```

### OpenAI-Compatible

```
buildOpenAiRequest(model, context, options):
  messages = convertToOpenAiMessages(context.messages)

  # Handle system prompt
  if (context.systemPrompt):
    messages.unshift({ role: "system", content: context.systemPrompt })

  # Handle image content
  for msg in messages:
    for part in msg.content:
      if (part.type === "image"):
        part → { type: "image_url", image_url: { url: "data:..." } }

  body = {
    model: model.id,
    messages,
    stream: true,
    max_tokens: options.maxTokens,
    temperature: options.temperature
  }

  endpoint = baseUrl + "/chat/completions"
```

### OpenResponses (Anthropic Native)

```
buildOpenResponsesRequest(model, context, options):
  # Zod validation of request body
  validated = OpenResponsesRequestSchema.parse({
    model: model.id,
    input: context.messages,
    instructions: context.systemPrompt,
    tools: extractToolDefinitions(context.tools),
    stream: true,
    ...options
  })

  endpoint = baseUrl + "/responses"
```

## Auth Profile Rotation

### Profile Selection Algorithm

```
resolveAuthProfileOrder(cfg, store, provider, preferredProfile):
  providerKey = normalizeProviderId(provider)
  now = Date.now()

  # Step 1: Clear expired cooldowns (circuit breaker reset)
  clearExpiredCooldowns(store, now)

  # Step 2: Determine base order
  storedOrder = store.order[providerKey]
  configuredOrder = cfg.auth.order[providerKey]
  explicitOrder = storedOrder ?? configuredOrder
  explicitProfiles = cfg.auth.profiles.filter(p => matches provider)

  baseOrder = explicitOrder ??
              (explicitProfiles.length > 0 ? explicitProfiles :
               listProfilesForProvider(store, provider))

  if (baseOrder.empty): return []

  # Step 3: Filter to eligible profiles
  filtered = baseOrder.filter(profileId =>
    resolveAuthProfileEligibility({ cfg, store, provider, profileId, now }).eligible
  )

  # Step 4: Handle config/store drift
  if (filtered.empty and explicitProfiles.length > 0):
    allBaseMissing = baseOrder.every(id => not in store.profiles)
    if (allBaseMissing):
      filtered = listProfilesForProvider(store, provider).filter(isValid)

  deduped = dedupeProfileIds(filtered)

  # Step 5: Sort by availability
  if (explicitOrder and explicitOrder.length > 0):
    # Respect explicit order but sort cooldown profiles to end
    available = []
    inCooldown = []

    for profileId in deduped:
      if (isProfileInCooldown(store, profileId)):
        cooldownUntil = resolveProfileUnusableUntil(store.usageStats[profileId])
        inCooldown.push({ profileId, cooldownUntil })
      else:
        available.push(profileId)

    cooldownSorted = inCooldown.sortBy(cooldownUntil ascending)
    ordered = [...available, ...cooldownSorted.map(e => e.profileId)]

    # Preferred profile goes first
    if (preferredProfile in ordered):
      return [preferredProfile, ...ordered.filter(e => e !== preferredProfile)]
    return ordered

  # Step 6: Round-robin with type preference
  return orderProfilesByMode(deduped, store)
```

### Round-Robin Ordering

```
orderProfilesByMode(order, store):
  available = []
  inCooldown = []

  for profileId in order:
    if (isProfileInCooldown(store, profileId)):
      inCooldown.push(profileId)
    else:
      available.push(profileId)

  # Score by type preference: oauth > token > api_key
  # Then by lastUsed (oldest first = round-robin)
  scored = available.map(profileId => ({
    profileId,
    typeScore: getTypeScore(store.profiles[profileId].type),
    lastUsed: store.usageStats[profileId].lastUsed ?? 0
  }))

  sorted = scored.sortBy(typeScore ascending, then lastUsed ascending)

  # Append cooldown profiles (soonest expiry first)
  cooldownSorted = inCooldown.map(profileId => ({
    profileId,
    cooldownUntil: resolveProfileUnusableUntil(store.usageStats[profileId])
  })).sortBy(cooldownUntil ascending)

  return [...sorted.map(profileId), ...cooldownSorted.map(profileId)]
```

### Cooldown Calculation (Exponential Backoff)

```
calculateAuthProfileCooldownMs(errorCount):
  normalized = max(1, errorCount)

  # Formula: 60s × 5^(n-1), capped at 1 hour
  baseMs = 60 × 1000
  exponent = min(normalized - 1, 3)
  cooldownMs = baseMs × (5 ^ exponent)

  return min(3600 × 1000, cooldownMs)

  # Results:
  # errorCount=1:  60s cooldown
  # errorCount=2:  300s (5 min)
  # errorCount=3:  1,500s (25 min)
  # errorCount=4+: 3,600s (1 hour max)
```

### Circuit Breaker Reset

```
clearExpiredCooldowns(store, now):
  for each profile in store.usageStats:
    stats = store.usageStats[profileId]

    cooldownExpired = (stats.cooldownUntil != null and now >= stats.cooldownUntil)
    disabledExpired = (stats.disabledUntil != null and now >= stats.disabledUntil)

    if (cooldownExpired):
      stats.cooldownUntil = undefined

    if (disabledExpired):
      stats.disabledUntil = undefined
      stats.disabledReason = undefined

    # Reset error counters when ALL cooldowns expire
    # (circuit breaker: half-open → closed)
    if (not resolveProfileUnusableUntil(stats)):
      stats.errorCount = 0
      stats.failureCounts = undefined
```

## Model Resolution

### Provider Discovery

Models are resolved through two paths:

```
1. EXPLICIT providers (from config):
   User configures provider + models in openclaw.json

2. IMPLICIT providers (autodiscovery):
   System probes known endpoints to find available models
```

### Autodiscovery Flow

```
resolveImplicitProviders(agentDir, config, env, explicit):
  discovered = []

  # Ollama (localhost:11434)
  if (ollamaReachable):
    response = await fetch(ollamaBase + "/api/tags", timeout: 5s)
    models = response.json().models

    # Inspect context window for each (8 concurrent)
    for batch of 8 models:
      for model in batch:
        contextWindow = await queryOllamaContextWindow(ollamaBase, model.name)
        isReasoning = model.name.includes("r1") or "reasoning"

        discovered.push({
          id: model.name,
          name: model.name,
          reasoning: isReasoning,
          input: ["text"],
          cost: { input: 0, output: 0 },
          contextWindow: contextWindow ?? 128000,
          maxTokens: 8192
        })

  # Similar for: vLLM, Huggingface, Bedrock, GitHub Copilot,
  # Cloudflare AI Gateway, Vercel AI Gateway, Together AI,
  # OpenRouter, Venice AI, and 20+ more

  return discovered
```

### Model Resolution Output

Each resolved model produces:

```json
{
  "id": "claude-opus-4-6",
  "name": "Claude Opus 4.6",
  "api": "openresponses",
  "provider": "anthropic",
  "baseUrl": "https://api.anthropic.com/v1",
  "headers": {},
  "contextWindow": 200000,
  "maxTokens": 8192,
  "cost": {
    "input": 0.015,
    "output": 0.075,
    "cacheRead": 0.0015,
    "cacheWrite": 0.01875
  },
  "input": ["text", "image"],
  "reasoning": false
}
```

### Models.json Merge

```
ensureOpenClawModelsJson(config):
  providers = resolveProviders(config)           # implicit + explicit
  normalized = normalizeProviders(providers)      # resolve secrets, headers

  existing = readExistingModelsFile(targetPath)

  mode = config.models.mode ?? "merge"
  # "merge": combine existing + new (preserves manual edits)
  # "replace": overwrite entirely

  merged = resolveProvidersForMode({ mode, existing, normalized })

  next = JSON.stringify({ providers: merged }, null, 2)
  if (existing.raw === next): return { wrote: false }    # no change

  writeModelsFileAtomic(targetPath, next)
  return { wrote: true }
```

## Token Counting & Cost Tracking

### Usage Object

```
buildZeroUsage():
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      total: 0
    }
  }
```

### Extracting Usage from Responses

```
extractUsageFromResult(result):
  meta = result?.meta?.agentMeta?.usage
  if (not meta): return createEmptyUsage()

  input = max(0, meta.input ?? 0)
  output = max(0, meta.output ?? 0)
  cacheRead = max(0, meta.cacheRead ?? 0)
  cacheWrite = max(0, meta.cacheWrite ?? 0)
  total = max(0, meta.total ?? (input + output + cacheRead + cacheWrite))

  return { input, output, cacheRead, cacheWrite, totalTokens: total }
```

### Cost Calculation

Costs are computed by multiplying token counts by per-model rates:

```
calculateCost(usage, modelCost):
  return {
    input: usage.input × modelCost.input / 1000,
    output: usage.output × modelCost.output / 1000,
    cacheRead: usage.cacheRead × (modelCost.cacheRead ?? 0) / 1000,
    cacheWrite: usage.cacheWrite × (modelCost.cacheWrite ?? 0) / 1000,
    total: sum of above
  }
```

## Streaming Response Assembly

### Event-Based Accumulation

```
handleStreamingRequest(req, res, opts):
  setSseHeaders(res)

  wroteRole = false
  sawAssistantDelta = false
  closed = false

  # Subscribe to agent events
  unsubscribe = onAgentEvent((evt) => {
    if (evt.runId !== runId): return
    if (closed): return

    if (evt.stream === "assistant"):
      content = resolveAssistantStreamDeltaText(evt) ?? ""
      if (not content): return

      # Write role chunk once (first delta)
      if (not wroteRole):
        wroteRole = true
        writeSse(res, {
          id: runId,
          object: "chat.completion.chunk",
          model,
          choices: [{ index: 0, delta: { role: "assistant" } }]
        })

      sawAssistantDelta = true
      writeSse(res, {
        id: runId,
        object: "chat.completion.chunk",
        model,
        choices: [{ index: 0, delta: { content }, finish_reason: null }]
      })

    if (evt.stream === "lifecycle"):
      if (evt.data.phase in ["end", "error"]):
        closed = true
        unsubscribe()
        writeDone(res)
        res.end()
  })

  # Run agent command in parallel
  try:
    result = await agentCommandFromIngress(...)

    if (closed): return

    # Fallback: if no streaming events, write complete response
    if (not sawAssistantDelta):
      if (not wroteRole):
        wroteRole = true
        writeRoleChunk(res)

      content = resolveAgentResponseText(result)
      writeContentChunk(res, content)

  catch err:
    writeContentChunk(res, "Error: internal error")
    emitLifecycleEvent("error")

  finally:
    if (not closed):
      closed = true
      unsubscribe()
      writeDone(res)
      res.end()
```

### Tool Call Accumulation

During streaming, tool calls are accumulated from partial chunks:

```
# During streaming:
pendingToolCall = {
  id: "call_...",
  name: "function_name",
  arguments: ""                # accumulated JSON string
}

# Each chunk appends to arguments:
onToolCallDelta(delta):
  pendingToolCall.arguments += delta.arguments

# On completion:
if (stopReason === "tool_calls" and pendingToolCalls.length > 0):
  functionCall = pendingToolCalls[0]

  response = {
    id: responseId,
    status: "incomplete",
    output: [{
      type: "function_call",
      id: "call_" + randomUUID(),
      call_id: functionCall.id,
      name: functionCall.name,
      arguments: functionCall.arguments,
      status: "completed"
    }]
  }
```

### Non-Streaming Fallback

```
handleNonStreamingRequest(req, res):
  result = await agentCommandFromIngress(commandInput)
  content = resolveAgentResponseText(result)

  sendJson(res, 200, {
    id: runId,
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [{
      index: 0,
      message: { role: "assistant", content },
      finish_reason: "stop"
    }],
    usage: {
      prompt_tokens: usage.input,
      completion_tokens: usage.output,
      total_tokens: usage.totalTokens
    }
  })
```

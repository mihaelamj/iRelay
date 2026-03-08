# Agents — Technical Implementation Details

## System Prompt Construction

### Assembly Pipeline

The system prompt is built dynamically from layered sources:

```
buildAgentSystemPrompt(params):
  prompt = ""

  # 1. Identity line
  prompt += "You are a personal assistant running inside OpenClaw"

  # 2. Prompt mode controls what sections are included
  switch promptMode:
    "full":    all sections (main agent)
    "minimal": reduced sections (subagents)
    "none":    just identity line

  # 3. Sections (if mode allows)
  prompt += buildToolingSection(tools, toolSummaries)
  prompt += buildSkillsSection(skillsPrompt)
  prompt += buildMemorySection(memoryTools)
  prompt += buildSafetySection()                    # always included
  prompt += buildCliReferenceSection()
  prompt += buildModelAliasesSection(aliases)
  prompt += buildWorkspaceSection(workspaceDir)
  prompt += buildSandboxSection(sandboxConfig)
  prompt += buildAuthorizedSendersSection(ownerIds)
  prompt += buildMessagingSection(replyTags)
  prompt += buildVoiceSection(voiceConfig)

  # 4. Project context (bootstrap files)
  prompt += buildBootstrapContext(SOUL.md, USER.md, HEARTBEAT.md, ...)

  return prompt
```

### Bootstrap File Loading

```
resolveBootstrapContextForRun(config):
  files = []

  # Scan workspace for bootstrap files (max 100KB default)
  candidates = [
    "SOUL.md",           # Agent personality/behavior
    "USER.md",           # User preferences
    "HEARTBEAT.md",      # Scheduled task context
    "MEMORY.md",         # Persistent memory
    ...config.contextFiles
  ]

  for path in candidates:
    content = readFile(path)
    if (content and content.length <= maxBootstrapBytes):
      files.push({ path, content })

  # Run bootstrap hooks (plugins can add/override files)
  files = await hookRunner.runBootstrapHooks(files)

  return files    # Array of { path, content }
```

### Tool Availability in Prompt

```
buildToolingSection(tools, summaries):
  # 1. Canonicalize names (preserve casing, dedupe by lowercase)
  canonical = new Map()
  for tool in tools:
    key = tool.name.toLowerCase()
    if (not canonical.has(key)):
      canonical.set(key, tool)

  # 2. Core tools first (fixed order)
  ordered = ["read", "write", "edit", "grep", "find", "exec", ...]
    .filter(name => canonical.has(name))

  # 3. Plugin tools appended alphabetically
  pluginTools = tools.filter(t => t.pluginId).sortBy(name)
  ordered = [...ordered, ...pluginTools]

  # 4. Format descriptions
  for tool in ordered:
    section += tool.name + ": " + (summaries[tool.name] ?? tool.description)

  return section
```

### Owner Identity Hashing

```
buildOwnerIdentityLine(ownerIds, displayMode):
  if (displayMode === "hash"):
    for id in ownerIds:
      hashed = hmacSha256(id, secret).substring(0, 12)    # first 12 hex chars
      result.push(hashed)
  else:
    result = ownerIds

  return "Authorized Senders: " + result.join(", ")
```

## Tool Policy Pipeline

### Multi-Stage Evaluation

Tools pass through a pipeline of policy stages. Each stage can filter out tools:

```
Pipeline stages (in order):
  1. Profile Policy         (tools.profile)
  2. Provider Profile Policy (tools.byProvider.profile)
  3. Global Allow           (tools.allow)
  4. Provider Global Allow  (tools.byProvider.allow)
  5. Agent-Specific Allow   (agents.<agentId>.tools.allow)
  6. Agent Provider Allow   (agents.<agentId>.tools.byProvider.allow)
  7. Group Allow            (tools.allow at group level)
```

### Evaluation Algorithm

```
applyToolPolicyPipeline(tools, steps):
  coreTools = buildSet(tools without pluginId)
  pluginGroups = buildPluginToolGroups(tools)

  filtered = tools
  for step in steps:
    if (step.policy is empty): continue

    # Prevent accidental core tool disabling
    resolved = stripPluginOnlyAllowlist(step.policy, pluginGroups, coreTools)
    if (resolved.unknownAllowlist.length > 0):
      warn("Unknown tools in allowlist: " + resolved.unknownAllowlist)

    # Expand "group:plugins" → all plugin tool names
    policy = expandPolicyWithPluginGroups(resolved.policy, pluginGroups)

    # Filter tools against this stage
    filtered = filterToolsByPolicy(filtered, policy)

  return filtered
```

### Special Policies

**Owner-Only Tools:**
```
OWNER_ONLY_TOOLS = ["whatsapp_login", "cron", "gateway"]

applyOwnerOnlyToolPolicy(tools, senderIsOwner):
  if (senderIsOwner): return tools    # no filtering
  return tools.filter(t => t.name not in OWNER_ONLY_TOOLS)
```

**Subagent Tool Restrictions:**
```
ALWAYS_DENY = ["gateway", "agents_list", "whatsapp_login",
               "session_status", "cron", "memory_search",
               "memory_get", "sessions_send"]

DENY_FOR_LEAF = ["sessions_list", "sessions_history", "sessions_spawn"]

resolveSubagentToolPolicy(tools, depth, maxDepth):
  filtered = tools.filter(t => t.name not in ALWAYS_DENY)

  if (depth >= maxDepth):    # leaf subagent
    filtered = filtered.filter(t => t.name not in DENY_FOR_LEAF)

  return filtered
```

## Agent Run Loop

### Outer Loop (Retry Management)

```
runEmbeddedPiAgent(params):
  # Initialize
  workspace = resolveWorkspaceDirectory()
  modelsJson = loadModelsJson()
  await hookRunner.runBeforeModelResolve()
  authProfiles = resolveAuthProfileOrder(config, store, provider)
  profileIndex = 0

  iterations = 0
  MAX_ITERATIONS = 160

  while (iterations < MAX_ITERATIONS):
    iterations += 1

    # Select current auth profile
    profile = authProfiles[profileIndex]
    apiKey = resolveApiKey(profile)

    # Run single attempt
    attempt = runEmbeddedAttempt({
      ...params,
      provider: profile.provider,
      model: resolvedModel,
      apiKey,
      thinkLevel
    })

    # Accumulate usage
    mergeUsage(totalUsage, attempt.usage)

    # Handle result
    switch attempt.result:
      case SUCCESS:
        return { payloads: attempt.payloads, usage: totalUsage }

      case CONTEXT_OVERFLOW:
        # Try auto-compaction (up to 3 times)
        if (compactionAttempts < 3):
          compactionAttempts += 1
          continue
        # Try tool result truncation
        # Give up
        return overflowError

      case AUTH_ERROR:
        # Try Copilot token refresh
        # Failover to next profile
        profileIndex += 1
        if (profileIndex >= authProfiles.length):
          return authError
        markProfileFailure(profile)
        continue

      case RATE_LIMIT:
        markProfileCooldown(profile)
        profileIndex += 1
        if (profileIndex >= authProfiles.length):
          return rateLimitError
        continue

      case OVERLOADED:
        # Backoff: 250ms initial, 1.5s max, factor 2, jitter 0.2
        await backoff(iterations)
        continue

  return maxIterationsError
```

### Single Attempt

```
runEmbeddedAttempt(params):
  # 1. Load and repair session file
  sessionFile = resolveSessionFile(params.sessionId)
  repairIfNeeded(sessionFile)

  # 2. Initialize session manager
  manager = SessionManager.open(sessionFile)
  session = new AgentSession(manager)

  # 3. Build system prompt
  systemPrompt = buildEmbeddedSystemPrompt({
    identity, tools, skills, memory, safety,
    workspace, bootstrap, voice
  })

  # 4. Filter tools by policy
  availableTools = applyToolPolicyPipeline(allTools, policySteps)
  codingTools = createOpenClawCodingTools(availableTools)

  # 5. Subscribe to events
  subscribe(session, {
    onMessageStart, onMessageUpdate, onMessageEnd,
    onToolStart, onToolUpdate, onToolEnd,
    onAgentStart, onAgentEnd,
    onCompactionStart, onCompactionEnd
  })

  # 6. Stream LLM call
  streamFn = createStreamFunction(params.provider)
  result = await session.run({
    message: params.userMessage,
    systemPrompt,
    tools: codingTools,
    streamFn,
    model: params.model,
    maxTokens: params.maxTokens,
    temperature: params.temperature
  })

  # 7. Return result with usage
  return {
    result: result.status,
    payloads: result.payloads,
    usage: result.usage,
    lastAssistant: result.lastAssistantMessage,
    compactionCount: result.compactionCount
  }
```

## Subagent Spawning

### Spawn Flow

```
spawnSubagentDirect(params, ctx):
  # Validation
  validate(agentId matches /^[a-z0-9][a-z0-9_-]{0,63}$/)
  validate(task is not empty)

  # Depth check
  callerDepth = getSubagentDepth(requesterSessionKey)
  maxDepth = config.agents.defaults.subagents.maxSpawnDepth    # default: 5
  if (callerDepth >= maxDepth):
    return forbidden("Max subagent depth reached")

  # Concurrency check
  activeChildren = countActiveRuns(requesterSessionKey)
  maxChildren = config.agents.defaults.subagents.maxChildrenPerAgent  # default: 5
  if (activeChildren >= maxChildren):
    return forbidden("Too many active subagents")

  # Target agent validation
  targetAgent = requestedAgentId ?? requesterAgentId
  if (targetAgent !== requesterAgentId):
    allowedAgents = config.agents[requesterAgentId].subagents.allowAgents
    if (not allowAny and targetAgent not in allowedAgents):
      return forbidden("Agent not in allowlist")

  # Create child session
  childSessionKey = "agent:" + agentId + ":subagent:" + uuid()
  childDepth = callerDepth + 1

  # Model selection
  model = resolveSubagentModelSelection(config, targetAgent, modelOverride)

  # Patch session metadata
  patchChildSession({
    spawnDepth: childDepth,
    model,
    thinking: normalizeThinkingLevel(params.thinking),
    spawnedBy: requesterSessionKey
  })

  # Thread binding (optional)
  if (params.thread):
    ensureThreadBinding(childSessionKey, requesterSessionKey)

  # Materialize attachments
  attachments = materializeSubagentAttachments(params.attachments)

  # Build child system prompt
  childPrompt = buildSubagentSystemPrompt({
    requesterKey: requesterSessionKey,
    childKey: childSessionKey,
    label: params.label,
    task: params.task,
    acpEnabled: config.acp?.enabled,
    depth: childDepth,
    maxDepth
  })

  # Construct task message
  taskMessage = "[Subagent Context] depth " + childDepth + "/" + maxDepth +
                ". Do not poll. [Subagent Task]: " + params.task

  # Send to gateway
  response = callGateway("agent", {
    message: taskMessage,
    sessionKey: childSessionKey,
    extraSystemPrompt: childPrompt,
    deliver: false,
    lane: SUBAGENT_LANE,
    timeout: runTimeoutSeconds
  })

  # Register for tracking
  registerSubagentRun({
    runId: response.runId,
    childSessionKey,
    requesterSessionKey,
    task: params.task,
    cleanup: params.cleanup ?? "keep"
  })

  return { status: "accepted", childSessionKey, runId: response.runId }
```

### Completion Announcement

When a subagent finishes, it announces back to the parent:

```
onSubagentComplete(childRunId, result):
  registration = getSubagentRegistration(childRunId)
  parentSessionKey = registration.requesterSessionKey

  # Send completion as user message to parent session
  completionMessage = "[Subagent Complete] " + registration.task +
                      "\nResult: " + summarize(result)

  sendToSession(parentSessionKey, completionMessage)

  # If parent already finished: parent replies with NO_REPLY
```

## Streaming Event Lifecycle

### Event Phases

```
AGENT RUN EVENT FLOW:

  agent_start
    │
    ├── message_start          ← LLM begins generating
    │   ├── message_update     ← delta content arrives (repeated)
    │   └── message_end        ← generation complete
    │
    ├── tool_execution_start   ← agent calls a tool
    │   ├── tool_execution_update  ← tool output streams
    │   └── tool_execution_end     ← tool result logged
    │
    ├── (repeat message/tool cycles)
    │
    ├── auto_compaction_start  ← context overflow detected
    │   └── auto_compaction_end    ← compaction result
    │
    └── agent_end              ← session done (success or error)
```

### Event Handler Dispatch

```
handleEvent(evt):
  switch evt.type:
    "message_start":
      handleMessageStart(ctx, evt)

    "message_update":
      handleMessageUpdate(ctx, evt)
      # Accumulates partial text in reply builder
      # Emits onPartialReply callback

    "message_end":
      handleMessageEnd(ctx, evt)
      # Flushes any pending reasoning blocks
      # Emits onReasoningEnd if <think> present

    "tool_execution_start":
      asyncTask(handleToolExecutionStart(ctx, evt))
      # Non-blocking: typing indicators, tool summaries

    "tool_execution_update":
      handleToolExecutionUpdate(ctx, evt)

    "tool_execution_end":
      asyncTask(handleToolExecutionEnd(ctx, evt))
      # Non-blocking: save outputs, log execution

    "agent_start":
      handleAgentStart(ctx)

    "auto_compaction_start":
      handleAutoCompactionStart(ctx)

    "auto_compaction_end":
      handleAutoCompactionEnd(ctx, evt)

    "agent_end":
      handleAgentEnd(ctx)
```

### Callback Chain

```
Streaming flow for a single assistant message:

1. onAssistantMessageStart()
2. (for each delta chunk):
   → onPartialReply({ text, mediaUrls })
   → accumulate in block reply builder
   → onBlockReply({ type, text }) every N tokens or at boundaries
3. onBlockReplyFlush() before tool execution
4. (if tool called):
   → onToolResult({ text, mediaUrls }) if shouldEmitToolResult()
   → onToolOutput() if shouldEmitToolOutput()
5. (if <think> block present):
   → onReasoningEnd()
6. onPartialReply({ ...final content })
```

### Usage Tracking

```
Each attempt tracks:
  input:      prompt token count
  output:     generated token count
  cacheRead:  prompt cache hits
  cacheWrite: prompt cache misses
  total:      input + output + cacheRead + cacheWrite

Accumulation across retries:
  totalUsage.input += attempt.usage.input
  totalUsage.output += attempt.usage.output
  # etc.

Context size reporting uses LAST call's cache fields only
(prevents N × context_size inflation across tool loops)
```

## Model Selection & Failover

### Selection Order

```
1. Check for user-locked auth profile
   if (lockedProfile and lockedProfile.provider !== requestedProvider):
     clearLock()

2. Build auth profile candidate list:
   profiles = resolveAuthProfileOrder(config, store, provider)
   # Returns profiles sorted by: available first, then cooldown (soonest expiry)

3. For each candidate:
   if (inCooldown and not allowTransientProbe): skip
   apiKey = resolveApiKey(profile)
   if (isCopilot): exchangeTokenAndScheduleRefresh()
   return profile
```

### Failover Classification

```
classifyFailoverReason(errorMessage):
  if matches /rate limit|too many requests|429/: return "rate_limit"
  if matches /overload|busy|throttle/:          return "overloaded"
  if matches /billing|payment|quota/:           return "billing"
  if matches /auth|unauthorized|invalid key/:   return "auth"
  if matches /context length|token limit/:      return "context_overflow"
  return null
```

### Failover Actions

```
rate_limit:
  → Mark profile in cooldown (60s × 5^(n-1), max 1 hour)
  → Advance to next profile
  → Retry

overloaded:
  → Backoff: 250ms initial, 1.5s max, factor 2, jitter 0.2
  → Retry with same model

auth:
  → If Copilot: try token refresh
  → Advance profile
  → Retry

context_overflow:
  → Try auto-compaction (up to 3x)
  → Try tool result truncation
  → Return error (no retry)

billing:
  → Permanent error, notify user
  → No retry
```

### Context Window Guard

```
evaluateContextWindowGuard(model, config):
  tokens = configOverride ?? model.contextWindow ?? DEFAULT

  if (tokens < 4000):     shouldBlock = true
  if (tokens < 20000):    shouldWarn = true

  return { tokens, shouldWarn, shouldBlock, source }
```

### Model Compatibility Checks

Before running, the system verifies:

```
- supportsModelTools(model)       # can the model use tool calls?
- supportsReasoning(model)        # is it a reasoning model?
- supportsThinkingTags(provider)  # does provider support <think>?
- Apply refusal-string scrubbing  # strip jailbreak test tokens
```

# Plugins — Technical Implementation Details

## Plugin SDK Exports

The Plugin SDK provides 50+ subpath exports:

```
openclaw/plugin-sdk/<export>

Categories:
  Core:       types, index
  Channels:   discord, slack, telegram, signal, imessage, whatsapp, ...
  Media:      agent-media-payload, outbound-media
  Voice:      voice-call, talk-voice, types.tts
  Webhooks:   webhook-targets, webhook-request-guards
  Auth:       command-auth, group-access, allow-from
  Memory:     dedupe, persistent-dedupe
  Storage:    config utilities
  Async:      keyed-async-queue, file-lock
```

### Resolution Strategy

```
resolvePluginSdkExport(subpath):
  # 1. Build alias map from package.json "exports" field
  # 2. Map subpath to file:
  #    Development: src/*.ts
  #    Production:  dist/*.js
  # 3. Walk up directory tree to find plugin-sdk location
  # 4. Cache result for subsequent imports
```

## Hook System

### 24 Available Hooks

```
Agent Lifecycle:
  before_model_resolve    → override provider/model selection
  before_prompt_build     → inject context into system prompt
  before_agent_start      → legacy combined phase
  llm_input               → inspect final LLM request
  llm_output              → modify LLM response
  agent_end               → finalize agent run

Compaction/Reset:
  before_compaction       → pre-compress state
  after_compaction        → post-compress state
  before_reset            → pre-clear session

Message Flow:
  message_received        → inbound message processing
  message_sending         → pre-send transformation
  message_sent            → post-send confirmation
  before_message_write    → before transcript persist

Tool Execution:
  before_tool_call        → pre-execute validation
  after_tool_call         → post-execute cleanup
  tool_result_persist     → persist tool output

Session Management:
  session_start           → new conversation begins
  session_end             → conversation finalizes

Subagent:
  subagent_spawning       → spawn decision gate
  subagent_delivery_target → route target override
  subagent_spawned        → post-spawn notification
  subagent_ended          → post-terminate cleanup

Gateway:
  gateway_start           → server startup
  gateway_stop            → server shutdown
```

### Registration

```
registerHook(events, handler, opts?):
  hookName = events    # string or string[] of hook names
  priority = opts?.priority ?? 0    # higher = runs earlier

  registry.typedHooks.push({
    hookName,
    handler,
    priority,
    pluginId
  })

  # Sorted by priority DESC on retrieval
```

### Dispatch Patterns

**Void Hooks (fire-and-forget, parallel):**
```
runVoidHook(hookName, event, context):
  handlers = getHooksForName(hookName)    # sorted by priority DESC

  # Execute ALL in parallel
  await Promise.all(
    handlers.map(h => h.handler(event, context))
  )

  # Errors logged individually (catchErrors=true)
```

**Modifying Hooks (sequential, accumulate):**
```
runModifyingHook(hookName, event, context, mergeResults?):
  handlers = getHooksForName(hookName)    # sorted by priority DESC
  accumulated = undefined

  # Execute SEQUENTIALLY (order matters)
  for handler in handlers:
    result = await handler(event, context)
    accumulated = mergeResults(accumulated, result)

  return accumulated
```

### Result Merging Strategy

```
before_model_resolve:
  modelOverride:    first-set wins (highest priority plugin wins)
  providerOverride: first-set wins

before_prompt_build:
  systemPrompt:          last-set wins (override behavior)
  prependContext:         all concatenated
  prependSystemContext:   all concatenated (for caching)
  appendSystemContext:    all concatenated

message_sending:
  text: last-set wins (plugins can rewrite message)
```

## Plugin Lifecycle

### Discovery

```
discoverOpenClawPlugins(params):
  # Scan 4 sources in order:
  sources = [
    bundledPluginsDir,                    # OpenClaw distribution
    globalConfigDir (~/.openclaw/extensions),
    workspaceDir (optional),
    configExtraPaths (env var)
  ]

  for root in sources:
    # Search for package.json + openclaw.plugin.json
    candidates = findPluginCandidates(root)

    for candidate in candidates:
      # Security checks (non-bundled only):
      if (not bundled):
        checkSymlinkEscape(candidate.path)       # realpath comparison
        checkWorldWritable(candidate.path)        # 0o002 check
        checkUidOwnership(candidate.path)         # except root

  return { candidates, diagnostics }

  # Cache: 1-second TTL (OPENCLAW_PLUGIN_DISCOVERY_CACHE_MS)
```

### Installation

```
installPluginBySpec(spec):
  if (isNpmSpec(spec)):
    # npm install to workspace node_modules
    npm install <spec> --save
  else if (isLocalPath(spec)):
    # Create symlink in extensions directory
    symlink(spec, extensionsDir/pluginId)

  reloadRegistry()
```

### Loading

```
loadPlugins(options):
  candidates = discoverOpenClawPlugins()
  manifestRegistry = loadPluginManifestRegistry()

  for plugin in enabledPlugins:
    try:
      # Dynamic import via jiti (TypeScript-aware eval)
      module = jiti(plugin.entryPoint)

      # Call register(api) or invoke module(api)
      module.register(buildPluginApi(plugin))

      # Validate config schema (JSON Schema via Ajv)
      if (plugin.configSchema):
        validateJsonSchemaValue(plugin.configSchema, plugin.config)

    catch err:
      diagnostics.push({ plugin: plugin.id, error: err })
      continue    # don't break other plugins

  return PluginRegistry
```

### Registration API

```
Plugin receives OpenClawPluginApi with:
  registerTool(tool, opts)           → add tool for agents
  registerHook(events, handler, opts) → subscribe to hooks
  registerChannel(plugin)            → add messaging channel
  registerProvider(provider)         → add LLM provider
  registerCommand(commandDef)        → add CLI command
  registerService(service)           → add background service
  registerHttpRoute(params)          → add HTTP endpoint
  registerGatewayMethod(method, handler) → add gateway RPC method
  registerContextEngine(id, factory)     → add context provider
  registerCli(registrar, opts)           → add CLI subcommand tree
```

### Plugin Manifest

```json
// openclaw.plugin.json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "What it does",
  "version": "1.0.0",
  "configSchema": { /* JSON Schema */ },
  "kind": "memory",
  "channels": [],
  "providers": [],
  "uiHints": {
    "apiKey": { "label": "API Key", "help": "Your key", "sensitive": true }
  }
}
```

## Hook Priority Ordering

### Execution Order Example

```
Hook: "before_prompt_build"

Plugin A (priority: 100) → runs first
  sets prependContext = "Context from A"

Plugin B (priority: 50)  → runs second
  sets prependContext = "Context from B"

Plugin C (priority: 0)   → runs last
  sets prependContext = "Context from C"

Result: prependContext = "Context from A\nContext from B\nContext from C"
  (all concatenated, highest priority first)

But for systemPrompt:
  Plugin A sets systemPrompt = "Prompt A"
  Plugin B sets systemPrompt = "Prompt B"
  Result: systemPrompt = "Prompt B"  (last-set wins)
```

### Priority Guidelines

```
priority > 0:   runs before default plugins
priority = 0:   default (most plugins)
priority < 0:   runs after default plugins

Higher priority wins for first-set fields (model, provider)
Lower priority wins for last-set fields (systemPrompt)
All priorities contribute for concatenated fields (context)
```

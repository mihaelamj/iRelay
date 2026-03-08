# Configuration — Technical Implementation Details

## Config Loading Pipeline

The complete loading sequence from file to usable config:

```
loadConfig()
  │
  ├─ Fast path: if runtimeConfigSnapshot exists, return it immediately
  │
  ├─ 1. RESOLVE PATH
  │     CLI flag --config > env OPENCLAW_CONFIG > default candidates
  │     Default: ~/.openclaw/openclaw.json
  │
  ├─ 2. LOAD .env FILE
  │     loadDotEnvForConfig() → parse ~/.openclaw/.env if exists
  │
  ├─ 3. READ FILE
  │     fs.readFileSync(configPath, "utf-8")
  │     If file missing → return empty {}
  │
  ├─ 4. PARSE JSON5
  │     JSON5.parse(raw)    # supports comments, trailing commas
  │
  ├─ 5. RESOLVE $include DIRECTIVES
  │     resolveConfigIncludesForRead()
  │     Supports: { "$include": "./other-config.json5" }
  │     Circular detection: throws CircularIncludeError
  │
  ├─ 6. APPLY config.env VARS
  │     For each key in config.env.vars:
  │       if not in process.env AND not isDangerousHostEnvVar(key):
  │         process.env[key] = value
  │
  ├─ 7. SUBSTITUTE ${VAR} REFERENCES
  │     resolveConfigEnvVars()
  │     Walk all string values in config tree
  │     Replace ${UPPERCASE_VAR} with process.env[VAR]
  │     $${VAR} → literal "${VAR}" (escaped)
  │     Missing vars → MissingEnvVarError (collected, non-fatal)
  │
  ├─ 8. VALIDATE WITH ZOD
  │     OpenClawSchema.parse(config)
  │     Additional checks:
  │       - Duplicate agent directories
  │       - Valid identity avatars
  │       - Tailscale binding compatibility
  │     If invalid → throw INVALID_CONFIG
  │
  ├─ 9. APPLY DEFAULTS (in this order)
  │     applyMessageDefaults()
  │     applyLoggingDefaults()
  │     applySessionDefaults()
  │     applyAgentDefaults()
  │     applyContextPruningDefaults()
  │     applyCompactionDefaults()
  │     applyModelDefaults()
  │     applyTalkConfigNormalization()
  │
  ├─ 10. NORMALIZE PATHS
  │      Resolve ~ to home directory
  │      Resolve relative paths to absolute
  │
  ├─ 11. LOAD SHELL ENV (optional)
  │      If config.env.shellEnv.enabled:
  │        Exec login shell, capture env vars
  │        Merge into process.env (timeout: 15s)
  │
  └─ 12. APPLY RUNTIME OVERRIDES
         applyConfigOverrides() → merge in-memory overrides
```

## Environment Variable Substitution

### Parsing Algorithm

The parser scans each string value character by character:

```
substituteEnvVars(value, configPath):
  result = ""
  i = 0

  while i < value.length:
    if value[i] !== "$":
      result += value[i]
      i += 1
      continue

    # Check for escape: $${VAR} → literal ${VAR}
    if value[i+1] === "$" AND value[i+2] === "{":
      end = indexOf("}", i+3)
      if end !== -1:
        name = value.slice(i+3, end)
        if isValidEnvName(name):     # /^[A-Z_][A-Z0-9_]*$/
          result += "${" + name + "}"
          i = end + 1
          continue

    # Check for substitution: ${VAR} → env value
    if value[i+1] === "{":
      end = indexOf("}", i+2)
      if end !== -1:
        name = value.slice(i+2, end)
        if isValidEnvName(name):
          envValue = process.env[name]
          if envValue === undefined:
            onMissing(name, configPath)    # collect warning
            result += "${" + name + "}"    # leave as-is
          else:
            result += envValue
          i = end + 1
          continue

    # Not a pattern, literal $
    result += "$"
    i += 1

  return result
```

**Key constraint**: Only `UPPERCASE_NAMES` are substituted. `${lowercase}` is left as-is.

## Zod Schema Patterns

### Discriminated Unions

For types that vary based on a key field:

```typescript
// Secret references: different shape based on "source" field
const SecretRefSchema = z.discriminatedUnion("source", [
  z.object({ source: z.literal("env"),  id: z.string().regex(/^[A-Z][A-Z0-9_]*$/) }).strict(),
  z.object({ source: z.literal("file"), id: z.string() }).strict(),
  z.object({ source: z.literal("exec"), command: z.string().min(1) }).strict(),
]);

// Validates: { source: "env", id: "API_KEY" } ✓
// Rejects:   { source: "env", id: "lowercase" } ✗ (regex fails)
// Rejects:   { source: "file", extra: "field" } ✗ (strict mode)
```

### Custom Validators

```typescript
const ExecProviderSchema = z.object({
  command: z.string()
    .min(1)
    .refine(isSafeExecutableValue, "command contains unsafe characters")
    .refine(isAbsolutePath, "command must be an absolute path"),

  args: z.array(z.string().max(1024)).max(128).optional(),
  timeoutMs: z.number().int().positive().max(120000).optional(),
}).strict();
```

`.refine()` runs custom validation functions after the base type checks pass.
`.strict()` rejects any fields not defined in the schema (catches typos).

## Config Merge Patch

### How Partial Updates Work

OpenClaw uses RFC 7396 Merge Patch semantics with extensions:

```
Rules:
  1. Non-object patch value → replace entirely
  2. Object patch + object base → recursive merge
  3. null patch value → delete field
  4. Array of objects with "id" field → merge by ID

Examples:

  Base: { "a": 1, "b": { "c": 2, "d": 3 } }
  Patch: { "b": { "c": 5 } }
  Result: { "a": 1, "b": { "c": 5, "d": 3 } }    # deep merge

  Base: { "a": 1, "b": 2 }
  Patch: { "b": null }
  Result: { "a": 1 }                                # null = delete

  Base: { "agents": [{ "id": "main", "model": "claude" }] }
  Patch: { "agents": [{ "id": "main", "model": "gpt-4" }] }
  Result: { "agents": [{ "id": "main", "model": "gpt-4" }] }   # merge by ID
```

### Prototype Pollution Protection

```
const BLOCKED_KEYS = new Set(["__proto__", "constructor", "prototype"])

for (key, value) of patch:
  if BLOCKED_KEYS.has(key):
    continue    # silently skip
  // ... normal merge
```

## Migration System

### How Migrations Run

```
applyLegacyMigrations(raw):
  changes = []

  # Collect all migrations from parts 1, 2, 3
  allMigrations = [
    ...LEGACY_CONFIG_MIGRATIONS_PART_1,
    ...LEGACY_CONFIG_MIGRATIONS_PART_2,
    ...LEGACY_CONFIG_MIGRATIONS_PART_3,
  ]

  # Run each migration
  for migration of allMigrations:
    try:
      migration.apply(raw, changes)    # mutates raw in-place
    catch (err):
      changes.push("Migration " + migration.id + " failed: " + err.message)

  # Validate result
  validated = validateConfig(raw)
  if not validated.ok:
    return { next: null, changes }

  return { next: validated.config, changes }
```

### Migration Detection

Migrations don't check a version number. Instead, each migration checks if its source field exists:

```typescript
{
  id: "bindings.match.provider->bindings.match.channel",
  apply: (raw, changes) => {
    const bindings = raw.bindings;
    if (!Array.isArray(bindings)) return;    // nothing to migrate

    for (const binding of bindings) {
      if (binding?.match?.provider) {         // legacy field exists?
        binding.match.channel = binding.match.provider;
        delete binding.match.provider;
        changes.push("Moved bindings[].match.provider to .channel");
      }
    }
  }
}
```

This makes migrations **idempotent** — running them on an already-migrated config does nothing.

## Default Application

### Pattern

Each subsystem has its own `applyXxxDefaults()` function that fills in missing fields:

```
applyAgentDefaults(cfg):
  agents = cfg.agents ?? {}
  defaults = agents.defaults ?? {}

  # Fill defaults
  defaults.concurrency ??= 8
  defaults.model ??= resolveDefaultModel(cfg.models)

  # Ensure at least one agent exists
  if not agents.list:
    agents.list = [{ id: "main", default: true }]

  # Apply defaults to each agent
  for agent of agents.list:
    agent.concurrency ??= defaults.concurrency
    agent.model ??= defaults.model
    agent.workspace ??= defaults.workspace

  return { ...cfg, agents }
```

The `??=` operator means "assign only if currently null or undefined". Existing values are preserved.

### Default Model Resolution

```
resolveDefaultModel(modelsConfig):
  # Check configured providers for first available model
  for provider of Object.keys(modelsConfig?.providers ?? {}):
    models = modelsConfig.providers[provider].models
    if models?.length > 0:
      return provider + "/" + models[0].id

  # Hard default
  return "anthropic/claude-opus-4-6"
```

## Hot-Reload Mechanism

### Runtime Snapshot Pattern

```
# In-memory state
runtimeConfigSnapshot = null       # current live config
runtimeConfigSourceSnapshot = null  # config without defaults (for diffing)

# Set by gateway when config changes
setRuntimeConfigSnapshot(config, sourceConfig):
  runtimeConfigSnapshot = config
  runtimeConfigSourceSnapshot = sourceConfig
  clearConfigCache()               # invalidate file-based cache

# loadConfig() fast path
loadConfig():
  if runtimeConfigSnapshot:
    return runtimeConfigSnapshot    # zero disk I/O
  // ... normal file loading

# Config write with patch preservation
writeConfig(newConfig):
  if runtimeConfigSnapshot AND runtimeConfigSourceSnapshot:
    # What changed? Create a diff
    patch = createMergePatch(runtimeConfigSnapshot, newConfig)

    # Apply diff to source config (preserves ${ENV_VARS} and comments)
    finalConfig = applyMergePatch(runtimeConfigSourceSnapshot, patch)

    # Write the source-level config (not the runtime-expanded version)
    writeTextAtomic(configPath, JSON.stringify(finalConfig, null, 2))
  else:
    writeTextAtomic(configPath, JSON.stringify(newConfig, null, 2))
```

This pattern ensures that writing config back preserves:
- Environment variable references (`${API_KEY}` stays as `${API_KEY}`, not the resolved value)
- Runtime defaults aren't written to disk (they'll be re-applied on next load)
- Only actual user changes are persisted

## Config Include Directives

### Format

```json
{
  "models": { "$include": "./models.json5" },
  "channels": { "$include": "./channels.json5" }
}
```

### Resolution

```
resolveIncludes(obj, basePath, seen = Set()):
  if obj has "$include":
    includePath = resolve(basePath, obj["$include"])

    # Circular detection
    if seen.has(includePath):
      throw CircularIncludeError(includePath)
    seen.add(includePath)

    # Load included file
    raw = readFileSync(includePath, "utf-8")
    parsed = JSON5.parse(raw)

    # Recursively resolve includes in the included file
    return resolveIncludes(parsed, dirname(includePath), seen)

  # Recurse into object properties
  for key of Object.keys(obj):
    if typeof obj[key] === "object":
      obj[key] = resolveIncludes(obj[key], basePath, seen)

  return obj
```

The `seen` Set tracks which files have been loaded to detect circular includes (A includes B includes A).

## Session Config Specifics

### Session Store Loading with Cache

```
loadSessionStore(storePath):
  # Check cache first
  stat = fs.stat(storePath)         # get mtime and size
  cached = readSessionStoreCache({
    storePath,
    ttlMs: 45000,                   # 45 second TTL
    mtimeMs: stat.mtimeMs,
    sizeBytes: stat.size,
  })
  if cached: return cached

  # Cache miss: read from disk
  raw = readFileSync(storePath, "utf-8")

  # Windows retry for empty file (mid-write observation)
  if raw.length === 0:
    for i in [1, 2]:
      sleep(50)                     # Atomics.wait
      raw = readFileSync(storePath, "utf-8")
      if raw.length > 0: break

  store = JSON.parse(raw)

  # Normalize entries
  for key of Object.keys(store):
    store[key] = normalizeSessionEntry(store[key])

  # Cache result
  writeSessionStoreCache({
    storePath,
    store,
    mtimeMs: stat.mtimeMs,
    sizeBytes: stat.size,
    serialized: raw,
  })

  return structuredClone(store)     # deep copy to prevent mutation
```

### Session Key Normalization

```
resolveSessionStoreEntry({ store, sessionKey }):
  normalized = sessionKey.toLowerCase()

  # Find existing entry (case-insensitive)
  existing = store[normalized]
  legacyKeys = []

  # Check for case variants (legacy)
  for key of Object.keys(store):
    if key.toLowerCase() === normalized AND key !== normalized:
      legacyKeys.push(key)
      if not existing OR store[key].updatedAt > existing.updatedAt:
        existing = store[key]    # use most recently updated variant

  return { normalizedKey: normalized, existing, legacyKeys }
```

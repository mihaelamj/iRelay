# Skills — Technical Implementation Details

## SKILL.md Parsing

### Dual-Parser Strategy

Skill files use YAML frontmatter between `---` delimiters, parsed with two parsers for robustness:

```
parseFrontmatterBlock(content):
  if (not content.startsWith("---")): return {}

  endIndex = content.indexOf("\n---", 3)
  if (endIndex === -1): return {}

  block = content.slice(4, endIndex)

  # Parser 1: YAML (structured)
  yamlParsed = YAML.parse(block, { schema: "core" })
  # Coerces: scalars → strings, objects → JSON

  # Parser 2: Line-based key:value (robust)
  lineParsed = {}
  for line in block.split("\n"):
    match = line.match(/^([\w-]+):\s*(.*)$/)
    if (match): lineParsed[match[1]] = match[2]
    # Supports multiline: indented continuation lines

  # Merge: YAML takes precedence, except inline colon-containing values
  merged = {}
  for (key, value) in yamlParsed:
    merged[key] = value
    if (lineParsed[key] and shouldPreferInlineLineValue(key)):
      merged[key] = lineParsed[key]

  for (key, value) in lineParsed:
    if (key not in merged): merged[key] = value

  return merged
```

### OpenClaw Metadata Fields

```yaml
---
name: prose
description: "Generate long-form content"
user-invocable: true
disable-model-invocation: false
command-dispatch: tool
command-tool: my_tool_name
command-arg-mode: raw
metadata:
  openclaw:
    skillKey: alternate-name
    primaryEnv: OPENAI_API_KEY
    emoji: "🪶"
    homepage: https://...
    always: true
    os: [darwin, linux]
    requires:
      bins: [jq, curl]
      anyBins: [python3, python]
      env: [OPENAI_API_KEY]
      config: [~/.ssh/config]
    install:
      - kind: brew
        formula: jq
        os: [darwin]
      - kind: node
        package: "@package/name@1.0.0"
      - kind: go
        module: github.com/user/tool@v1.0
      - kind: uv
        package: requests
      - kind: download
        url: https://...
        archive: zip
        extract: true
        stripComponents: 1
        targetDir: ~/.local/bin
---
```

## Gating System

### Multi-Layer Eligibility

```
shouldIncludeSkill(entry, config, eligibility):
  skillKey = resolveSkillKey(entry.skill, entry)
  skillConfig = resolveSkillConfig(config, skillKey)

  # Gate 1: Explicit disable
  if (skillConfig?.enabled === false): return false

  # Gate 2: Bundled allowlist
  if (not isBundledSkillAllowed(entry, config.skills.allowBundled)):
    return false

  # Gate 3: Runtime eligibility
  return evaluateRuntimeEligibility({
    os: entry.metadata?.os,
    requires: entry.metadata?.requires,
    always: entry.metadata?.always,
    hasBin: (name) => binaryExistsOnPath(name),
    hasRemoteBin: eligibility?.remote?.hasBin,
    hasEnv: (envName) => {
      process.env[envName] or
      skillConfig?.env?.[envName] or
      (skillConfig?.apiKey and entry.metadata?.primaryEnv === envName)
    },
    isConfigPathTruthy: (path) => resolveConfigPath(config, path)
  })
```

### Runtime Eligibility Check

```
evaluateRuntimeEligibility(params):
  if (params.always === true): return true    # skip all checks

  # OS check
  if (params.os and process.platform not in params.os):
    return false

  # Required binaries (ALL must exist)
  if (params.requires.bins):
    for bin in params.requires.bins:
      if (not params.hasBin(bin) and not params.hasRemoteBin?(bin)):
        return false

  # Any-of binaries (AT LEAST ONE must exist)
  if (params.requires.anyBins):
    found = false
    for bin in params.requires.anyBins:
      if (params.hasBin(bin) or params.hasRemoteBin?(bin)):
        found = true; break
    if (not found): return false

  # Required environment variables
  if (params.requires.env):
    for envName in params.requires.env:
      if (not params.hasEnv(envName)): return false

  # Required config paths
  if (params.requires.config):
    for configPath in params.requires.config:
      if (not params.isConfigPathTruthy(configPath)): return false

  return true
```

### Config Structure

```json
{
  "skills": {
    "allowBundled": ["skill-name", "skill-key"],
    "entries": {
      "skill-name": {
        "enabled": false,
        "env": { "ENV_VAR": "value" },
        "apiKey": "${secret:key-name}"
      }
    },
    "limits": {
      "maxCandidatesPerRoot": 300,
      "maxSkillsLoadedPerSource": 200,
      "maxSkillsInPrompt": 150,
      "maxSkillsPromptChars": 30000,
      "maxSkillFileBytes": 256000
    },
    "load": {
      "extraDirs": ["/path/to/skills"]
    }
  }
}
```

## Skill Execution

### Prompt Building Pipeline

```
buildWorkspaceSkillsPrompt(workspaceDir, opts):
  # Step 1: Load all skill entries from disk
  entries = loadSkillEntries(workspaceDir, opts)

  # Step 2: Filter by eligibility + config
  eligible = filterSkillEntries(entries, config, skillFilter, eligibility)

  # Step 3: Exclude disabled-for-model-invocation
  promptEntries = eligible.filter(e => e.invocation?.disableModelInvocation !== true)

  # Step 4: Extract Skill objects
  skills = promptEntries.map(e => e.skill)

  # Step 5: Apply limits (count + character budget)
  { skillsForPrompt, truncated } = applySkillsPromptLimits({
    skills,
    maxCount: config.skills.limits.maxSkillsInPrompt,      # 150
    maxChars: config.skills.limits.maxSkillsPromptChars     # 30000
  })

  # Step 6: Compact paths (replace $HOME with ~)
  skillsForPrompt = compactSkillPaths(skillsForPrompt)

  # Step 7: Format for injection
  prompt = formatSkillsForPrompt(skillsForPrompt)
  # Output: "## skillname\n<body>\n\n## nextskill\n<body>..."

  if (truncated):
    prompt = "⚠️ Skills truncated: included N of M\n" + prompt

  return prompt
```

### Limits Application

```
applySkillsPromptLimits(skills, maxCount, maxChars):
  if (skills.length <= maxCount):
    totalChars = sum(skill.body.length for skill in skills)
    if (totalChars <= maxChars):
      return { skillsForPrompt: skills, truncated: false }

  # Binary search for the right number of skills
  # that fits within maxChars
  lo = 1; hi = min(skills.length, maxCount)
  while (lo < hi):
    mid = (lo + hi + 1) / 2
    chars = sum(skills[0..mid].body.length)
    if (chars <= maxChars): lo = mid
    else: hi = mid - 1

  return { skillsForPrompt: skills.slice(0, lo), truncated: true }
```

## Skill Discovery

### Source Precedence

Skills are loaded from multiple directories. Later sources override earlier:

```
Source order (lowest → highest priority):
  1. Extra dirs (config: skills.load.extraDirs)
  2. Bundled (OpenClaw distribution directory)
  3. Managed (~/.openclaw/skills)
  4. Personal agents (~/.agents/skills)
  5. Project agents (workspace/.agents/skills)
  6. Workspace (workspace/skills)
```

### Loading Algorithm

```
loadSkillEntries(workspaceDir, opts):
  limits = resolveSkillsLimits(config)
  merged = Map()

  for (dir, source) in sources:
    resolved = resolveNestedSkillsRoot(dir)    # check for dir/skills/ subdir

    # If dir itself has SKILL.md
    if (exists(resolved/SKILL.md)):
      skills = loadSkillsFromDir(resolved, source)
    else:
      # Scan immediate subdirectories
      childDirs = listChildDirectories(resolved).slice(0, limits.maxCandidatesPerRoot)
      skills = []
      for name in childDirs:
        if (exists(resolved/name/SKILL.md)):
          skills.push(loadSkillFromDir(resolved/name, source))
        if (skills.length >= limits.maxSkillsLoadedPerSource): break

    for skill in skills:
      merged[skill.name] = skill    # later sources override earlier

  # Parse frontmatter for each
  entries = []
  for skill in merged.values():
    frontmatter = parseFrontmatterBlock(readFile(skill.filePath))
    metadata = resolveOpenClawMetadata(frontmatter)
    invocation = resolveSkillInvocationPolicy(frontmatter)
    entries.push({ skill, frontmatter, metadata, invocation })

  return entries
```

## Parameter Resolution

### Environment Variable Injection

```
applySkillEnvOverrides(skills, config):
  updates = []

  for entry in skills:
    skillKey = resolveSkillKey(entry.skill, entry)
    skillConfig = resolveSkillConfig(config, skillKey)
    if (not skillConfig): continue

    allowedSensitiveKeys = Set()
    if (entry.metadata?.primaryEnv):
      allowedSensitiveKeys.add(entry.metadata.primaryEnv)
    for env in (entry.metadata?.requires?.env ?? []):
      allowedSensitiveKeys.add(env)

    pendingOverrides = {}

    # Collect env overrides from config
    if (skillConfig.env):
      for (key, value) in skillConfig.env:
        envKey = key.trim()
        hasExternalValue = process.env[envKey] !== undefined and
                           not activeSkillEnvEntries.has(envKey)
        if (envKey and value and not hasExternalValue):
          pendingOverrides[envKey] = value

    # Inject apiKey as primary env
    if (entry.metadata?.primaryEnv and skillConfig.apiKey):
      resolvedKey = normalizeResolvedSecretInputString(skillConfig.apiKey)
      if (resolvedKey):
        pendingOverrides[entry.metadata.primaryEnv] = resolvedKey

    # Safety: sanitize and validate
    sanitized = sanitizeSkillEnvOverrides(pendingOverrides, allowedSensitiveKeys)

    # Blocked patterns (never injectable)
    ALWAYS_BLOCKED = [/^OPENSSL_CONF$/i, ...isDangerousHostEnvVarNames()]

    # Inject allowed vars
    for (envKey, value) in sanitized.allowed:
      if (acquireActiveSkillEnvKey(envKey, value)):
        updates.push({ key: envKey })
        process.env[envKey] = value

  # Return revert function
  return () => {
    for update in updates:
      releaseActiveSkillEnvKey(update.key)
  }
```

### Safety Guarantees

- Skills cannot override dangerous env vars (`PATH`, `LD_LIBRARY_PATH`, `OPENSSL_CONF`, etc.)
- Sensitive keys (`primaryEnv`, `requiredEnv`) must be explicitly whitelisted in metadata
- External host env vars are protected — once set externally, skills can't override
- Ref counting tracks active overrides (multiple skills can stack)
- Revert function restores original state when skill execution completes

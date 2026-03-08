# CLI — Technical Implementation Details

## Command Registration

### Lazy Loading Pattern

Commands are registered lazily to minimize startup time:

```
CoreCliCommands = [
  { name: "setup",     register: registerSetupCommand },
  { name: "config",    register: registerConfigCli, hasSubcommands: true },
  { name: "agent",     register: registerAgentCommands, hasSubcommands: true },
  { name: "skills",    register: registerSkillsCli },
  { name: "plugins",   register: registerPluginsCli },
  { name: "health",    register: registerHealthCommand },
  ... (~20+ total)
]

buildProgram():
  program = new Commander.Program()

  registerProgramCommands(program):
    primaryCommand = getPrimaryCommand(argv)

    if (PRIMARY_ONLY mode):
      # Only register the target command as a lazy placeholder
      placeholder = program.command(primaryCommand)
      placeholder.allowUnknownOption()
      placeholder.allowExcessArguments()
      placeholder.action(() => {
        # Remove placeholder, import real module, reparse
        removeCommand(placeholder)
        importActualModule(primaryCommand)
        reparseProgramFromActionArgs(program, argv)
      })

    if (HELP or VERSION mode):
      # Register all commands as lazy placeholders (for help text)
      for cmd in CoreCliCommands:
        registerLazyPlaceholder(cmd)
```

### Plugin CLI Extension

```
registerSubCliCommands(program):
  registry = loadPluginManifestRegistry()

  for plugin in registry.plugins:
    if (plugin.cli):
      # Plugin CLI commands are discovered from manifest
      # Core commands override plugin commands (same name)
      if (not coreCommandNames.has(plugin.cli.name)):
        registerLazyPlaceholder(plugin.cli)
```

## Argument Parsing

### Multi-Level Parsing

```
Layer 1: ROOT OPTIONS (global, consumed before subcommand)
  --profile <name>    → active profile
  --workspace <path>  → workspace directory
  --yes               → auto-confirm prompts
  --verbose           → detailed output

  consumeRootOptionToken(args, index):
    if (args[index] in ["--profile", "--workspace"]):
      return 2    # consume flag + value
    if (args[index] in ["--yes", "-y", "--verbose"]):
      return 1    # consume flag only
    return 0      # not a root option

Layer 2: PRIMARY COMMAND
  getPrimaryCommand(argv):
    # Skip binary path, skip root options
    for token in argv.slice(2):
      if (not isRootOption(token) and not token.startsWith("-")):
        return token
    return null

Layer 3: SUBCOMMAND STRUCTURE
  getCommandPath(argv, depth):
    # Extract [command, subcommand, ...] up to depth
    path = []
    for token in argv after root options:
      if (not token.startsWith("-") and path.length < depth):
        path.push(token)
    return path

Layer 4: FLAG VALUE RESOLUTION
  getFlagValue(name):
    # Handle both --flag value and --flag=value
    for i in argv:
      if (argv[i] === name and isValueToken(argv[i+1])):
        return argv[i+1]
      if (argv[i].startsWith(name + "=")):
        return argv[i].split("=")[1]
    return undefined
```

### State Migration Guard

```
shouldMigrateState(command):
  READ_ONLY_COMMANDS = ["health", "config get", "models list", "version"]
  if (command in READ_ONLY_COMMANDS): return false
  return true    # expensive migration only for mutating commands
```

## Interactive Prompts

```
promptYesNo(question, defaultYes = false):
  # Auto-confirm if --yes flag set
  if (isYes()): return true

  rl = readline.createInterface(process.stdin, process.stdout)
  suffix = defaultYes ? " [Y/n] " : " [y/N] "
  answer = await rl.question(question + suffix)

  if (answer is empty): return defaultYes
  return answer.toLowerCase().startsWith("y")
```

For complex multi-step wizards (onboarding, config setup), the `inquirer` library is used.

## Output Formatting

### Dual Output Mode

Every command supports `--json` for scripting and human-readable text:

```
formatSkillsList(report, options):
  if (options.json):
    return JSON.stringify({
      workspaceDir,
      managedSkillsDir,
      skills: report.skills.map(s => ({
        name: s.name, description: s.description,
        eligible: s.eligible, source: s.source
      }))
    }, null, 2)

  # Human-readable table
  tableWidth = max(60, process.stdout.columns - 1)

  rows = report.skills.map(skill => ({
    Status: formatSkillStatus(skill),        # ✓ ready, ⏸ disabled, ✗ missing
    Skill: formatSkillName(skill),            # emoji + command(name)
    Description: muted(skill.description),
    Source: skill.source
  }))

  columns = [
    { key: "Status",      header: "Status",      minWidth: 10 },
    { key: "Skill",       header: "Skill",        minWidth: 18, flex: true },
    { key: "Description", header: "Description", minWidth: 24, flex: true },
    { key: "Source",      header: "Source",       minWidth: 10 }
  ]

  return renderTable({ width: tableWidth, columns, rows })
```

### Theme System

```
theme.success(text)  → green ANSI
theme.error(text)    → red ANSI
theme.warn(text)     → yellow ANSI
theme.muted(text)    → gray ANSI

formatCliCommand(cmd) → backtick-wrapped for terminal
renderTable({ width, columns, rows }) → ASCII table with flex columns
```

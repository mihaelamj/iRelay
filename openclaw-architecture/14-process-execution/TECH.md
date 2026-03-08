# Process Execution — Technical Implementation Details

## PTY Allocation

### Two Spawn Modes

OpenClaw supports two process execution modes:
- **PTY** (pseudo-terminal): for interactive shells, combined stdout+stderr
- **Child** (direct spawn): for non-interactive commands, separate streams

### PTY Adapter

```
createPtyAdapter(params):
  # params: { shell, args, cwd, env, cols=120, rows=30, name="xterm-256color" }

  pty = nodePty.spawn(
    params.shell,
    params.args,
    {
      cwd: params.cwd,
      env: toStringEnv(params.env),
      name: params.name,
      cols: params.cols,
      rows: params.rows
    }
  )

  return {
    pid: pty.pid,

    stdin: {
      write(data):  pty.write(data),
      end():
        # Send EOF: Ctrl-D (0x04) on Unix, Ctrl-Z (0x1a) on Windows
        eof = process.platform === "win32" ? "\x1a" : "\x04"
        pty.write(eof)
    },

    onStdout(listener):
      pty.onData((chunk) => listener(chunk.toString()))
      # PTY emits combined stdout+stderr — no separate stderr

    onStderr(_listener):
      # No-op in PTY mode (combined stream)

    kill(signal = "SIGKILL"):
      if (signal === "SIGKILL"):
        killProcessTree(pty.pid)
      else:
        pty.kill(signal)
      # Fallback timer: force kill after 4 seconds
      scheduleForceKillFallback(4000)

    wait(): Promise<{ code, signal }>:
      return new Promise(resolve => {
        pty.onExit(event => {
          resolve({ code: event.exitCode, signal: event.signal })
        })
      })
  }
```

## Command Parsing & Execution

### Child Process Adapter

```
createChildAdapter(params):
  # params: { argv, cwd, env, input?, stdinMode? }

  resolvedArgv = [...params.argv]
  resolvedArgv[0] = resolveCommand(params.argv[0])

  # Windows: handle npm/npx special case (CVE-2024-27980)
  if (process.platform === "win32"):
    npmResolved = resolveNpmArgvForWindows(resolvedArgv)
    if (npmResolved): resolvedArgv = npmResolved

  options = {
    cwd: params.cwd,
    env: toStringEnv(params.env),
    stdio: resolveStdioMode(params.stdinMode),
    detached: process.platform !== "win32",    # POSIX: detach for process group
    windowsHide: true
  }

  # Fallback: retry without detached if spawn fails
  child = await spawnWithFallback({
    argv: resolvedArgv,
    options,
    fallbacks: [{ label: "no-detach", options: { detached: false } }]
  })

  # Handle stdin
  if (params.input !== undefined):
    child.stdin.write(params.input)
    child.stdin.end()
  else if (params.stdinMode === "pipe-closed"):
    child.stdin.end()

  return {
    pid: child.pid,
    stdin, onStdout, onStderr, kill, wait
    # (same interface as PTY adapter)
  }
```

### Command Resolution (Windows)

```
resolveCommand(command):
  if (process.platform !== "win32"): return command

  basename = path.basename(command).toLowerCase()

  # Add .cmd extension for package managers
  if (basename in ["pnpm", "yarn", "npm", "npx"] and not basename.includes(".")):
    return command + ".cmd"

  return command

# For .cmd/.bat files on Windows: route through cmd.exe
buildCmdExeCommandLine(command, args):
  # SECURITY: reject cmd metacharacters (&|<>^%) to prevent injection
  for arg in [command, ...args]:
    if (WINDOWS_UNSAFE_CMD_CHARS.test(arg)):
      throw Error("Unsafe Windows cmd.exe argument")

  return [escapeForCmdExe(command), ...args.map(escapeForCmdExe)].join(" ")
```

## Output Streaming

### Managed Run

```
spawn(input):
  runId = input.runId ?? randomUUID()
  startedAtMs = Date.now()

  # Create adapter (PTY or child)
  adapter = input.mode === "pty"
    ? await createPtyAdapter({ shell, args, ... })
    : await createChildAdapter({ argv, ... })

  # Track in registry
  registry.updateState(runId, "running", { pid: adapter.pid })

  stdout = ""
  stderr = ""
  settled = false
  forcedReason = null

  # Setup timeouts
  overallTimer = setTimeout(() => requestCancel("overall-timeout"), overallTimeoutMs)
  noOutputTimer = setTimeout(() => requestCancel("no-output-timeout"), noOutputTimeoutMs)

  # Stream stdout
  adapter.onStdout((chunk) => {
    if (input.captureOutput !== false): stdout += chunk
    input.onStdout?.(chunk)    # stream to caller

    # Reset inactivity timer on every chunk
    clearTimeout(noOutputTimer)
    registry.touchOutput(runId)
    noOutputTimer = setTimeout(() => requestCancel("no-output-timeout"), noOutputTimeoutMs)
  })

  # Stream stderr (same pattern)
  adapter.onStderr((chunk) => {
    if (input.captureOutput !== false): stderr += chunk
    input.onStderr?.(chunk)
    registry.touchOutput(runId)
  })

  # Wait for exit
  waitPromise = adapter.wait().then(result => {
    if (not settled):
      settled = true
      clearTimeout(overallTimer)
      clearTimeout(noOutputTimer)
      adapter.dispose()

      return {
        reason: forcedReason ?? (result.signal ? "signal" : "exit"),
        exitCode: result.code,
        exitSignal: result.signal,
        durationMs: Date.now() - startedAtMs,
        stdout, stderr,
        timedOut: forcedReason in ["overall-timeout", "no-output-timeout"]
      }
  })

  return {
    runId,
    pid: adapter.pid,
    stdin: adapter.stdin,
    wait: () => waitPromise,
    cancel: (reason = "manual-cancel") => {
      if (not settled):
        forcedReason = reason
        adapter.kill("SIGKILL")
    }
  }
```

## Timeout & Kill Mechanisms

### Process Tree Termination

```
killProcessTree(pid, graceMs = 3000):
  if (process.platform === "win32"):
    killProcessTreeWindows(pid, graceMs)
  else:
    killProcessTreeUnix(pid, graceMs)

killProcessTreeUnix(pid, graceMs):
  # Step 1: Graceful SIGTERM to process group
  try:
    process.kill(-pid, "SIGTERM")    # negative PID = entire process group
  catch:
    try: process.kill(pid, "SIGTERM")    # fallback to single process
    catch: return                         # already dead

  # Step 2: Wait grace period, then SIGKILL if still alive
  setTimeout(() => {
    if (isProcessAlive(-pid)):
      try: process.kill(-pid, "SIGKILL")
      catch: pass

    if (isProcessAlive(pid)):
      try: process.kill(pid, "SIGKILL")
      catch: pass
  }, graceMs).unref()    # don't block event loop

killProcessTreeWindows(pid, graceMs):
  # Step 1: taskkill /T (tree) without /F (graceful)
  spawn("taskkill", ["/T", "/PID", String(pid)])

  # Step 2: Wait, then force kill
  setTimeout(() => {
    if (isProcessAlive(pid)):
      spawn("taskkill", ["/F", "/T", "/PID", String(pid)])
  }, graceMs).unref()

isProcessAlive(pid):
  try:
    process.kill(pid, 0)    # signal 0 = liveness check
    return true
  catch:
    return false
```

### Timeout Types

```
Two independent timeouts per process:

1. Overall Timeout (overallTimeoutMs):
   - Maximum total execution time
   - Default: configurable per tool
   - Action: kill entire process tree

2. No-Output Timeout (noOutputTimeoutMs):
   - Maximum time without any stdout/stderr output
   - Resets on every output chunk
   - Detects hung/stalled processes
   - Action: kill entire process tree

Both timeouts:
  - Set forcedReason before killing
  - Result includes timedOut=true and noOutputTimedOut flags
  - Process group killed (not just lead process)
```

### Graceful Shutdown Sequence

```
1. SIGTERM to process group (-pid)
2. Wait graceMs (default 3 seconds)
3. Check if still alive
4. If alive: SIGKILL to process group
5. If still alive: SIGKILL to individual PID

The .unref() on the timer ensures Node.js can
exit even if the grace period timer is pending.

On Windows: taskkill /T for tree, /F for force.
```

## Simple Exec (Non-Interactive)

```
runExec(command, args, opts):
  if (process.platform === "win32"):
    command = resolveCommand(command)

    if (isWindowsBatchCommand(command)):
      # Route through cmd.exe with escaped arguments
      cmdLine = buildCmdExeCommandLine(command, args)
      return execFile(
        process.env.ComSpec ?? "cmd.exe",
        ["/d", "/s", "/c", cmdLine],
        { timeout: opts.timeoutMs, windowsVerbatimArguments: true }
      )

  return execFile(command, args, {
    timeout: opts.timeoutMs ?? 10000,
    maxBuffer: opts.maxBuffer,
    cwd: opts.cwd,
    encoding: "utf8"
  })
```

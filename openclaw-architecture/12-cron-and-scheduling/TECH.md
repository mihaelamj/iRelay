# Cron & Scheduling — Technical Implementation Details

## Job Types

### Schedule Variants

```
CronSchedule =
  | { kind: "at",    at: string }                          # One-time at ISO timestamp
  | { kind: "every", everyMs: number, anchorMs?: number }  # Recurring interval
  | { kind: "cron",  expr: string, tz?: string, staggerMs?: number }  # Cron expression
```

### Job Structure

```
CronJob = {
  id: string,
  name: string,
  enabled: boolean,
  schedule: CronSchedule,
  payload:
    | { kind: "systemEvent", text: string }
    | { kind: "agentTurn", message: string, model?: string, deliver?: boolean },
  sessionTarget: "main" | "isolated",
  wakeMode: "now" | "next-heartbeat",
  delivery?: {
    mode: "announce" | "webhook",
    channel?: string,
    to?: string,
    bestEffort?: boolean
  },
  failureAlert?: false | { after?: number, cooldownMs?: number },
  state: {
    nextRunAtMs?: number,
    runningAtMs?: number,           # lock: currently executing
    lastRunAtMs?: number,
    lastRunStatus?: "ok" | "error" | "skipped",
    lastError?: string,
    consecutiveErrors?: number,
    lastFailureAlertAtMs?: number,
    scheduleErrorCount?: number,
    lastDeliveryStatus?: "delivered" | "not-delivered" | "unknown"
  }
}
```

## Cron Expression Parsing

### Next-Run Computation

```
computeNextRunAtMs(schedule, nowMs):
  if (schedule.kind === "at"):
    atMs = parseAbsoluteTimeMs(schedule.at)
    return atMs > nowMs ? atMs : undefined    # one-shot: fire once

  if (schedule.kind === "every"):
    everyMs = coerceFiniteScheduleNumber(schedule.everyMs)
    anchor = schedule.anchorMs ?? nowMs

    if (nowMs < anchor): return anchor
    elapsed = nowMs - anchor
    steps = max(1, ceil(elapsed / everyMs))
    return anchor + (steps × everyMs)

  if (schedule.kind === "cron"):
    # Use croner library with timezone + LRU cache (512 entries)
    cron = resolveCachedCron(schedule.expr, schedule.tz ?? systemTz)
    next = cron.nextRun(new Date(nowMs))

    # Workaround: croner timezone bug (year-rollback in some TZ)
    if (next <= nowMs):
      retry from nextSecond or tomorrow (UTC)

    # Stagger: deterministic offset = hash(jobId) % staggerMs
    if (schedule.staggerMs > 0):
      offset = sha256(jobId) % schedule.staggerMs
      return next + offset

    return next
```

## Heartbeat Mechanism

### Timer Loop

```
CronService:
  state:
    store: CronStoreFile        # in-memory job store
    timer: Timeout               # single setTimeout
    running: boolean             # prevents concurrent callbacks

  start():
    store = loadCronStore(storePath)

    # Run missed jobs from downtime
    missedJobs = store.jobs.filter(j =>
      j.enabled and
      computePreviousRunAtMs(j.schedule, now) > j.state.lastRunAtMs
    )
    for job in missedJobs:
      execute(job)

    armTimer()

  armTimer():
    # Find earliest nextRunAtMs across all enabled jobs
    nextWakeMs = min(jobs.map(j => j.state.nextRunAtMs))
    if (nextWakeMs === null): return    # no jobs scheduled

    # Clamp delay: [2 seconds, 60 seconds]
    delay = clamp(nextWakeMs - now(), 2000, 60000)
    timer = setTimeout(onTimer, delay)

  onTimer():
    if (state.running):
      armRunningRecheckTimer()    # re-arm if still executing
      return

    state.running = true
    try:
      # Force-reload store (pick up cross-process edits)
      ensureLoaded({ forceReload: true })

      # Find all due jobs
      dueJobs = findDueJobs(state, now())

      # Lock all due jobs
      for job in dueJobs:
        job.state.runningAtMs = now()
      persist(store)

      # Execute in parallel (up to maxConcurrentRuns, default=1)
      results = await executeInParallel(dueJobs)

      # Apply outcomes
      ensureLoaded({ forceReload: true })
      for result in results:
        applyJobResult(result)
      persist(store)

      # Periodic cleanup (every 5 min): sweep old session files
      sweepCronRunSessions()
    finally:
      state.running = false
      armTimer()
```

## Job Execution

### Execution Paths

```
executeJobCore(job, abortSignal):
  if (job.sessionTarget === "main"):
    # Enqueue to main agent session
    enqueueSystemEvent(job.payload.text, {
      agentId,
      sessionKey,
      contextKey: "cron:" + job.id
    })

    if (job.wakeMode === "now"):
      # Wait up to 2 min for runHeartbeatOnce
      for i in 0..maxRetries:
        result = runHeartbeatOnce({ heartbeat: { target: "last" } })
        if (result.status !== "skipped"): break
        await sleep(retryDelayMs)
      return { status: "ok", summary: job.payload.text }
    else:
      # next-heartbeat: just queue and let next heartbeat run
      requestHeartbeatNow()
      return { status: "ok" }

  else:    # sessionTarget === "isolated"
    result = runIsolatedAgentJob({
      job,
      message: job.payload.message,
      abortSignal
    })

    # Post summary to main session if announce delivery requested
    if (shouldEnqueueSummary()):
      enqueueSystemEvent("Cron: " + result.summary)
      if (job.wakeMode === "now"):
        requestHeartbeatNow()

    return result
```

### Result Application

```
applyJobResult(job, result):
  job.state.lastRunAtMs = result.startedAt
  job.state.lastRunStatus = result.status
  job.state.lastDurationMs = result.endedAt - result.startedAt

  if (result.status === "error"):
    job.state.consecutiveErrors += 1

    # Backoff schedule:
    # [30s, 1min, 5min, 15min, 60min+]
    backoffMs = BACKOFF_SCHEDULE[min(consecutiveErrors - 1, 4)]

    # Failure alerts after N consecutive errors (default=2)
    if (consecutiveErrors >= alertThreshold):
      if (not inCooldown(lastFailureAlertAtMs, cooldownMs)):
        sendFailureAlert()
        job.state.lastFailureAlertAtMs = now()
  else:
    job.state.consecutiveErrors = 0

  # Recompute nextRunAtMs
  if (job.schedule.kind === "at"):
    if (result.status in ["ok", "skipped"]):
      job.enabled = false    # one-shot: disable after success
    else if (isTransientError()):
      job.state.nextRunAtMs = result.endedAt + backoffMs    # retry
    else:
      job.enabled = false

  else:    # recurring
    naturalNext = computeNextRunAtMs(job.schedule, result.endedAt)
    if (result.status === "error"):
      job.state.nextRunAtMs = max(naturalNext, result.endedAt + backoffMs)
    else:
      job.state.nextRunAtMs = naturalNext

    # Safety: enforce 2s minimum gap to prevent spin-loops
    job.state.nextRunAtMs = max(job.state.nextRunAtMs, result.endedAt + 2000)
```

## Job Persistence

### Store Format

```json
// ~/.openclaw/cron/jobs.json
{
  "version": 1,
  "jobs": [
    {
      "id": "daily-summary",
      "name": "Daily Summary",
      "enabled": true,
      "schedule": { "kind": "cron", "expr": "0 9 * * *", "tz": "America/New_York" },
      "payload": { "kind": "agentTurn", "message": "Generate daily summary" },
      "sessionTarget": "isolated",
      "wakeMode": "now",
      "state": {
        "nextRunAtMs": 1709978400000,
        "lastRunAtMs": 1709892000000,
        "lastRunStatus": "ok"
      }
    }
  ]
}
```

### Atomic Write

```
saveCronStore(storePath, store):
  json = JSON.stringify(store, null, 2)

  # Skip if unchanged
  if (serializedCache.get(storePath) === json): return

  # Write to temp file
  tmpPath = storePath + "." + pid + "." + randomBytes(8) + ".tmp"
  writeFile(tmpPath, json, { mode: 0o600 })

  # Secure directory
  mkdir(dirname(storePath), { mode: 0o700, recursive: true })

  # Backup before overwrite
  copyFile(storePath, storePath + ".bak")

  # Atomic rename
  rename(tmpPath, storePath)

  serializedCache.set(storePath, json)
```

### Store Loading

```
ensureLoaded(state, opts):
  if (state.store and not opts.forceReload): return

  raw = readFile(storePath, "utf-8")
  store = JSON5.parse(raw)

  # Normalize legacy fields
  for job in store.jobs:
    # Convert jobId → id
    # Convert atMs (number) → at (ISO string)
    # Strip top-level legacy fields
    normalizeJob(job)

  state.store = store
```

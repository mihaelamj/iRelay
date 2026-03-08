# Browser Automation — Technical Implementation Details

## CDP Connection

### Chrome DevTools Protocol

OpenClaw communicates with Chrome/Chromium via CDP (JSON-RPC over WebSocket):

```
CDP Frame:
  Request:  { id: 1, method: "Page.captureScreenshot", params: { format: "png" } }
  Response: { id: 1, result: { data: "base64..." } }
  Event:    { method: "Network.responseReceived", params: { ... } }
```

### WebSocket Sender

```
createCdpSender(ws):
  nextId = 1
  pending = Map<id, { resolve, reject }>

  send(method, params?, sessionId?):
    id = nextId++
    msg = { id, method, params, sessionId }
    ws.send(JSON.stringify(msg))

    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject })
    })

  ws.on("message", (data) => {
    parsed = JSON.parse(data)
    p = pending.get(parsed.id)
    pending.delete(parsed.id)
    if (parsed.error): p.reject(Error(parsed.error.message))
    else: p.resolve(parsed.result)
  })

  ws.on("error", (err) => {
    for p in pending.values(): p.reject(err)
    pending.clear()
    ws.close()
  })

  return send
```

### Connection Lifecycle

```
withCdpSocket(wsUrl, fn):
  ws = openCdpWebSocket(wsUrl, {
    headers: getHeadersWithAuth(wsUrl),
    handshakeTimeoutMs: 5000
  })

  sender = createCdpSender(ws)
  await waitForOpen(ws)

  try:
    return await fn(sender.send)
  finally:
    ws.close()
```

### Endpoint Discovery

```
If cdpUrl is HTTP(S):
  1. Fetch /json/version → get webSocketDebuggerUrl
  2. Normalize URL (rewrite wildcard binds, match auth)

normalizeCdpWsUrl(wsUrlRaw, cdpUrl):
  ws = URL(wsUrlRaw)
  cdp = URL(cdpUrl)

  # Rewrite 0.0.0.0 / :: to actual host
  if (ws.hostname in ["0.0.0.0", "::"]):
    ws.hostname = cdp.hostname
    ws.port = cdp.port

  # Match protocol (ws → wss if cdp is https)
  if (cdp.protocol === "https:" and ws.protocol === "ws:"):
    ws.protocol = "wss:"

  # Inherit auth
  if (not ws.username and cdp.username):
    ws.username = cdp.username
    ws.password = cdp.password

  return ws.toString()
```

## Page Navigation & Interaction

### Action Types

```
BrowserActRequest =
  | { kind: "click",     ref, doubleClick?, button?, modifiers?, timeoutMs? }
  | { kind: "type",      ref, text, submit?, slowly?, timeoutMs? }
  | { kind: "press",     key, delayMs? }
  | { kind: "hover",     ref, timeoutMs? }
  | { kind: "scrollIntoView", ref, timeoutMs? }
  | { kind: "drag",      startRef, endRef, timeoutMs? }
  | { kind: "select",    ref, values[], timeoutMs? }
  | { kind: "fill",      fields: FormField[], timeoutMs? }
  | { kind: "resize",    width, height }
  | { kind: "wait",      timeMs?, text?, textGone?, selector?, url?, loadState?, fn? }
  | { kind: "evaluate",  fn, ref?, timeoutMs? }
  | { kind: "close",     targetId? }
```

### Action Dispatch

```
handleActRequest(req, page):
  switch req.kind:
    "click":
      locator = getRoleRefLocator(page, req.ref)
      await locator.click({
        timeout: req.timeoutMs,
        button: req.button ?? "left",
        clickCount: req.doubleClick ? 2 : 1
      })

    "type":
      locator = getRoleRefLocator(page, req.ref)
      if (req.slowly):
        await locator.type(req.text, { delay: 50 })
      else:
        await locator.fill(req.text)
      if (req.submit):
        await locator.press("Enter")

    "wait":
      if (req.text):     await page.getByText(RegExp(req.text)).waitFor()
      if (req.selector): await page.locator(req.selector).waitFor()
      if (req.url):      await page.waitForURL(RegExp(req.url))
      if (req.loadState): await page.waitForLoadState(req.loadState)
      if (req.fn):       await page.waitForFunction(req.fn)

    "evaluate":
      if (req.ref):
        locator = getRoleRefLocator(page, req.ref)
        return await locator.evaluate(req.fn)
      else:
        return await page.evaluate(req.fn)
```

## Content Extraction

### Accessibility Tree Snapshot

```
snapshotAriaViaPlaywright(cdpUrl, targetId?):
  page = await getPageForTargetId({ cdpUrl, targetId })

  session = await page.context().newCDPSession(page)
  await session.send("Accessibility.enable")
  axTree = await session.send("Accessibility.getFullAXTree")

  return { nodes: formatAriaSnapshot(axTree.nodes, limit=500) }
```

### AI Snapshot (Playwright)

```
snapshotAiViaPlaywright(cdpUrl, targetId?, maxChars?, timeoutMs?):
  page = await getPageForTargetId({ cdpUrl, targetId })

  result = await page._snapshotForAI({
    timeout: clamp(timeoutMs ?? 5000, 500, 60000),
    track: "response"
  })

  snapshot = result.full ?? ""

  if (snapshot.length > maxChars):
    snapshot = snapshot.slice(0, maxChars) + "\n\n[...TRUNCATED]"

  # Extract role references for later click/fill operations
  refs = buildRoleSnapshotFromAiSnapshot(snapshot)
  storeRoleRefsForTarget({ page, cdpUrl, targetId, refs })

  return { snapshot, refs, truncated }
```

### Storage Access

```
getStorageViaPlaywright(cdpUrl, targetId?, storageType):
  page = await getPageForTargetId({ cdpUrl, targetId })

  if (storageType === "cookies"):
    return await page.context().cookies()

  if (storageType === "localStorage"):
    return await page.evaluate(() => {
      result = {}
      for i in 0..localStorage.length:
        key = localStorage.key(i)
        result[key] = localStorage.getItem(key)
      return result
    })

  # Same pattern for sessionStorage
```

## Screenshot Capture

### Basic Capture

```
captureScreenshot(wsUrl, fullPage?, format?, quality?):
  return await withCdpSocket(wsUrl, async (send) => {
    await send("Page.enable")

    clip = undefined
    if (fullPage):
      metrics = await send("Page.getLayoutMetrics")
      size = metrics.cssContentSize ?? metrics.contentSize
      clip = { x: 0, y: 0, width: size.width, height: size.height, scale: 1 }

    result = await send("Page.captureScreenshot", {
      format: format ?? "png",
      quality: quality ? clamp(quality, 0, 100) : undefined,
      fromSurface: true,
      captureBeyondViewport: true,
      clip
    })

    return Buffer.from(result.data, "base64")
  })
```

### Normalization (Size Limits)

```
normalizeBrowserScreenshot(buffer, maxSide=2000, maxBytes=5MB):
  meta = getImageMetadata(buffer)
  if (buffer.length <= maxBytes and width <= maxSide and height <= maxSide):
    return { buffer }    # already within limits

  # Progressive resize: try different sizes × qualities
  sideGrid = buildImageResizeSideGrid(maxSide)
  smallest = null

  for side in sideGrid:
    for quality in [75, 50, 25]:
      resized = resizeToJpeg({ buffer, maxSide: side, quality })

      if (not smallest or resized.length < smallest.length):
        smallest = resized

      if (resized.length <= maxBytes):
        return { buffer: resized, contentType: "image/jpeg" }

  if (smallest.length > maxBytes):
    throw Error("Screenshot exceeds limit even after resize")

  return { buffer: smallest, contentType: "image/jpeg" }
```

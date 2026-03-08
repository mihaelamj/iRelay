# Voice & Media — Technical Implementation Details

## TTS Providers

### Supported Providers

| Provider   | API Key Required | Models | Audio Format |
|-----------|-----------------|--------|-------------|
| ElevenLabs | Yes | tts-1-hd, turbo | MP3, PCM |
| OpenAI     | Yes | gpt-4o-mini-tts, tts-1, tts-1-hd | PCM 24kHz mono 16-bit |
| Edge       | No  | Microsoft built-in voices | Configurable |

### Provider Configuration

```
TtsConfig = {
  auto: "off" | "always" | "inbound" | "tagged",
  mode: "final" | "all",
  provider: "elevenlabs" | "openai" | "edge",
  summaryModel: string,
  timeoutMs: number,
  maxTextLength: number,

  elevenlabs: {
    apiKey, baseUrl, voiceId, modelId, seed,
    applyTextNormalization: "auto" | "on" | "off",
    languageCode: string,
    voiceSettings: {
      stability: 0-1,
      similarityBoost: 0-1,
      style: 0-1,
      useSpeakerBoost: boolean,
      speed: 0.5-2
    }
  },

  openai: {
    apiKey, baseUrl, model, voice
    # 13 voices: alloy, ash, coral, echo, fable, marin, cedar, ...
  },

  edge: {
    enabled, voice, lang, outputFormat,
    pitch, rate, volume, saveSubtitles,
    proxy, timeoutMs
  }
}
```

### TTS Directives (Model Overrides)

The agent can embed TTS control tags in its response:

```
[[tts:text]]Custom spoken text, different from displayed text[[/tts:text]]
[[tts:provider=openai voice=nova speed=1.2]]
[[tts:voiceid=JZq3gSRV9P8jCLkY modelid=eleven_turbo_v2]]
[[tts:stability=0.7 similarityBoost=0.8]]
```

Model overrides are gated by config:
```
modelOverrides: {
  enabled: boolean,
  allowText: boolean,           # [[tts:text]]...[[/tts:text]]
  allowProvider: boolean,
  allowVoice: boolean,
  allowModelId: boolean,
  allowVoiceSettings: boolean,
  allowNormalization: boolean,
  allowSeed: boolean
}
```

## STT Providers

### OpenAI Realtime STT

```
WebSocket Connection:
  URL: wss://api.openai.com/v1/realtime?intent=transcription
  Headers:
    Authorization: Bearer <apiKey>
    OpenAI-Beta: realtime=v1

  Session Setup:
    send({
      type: "transcription_session.update",
      session: {
        input_audio_format: "g711_ulaw",
        input_audio_transcription: {
          model: "gpt-4o-transcribe"
        },
        turn_detection: {
          type: "server_vad",          # server-side voice activity detection
          threshold: 0.5,
          prefix_padding_ms: 300,
          silence_duration_ms: 800
        }
      }
    })
```

### STT Session Interface

```
RealtimeSTTSession:
  connect()                           → WebSocket to OpenAI
  sendAudio(audio: Buffer)            → mu-law 8kHz mono
  waitForTranscript(timeoutMs?)       → Promise<string>
  onPartial(callback)                 → partial transcript
  onTranscript(callback)              → final transcript
  onSpeechStart(callback)             → VAD detected speech
  close()
  isConnected()
```

Server-side VAD handles:
- Speech start detection → `onSpeechStart` callback
- Partial transcripts during speech → `onPartial`
- Silence detection → `onTranscript` (final)
- No client-side buffering needed

## Media Pipeline

### Input File Loading

```
InputFileLimits = {
  allowUrl: boolean,
  urlAllowlist: string[],
  allowedMimes: Set<string>,
  maxBytes: number,              # Image: 10MB, Document: 5MB
  maxChars: number,              # Text: 200,000 chars
  maxRedirects: 3,
  timeoutMs: 10000,
  pdf: {
    maxPages: 4,
    maxPixels: 4000000,
    minTextChars: 200
  }
}

Supported MIME Types:
  Images:    image/jpeg, image/png, image/gif, image/webp, image/heic, image/heif
  Documents: text/plain, text/markdown, text/html, text/csv,
             application/json, application/pdf
```

### MEDIA: Token Parsing

```
parseMediaTokens(text):
  # Extract MEDIA: lines (not inside fenced code blocks)
  # Format: MEDIA: `/path/to/image.jpg`
  #         MEDIA: `https://example.com/file.pdf`

  mediaUrls = []
  for line in text.split("\n"):
    if (insideFencedBlock): continue
    match = line.match(/^MEDIA:\s*`([^`]+)`/)
    if (match):
      source = match[1]
      # Detect type:
      if (source.startsWith("http")): type = "url"
      else if (source.startsWith("/")): type = "absolute"
      else if (source.startsWith("./")): type = "relative"
      mediaUrls.push({ source, type })

  return { text: stripMediaLines(text), mediaUrls }
```

### Media Storage

```
Storage Location: ~/.openclaw/state/media/

File Naming:
  {sanitizedOriginal}---{uuid}.{ext}
  # Sanitizes unsafe chars (Windows/SharePoint compatible)
  # 60-char limit on filename

Permissions:
  Files: 0o644 (readable for Docker containers)
  Directory: 0o700 (trust boundary)

Download:
  downloadToFile(url, dest, maxBytes, maxRedirects):
    1. Sniff MIME from first KB
    2. Stream to disk with size limit
    3. Follow redirects up to N times
    4. Detect MIME via Content-Type, magic bytes, or extension

Processing:
  HEIC/HEIF images → convert to JPEG
  PNG → encode with dimensions
  PDF → extract text + images (max 4 pages, 4M pixels)

Cleanup:
  cleanOldMedia(ttlMs = 120000):    # 2-minute TTL
    remove files where mtime > ttl
```

## Voice Session Management

### Call Manager State

```
CallManager:
  activeCalls: Map<CallId, CallRecord>
  providerCallIdMap: Map<ProviderCallId, CallId>
  processedEventIds: Set<string>         # webhook dedup
  rejectedProviderCallIds: Set<string>
  transcriptWaiters: Map<CallId, Waiter>
  maxDurationTimers: Map<CallId, Timeout>
```

### Call State Machine

```
pending → ringing → answered → [speaking|listening] → ended/failed
```

### Call Operations

```
initiateCall(phoneNumber, message):
  1. Create outbound call via provider (Twilio)
  2. Speak initial message (TTS)
  return { callId, success }

continueCall(callId):
  1. Wait for next user speech (STT)
  return { transcript, success }

speak(callId, text):
  1. Generate TTS audio (24kHz PCM from OpenAI)
  2. Resample 24kHz → 8kHz
  3. Encode to mu-law (Twilio G.711 format)
  4. Stream to voice provider

endCall(callId):
  1. Hangup via provider
  2. Persist to store
```

### Audio Format Conversion

```
Pipeline: PCM 24kHz → PCM 8kHz → mu-law

Resample (24→8kHz, 3:1 ratio):
  for i in 0..outputSamples:
    srcPos = i × 3
    s0 = input[srcPos]
    s1 = input[srcPos + 1]
    frac = srcPos % 1
    sample = round(s0 + frac × (s1 - s0))

Chunk audio (20ms frames):
  chunkSize = 160 bytes    # 160 bytes at 8kHz = 20ms
  yield 160-byte chunks from buffer
```

### Persistence

```
Store: ~/.openclaw/voice-calls/calls.jsonl

Load on startup:
  1. Parse calls.jsonl
  2. Filter terminal states (ended, failed, missed)
  3. Verify active calls with provider (status check)
  4. Rebuild internal maps
  5. Restart max-duration timers

Save on change:
  Append to calls.jsonl

Max Duration Timer:
  Started: when call answered
  Duration: config.maxDurationSeconds
  Action: auto-hangup on timeout
  Restored: restarted on manager init

Event Deduplication:
  Track eventId from provider webhooks
  Skip already-processed events
```

# 11 — Voice & Media

## Voice System

The voice system gives OpenClaw the ability to speak (TTS) and listen (STT). It supports multiple providers and integrates with native device capabilities.

### TTS (Text-to-Speech) Providers

#### 1. OpenAI TTS
- **Model**: `gpt-4o-mini-tts`
- **Voices**: `alloy`, `echo`, `fable`, `onyx`, `shimmer`, `nova`
- **Auth**: OpenAI API key
- **Quality**: High, natural-sounding

#### 2. ElevenLabs
- **Models**: `eleven_multilingual_v2`, `eleven_turbo_v2`, `eleven_turbo_v2_5`
- **Voices**: Custom voice IDs (extensive voice library)
- **Auth**: ElevenLabs API key
- **Settings**: stability, similarity boost, style, speaker boost, speed
- **Quality**: Very high, cloneable voices

#### 3. Microsoft Edge TTS (Free)
- **Voices**: `en-US-MichelleNeural` and hundreds of variants
- **Languages**: All major languages
- **Settings**: pitch, rate, volume, output format
- **Auth**: None (free service)
- **Quality**: Good, no API key needed

### TTS Configuration

```json
{
  "messages": {
    "tts": {
      "auto": "off",
      "mode": "final",
      "provider": "openai",
      "summaryModel": "gpt-4o-mini",
      "timeoutMs": 30000,
      "maxTextLength": 4096,

      "openai": {
        "apiKey": { "env": "OPENAI_API_KEY" },
        "model": "gpt-4o-mini-tts",
        "voice": "nova"
      },

      "elevenlabs": {
        "apiKey": { "env": "ELEVENLABS_API_KEY" },
        "voiceId": "pMsXgVXv3BLzUgSXRplE",
        "modelId": "eleven_multilingual_v2",
        "voiceSettings": {
          "stability": 0.5,
          "similarityBoost": 0.75,
          "style": 0.0,
          "useSpeakerBoost": true,
          "speed": 1.0
        }
      },

      "edge": {
        "voice": "en-US-MichelleNeural",
        "lang": "en-US",
        "outputFormat": "audio-24khz-48kbitrate-mono-mp3"
      },

      "modelOverrides": {
        "enabled": true,
        "allowText": true,
        "allowProvider": true,
        "allowVoice": true
      }
    }
  }
}
```

### TTS Auto Modes

- `"off"`: No automatic TTS (user must request)
- `"always"`: Every response gets spoken
- `"inbound"`: Only when the inbound message was voice
- `"tagged"`: Only when the agent tags the response for TTS

### STT (Speech-to-Text)

STT is primarily handled through:
- **OpenAI Whisper**: API-based transcription
- **OpenAI Realtime API**: Live streaming transcription (for voice calls)
- **Native device**: iOS/macOS Speech framework

### Voice Call Extension

The `voice-call` extension adds phone call integration:

- **Telephony providers**: Twilio, Telnyx, Plivo, Mock
- **Inbound call handling**: Allowlist, pairing, or open
- **Streaming**: OpenAI Realtime API for live STT/TTS
- **Recording**: Optional call recording and transcription
- **Webhooks**: Inbound call routing via webhook + tunneling (ngrok, Tailscale)

### Talk Voice Extension

The `talk-voice` extension manages voice preferences for iOS Talk mode:

```bash
/voice status       # Show current voice settings
/voice list [limit] # List available ElevenLabs voices
/voice set <id>     # Set voice by ID or name
```

## Media Pipeline

The media pipeline handles all non-text content: images, audio, video, and documents.

### Media Processing Flow

```
1. Receive media (URL or file path)
   ↓
2. Validate: Check size, format, MIME type
   ↓
3. Fetch: Download if remote URL
   ↓
4. Convert: Resize, transcode if needed
   ↓
5. Store: Save to local workspace
   ↓
6. Deliver: Upload to channel or serve inline
```

### Size Limits by Channel

| Channel | Max File Size |
|---------|--------------|
| Discord | 8 MB |
| Telegram | 50 MB |
| WhatsApp | ~16 MB |
| Slack | 250 MB (workspace limit) |
| Signal | 50 MB |
| IRC | None (URL sharing only) |
| iMessage | 100 MB |

### Supported Formats

| Type | Formats |
|------|---------|
| **Images** | PNG, JPEG, WEBP, GIF |
| **Audio** | MP3, WAV, OGG, M4A |
| **Video** | MP4, MOV (limited, platform-specific) |
| **Documents** | PDF, DOCX, XLSX, TXT |

### Security

- **SSRF prevention**: Validates origins before fetching remote URLs
- **Path isolation**: Media stored in workspace-scoped directories
- **Hardlink rejection**: Prevents symlink escapes
- **Realpath validation**: Ensures no filesystem traversal
- **Size enforcement**: Hard limits per file and total

### Media Store

- Memory-backed and disk-backed storage
- Base64 or file reference modes
- Streaming responses with size limits
- Temp file lifecycle management with cleanup

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/tts/tts.ts` | TTS provider selection and generation |
| `src/media/store.ts` | Media storage |
| `src/media/fetch.ts` | Remote media fetching with guards |
| `src/media/constants.ts` | Size limits |
| `src/media/inbound-path-policy.ts` | Security path validation |
| `extensions/talk-voice/` | Voice preference management |
| `extensions/voice-call/` | Phone call integration |

## Swift Replication Notes

1. **TTS**: Use `AVSpeechSynthesizer` for local TTS (already in iRelay's `Voice` package)
2. **STT**: Use `Speech` framework for on-device recognition
3. **Remote TTS**: URLSession calls to OpenAI/ElevenLabs APIs
4. **Media handling**: Use `AVFoundation` for audio/video processing
5. **Image processing**: Use `CoreImage` or `vImage` for resize/convert
6. **Security**: Use `FileManager` path validation, reject symlinks outside workspace

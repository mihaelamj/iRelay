# Voice & Media — Purpose

## Why This System Exists

Voice and media let the agent **speak and see**. TTS converts text responses to speech audio, STT converts voice input to text, and the media pipeline handles images, documents, and files that users share or the agent generates.

## The Problem It Solves

1. **Voice conversations**: Some channels (phone calls, voice messages) need audio, not text. The TTS system converts agent responses to speech using ElevenLabs, OpenAI, or Microsoft Edge TTS, with fallback between providers.

2. **Voice input**: Phone calls and voice messages arrive as audio. The STT system (OpenAI Realtime with server-side VAD) transcribes speech to text so the agent can process it.

3. **Media handling**: Users send images, PDFs, and files. The media pipeline downloads them safely (SSRF protection, size limits), detects MIME types, converts formats (HEIC → JPEG), and makes them available to the agent.

4. **Audio format conversion**: Phone systems use 8kHz mu-law audio, but TTS providers output 24kHz PCM. The conversion pipeline (resample + encode) bridges this gap.

## What SwiftClaw Needs from This

SwiftClaw's `ClawVoiceEngine` needs TTS provider abstraction (multiple providers with fallback), the TTS directive parsing (inline `[[tts:...]]` tags), and media pipeline basics (download with size limits, MIME detection, format conversion). For voice calls, the audio resampling pipeline (24kHz PCM → 8kHz mu-law) is essential.

## Key Insight for Replication

Voice is **text-to-audio and audio-to-text wrapping around the normal text pipeline**. The agent still thinks in text — voice is an I/O transformation layer. Media is similar: files are converted to a format the agent can consume (text extraction, image encoding) and results are converted back to the channel's expected format.

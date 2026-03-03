# SwiftClaw

Apple-native AI assistant. Pure Swift. macOS + iOS.

## What

A local-first AI assistant that lives on your Apple devices. No Node.js, no Electron, no cross-platform compromises.

- 8 messaging channels (iMessage, Telegram, Slack, Discord, Signal, Matrix, IRC, WebChat)
- 4 LLM providers (Claude, OpenAI, Ollama, Gemini)
- WebSocket gateway (Hummingbird)
- GRDB/SQLite storage
- CLI via ArgumentParser

## Build

```bash
make build        # release build
make build-debug  # debug build
make test         # run tests
make install      # install to /usr/local/bin
```

## Structure

Extreme Packaging — single `Package.swift` in `Packages/`, `Main.xcworkspace` at root.

See [ARCHITECTURE.md](ARCHITECTURE.md) for full details.

## License

MIT

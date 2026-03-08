# Channel Protocol Refactor

## Why Refactor

The current `Channel` protocol works but is text-centric by accident. Every channel's `send()` guards on `textValue` and throws on media. The types support multimodal (`MessageContent` has `.image`, `.file`, etc.) but nothing flows through.

For MVP we need images and videos to flow from iMessage/WhatsApp → through the pipeline → to the coding agent and back. This requires the channel protocol to be explicitly multimodal and for channels to declare their capabilities.

## Design Goals

1. **Channels declare capabilities** — "I support images, video, files" vs "text only"
2. **Media flows end-to-end** — inbound attachment → provider → agent → outbound attachment
3. **Easy to add channels** — WhatsApp today, Telegram tomorrow, same protocol
4. **No breaking the working channels** — existing text-only channels keep working with zero changes

## Current Protocol (What Exists)

```swift
public protocol Channel: Actor {
    var id: String { get }
    var displayName: String { get }
    var status: ChannelStatus { get }
    var maxTextLength: Int { get }
    func start() async throws
    func stop() async throws
    func send(_ message: OutboundMessage) async throws
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)
}
```

**Problem**: No way to know what a channel supports. The orchestrator can't make smart decisions about how to format responses (plain text? with images? as files?).

## Proposed Protocol

```swift
// MARK: - Channel Capabilities

public struct ChannelCapabilities: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let text          = ChannelCapabilities(rawValue: 1 << 0)
    public static let images        = ChannelCapabilities(rawValue: 1 << 1)
    public static let video         = ChannelCapabilities(rawValue: 1 << 2)
    public static let audio         = ChannelCapabilities(rawValue: 1 << 3)
    public static let files         = ChannelCapabilities(rawValue: 1 << 4)
    public static let links         = ChannelCapabilities(rawValue: 1 << 5)
    public static let reactions     = ChannelCapabilities(rawValue: 1 << 6)
    public static let typing        = ChannelCapabilities(rawValue: 1 << 7)
    public static let readReceipts  = ChannelCapabilities(rawValue: 1 << 8)
    public static let threads       = ChannelCapabilities(rawValue: 1 << 9)

    /// Common presets
    public static let textOnly: ChannelCapabilities = [.text]
    public static let multimedia: ChannelCapabilities = [.text, .images, .video, .audio, .files, .links]
    public static let full: ChannelCapabilities = [.text, .images, .video, .audio, .files, .links, .reactions, .typing]
}

// MARK: - Channel Limits

public struct ChannelLimits: Sendable {
    public let maxTextLength: Int
    public let maxImageSize: Int?       // bytes
    public let maxVideoSize: Int?       // bytes
    public let maxFileSize: Int?        // bytes
    public let supportedImageFormats: Set<String>   // ["image/jpeg", "image/png", ...]
    public let supportedVideoFormats: Set<String>

    public init(
        maxTextLength: Int,
        maxImageSize: Int? = nil,
        maxVideoSize: Int? = nil,
        maxFileSize: Int? = nil,
        supportedImageFormats: Set<String> = ["image/jpeg", "image/png", "image/gif"],
        supportedVideoFormats: Set<String> = ["video/mp4"]
    ) {
        self.maxTextLength = maxTextLength
        self.maxImageSize = maxImageSize
        self.maxVideoSize = maxVideoSize
        self.maxFileSize = maxFileSize
        self.supportedImageFormats = supportedImageFormats
        self.supportedVideoFormats = supportedVideoFormats
    }

    public static let imessage = ChannelLimits(
        maxTextLength: 20_000,
        maxImageSize: 100_000_000,
        maxVideoSize: 100_000_000,
        maxFileSize: 100_000_000,
        supportedImageFormats: ["image/jpeg", "image/png", "image/gif", "image/heic"],
        supportedVideoFormats: ["video/mp4", "video/quicktime"]
    )

    public static let whatsapp = ChannelLimits(
        maxTextLength: 4_096,
        maxImageSize: 5_000_000,
        maxVideoSize: 16_000_000,
        maxFileSize: 100_000_000,
        supportedImageFormats: ["image/jpeg", "image/png"],
        supportedVideoFormats: ["video/mp4", "video/3gpp"]
    )
}

// MARK: - Refactored Channel Protocol

public protocol Channel: Actor {
    var id: String { get }
    var displayName: String { get }
    var status: ChannelStatus { get }

    /// What this channel can do
    var capabilities: ChannelCapabilities { get }

    /// Size and format constraints
    var limits: ChannelLimits { get }

    func start() async throws
    func stop() async throws
    func send(_ message: OutboundMessage) async throws
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)
}

/// Default: text-only with generous limits (backward compat)
extension Channel {
    public var capabilities: ChannelCapabilities { .textOnly }
    public var limits: ChannelLimits { .init(maxTextLength: 4096) }
}
```

## Backward Compatibility

The defaults (`capabilities: .textOnly`, generic limits) mean **every existing channel compiles unchanged**. Channels opt into multimodal by overriding `capabilities` and `limits`. The orchestrator uses `capabilities` to decide how to format responses.

## MessageContent Expansion

```swift
public enum MessageContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case video(Data, mimeType: String)          // NEW: separate from file
    case file(Data, filename: String, mimeType: String)
    case link(URL, title: String?)              // NEW: rich link preview
    case location(latitude: Double, longitude: Double)
    case compound([MessageContent])             // NEW: text + image in one message
}
```

The `compound` case is key — an agent reply is often "here's what I did" (text) + a screenshot or diff (image/file). This lets the orchestrator send it as one logical message that the channel can split as needed.

## ChatMessage Goes Multimodal

```swift
/// A content block within a chat message (matches Claude/OpenAI API format)
public enum ContentBlock: Sendable, Codable {
    case text(String)
    case image(source: ImageSource)
    case toolUse(id: String, name: String, input: String)
    case toolResult(toolUseID: String, content: String, isError: Bool)
}

public struct ImageSource: Sendable, Codable {
    public let type: ImageSourceType
    public let mediaType: String
    public let data: String  // base64 for inline, URL for remote

    public enum ImageSourceType: String, Sendable, Codable {
        case base64
        case url
    }
}

public struct ChatMessage: Sendable, Codable {
    public let role: ChatRole
    public let content: [ContentBlock]  // ← Was: String
    public let timestamp: Date
    public let metadata: [String: String]?
}
```

This matches how Claude and OpenAI actually accept multimodal input (array of content blocks). The provider layer already knows how to format these for each API.

## Channel Implementations for MVP

### iMessage — Multimedia

```swift
public actor IMessageChannel: Channel {
    public let capabilities: ChannelCapabilities = .multimedia
    public let limits: ChannelLimits = .imessage

    public func send(_ message: OutboundMessage) async throws {
        switch message.content {
        case .text(let text):
            try await sendTextViaAppleScript(text, to: message.recipientID)
        case .image(let data, _):
            let path = try writeTempFile(data, extension: "jpg")
            try await sendFileViaAppleScript(path, to: message.recipientID)
        case .video(let data, _):
            let path = try writeTempFile(data, extension: "mp4")
            try await sendFileViaAppleScript(path, to: message.recipientID)
        case .file(let data, let name, _):
            let path = try writeTempFile(data, extension: name)
            try await sendFileViaAppleScript(path, to: message.recipientID)
        case .compound(let parts):
            for part in parts { try await send(message.with(content: part)) }
        default:
            try await sendTextViaAppleScript(message.content.textFallback, to: message.recipientID)
        }
    }
}
```

### WhatsApp — Multimedia

```swift
public actor WhatsAppChannel: Channel {
    public let capabilities: ChannelCapabilities = .multimedia
    public let limits: ChannelLimits = .whatsapp

    public func send(_ message: OutboundMessage) async throws {
        switch message.content {
        case .text(let text):
            try await sendText(text, to: message.recipientID)
        case .image(let data, let mime):
            let mediaID = try await uploadMedia(data, mimeType: mime)
            try await sendMedia(type: "image", mediaID: mediaID, to: message.recipientID)
        case .video(let data, let mime):
            let mediaID = try await uploadMedia(data, mimeType: mime)
            try await sendMedia(type: "video", mediaID: mediaID, to: message.recipientID)
        case .file(let data, let name, let mime):
            let mediaID = try await uploadMedia(data, mimeType: mime)
            try await sendDocument(mediaID: mediaID, filename: name, to: message.recipientID)
        case .compound(let parts):
            for part in parts { try await send(message.with(content: part)) }
        default:
            try await sendText(message.content.textFallback, to: message.recipientID)
        }
    }
}
```

### Existing Text-Only Channels — Zero Changes

```swift
// Telegram, Slack, Discord, etc. — no changes needed.
// They inherit default capabilities (.textOnly) and their send() still guards on textValue.
// The orchestrator sees .textOnly and converts media to text descriptions automatically.
```

## Orchestrator Uses Capabilities

```swift
// In ServiceOrchestrator
func deliver(_ content: MessageContent, via channel: any Channel) async throws {
    let caps = await channel.capabilities

    if content.isMedia && !caps.contains(.images) {
        // Channel is text-only, convert to description
        let fallback = OutboundMessage(..., content: .text(content.textFallback))
        try await channel.send(fallback)
    } else {
        try await channel.send(OutboundMessage(..., content: content))
    }
}
```

## Migration Plan

1. Add `ChannelCapabilities`, `ChannelLimits` to `ChannelKit` — non-breaking (default impls)
2. Add `.video`, `.link`, `.compound` to `MessageContent` — non-breaking (additive enum cases)
3. Add `ContentBlock` and make `ChatMessage.content` multimodal — **breaking** but contained to `Shared` + providers
4. Update `IMessageChannel` with capabilities + media send/receive
5. Update `WhatsAppChannel` with capabilities + media handling
6. Update orchestrator to check capabilities before delivery

Steps 1-2 are pure additions. Step 3 is the only breaking change and it's internal.

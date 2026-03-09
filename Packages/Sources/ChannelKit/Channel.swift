import Foundation
import Shared

// MARK: - Channel Capabilities

public struct ChannelCapabilities: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let text         = ChannelCapabilities(rawValue: 1 << 0)
    public static let images       = ChannelCapabilities(rawValue: 1 << 1)
    public static let video        = ChannelCapabilities(rawValue: 1 << 2)
    public static let audio        = ChannelCapabilities(rawValue: 1 << 3)
    public static let files        = ChannelCapabilities(rawValue: 1 << 4)
    public static let links        = ChannelCapabilities(rawValue: 1 << 5)
    public static let reactions    = ChannelCapabilities(rawValue: 1 << 6)
    public static let typing       = ChannelCapabilities(rawValue: 1 << 7)
    public static let readReceipts = ChannelCapabilities(rawValue: 1 << 8)
    public static let threads      = ChannelCapabilities(rawValue: 1 << 9)

    public static let textOnly: ChannelCapabilities = [.text]
    public static let multimedia: ChannelCapabilities = [.text, .images, .video, .audio, .files, .links]
    public static let full: ChannelCapabilities = [.text, .images, .video, .audio, .files, .links, .reactions, .typing]
}

// MARK: - Channel Limits

public struct ChannelLimits: Sendable {
    public let maxTextLength: Int
    public let maxImageSize: Int?
    public let maxVideoSize: Int?
    public let maxFileSize: Int?
    public let supportedImageFormats: Set<String>
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
        maxTextLength: Defaults.TextLimits.iMessage,
        maxImageSize: 100_000_000,
        maxVideoSize: 100_000_000,
        maxFileSize: 100_000_000,
        supportedImageFormats: ["image/jpeg", "image/png", "image/gif", "image/heic"],
        supportedVideoFormats: ["video/mp4", "video/quicktime"]
    )

    public static let whatsapp = ChannelLimits(
        maxTextLength: Defaults.TextLimits.whatsApp,
        maxImageSize: 5_000_000,
        maxVideoSize: 16_000_000,
        maxFileSize: 100_000_000,
        supportedImageFormats: ["image/jpeg", "image/png"],
        supportedVideoFormats: ["video/mp4", "video/3gpp"]
    )

    public static let telegram = ChannelLimits(
        maxTextLength: Defaults.TextLimits.telegram,
        maxImageSize: 10_000_000,
        maxVideoSize: 50_000_000,
        maxFileSize: 50_000_000
    )

    public static let `default` = ChannelLimits(maxTextLength: Defaults.TextLimits.default)
}

// MARK: - Channel Protocol

public protocol Channel: Actor {
    var id: String { get }
    var displayName: String { get }
    var status: ChannelStatus { get }

    /// What this channel can send/receive.
    var capabilities: ChannelCapabilities { get }

    /// Size and format constraints.
    var limits: ChannelLimits { get }

    /// Start listening for inbound messages.
    func start() async throws

    /// Stop the channel gracefully.
    func stop() async throws

    /// Send an outbound message through this channel.
    func send(_ message: OutboundMessage) async throws

    /// Register a handler for inbound messages.
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)
}

// MARK: - Default implementations

extension Channel {
    public var capabilities: ChannelCapabilities { .textOnly }
    public var limits: ChannelLimits { .default }
    /// Deprecated: use limits.maxTextLength instead.
    public var maxTextLength: Int { limits.maxTextLength }
}

// MARK: - Channel Status

public enum ChannelStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Channel Configuration Protocol

public protocol ChannelConfiguration: Sendable, Codable {
    var channelID: String { get }
    var isEnabled: Bool { get }
}

// MARK: - Channel Registry

public actor ChannelRegistry {
    private var channels: [String: any Channel] = [:]

    public init() {}

    public func register(_ channel: any Channel) async {
        let id = await channel.id
        channels[id] = channel
    }

    public func channel(for id: String) -> (any Channel)? {
        channels[id]
    }

    public var all: [any Channel] {
        Array(channels.values)
    }

    public var ids: [String] {
        Array(channels.keys)
    }

    /// Start all enabled channels.
    public func startAll() async throws {
        for channel in channels.values {
            try await channel.start()
        }
    }

    /// Stop all channels.
    public func stopAll() async {
        for channel in channels.values {
            try? await channel.stop()
        }
    }
}

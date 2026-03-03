import Foundation
import Shared

// MARK: - Channel Protocol

public protocol Channel: Actor {
    var id: String { get }
    var displayName: String { get }
    var status: ChannelStatus { get }

    /// Start listening for inbound messages.
    func start() async throws

    /// Stop the channel gracefully.
    func stop() async throws

    /// Send an outbound message through this channel.
    func send(_ message: OutboundMessage) async throws

    /// Register a handler for inbound messages.
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)

    /// Maximum text length this channel supports (for chunking).
    var maxTextLength: Int { get }
}

// MARK: - Default implementations

extension Channel {
    public var maxTextLength: Int { Defaults.TextLimits.default }
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

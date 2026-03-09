import Foundation
import ChannelKit
import Shared
import Networking
import ClawLogging

// MARK: - Configuration

public struct DiscordChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "discord"
    public var isEnabled: Bool = true
    public var botToken: String
    public var applicationID: String

    public init(botToken: String, applicationID: String) {
        self.botToken = botToken
        self.applicationID = applicationID
    }
}

// MARK: - Discord Channel

/// Discord channel using REST API for sending and Gateway for receiving.
public actor DiscordChannel: Channel {
    public let id = "discord"
    public let displayName = "Discord"
    public let maxTextLength = Defaults.TextLimits.discord

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private let config: DiscordChannelConfiguration
    private let client: HTTPClient
    private let logger = Log.channels

    public init(config: DiscordChannelConfiguration) {
        self.config = config
        self.client = HTTPClient(
            baseURL: URL(string: "https://discord.com/api/v10")!,
            defaultHeaders: [
                "Authorization": "Bot \(config.botToken)",
                "Content-Type": "application/json",
            ]
        )
    }

    public func start() async throws {
        status = .connecting
        logger.info("Discord channel starting")

        // Verify bot token
        let _: DiscordUser = try await client.request(path: "/users/@me")

        status = .connected
        logger.info("Discord channel connected")
        // Full implementation: connect to Gateway WebSocket for events
    }

    public func stop() async throws {
        status = .disconnected
        logger.info("Discord channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let payload = CreateMessage(content: text)
        let _: DiscordMessage = try await client.request(
            path: "/channels/\(message.recipientID)/messages",
            method: .post,
            body: payload
        )

        logger.debug("Discord message sent to channel \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Interaction Handling

    /// Handle Discord interaction webhook (slash commands, buttons).
    public func handleInteraction(body: Data) async throws -> Data {
        let interaction = try JSONDecoder().decode(DiscordInteraction.self, from: body)

        // Ping
        if interaction.type == 1 {
            return Data("{\"type\":1}".utf8)
        }

        // Slash command or message
        if let data = interaction.data, let content = data.options?.first?.value {
            let inbound = InboundMessage(
                channelID: id,
                senderID: interaction.member?.user?.id ?? interaction.user?.id ?? "unknown",
                sessionKey: "discord:\(interaction.channel_id ?? "dm")",
                content: .text(content)
            )
            await messageHandler?(inbound)
        }

        return Data("{\"type\":5}".utf8) // Deferred response
    }
}

// MARK: - API Types

private struct CreateMessage: Encodable {
    let content: String
}

private struct DiscordUser: Decodable {
    let id: String
    let username: String
}

private struct DiscordMessage: Decodable {
    let id: String
    let content: String
}

private struct DiscordInteraction: Decodable {
    let type: Int
    let channel_id: String?
    let data: InteractionData?
    let member: Member?
    let user: DiscordUser?

    struct InteractionData: Decodable {
        let name: String?
        let options: [Option]?
        struct Option: Decodable {
            let value: String
        }
    }
    struct Member: Decodable {
        let user: DiscordUser?
    }
}

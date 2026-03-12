import Foundation
import ChannelKit
import Shared
import Networking
import IRelayLogging

// MARK: - Configuration

public struct SlackChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "slack"
    public var isEnabled: Bool = true
    public var botToken: String
    public var appToken: String // for Socket Mode
    public var signingSecret: String
    public var webhookPath: String = "/webhooks/slack"

    public init(botToken: String, appToken: String, signingSecret: String) {
        self.botToken = botToken
        self.appToken = appToken
        self.signingSecret = signingSecret
    }
}

// MARK: - Slack Channel

/// Slack channel using Web API for sending and Events API / Socket Mode for receiving.
public actor SlackChannel: Channel {
    public let id = "slack"
    public let displayName = "Slack"
    public let maxTextLength = Defaults.TextLimits.slack

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private let config: SlackChannelConfiguration
    private let client: HTTPClient
    private let logger = Log.channels

    public init(config: SlackChannelConfiguration) {
        self.config = config
        self.client = HTTPClient(
            baseURL: URL(string: "https://slack.com/api")!,
            defaultHeaders: [
                "Authorization": "Bearer \(config.botToken)",
                "Content-Type": "application/json; charset=utf-8",
            ]
        )
    }

    public func start() async throws {
        status = .connecting
        logger.info("Slack channel starting")

        // Verify bot token
        let auth: SlackResponse<AuthTest> = try await client.request(path: "/auth.test", method: .post)
        guard auth.ok else {
            status = .error("Auth failed")
            throw IRelayError.channelNotFound("Slack auth failed: \(auth.error ?? "unknown")")
        }

        logger.info("Slack bot: \(auth.data?.user ?? "unknown") in \(auth.data?.team ?? "unknown")")
        status = .connected
    }

    public func stop() async throws {
        status = .disconnected
        logger.info("Slack channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let payload = PostMessage(channel: message.recipientID, text: text, thread_ts: message.replyTo)
        let response: SlackResponse<MessageSent> = try await client.request(
            path: "/chat.postMessage",
            method: .post,
            body: payload
        )

        guard response.ok else {
            throw IRelayError.channelSendFailed(channelID: id, reason: response.error ?? "unknown")
        }
        logger.debug("Slack message sent to \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Event Processing

    /// Called by gateway when a Slack event arrives (Events API or Socket Mode).
    public func handleEvent(body: Data) async throws -> Data {
        let event = try JSONDecoder().decode(SlackEvent.self, from: body)

        // URL verification challenge
        if event.type == "url_verification", let challenge = event.challenge {
            return Data("{\"challenge\":\"\(challenge)\"}".utf8)
        }

        // Message event
        if let innerEvent = event.event,
           innerEvent.type == "message",
           innerEvent.bot_id == nil,
           let text = innerEvent.text,
           let user = innerEvent.user {
            let inbound = InboundMessage(
                channelID: id,
                senderID: user,
                sessionKey: "slack:\(innerEvent.channel ?? "dm"):\(user)",
                content: .text(text),
                replyTo: innerEvent.thread_ts
            )
            await messageHandler?(inbound)
        }

        return Data("{}".utf8)
    }
}

// MARK: - API Types

private struct PostMessage: Encodable {
    let channel: String
    let text: String
    let thread_ts: String?
}

private struct SlackResponse<T: Decodable>: Decodable {
    let ok: Bool
    let error: String?
    let data: T?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(RawSlackResponse<T>.self)
        self.ok = raw.ok
        self.error = raw.error
        self.data = raw.data
    }

    private struct RawSlackResponse<V: Decodable>: Decodable {
        let ok: Bool
        let error: String?
        var data: V?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.ok = try container.decode(Bool.self, forKey: .ok)
            self.error = try container.decodeIfPresent(String.self, forKey: .error)
            self.data = try? V(from: decoder)
        }

        enum CodingKeys: String, CodingKey { case ok, error }
    }
}

private struct AuthTest: Decodable {
    let user: String?
    let team: String?
}

private struct MessageSent: Decodable {
    let ts: String?
}

private struct SlackEvent: Decodable {
    let type: String?
    let challenge: String?
    let event: InnerEvent?

    struct InnerEvent: Decodable {
        let type: String?
        let text: String?
        let user: String?
        let channel: String?
        let bot_id: String?
        let thread_ts: String?
    }
}

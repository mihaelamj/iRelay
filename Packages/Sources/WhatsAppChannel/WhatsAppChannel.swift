import Foundation
import ChannelKit
import Shared
import Networking
import ClawLogging

// MARK: - Configuration

public struct WhatsAppChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "whatsapp"
    public var isEnabled: Bool = true
    public var phoneNumberID: String
    public var accessToken: String
    public var verifyToken: String
    public var webhookPath: String = "/webhooks/whatsapp"

    public init(phoneNumberID: String, accessToken: String, verifyToken: String) {
        self.phoneNumberID = phoneNumberID
        self.accessToken = accessToken
        self.verifyToken = verifyToken
    }
}

// MARK: - WhatsApp Channel

/// WhatsApp Business Cloud API channel.
/// Receives messages via webhook, sends via REST API.
public actor WhatsAppChannel: Channel {
    public let id = "whatsapp"
    public let displayName = "WhatsApp"
    public let maxTextLength = Defaults.TextLimits.whatsApp

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private let config: WhatsAppChannelConfiguration
    private let client: HTTPClient
    private let logger = Log.channels

    public init(config: WhatsAppChannelConfiguration) {
        self.config = config
        self.client = HTTPClient(
            baseURL: URL(string: "https://graph.facebook.com/v21.0")!,
            defaultHeaders: [
                "Authorization": "Bearer \(config.accessToken)",
                "Content-Type": "application/json",
            ]
        )
    }

    public func start() async throws {
        status = .connecting
        logger.info("WhatsApp channel starting (phone: \(config.phoneNumberID))")
        // Webhook registration is handled externally (via Meta dashboard)
        // The gateway exposes config.webhookPath for Meta to POST to
        status = .connected
        logger.info("WhatsApp channel ready (webhook: \(config.webhookPath))")
    }

    public func stop() async throws {
        status = .disconnected
        logger.info("WhatsApp channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw SwiftClawError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let payload = SendMessagePayload(
            messaging_product: "whatsapp",
            to: message.recipientID,
            type: "text",
            text: .init(body: text)
        )

        let _: SendMessageResponse = try await client.request(
            path: "/\(config.phoneNumberID)/messages",
            method: .post,
            body: payload
        )

        logger.debug("WhatsApp message sent to \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Webhook Processing

    /// Called by the gateway when a webhook POST arrives.
    public func handleWebhook(body: Data) async throws {
        let webhook = try JSONDecoder().decode(WhatsAppWebhook.self, from: body)

        for entry in webhook.entry {
            for change in entry.changes {
                guard change.field == "messages" else { continue }
                for message in change.value.messages ?? [] {
                    let inbound = InboundMessage(
                        channelID: id,
                        senderID: message.from,
                        content: .text(message.text?.body ?? ""),
                        timestamp: Date(timeIntervalSince1970: TimeInterval(message.timestamp) ?? Date.now.timeIntervalSince1970)
                    )
                    await messageHandler?(inbound)
                }
            }
        }
    }

    /// Verify webhook challenge from Meta.
    public func verifyWebhook(mode: String, token: String, challenge: String) -> String? {
        guard mode == "subscribe", token == config.verifyToken else { return nil }
        return challenge
    }
}

// MARK: - API Types

private struct SendMessagePayload: Encodable {
    let messaging_product: String
    let to: String
    let type: String
    let text: TextBody

    struct TextBody: Encodable {
        let body: String
    }
}

private struct SendMessageResponse: Decodable {
    let messages: [MessageID]?
    struct MessageID: Decodable {
        let id: String
    }
}

// MARK: - Webhook Types

private struct WhatsAppWebhook: Decodable {
    let entry: [Entry]

    struct Entry: Decodable {
        let changes: [Change]
    }

    struct Change: Decodable {
        let field: String
        let value: Value
    }

    struct Value: Decodable {
        let messages: [Message]?
    }

    struct Message: Decodable {
        let from: String
        let timestamp: String
        let type: String
        let text: Text?

        struct Text: Decodable {
            let body: String
        }
    }
}

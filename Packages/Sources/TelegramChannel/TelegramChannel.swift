import Foundation
import ChannelKit
import Shared
import Networking
import ClawLogging

// MARK: - Configuration

public struct TelegramChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "telegram"
    public var isEnabled: Bool = true
    public var botToken: String
    public var webhookURL: String?
    public var pollingTimeout: Int = 30

    public init(botToken: String, webhookURL: String? = nil) {
        self.botToken = botToken
        self.webhookURL = webhookURL
    }
}

// MARK: - Telegram Channel

/// Telegram Bot API channel.
/// Supports both long polling and webhook modes.
public actor TelegramChannel: Channel {
    public let id = "telegram"
    public let displayName = "Telegram"
    public let maxTextLength = Defaults.TextLimits.telegram

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private var pollTask: Task<Void, Never>?
    private let config: TelegramChannelConfiguration
    private let client: HTTPClient
    private let logger = Log.channels
    private var lastUpdateID: Int = 0

    public init(config: TelegramChannelConfiguration) {
        self.config = config
        self.client = HTTPClient(
            baseURL: URL(string: "https://api.telegram.org/bot\(config.botToken)")!,
            defaultHeaders: ["Content-Type": "application/json"]
        )
    }

    public func start() async throws {
        status = .connecting
        logger.info("Telegram channel starting")

        // Verify bot token
        let me: TGResponse<TGUser> = try await client.request(path: "/getMe")
        logger.info("Telegram bot: @\(me.result.username ?? "unknown")")

        if let webhookURL = config.webhookURL {
            // Webhook mode
            let _: TGResponse<Bool> = try await client.request(
                path: "/setWebhook",
                method: .post,
                body: ["url": webhookURL]
            )
            logger.info("Telegram webhook set: \(webhookURL)")
        } else {
            // Long polling mode
            let _: TGResponse<Bool> = try await client.request(
                path: "/deleteWebhook",
                method: .post
            )
            startPolling()
            logger.info("Telegram long polling started")
        }

        status = .connected
    }

    public func stop() async throws {
        pollTask?.cancel()
        pollTask = nil
        status = .disconnected
        logger.info("Telegram channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let payload = SendMessageRequest(
            chat_id: message.recipientID,
            text: text,
            reply_to_message_id: message.replyTo.flatMap(Int.init)
        )

        let _: TGResponse<TGMessage> = try await client.request(
            path: "/sendMessage",
            method: .post,
            body: payload
        )

        logger.debug("Telegram message sent to \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Webhook Processing

    /// Called by the gateway when a webhook POST arrives.
    public func handleWebhook(body: Data) async throws {
        let update = try JSONDecoder().decode(TGUpdate.self, from: body)
        await processUpdate(update)
    }

    // MARK: - Long Polling

    private func startPolling() {
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let params = GetUpdatesRequest(
                        offset: lastUpdateID + 1,
                        timeout: config.pollingTimeout
                    )
                    let response: TGResponse<[TGUpdate]> = try await client.request(
                        path: "/getUpdates",
                        method: .post,
                        body: params
                    )
                    for update in response.result {
                        await processUpdate(update)
                        if update.update_id > lastUpdateID {
                            lastUpdateID = update.update_id
                        }
                    }
                } catch {
                    logger.warning("Telegram poll error: \(error)")
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func processUpdate(_ update: TGUpdate) async {
        guard let msg = update.message, let text = msg.text else { return }

        let inbound = InboundMessage(
            channelID: id,
            senderID: String(msg.from?.id ?? msg.chat.id),
            sessionKey: "tg:\(msg.chat.id)",
            content: .text(text),
            timestamp: Date(timeIntervalSince1970: TimeInterval(msg.date)),
            replyTo: msg.reply_to_message.map { String($0.message_id) }
        )

        await messageHandler?(inbound)
    }
}

// MARK: - Telegram API Types

private struct SendMessageRequest: Encodable {
    let chat_id: String
    let text: String
    let reply_to_message_id: Int?
}

private struct GetUpdatesRequest: Encodable {
    let offset: Int
    let timeout: Int
}

private struct TGResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T
}

private struct TGUser: Decodable {
    let id: Int
    let username: String?
    let first_name: String
}

private struct TGUpdate: Decodable {
    let update_id: Int
    let message: TGMessage?
}

private struct TGMessage: Decodable {
    let message_id: Int
    let from: TGUser?
    let chat: TGChat
    let date: Int
    let text: String?
    let reply_to_message: TGReplyMessage?
}

private struct TGChat: Decodable {
    let id: Int
    let type: String
}

private struct TGReplyMessage: Decodable {
    let message_id: Int
}

import Foundation
import ChannelKit
import Shared
import Networking
import IRelayLogging

// MARK: - Configuration

public struct MatrixChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "matrix"
    public var isEnabled: Bool = true
    public var homeserverURL: String
    public var accessToken: String
    public var userID: String

    public init(homeserverURL: String, accessToken: String, userID: String) {
        self.homeserverURL = homeserverURL
        self.accessToken = accessToken
        self.userID = userID
    }
}

// MARK: - Matrix Channel

/// Matrix channel using Client-Server API.
/// Long-polls /sync for incoming, sends via PUT /rooms/{roomId}/send.
public actor MatrixChannel: Channel {
    public let id = "matrix"
    public let displayName = "Matrix"
    public let maxTextLength = Defaults.TextLimits.default

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private var syncTask: Task<Void, Never>?
    private let config: MatrixChannelConfiguration
    private let client: HTTPClient
    private let logger = Log.channels
    private var nextBatch: String?

    public init(config: MatrixChannelConfiguration) {
        self.config = config
        self.client = HTTPClient(
            baseURL: URL(string: config.homeserverURL)!,
            defaultHeaders: [
                "Authorization": "Bearer \(config.accessToken)",
                "Content-Type": "application/json",
            ]
        )
    }

    public func start() async throws {
        status = .connecting
        logger.info("Matrix channel starting (\(config.userID))")

        // Verify auth
        let _: WhoAmI = try await client.request(path: "/_matrix/client/v3/account/whoami")
        status = .connected
        startSync()
        logger.info("Matrix channel connected")
    }

    public func stop() async throws {
        syncTask?.cancel()
        syncTask = nil
        status = .disconnected
        logger.info("Matrix channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let txnID = UUID().uuidString
        let body = MatrixMessage(msgtype: "m.text", body: text)
        let _: EventResponse = try await client.request(
            path: "/_matrix/client/v3/rooms/\(message.recipientID)/send/m.room.message/\(txnID)",
            method: .put,
            body: body
        )
        logger.debug("Matrix message sent to room \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Sync Loop

    private func startSync() {
        syncTask = Task {
            while !Task.isCancelled {
                do {
                    var path = "/_matrix/client/v3/sync?timeout=30000"
                    if let batch = nextBatch {
                        path += "&since=\(batch)"
                    }
                    let sync: SyncResponse = try await client.request(path: path)
                    nextBatch = sync.next_batch

                    for (roomID, room) in sync.rooms?.join ?? [:] {
                        for event in room.timeline?.events ?? [] {
                            guard event.type == "m.room.message",
                                  event.sender != config.userID,
                                  let body = event.content?.body else { continue }

                            let inbound = InboundMessage(
                                channelID: id,
                                senderID: event.sender ?? "unknown",
                                sessionKey: "matrix:\(roomID)",
                                content: .text(body)
                            )
                            await messageHandler?(inbound)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
            }
        }
    }
}

// MARK: - API Types

private struct WhoAmI: Decodable { let user_id: String }
private struct EventResponse: Decodable { let event_id: String }
private struct MatrixMessage: Encodable { let msgtype: String; let body: String }

private struct SyncResponse: Decodable {
    let next_batch: String
    let rooms: Rooms?
    struct Rooms: Decodable {
        let join: [String: JoinedRoom]?
    }
    struct JoinedRoom: Decodable {
        let timeline: Timeline?
    }
    struct Timeline: Decodable {
        let events: [Event]?
    }
    struct Event: Decodable {
        let type: String?
        let sender: String?
        let content: Content?
    }
    struct Content: Decodable {
        let body: String?
        let msgtype: String?
    }
}

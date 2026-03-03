import Foundation

public struct InboundMessage: Sendable {
    public let channelID: String
    public let senderID: String
    public let sessionKey: String?
    public let content: MessageContent
    public let timestamp: Date
    public let replyTo: String?

    public init(
        channelID: String,
        senderID: String,
        sessionKey: String? = nil,
        content: MessageContent,
        timestamp: Date = .now,
        replyTo: String? = nil
    ) {
        self.channelID = channelID
        self.senderID = senderID
        self.sessionKey = sessionKey
        self.content = content
        self.timestamp = timestamp
        self.replyTo = replyTo
    }
}

public struct OutboundMessage: Sendable {
    public let sessionID: String
    public let channelID: String
    public let recipientID: String
    public let content: MessageContent
    public let replyTo: String?

    public init(
        sessionID: String,
        channelID: String,
        recipientID: String,
        content: MessageContent,
        replyTo: String? = nil
    ) {
        self.sessionID = sessionID
        self.channelID = channelID
        self.recipientID = recipientID
        self.content = content
        self.replyTo = replyTo
    }
}

public struct ChatMessage: Sendable, Codable {
    public let role: ChatRole
    public let content: String
    public let timestamp: Date
    public let metadata: [String: String]?

    public init(
        role: ChatRole,
        content: String,
        timestamp: Date = .now,
        metadata: [String: String]? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public enum ChatRole: String, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}

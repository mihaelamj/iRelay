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

    /// Create a copy with different content (for splitting compound messages).
    public func with(content newContent: MessageContent) -> OutboundMessage {
        OutboundMessage(
            sessionID: sessionID,
            channelID: channelID,
            recipientID: recipientID,
            content: newContent,
            replyTo: replyTo
        )
    }
}

public struct ChatMessage: Sendable, Codable {
    public let role: ChatRole
    public let content: [ContentBlock]
    public let timestamp: Date
    public let metadata: [String: String]?

    public init(
        role: ChatRole,
        content: [ContentBlock],
        timestamp: Date = .now,
        metadata: [String: String]? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }

    /// Convenience: create a text-only message.
    public init(
        role: ChatRole,
        text: String,
        timestamp: Date = .now,
        metadata: [String: String]? = nil
    ) {
        self.role = role
        self.content = [.text(text)]
        self.timestamp = timestamp
        self.metadata = metadata
    }

    /// The concatenated text from all text blocks.
    public var textContent: String {
        content.compactMap(\.textValue).joined()
    }
}

public enum ChatRole: String, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}

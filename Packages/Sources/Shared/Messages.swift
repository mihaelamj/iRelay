// Message types shared across the system
import Foundation

public struct InboundMessage: Sendable {
    public let channelID: String
    public let senderID: String
    public let content: String
    public let timestamp: Date

    public init(channelID: String, senderID: String, content: String, timestamp: Date = .now) {
        self.channelID = channelID
        self.senderID = senderID
        self.content = content
        self.timestamp = timestamp
    }
}

public struct OutboundMessage: Sendable {
    public let sessionID: String
    public let content: String

    public init(sessionID: String, content: String) {
        self.sessionID = sessionID
        self.content = content
    }
}

public struct ChatMessage: Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

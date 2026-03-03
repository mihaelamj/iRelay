import Foundation

public struct SessionMetadata: Codable, Sendable {
    public var agentID: String
    public var channelID: String
    public var peerID: String
    public var modelOverride: String?
    public var thinkingLevel: ThinkingLevel
    public var createdAt: Date
    public var lastActiveAt: Date

    public init(
        agentID: String = Defaults.defaultAgentID,
        channelID: String,
        peerID: String,
        modelOverride: String? = nil,
        thinkingLevel: ThinkingLevel = .medium,
        createdAt: Date = .now,
        lastActiveAt: Date = .now
    ) {
        self.agentID = agentID
        self.channelID = channelID
        self.peerID = peerID
        self.modelOverride = modelOverride
        self.thinkingLevel = thinkingLevel
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }
}

public enum ThinkingLevel: String, Codable, Sendable, CaseIterable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
}

import Foundation

public struct AgentSession: Sendable, Identifiable {
    public let id: UUID
    public let agentType: AgentType
    public let senderID: String
    public let prompt: String
    public let workingDirectory: URL
    public let startedAt: Date
    public var agentSessionID: String?

    public init(
        id: UUID = UUID(),
        agentType: AgentType,
        senderID: String,
        prompt: String,
        workingDirectory: URL,
        startedAt: Date = Date(),
        agentSessionID: String? = nil
    ) {
        self.id = id
        self.agentType = agentType
        self.senderID = senderID
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.agentSessionID = agentSessionID
    }
}

import Foundation
import Shared

public struct AgentSpawnConfig: Sendable {
    public let type: AgentType
    public let workingDirectory: URL
    public let model: String?
    public let systemPrompt: String?
    public let allowedTools: [String]?
    public let timeout: TimeInterval
    public let idleTimeout: TimeInterval
    public let sessionID: String?
    public let continueSession: Bool
    public let environment: [String: String]

    public init(
        type: AgentType,
        workingDirectory: URL,
        model: String? = nil,
        systemPrompt: String? = nil,
        allowedTools: [String]? = nil,
        timeout: TimeInterval = Defaults.Spawner.defaultTimeout,
        idleTimeout: TimeInterval = Defaults.Spawner.defaultIdleTimeout,
        sessionID: String? = nil,
        continueSession: Bool = false,
        environment: [String: String] = [:]
    ) {
        self.type = type
        self.workingDirectory = workingDirectory
        self.model = model
        self.systemPrompt = systemPrompt
        self.allowedTools = allowedTools
        self.timeout = timeout
        self.idleTimeout = idleTimeout
        self.sessionID = sessionID
        self.continueSession = continueSession
        self.environment = environment
    }
}

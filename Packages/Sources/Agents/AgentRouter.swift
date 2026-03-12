import Foundation
import Shared
import ProviderKit
import Sessions
import IRelayLogging

// MARK: - Agent Definition

public struct Agent: Sendable {
    public let id: String
    public let name: String
    public let systemPrompt: String
    public let providerID: String
    public let modelID: String
    public let defaultOptions: CompletionOptions

    public init(
        id: String,
        name: String,
        systemPrompt: String = "You are a helpful assistant.",
        providerID: String = "claude",
        modelID: String = Defaults.defaultModelID,
        defaultOptions: CompletionOptions = .init()
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.defaultOptions = defaultOptions
    }
}

// MARK: - Agent Router

public actor AgentRouter {
    private var agents: [String: Agent] = [:]
    private let providers: ProviderRegistry
    private let logger = Log.agents

    public init(providers: ProviderRegistry) {
        self.providers = providers
    }

    /// Register an agent.
    public func register(_ agent: Agent) {
        agents[agent.id] = agent
        logger.info("Registered agent: \(agent.id) (\(agent.providerID)/\(agent.modelID))")
    }

    /// Route a message to the appropriate agent and stream the response.
    public func route(
        message: String,
        session: Session,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let agentID = session.metadata.agentID
        guard let agent = agents[agentID] else {
            return AsyncThrowingStream { $0.finish(throwing: IRelayError.agentNotFound(agentID)) }
        }

        return invoke(agent: agent, message: message, session: session, history: history)
    }

    /// Invoke a specific agent.
    public func invoke(
        agent: Agent,
        message: String,
        session: Session,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let provider = await providers.provider(for: agent.providerID) else {
                        throw IRelayError.providerNotFound(agent.providerID)
                    }

                    let modelID = session.metadata.modelOverride ?? agent.modelID

                    var options = agent.defaultOptions
                    options.systemPrompt = agent.systemPrompt
                    options.thinkingLevel = session.metadata.thinkingLevel

                    // Build messages: history + new user message
                    var messages = history
                    messages.append(ChatMessage(role: .user, text: message))

                    let stream = provider.complete(messages, model: modelID, options: options)

                    for try await event in stream {
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Get agent by ID.
    public func agent(for id: String) -> Agent? {
        agents[id]
    }

    /// All registered agent IDs.
    public var registeredIDs: [String] {
        Array(agents.keys)
    }
}

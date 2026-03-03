import Foundation
import Shared

// MARK: - LLM Provider Protocol

public protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedModels: [ModelInfo] { get }

    /// Stream a completion from the provider.
    func complete(
        _ messages: [ChatMessage],
        model: String,
        options: CompletionOptions
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Check if the provider is reachable and authenticated.
    func validate() async throws -> Bool
}

// MARK: - Default implementations

extension LLMProvider {
    public func complete(
        _ messages: [ChatMessage],
        model: String
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        complete(messages, model: model, options: .init())
    }
}

// MARK: - Stream Events

public enum StreamEvent: Sendable {
    case text(String)
    case toolCall(ToolCall)
    case usage(TokenUsage)
    case done(StopReason)
    case error(String)
}

public enum StopReason: String, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case toolUse = "tool_use"
    case stopSequence = "stop_sequence"
}

// MARK: - Completion Options

public struct CompletionOptions: Sendable {
    public var maxTokens: Int
    public var temperature: Double?
    public var topP: Double?
    public var stopSequences: [String]
    public var systemPrompt: String?
    public var tools: [ToolDefinition]
    public var thinkingLevel: ThinkingLevel

    public init(
        maxTokens: Int = 4096,
        temperature: Double? = nil,
        topP: Double? = nil,
        stopSequences: [String] = [],
        systemPrompt: String? = nil,
        tools: [ToolDefinition] = [],
        thinkingLevel: ThinkingLevel = .off
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.thinkingLevel = thinkingLevel
    }
}

// MARK: - Tool Support

public struct ToolDefinition: Sendable, Codable {
    public let name: String
    public let description: String
    public let inputSchema: String // JSON Schema

    public init(name: String, description: String, inputSchema: String) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ToolCall: Sendable {
    public let id: String
    public let name: String
    public let input: String // JSON

    public init(id: String, name: String, input: String) {
        self.id = id
        self.name = name
        self.input = input
    }
}

// MARK: - Model Info

public struct ModelInfo: Sendable {
    public let id: String
    public let displayName: String
    public let contextWindow: Int
    public let supportsTools: Bool
    public let supportsStreaming: Bool

    public init(
        id: String,
        displayName: String,
        contextWindow: Int,
        supportsTools: Bool = true,
        supportsStreaming: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.supportsTools = supportsTools
        self.supportsStreaming = supportsStreaming
    }
}

// MARK: - Token Usage

public struct TokenUsage: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Provider Registry

public actor ProviderRegistry {
    private var providers: [String: any LLMProvider] = [:]

    public init() {}

    public func register(_ provider: any LLMProvider) {
        providers[provider.id] = provider
    }

    public func provider(for id: String) -> (any LLMProvider)? {
        providers[id]
    }

    public var all: [any LLMProvider] {
        Array(providers.values)
    }

    public var ids: [String] {
        Array(providers.keys)
    }
}

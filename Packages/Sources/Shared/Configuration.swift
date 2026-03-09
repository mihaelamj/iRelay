import Foundation

public struct IRelayConfig: Codable, Sendable {
    public var gateway: GatewayConfig
    public var agents: AgentsConfig
    public var channels: ChannelsConfig
    public var providers: ProvidersConfig

    public init(
        gateway: GatewayConfig = .init(),
        agents: AgentsConfig = .init(),
        channels: ChannelsConfig = .init(),
        providers: ProvidersConfig = .init()
    ) {
        self.gateway = gateway
        self.agents = agents
        self.channels = channels
        self.providers = providers
    }
}

// MARK: - Gateway

public struct GatewayConfig: Codable, Sendable {
    public var host: String
    public var port: Int
    public var authToken: String?

    public init(
        host: String = Defaults.gatewayHost,
        port: Int = Defaults.gatewayPort,
        authToken: String? = nil
    ) {
        self.host = host
        self.port = port
        self.authToken = authToken
    }
}

// MARK: - Agents

public struct AgentsConfig: Codable, Sendable {
    public var defaultAgentID: String
    public var defaultModelID: String
    public var agents: [AgentDefinition]

    public init(
        defaultAgentID: String = Defaults.defaultAgentID,
        defaultModelID: String = Defaults.defaultModelID,
        agents: [AgentDefinition] = []
    ) {
        self.defaultAgentID = defaultAgentID
        self.defaultModelID = defaultModelID
        self.agents = agents
    }
}

public struct AgentDefinition: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var systemPrompt: String
    public var providerID: String?
    public var modelID: String?

    public init(
        id: String,
        name: String,
        systemPrompt: String = "You are a helpful assistant.",
        providerID: String? = nil,
        modelID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
    }
}

// MARK: - Channels

public struct ChannelsConfig: Codable, Sendable {
    public var enabled: [String: ChannelEntry]

    public init(enabled: [String: ChannelEntry] = [:]) {
        self.enabled = enabled
    }
}

public struct ChannelEntry: Codable, Sendable {
    public var isEnabled: Bool
    public var settings: [String: String]

    public init(isEnabled: Bool = true, settings: [String: String] = [:]) {
        self.isEnabled = isEnabled
        self.settings = settings
    }
}

// MARK: - Providers

public struct ProvidersConfig: Codable, Sendable {
    public var providers: [String: ProviderEntry]

    public init(providers: [String: ProviderEntry] = [:]) {
        self.providers = providers
    }
}

public struct ProviderEntry: Codable, Sendable {
    public var isEnabled: Bool
    public var baseURL: String?
    public var apiKeyRef: String?

    public init(isEnabled: Bool = true, baseURL: String? = nil, apiKeyRef: String? = nil) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
    }
}

// MARK: - Load / Save

extension IRelayConfig {
    public static func load(from url: URL = ClawPaths.configFile) throws -> IRelayConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return IRelayConfig()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(IRelayConfig.self, from: data)
    }

    public func save(to url: URL = ClawPaths.configFile) throws {
        try ClawPaths.ensureDirectoryExists(url.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

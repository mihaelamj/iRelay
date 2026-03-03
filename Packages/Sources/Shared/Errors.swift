import Foundation

public enum SwiftClawError: Error, Sendable {
    // Gateway
    case connectionFailed(String)
    case authenticationFailed(String)
    case protocolError(String)

    // Channel
    case channelNotFound(String)
    case channelDisconnected(String)
    case channelSendFailed(channelID: String, reason: String)
    case messageNormalizationFailed(String)

    // Provider
    case providerNotFound(String)
    case providerAuthFailed(providerID: String, reason: String)
    case modelNotFound(providerID: String, modelID: String)
    case streamingFailed(String)
    case toolCallFailed(toolName: String, reason: String)

    // Session
    case sessionNotFound(String)
    case sessionExpired(String)

    // Agent
    case agentNotFound(String)
    case agentRoutingFailed(String)

    // Storage
    case databaseError(String)
    case migrationFailed(version: Int, reason: String)

    // Config
    case configLoadFailed(path: String, reason: String)
    case configInvalid(key: String, reason: String)
    case secretNotFound(String)

    // Delivery
    case deliveryFailed(channelID: String, reason: String)
    case chunkingFailed(String)

    // General
    case timeout(operation: String, seconds: Int)
    case platformUnsupported(feature: String)
}

extension SwiftClawError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): "Connection failed: \(msg)"
        case .authenticationFailed(let msg): "Authentication failed: \(msg)"
        case .protocolError(let msg): "Protocol error: \(msg)"
        case .channelNotFound(let id): "Channel not found: \(id)"
        case .channelDisconnected(let id): "Channel disconnected: \(id)"
        case .channelSendFailed(let id, let reason): "Channel \(id) send failed: \(reason)"
        case .messageNormalizationFailed(let msg): "Message normalization failed: \(msg)"
        case .providerNotFound(let id): "Provider not found: \(id)"
        case .providerAuthFailed(let id, let reason): "Provider \(id) auth failed: \(reason)"
        case .modelNotFound(let provider, let model): "Model \(model) not found in provider \(provider)"
        case .streamingFailed(let msg): "Streaming failed: \(msg)"
        case .toolCallFailed(let name, let reason): "Tool call \(name) failed: \(reason)"
        case .sessionNotFound(let id): "Session not found: \(id)"
        case .sessionExpired(let id): "Session expired: \(id)"
        case .agentNotFound(let id): "Agent not found: \(id)"
        case .agentRoutingFailed(let msg): "Agent routing failed: \(msg)"
        case .databaseError(let msg): "Database error: \(msg)"
        case .migrationFailed(let version, let reason): "Migration v\(version) failed: \(reason)"
        case .configLoadFailed(let path, let reason): "Config load failed at \(path): \(reason)"
        case .configInvalid(let key, let reason): "Config invalid [\(key)]: \(reason)"
        case .secretNotFound(let name): "Secret not found: \(name)"
        case .deliveryFailed(let id, let reason): "Delivery to \(id) failed: \(reason)"
        case .chunkingFailed(let msg): "Chunking failed: \(msg)"
        case .timeout(let op, let secs): "Timeout after \(secs)s: \(op)"
        case .platformUnsupported(let feature): "Platform unsupported: \(feature)"
        }
    }
}

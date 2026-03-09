public enum AgentStreamEvent: Sendable {
    /// Text output chunk
    case text(String)
    /// Agent using a tool
    case toolUse(name: String, input: String)
    /// Tool result
    case toolResult(String)
    /// Coalesced status update
    case progress(String)
    /// Error message
    case error(String)
    /// Agent finished
    case done(summary: String, sessionID: String?)
}

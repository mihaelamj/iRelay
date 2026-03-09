public enum AgentType: String, Sendable, Codable, CaseIterable {
    case claude
    case codex

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}

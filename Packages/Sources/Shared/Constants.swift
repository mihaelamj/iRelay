public enum Defaults {
    public static let gatewayPort: Int = 18789
    public static let gatewayHost = "127.0.0.1"

    public static let sessionTimeoutSeconds: Int = 3600
    public static let connectionHeartbeatSeconds: Int = 30
    public static let requestTimeoutSeconds: Int = 300

    public static let maxMessageHistoryTokens: Int = 100_000
    public static let maxSessionAge: Int = 86400 * 30 // 30 days

    public static let defaultAgentID = "main"
    public static let defaultModelID = "claude-sonnet-4-20250514"

    public enum TextLimits {
        public static let telegram: Int = 4000
        public static let discord: Int = 2000
        public static let whatsApp: Int = 4000
        public static let slack: Int = 4000
        public static let irc: Int = 512
        public static let iMessage: Int = 20000
        public static let `default`: Int = 4000
    }
}

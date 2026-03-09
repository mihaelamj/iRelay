import Foundation
import Logging
import Shared

// MARK: - Logger Factory

public enum Log {
    /// Shared bootstrap — call once at app launch.
    public static func bootstrap(level: Logger.Level = .info) {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = level
            return handler
        }
    }

    /// Create a logger for the given subsystem.
    public static func logger(for subsystem: String) -> Logger {
        Logger(label: "com.swiftclaw.\(subsystem)")
    }

    // MARK: - Convenience subsystem loggers

    public static var gateway: Logger { logger(for: "gateway") }
    public static var channels: Logger { logger(for: "channels") }
    public static var providers: Logger { logger(for: "providers") }
    public static var sessions: Logger { logger(for: "sessions") }
    public static var agents: Logger { logger(for: "agents") }
    public static var storage: Logger { logger(for: "storage") }
    public static var delivery: Logger { logger(for: "delivery") }
    public static var scheduler: Logger { logger(for: "scheduler") }
    public static var cli: Logger { logger(for: "cli") }
    public static var spawner: Logger { logger(for: "spawner") }
}

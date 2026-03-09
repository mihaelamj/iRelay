import Foundation

public enum ClawPaths {
    public static var configDirectory: URL {
        #if os(macOS) || os(iOS)
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".irelay", isDirectory: true)
        #else
        // XDG_CONFIG_HOME or ~/.config/irelay on Linux
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdg)
                .appendingPathComponent("irelay", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("irelay", isDirectory: true)
        #endif
    }

    public static var dataDirectory: URL {
        #if os(macOS) || os(iOS)
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".irelay", isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
        #else
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: xdg)
                .appendingPathComponent("irelay", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("irelay", isDirectory: true)
        #endif
    }

    public static var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    public static var databaseFile: URL {
        dataDirectory.appendingPathComponent("irelay.db")
    }

    public static func agentDirectory(agentID: String) -> URL {
        dataDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
    }

    public static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
}

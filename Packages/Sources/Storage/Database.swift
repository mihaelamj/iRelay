import Foundation
import GRDB
import Shared
import ClawLogging

// MARK: - Database

public final class ClawDatabase: Sendable {
    private let dbPool: DatabasePool
    private let logger = Log.storage

    public init(path: URL? = nil) throws {
        let dbPath = path ?? ClawPaths.databaseFile
        try ClawPaths.ensureDirectoryExists(dbPath.deletingLastPathComponent())
        self.dbPool = try DatabasePool(path: dbPath.path)
        logger.info("Database opened at \(dbPath.path)")
    }

    /// Run all pending migrations.
    public func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_sessions") { db in
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentID", .text).notNull()
                t.column("channelID", .text).notNull()
                t.column("peerID", .text).notNull()
                t.column("modelOverride", .text)
                t.column("thinkingLevel", .text).notNull().defaults(to: "medium")
                t.column("createdAt", .datetime).notNull()
                t.column("lastActiveAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v1_messages") { db in
            try db.create(table: "messages", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionID", .text).notNull().indexed()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("metadata", .text) // JSON
            }
        }
        try migrator.migrate(dbPool)
        logger.info("Migrations complete")
    }

    /// Access the database for reads.
    public func read<T>(_ block: @Sendable (GRDB.Database) throws -> T) throws -> T {
        try dbPool.read(block)
    }

    /// Access the database for writes.
    public func write<T>(_ block: @Sendable (GRDB.Database) throws -> T) throws -> T {
        try dbPool.write(block)
    }
}

// MARK: - Session Record

public struct SessionRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sessions"

    public var id: String
    public var agentID: String
    public var channelID: String
    public var peerID: String
    public var modelOverride: String?
    public var thinkingLevel: String
    public var createdAt: Date
    public var lastActiveAt: Date

    public init(from metadata: SessionMetadata, id: String) {
        self.id = id
        self.agentID = metadata.agentID
        self.channelID = metadata.channelID
        self.peerID = metadata.peerID
        self.modelOverride = metadata.modelOverride
        self.thinkingLevel = metadata.thinkingLevel.rawValue
        self.createdAt = metadata.createdAt
        self.lastActiveAt = metadata.lastActiveAt
    }
}

// MARK: - Message Record

public struct MessageRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "messages"

    public var id: Int64?
    public var sessionID: String
    public var role: String
    public var content: String
    public var timestamp: Date
    public var metadata: String? // JSON-encoded [String: String]

    public init(sessionID: String, message: ChatMessage) {
        self.id = nil
        self.sessionID = sessionID
        self.role = message.role.rawValue
        self.content = message.content
        self.timestamp = message.timestamp
        if let meta = message.metadata {
            self.metadata = try? String(data: JSONEncoder().encode(meta), encoding: .utf8)
        } else {
            self.metadata = nil
        }
    }
}

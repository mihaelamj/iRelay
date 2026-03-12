import Foundation
import Shared
import Storage
import IRelayLogging
import GRDB

// MARK: - Memory Store

/// Stores and retrieves conversation memories using keyword-based search.
/// Phase 1: SQLite FTS (full-text search). Phase 2: vector embeddings.
public actor MemoryStore {
    private let db: IRelayDatabase
    private let logger = Log.logger(for: "memory")

    public init(db: IRelayDatabase) {
        self.db = db
    }

    /// Run memory-specific migrations.
    public func migrate() throws {
        try db.write { db in
            // Memories table
            try db.create(table: "memories", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("agentID", .text).notNull().indexed()
                t.column("sessionID", .text).indexed()
                t.column("content", .text).notNull()
                t.column("tags", .text) // comma-separated
                t.column("importance", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            // Full-text search index
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts
                USING fts5(content, tags, content=memories, content_rowid=id)
                """)
        }
        logger.info("Memory migrations complete")
    }

    // MARK: - Store

    /// Save a memory.
    public func store(
        content: String,
        agentID: String = Defaults.defaultAgentID,
        sessionID: String? = nil,
        tags: [String] = [],
        importance: Int = 0
    ) throws -> Int64 {
        try db.write { db in
            let record = MemoryRecord(
                id: nil,
                agentID: agentID,
                sessionID: sessionID,
                content: content,
                tags: tags.joined(separator: ","),
                importance: importance,
                createdAt: .now
            )
            try record.insert(db)

            // Update FTS index
            if let id = record.id {
                try db.execute(
                    sql: "INSERT INTO memories_fts(rowid, content, tags) VALUES (?, ?, ?)",
                    arguments: [id, content, tags.joined(separator: ",")]
                )
            }

            return record.id ?? 0
        }
    }

    // MARK: - Search

    /// Search memories by keyword using FTS.
    public func search(
        query: String,
        agentID: String? = nil,
        limit: Int = 10
    ) throws -> [MemoryRecord] {
        try db.read { db in
            var sql = """
                SELECT m.* FROM memories m
                JOIN memories_fts f ON m.id = f.rowid
                WHERE memories_fts MATCH ?
                """
            var args: [DatabaseValueConvertible] = [query]

            if let agentID {
                sql += " AND m.agentID = ?"
                args.append(agentID)
            }

            sql += " ORDER BY m.importance DESC, m.createdAt DESC LIMIT ?"
            args.append(limit)

            return try MemoryRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Get recent memories for a session.
    public func recent(
        sessionID: String,
        limit: Int = 20
    ) throws -> [MemoryRecord] {
        try db.read { db in
            try MemoryRecord
                .filter(Column("sessionID") == sessionID)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Delete

    /// Delete a memory by ID.
    public func delete(id: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM memories WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM memories_fts WHERE rowid = ?", arguments: [id])
        }
    }

    /// Delete all memories for an agent.
    public func deleteAll(agentID: String) throws {
        try db.write { db in
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM memories WHERE agentID = ?", arguments: [agentID])
            try db.execute(sql: "DELETE FROM memories WHERE agentID = ?", arguments: [agentID])
            for id in ids {
                try db.execute(sql: "DELETE FROM memories_fts WHERE rowid = ?", arguments: [id])
            }
        }
        logger.info("Deleted all memories for agent \(agentID)")
    }
}

// MARK: - Memory Record

public struct MemoryRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memories"

    public var id: Int64?
    public var agentID: String
    public var sessionID: String?
    public var content: String
    public var tags: String?
    public var importance: Int
    public var createdAt: Date

    public var tagList: [String] {
        tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
    }
}

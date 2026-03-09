import Foundation
import GRDB
import Shared
import Storage
import ClawLogging

// MARK: - Session Manager

public actor SessionManager {
    private let db: ClawDatabase
    private let logger = Log.sessions
    private var activeSessions: [String: Session] = [:]

    public init(db: ClawDatabase) {
        self.db = db
    }

    // MARK: - Get or Create

    /// Find an existing session or create a new one for the given key.
    public func session(
        for key: String,
        channelID: String,
        peerID: String,
        agentID: String = Defaults.defaultAgentID
    ) throws -> Session {
        if let existing = activeSessions[key] {
            return existing
        }

        // Check database
        if let record = try db.read({ db in
            try SessionRecord.fetchOne(db, key: key)
        }) {
            let session = Session(
                id: record.id,
                metadata: SessionMetadata(
                    agentID: record.agentID,
                    channelID: record.channelID,
                    peerID: record.peerID,
                    modelOverride: record.modelOverride,
                    thinkingLevel: ThinkingLevel(rawValue: record.thinkingLevel) ?? .medium,
                    createdAt: record.createdAt,
                    lastActiveAt: record.lastActiveAt
                )
            )
            activeSessions[key] = session
            return session
        }

        // Create new
        let session = Session(
            id: key,
            metadata: SessionMetadata(
                agentID: agentID,
                channelID: channelID,
                peerID: peerID
            )
        )
        activeSessions[key] = session
        try persist(session)
        logger.info("New session: \(key) (channel: \(channelID), peer: \(peerID))")
        return session
    }

    // MARK: - History

    /// Append a message to a session's history.
    public func appendMessage(_ message: ChatMessage, to sessionID: String) throws {
        let record = MessageRecord(sessionID: sessionID, message: message)
        try db.write { db in
            try record.insert(db)
        }
    }

    /// Load message history for a session.
    public func history(for sessionID: String, limit: Int = 50) throws -> [ChatMessage] {
        try db.read { db in
            let records = try MessageRecord
                .filter(Column("sessionID") == sessionID)
                .order(Column("timestamp").asc)
                .limit(limit)
                .fetchAll(db)

            return records.map { record in
                ChatMessage(
                    role: ChatRole(rawValue: record.role) ?? .user,
                    text: record.content,
                    timestamp: record.timestamp
                )
            }
        }
    }

    // MARK: - Touch / Expire

    /// Mark session as recently active.
    public func touch(_ sessionID: String) throws {
        if var session = activeSessions[sessionID] {
            session.metadata.lastActiveAt = .now
            activeSessions[sessionID] = session
            try persist(session)
        }
    }

    /// Remove expired sessions from memory.
    public func pruneExpired(maxAge: TimeInterval = TimeInterval(Defaults.maxSessionAge)) {
        let cutoff = Date.now.addingTimeInterval(-maxAge)
        let expired = activeSessions.filter { $0.value.metadata.lastActiveAt < cutoff }
        for key in expired.keys {
            activeSessions.removeValue(forKey: key)
        }
        if !expired.isEmpty {
            logger.info("Pruned \(expired.count) expired sessions")
        }
    }

    // MARK: - Persist

    private func persist(_ session: Session) throws {
        let record = SessionRecord(from: session.metadata, id: session.id)
        try db.write { db in
            try record.save(db)
        }
    }
}

// MARK: - Session

public struct Session: Sendable {
    public let id: String
    public var metadata: SessionMetadata

    public init(id: String, metadata: SessionMetadata) {
        self.id = id
        self.metadata = metadata
    }
}

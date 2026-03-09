#if os(macOS)
import Foundation
import GRDB
import ClawLogging

// MARK: - Chat DB Reader

/// Reads incoming messages from macOS chat.db using GRDB (read-only).
struct ChatDBReader: Sendable {
    private let dbPath: String
    private let cursorPath: String
    private let logger = Log.channels

    init(
        dbPath: String = NSHomeDirectory() + "/Library/Messages/chat.db",
        cursorPath: String = NSHomeDirectory() + "/.swiftclaw/imessage-cursor.txt"
    ) {
        self.dbPath = dbPath
        self.cursorPath = cursorPath
    }

    // MARK: - Database Access

    private func openDatabase() throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: dbPath, configuration: config)
    }

    // MARK: - Cursor Persistence

    func loadLastSeenRowID() -> Int64? {
        guard let contents = try? String(contentsOfFile: cursorPath, encoding: .utf8),
              let value = Int64(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return value
    }

    func saveLastSeenRowID(_ rowID: Int64) {
        let directory = (cursorPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? String(rowID).write(toFile: cursorPath, atomically: true, encoding: .utf8)
    }

    /// Query current max ROWID to skip history on first launch.
    func currentMaxRowID() throws -> Int64 {
        let db = try openDatabase()
        return try db.read { db in
            try Int64.fetchOne(db, sql: "SELECT MAX(ROWID) FROM message") ?? 0
        }
    }

    // MARK: - Fetch New Messages

    func fetchNewMessages(since lastRowID: Int64) throws -> [ParsedMessage] {
        let db = try openDatabase()

        let rawMessages: [RawMessageRow] = try db.read { db in
            try RawMessageRow.fetchAll(db, sql: """
                SELECT m.ROWID, m.guid, m.text, m.attributedBody, m.date,
                       m.is_from_me, m.cache_has_attachments, m.associated_message_type,
                       h.id as sender_id
                FROM message m
                LEFT JOIN handle h ON m.handle_id = h.ROWID
                WHERE m.ROWID > ?
                  AND m.is_from_me = 0
                  AND m.associated_message_type = 0
                  AND m.item_type = 0
                ORDER BY m.ROWID ASC
                LIMIT 50
                """, arguments: [lastRowID])
        }

        var parsed: [ParsedMessage] = []

        for raw in rawMessages {
            let messageText = AttributedBodyParser.parseMessageText(
                text: raw.text,
                attributedBody: raw.attributedBody
            )

            var attachments: [ParsedAttachment] = []
            if raw.cacheHasAttachments {
                attachments = (try? fetchAttachments(for: raw.rowID, db: db)) ?? []
            }

            // Skip messages with no text and no attachments
            guard messageText != nil || !attachments.isEmpty else { continue }

            parsed.append(ParsedMessage(
                rowID: raw.rowID,
                guid: raw.guid,
                text: messageText,
                senderID: raw.senderID ?? "unknown",
                timestamp: dateFromAppleNanoseconds(raw.date),
                attachments: attachments
            ))
        }

        return parsed
    }

    // MARK: - Attachments

    private func fetchAttachments(for messageRowID: Int64, db: DatabaseQueue) throws -> [ParsedAttachment] {
        let rows: [AttachmentRow] = try db.read { db in
            try AttachmentRow.fetchAll(db, sql: """
                SELECT a.filename, a.mime_type, a.total_bytes, a.transfer_name
                FROM attachment a
                JOIN message_attachment_join maj ON maj.attachment_id = a.ROWID
                WHERE maj.message_id = ?
                """, arguments: [messageRowID])
        }

        var attachments: [ParsedAttachment] = []

        for row in rows {
            guard let rawPath = row.filename else { continue }

            let expandedPath = NSString(string: rawPath).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expandedPath)

            guard let data = try? Data(contentsOf: fileURL) else {
                logger.warning("Could not read attachment at \(expandedPath)")
                continue
            }

            let filename = row.transferName ?? (expandedPath as NSString).lastPathComponent
            let mimeType = row.mimeType ?? "application/octet-stream"

            attachments.append(ParsedAttachment(
                filename: filename,
                mimeType: mimeType,
                data: data
            ))
        }

        return attachments
    }
}
#endif

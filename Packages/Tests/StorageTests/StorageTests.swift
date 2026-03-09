import XCTest
import GRDB
@testable import Storage
@testable import Shared

final class StorageTests: XCTestCase {
    private func makeTempDB() throws -> ClawDatabase {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).db")
        let db = try ClawDatabase(path: path)
        try db.migrate()
        return db
    }

    func testCreateAndMigrate() throws {
        let db = try makeTempDB()
        XCTAssertNotNil(db)
    }

    func testSessionRecordRoundtrip() throws {
        let db = try makeTempDB()
        let meta = SessionMetadata(agentID: "main", channelID: "telegram", peerID: "user1",
                                   thinkingLevel: .high,
                                   createdAt: Date(timeIntervalSince1970: 1000),
                                   lastActiveAt: Date(timeIntervalSince1970: 2000))
        let record = SessionRecord(from: meta, id: "sess-1")
        try db.write { db in try record.save(db) }

        let fetched = try db.read { db in try SessionRecord.fetchOne(db, key: "sess-1") }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.agentID, "main")
        XCTAssertEqual(fetched?.channelID, "telegram")
        XCTAssertEqual(fetched?.peerID, "user1")
        XCTAssertEqual(fetched?.thinkingLevel, "high")
    }

    func testMessageRecordRoundtrip() throws {
        let db = try makeTempDB()
        let msg = ChatMessage(role: .user, text: "Hello",
                              timestamp: Date(timeIntervalSince1970: 3000),
                              metadata: ["key": "val"])
        let record = MessageRecord(sessionID: "sess-1", message: msg)
        try db.write { db in try record.insert(db) }

        let fetched = try db.read { db in
            try MessageRecord.filter(Column("sessionID") == "sess-1").fetchAll(db)
        }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.role, "user")
        XCTAssertEqual(fetched.first?.content, "Hello")
    }

    func testMultipleMessages() throws {
        let db = try makeTempDB()
        for i in 0..<5 {
            let msg = ChatMessage(role: i % 2 == 0 ? .user : .assistant, text: "msg-\(i)")
            let record = MessageRecord(sessionID: "sess-1", message: msg)
            try db.write { db in try record.insert(db) }
        }
        let count = try db.read { db in try MessageRecord.fetchCount(db) }
        XCTAssertEqual(count, 5)
    }

    func testSessionRecordFromMetadata() {
        let meta = SessionMetadata(channelID: "slack", peerID: "p1")
        let record = SessionRecord(from: meta, id: "test-id")
        XCTAssertEqual(record.id, "test-id")
        XCTAssertEqual(record.agentID, "main")
        XCTAssertEqual(record.thinkingLevel, "medium")
        XCTAssertNil(record.modelOverride)
    }

    func testMessageRecordMetadataEncoding() {
        let msg = ChatMessage(role: .assistant, text: "Hi", metadata: ["a": "b"])
        let record = MessageRecord(sessionID: "s1", message: msg)
        XCTAssertNotNil(record.metadata)
        XCTAssertTrue(record.metadata?.contains("\"a\"") ?? false)
    }

    func testMessageRecordNilMetadata() {
        let msg = ChatMessage(role: .user, text: "Hi")
        let record = MessageRecord(sessionID: "s1", message: msg)
        XCTAssertNil(record.metadata)
    }
}

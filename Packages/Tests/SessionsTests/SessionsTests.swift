import XCTest
@testable import Sessions
@testable import Storage
@testable import Shared

final class SessionsTests: XCTestCase {

    private func makeManager() throws -> SessionManager {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-sess-\(UUID().uuidString).db")
        let db = try ClawDatabase(path: path)
        try db.migrate()
        return SessionManager(db: db)
    }

    func testSessionStruct() {
        let meta = SessionMetadata(channelID: "tg", peerID: "u1")
        let session = Session(id: "s1", metadata: meta)
        XCTAssertEqual(session.id, "s1")
        XCTAssertEqual(session.metadata.channelID, "tg")
    }

    func testCreateSession() async throws {
        let mgr = try makeManager()
        let session = try await mgr.session(for: "key1", channelID: "telegram", peerID: "user1")
        XCTAssertEqual(session.id, "key1")
        XCTAssertEqual(session.metadata.channelID, "telegram")
        XCTAssertEqual(session.metadata.peerID, "user1")
        XCTAssertEqual(session.metadata.agentID, "main")
    }

    func testGetSameSession() async throws {
        let mgr = try makeManager()
        let s1 = try await mgr.session(for: "key1", channelID: "tg", peerID: "u1")
        let s2 = try await mgr.session(for: "key1", channelID: "tg", peerID: "u1")
        XCTAssertEqual(s1.id, s2.id)
    }

    func testAppendAndHistory() async throws {
        let mgr = try makeManager()
        _ = try await mgr.session(for: "s1", channelID: "tg", peerID: "u1")
        let msg1 = ChatMessage(role: .user, content: "Hello")
        let msg2 = ChatMessage(role: .assistant, content: "Hi there")
        try await mgr.appendMessage(msg1, to: "s1")
        try await mgr.appendMessage(msg2, to: "s1")
        let history = try await mgr.history(for: "s1")
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].role, .user)
        XCTAssertEqual(history[1].role, .assistant)
    }

    func testHistoryLimit() async throws {
        let mgr = try makeManager()
        _ = try await mgr.session(for: "s1", channelID: "tg", peerID: "u1")
        for i in 0..<10 {
            try await mgr.appendMessage(ChatMessage(role: .user, content: "msg-\(i)"), to: "s1")
        }
        let history = try await mgr.history(for: "s1", limit: 3)
        XCTAssertEqual(history.count, 3)
    }

    func testPruneExpired() async throws {
        let mgr = try makeManager()
        _ = try await mgr.session(for: "old", channelID: "tg", peerID: "u1")
        await mgr.pruneExpired(maxAge: 0)
        // After pruning with maxAge 0, the in-memory cache should be empty
        // Creating a new session with same key should work
        let s = try await mgr.session(for: "old", channelID: "tg", peerID: "u1")
        XCTAssertEqual(s.id, "old")
    }
}

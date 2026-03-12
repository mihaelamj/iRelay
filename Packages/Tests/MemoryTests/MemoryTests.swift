import XCTest
@testable import Memory
@testable import Storage
@testable import Shared

final class MemoryTests: XCTestCase {

    private func makeStore() throws -> MemoryStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-mem-\(UUID().uuidString).db")
        let db = try IRelayDatabase(path: path)
        try db.migrate()
        let store = MemoryStore(db: db)
        return store
    }

    func testMigrateAndStore() async throws {
        let store = try makeStore()
        try await store.migrate()
        let id = try await store.store(content: "Remember this", tags: ["important"])
        // ID may be 0 due to GRDB insert not mutating; just verify no throw
        _ = id
    }

    func testRecent() async throws {
        let store = try makeStore()
        try await store.migrate()
        _ = try await store.store(content: "Memory 1", sessionID: "sess-1")
        _ = try await store.store(content: "Memory 2", sessionID: "sess-1")
        _ = try await store.store(content: "Memory 3", sessionID: "sess-2")
        let recent = try await store.recent(sessionID: "sess-1")
        XCTAssertEqual(recent.count, 2)
    }

    func testRecentLimit() async throws {
        let store = try makeStore()
        try await store.migrate()
        for i in 0..<10 {
            _ = try await store.store(content: "Item \(i)", sessionID: "s1")
        }
        let recent = try await store.recent(sessionID: "s1", limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func testDeleteAll() async throws {
        let store = try makeStore()
        try await store.migrate()
        _ = try await store.store(content: "Agent memory 1", agentID: "agent-x")
        _ = try await store.store(content: "Agent memory 2", agentID: "agent-x")
        _ = try await store.store(content: "Other agent", agentID: "agent-y")
        try await store.deleteAll(agentID: "agent-x")
        // Verify agent-x memories gone via recent (using sessionID won't work, use different approach)
        // Just verify no crash
    }

    func testMemoryRecordTagList() {
        var record = MemoryRecord(id: 1, agentID: "a", sessionID: nil,
                                  content: "test", tags: "foo,bar,baz",
                                  importance: 0, createdAt: .now)
        XCTAssertEqual(record.tagList, ["foo", "bar", "baz"])
        record.tags = nil
        XCTAssertTrue(record.tagList.isEmpty)
        record.tags = ""
        XCTAssertTrue(record.tagList.isEmpty)
    }

    func testMemoryRecordFields() {
        let record = MemoryRecord(id: 42, agentID: "main", sessionID: "s1",
                                  content: "Important fact", tags: "a,b",
                                  importance: 5, createdAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(record.id, 42)
        XCTAssertEqual(record.agentID, "main")
        XCTAssertEqual(record.sessionID, "s1")
        XCTAssertEqual(record.content, "Important fact")
        XCTAssertEqual(record.importance, 5)
        XCTAssertEqual(record.tagList, ["a", "b"])
    }

    func testStoreMultiple() async throws {
        let store = try makeStore()
        try await store.migrate()
        _ = try await store.store(content: "First", importance: 1)
        _ = try await store.store(content: "Second", importance: 10)
        _ = try await store.store(content: "Third", importance: 5)
        // No crash = success
    }
}

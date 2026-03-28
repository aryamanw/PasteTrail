import XCTest
import GRDB
@testable import PasteTrail

@MainActor
final class ClipStoreTests: XCTestCase {

    func makeInMemoryStore() throws -> ClipStore {
        try ClipStore(dbQueue: DatabaseQueue())
    }

    func testDatabaseMigrationCreatesTable() throws {
        let store = try makeInMemoryStore()
        let tableExists = try store.dbQueue.read { db in
            try db.tableExists("clip_items")
        }
        XCTAssertTrue(tableExists)
    }

    func testInsertAddsClip() throws {
        let store = try makeInMemoryStore()
        let item = ClipItem(id: UUID(), text: "hello", sourceApp: "com.apple.Terminal", timestamp: Date())
        try store.insert(item)
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(store.clips[0].text, "hello")
    }

    func testFreeCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<7 {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.freeCap)
        }
        XCTAssertEqual(store.clips.count, ClipStore.freeCap)
        XCTAssertEqual(store.clips[0].text, "clip 6")
    }

    func testDedupSkipsConsecutiveDuplicate() throws {
        let store = try makeInMemoryStore()
        let first  = ClipItem(id: UUID(), text: "dup", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 0))
        let second = ClipItem(id: UUID(), text: "dup", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 1))
        try store.insert(first)
        try store.insert(second)
        XCTAssertEqual(store.clips.count, 1)
    }

    func testDedupAllowsNonConsecutiveDuplicate() throws {
        let store = try makeInMemoryStore()
        let a = ClipItem(id: UUID(), text: "aaa", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 0))
        let b = ClipItem(id: UUID(), text: "bbb", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 1))
        let c = ClipItem(id: UUID(), text: "aaa", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 2))
        try store.insert(a)
        try store.insert(b)
        try store.insert(c)
        XCTAssertEqual(store.clips.count, 3)
    }

    func testSearchReturnsMatchingClips() throws {
        let store = try makeInMemoryStore()
        try store.insert(ClipItem(id: UUID(), text: "git commit -m fix", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 1)))
        try store.insert(ClipItem(id: UUID(), text: "npm install", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 2)))
        try store.insert(ClipItem(id: UUID(), text: "git push origin main", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 3)))

        let results = try store.search("git")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.text.lowercased().contains("git") })
    }

    func testSearchEmptyQueryReturnsAll() throws {
        let store = try makeInMemoryStore()
        try store.insert(ClipItem(id: UUID(), text: "aaa", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 1)))
        try store.insert(ClipItem(id: UUID(), text: "bbb", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: 2)))

        let results = try store.search("")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchIsCaseInsensitive() throws {
        let store = try makeInMemoryStore()
        try store.insert(ClipItem(id: UUID(), text: "Hello World", sourceApp: "com.test", timestamp: Date()))

        let results = try store.search("hello")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchIsUnicodeCaseInsensitive() throws {
        let store = try makeInMemoryStore()
        try store.insert(ClipItem(id: UUID(), text: "Héllo World", sourceApp: "com.test", timestamp: Date()))
        // lowercased query should still find it via lower(text) LIKE
        let results = try store.search("héllo")
        XCTAssertEqual(results.count, 1)
    }

    func testPaidCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<502 {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.paidCap)
        }
        XCTAssertEqual(store.clips.count, ClipStore.paidCap)
        XCTAssertEqual(store.clips[0].text, "clip 501")
    }
}

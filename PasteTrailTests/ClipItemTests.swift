import XCTest
import GRDB
@testable import PasteTrail

final class ClipItemTests: XCTestCase {

    func testClipItemRoundTrip() throws {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.create(table: "clip_items") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("text", .text).notNull()
                t.column("sourceApp", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
        }
        let original = ClipItem(id: UUID(), text: "hello", sourceApp: "com.apple.Terminal", timestamp: Date(timeIntervalSince1970: 0))
        try db.write { db in try original.insert(db) }
        let fetched = try db.read { db in try ClipItem.fetchAll(db) }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "hello")
        XCTAssertEqual(fetched[0].sourceApp, "com.apple.Terminal")
    }

    func testClipItemDatabaseColumnNames() {
        let cols = ClipItem.databaseColumnNames
        XCTAssertTrue(cols.contains("id"))
        XCTAssertTrue(cols.contains("text"))
        XCTAssertTrue(cols.contains("sourceApp"))
        XCTAssertTrue(cols.contains("timestamp"))
    }
}

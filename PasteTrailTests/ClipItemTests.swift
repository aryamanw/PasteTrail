import XCTest
import GRDB
@testable import PasteTrail

final class ClipItemTests: XCTestCase {

    // Updated: table now includes contentType and imagePath columns
    func testClipItemRoundTrip() throws {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.create(table: "clip_items") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("contentType", .text).notNull().defaults(to: "text")
                t.column("text", .text).notNull()
                t.column("imagePath", .text)
                t.column("sourceApp", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }
        }
        let original = ClipItem(id: UUID(), text: "hello", sourceApp: "com.apple.Terminal", timestamp: Date(timeIntervalSince1970: 0))
        try db.write { db in try original.insert(db) }
        let fetched = try db.read { db in try ClipItem.fetchAll(db) }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].contentType, .text)
        XCTAssertNil(fetched[0].imagePath)
        XCTAssertEqual(fetched[0].text, "hello")
        XCTAssertEqual(fetched[0].sourceApp, "com.apple.Terminal")
        XCTAssertEqual(fetched[0].id, original.id)
        XCTAssertEqual(fetched[0].timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testClipItemDatabaseColumnNames() {
        let cols = ClipItem.databaseColumnNames
        XCTAssertTrue(cols.contains("id"))
        XCTAssertTrue(cols.contains("contentType"))
        XCTAssertTrue(cols.contains("text"))
        XCTAssertTrue(cols.contains("imagePath"))
        XCTAssertTrue(cols.contains("sourceApp"))
        XCTAssertTrue(cols.contains("timestamp"))
        XCTAssertTrue(cols.contains("isPinned"))
    }

    func testImageClipItemFields() {
        let id = UUID()
        let item = ClipItem(
            id: id,
            contentType: .image,
            text: "",
            imagePath: "test.png",
            sourceApp: "com.apple.screencaptureui",
            timestamp: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(item.contentType, .image)
        XCTAssertEqual(item.imagePath, "test.png")
        XCTAssertEqual(item.text, "")
    }

    func testTextClipItemDefaultsToTextContentType() {
        // Existing call sites omit contentType and imagePath — must still compile with defaults
        let item = ClipItem(id: UUID(), text: "hello", sourceApp: "com.test", timestamp: Date())
        XCTAssertEqual(item.contentType, .text)
        XCTAssertNil(item.imagePath)
    }
}

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
}

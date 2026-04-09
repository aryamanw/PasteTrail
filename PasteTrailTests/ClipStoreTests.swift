import XCTest
import GRDB
@testable import PasteTrail

@MainActor
final class ClipStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func makeInMemoryStore() throws -> ClipStore {
        try ClipStore(dbQueue: DatabaseQueue(), imagesDirectory: tmpDir)
    }

    func testDatabaseMigrationCreatesTable() throws {
        let store = try makeInMemoryStore()
        let tableExists = try store.dbQueue.read { db in
            try db.tableExists("clip_items")
        }
        XCTAssertTrue(tableExists)
    }

    func testMigrationV2AddsColumns() throws {
        let store = try makeInMemoryStore()
        let columns = try store.dbQueue.read { db in
            try db.columns(in: "clip_items").map { $0.name }
        }
        XCTAssertTrue(columns.contains("contentType"))
        XCTAssertTrue(columns.contains("imagePath"))
    }

    func testInsertAddsClip() throws {
        let store = try makeInMemoryStore()
        let item = ClipItem(id: UUID(), text: "hello", sourceApp: "com.apple.Terminal", timestamp: Date())
        try store.insert(item)
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(store.clips[0].text, "hello")
    }

    func testCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<(ClipStore.cap + 3) {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test",
                                timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item)
        }
        XCTAssertEqual(store.clips.count, ClipStore.cap)
        XCTAssertEqual(store.clips[0].text, "clip \(ClipStore.cap + 2)")
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

    // MARK: - Helpers

    private func makePNGData() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: - Image tests

    func testInsertImageWritesFileAndAddsClip() throws {
        let store = try makeInMemoryStore()
        let id = UUID()
        let capture = ImageCapture(
            id: id,
            pngData: makePNGData(),
            sourceApp: "com.apple.screencaptureui",
            timestamp: Date()
        )
        try store.insertImage(capture)

        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(store.clips[0].contentType, .image)
        XCTAssertEqual(store.clips[0].imagePath, "\(id.uuidString).png")

        let fileURL = store.imagesDirectory.appendingPathComponent("\(id.uuidString).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testImageFileDeletedWhenEvictedByCap() throws {
        let store = try makeInMemoryStore()
        let imageID = UUID()
        let capture = ImageCapture(
            id: imageID,
            pngData: makePNGData(),
            sourceApp: "com.test",
            timestamp: Date(timeIntervalSince1970: 0) // oldest
        )
        try store.insertImage(capture, cap: ClipStore.cap)
        let imageFileURL = store.imagesDirectory.appendingPathComponent("\(imageID.uuidString).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageFileURL.path))

        // Push image out of the cap with newer text clips
        for i in 1...ClipStore.cap {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test",
                                timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.cap)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageFileURL.path))
        XCTAssertEqual(store.clips.count, ClipStore.cap)
    }

    func testSearchReturnsImageClipsBySourceAppBundleID() throws {
        let store = try makeInMemoryStore()
        let capture = ImageCapture(
            id: UUID(),
            pngData: makePNGData(),
            sourceApp: "com.figma.agent",
            timestamp: Date()
        )
        try store.insertImage(capture)

        let results = try store.search("figma")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].contentType, .image)
    }

    func testSearchDoesNotReturnImageClipForUnrelatedQuery() throws {
        let store = try makeInMemoryStore()
        let capture = ImageCapture(
            id: UUID(),
            pngData: makePNGData(),
            sourceApp: "com.apple.screencaptureui",
            timestamp: Date()
        )
        try store.insertImage(capture)

        let results = try store.search("git")
        XCTAssertEqual(results.count, 0)
    }

    func testSearchMixedResultsSortedByTimestamp() throws {
        let store = try makeInMemoryStore()
        try store.insert(ClipItem(id: UUID(), text: "git commit", sourceApp: "com.test",
                                  timestamp: Date(timeIntervalSince1970: 1)))
        let capture = ImageCapture(
            id: UUID(), pngData: makePNGData(),
            sourceApp: "com.git.tool",
            timestamp: Date(timeIntervalSince1970: 2)
        )
        try store.insertImage(capture)

        let results = try store.search("git")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].contentType, .image)
        XCTAssertEqual(results[1].contentType, .text)
    }

    func testTextDedupDoesNotTriggerForImageClips() throws {
        let store = try makeInMemoryStore()
        // Two image clips in a row should both be stored (no dedup)
        let c1 = ImageCapture(id: UUID(), pngData: makePNGData(), sourceApp: "com.test",
                              timestamp: Date(timeIntervalSince1970: 0))
        let c2 = ImageCapture(id: UUID(), pngData: makePNGData(), sourceApp: "com.test",
                              timestamp: Date(timeIntervalSince1970: 1))
        try store.insertImage(c1)
        try store.insertImage(c2)
        XCTAssertEqual(store.clips.count, 2)
    }
}

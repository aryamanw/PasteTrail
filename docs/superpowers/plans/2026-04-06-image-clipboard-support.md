# Image Clipboard Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture, store, display, and paste image clips (screenshots, in-app images, Finder file copies) inline alongside text clips in a single unified history.

**Architecture:** `ClipItem` gains a `contentType` enum field and optional `imagePath`; images are stored as PNG files in the app support directory while SQLite holds only metadata. `ClipboardMonitor` emits a new `ClipEvent` discriminated union; `ClipStore` owns all disk I/O for images.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, GRDB.swift, NSPasteboard, NSImage/NSBitmapImageRep, XCTest

---

## File Map

| File | Change |
|---|---|
| `PasteTrail/Clipboard/ClipItem.swift` | Add `ContentType` enum, `contentType` + `imagePath` fields, update GRDB columns |
| `PasteTrail/Clipboard/ClipboardMonitor.swift` | Add `ImageCapture`, `ClipEvent`; change publisher type; update `poll()` |
| `PasteTrail/Storage/ClipStore.swift` | Add `imagesDirectory`; v2 migration; `insertImage(_:cap:)`; updated eviction, dedup, `paste`, `search` |
| `PasteTrail/App/AppDelegate.swift` | Route `ClipEvent` to `insert` vs `insertImage` |
| `PasteTrail/MenuBar/ClipPopoverView.swift` | Update `ClipRowView` + `clipList` for image rows |
| `PasteTrailTests/ClipItemTests.swift` | Update round-trip table + column name test |
| `PasteTrailTests/ClipStoreTests.swift` | Update `makeInMemoryStore`; add migration, image insert, eviction, search tests |
| `PasteTrailTests/ClipboardMonitorTests.swift` | Add image extensions test |

---

## Task 1: Extend `ClipItem` — `ContentType` enum + new fields

**Files:**
- Modify: `PasteTrail/Clipboard/ClipItem.swift`
- Modify: `PasteTrailTests/ClipItemTests.swift`

- [ ] **Step 1: Write failing tests**

Open `PasteTrailTests/ClipItemTests.swift`. Replace the entire file with:

```swift
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipItemTests test 2>&1 | tail -20
```

Expected: compile error — `ContentType` not found, `ClipItem` has no `contentType` member.

- [ ] **Step 3: Update `ClipItem.swift`**

Replace the entire file with:

```swift
import Foundation
import GRDB

enum ContentType: String, Codable {
    case text
    case image
}

struct ClipItem: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    var id: UUID
    var contentType: ContentType = .text
    var text: String
    var imagePath: String? = nil
    var sourceApp: String
    var timestamp: Date
}

// MARK: - GRDB

extension ClipItem {
    static let databaseTableName = "clip_items"

    static var databaseColumnNames: [String] {
        ["id", "contentType", "text", "imagePath", "sourceApp", "timestamp"]
    }

    enum Columns {
        static let id          = Column(CodingKeys.id)
        static let contentType = Column(CodingKeys.contentType)
        static let text        = Column(CodingKeys.text)
        static let imagePath   = Column(CodingKeys.imagePath)
        static let sourceApp   = Column(CodingKeys.sourceApp)
        static let timestamp   = Column(CodingKeys.timestamp)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipItemTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add PasteTrail/Clipboard/ClipItem.swift PasteTrailTests/ClipItemTests.swift
git commit -m "feat: add ContentType enum and imagePath field to ClipItem"
```

---

## Task 2: `ClipStore` — `imagesDirectory`, v2 migration, updated inits

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Open `PasteTrailTests/ClipStoreTests.swift`. At the top of the class, update `makeInMemoryStore` and add a migration test. Replace the `makeInMemoryStore` helper and add the new test (keep all existing tests unchanged):

```swift
// Replace this:
func makeInMemoryStore() throws -> ClipStore {
    try ClipStore(dbQueue: DatabaseQueue())
}

// With this:
func makeInMemoryStore() throws -> ClipStore {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return try ClipStore(dbQueue: DatabaseQueue(), imagesDirectory: tmpDir)
}
```

Add this test after `testDatabaseMigrationCreatesTable`:

```swift
func testMigrationV2AddsColumns() throws {
    let store = try makeInMemoryStore()
    let columns = try store.dbQueue.read { db in
        try db.columns(in: "clip_items").map { $0.name }
    }
    XCTAssertTrue(columns.contains("contentType"))
    XCTAssertTrue(columns.contains("imagePath"))
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | tail -20
```

Expected: compile error — `ClipStore.init(dbQueue:imagesDirectory:)` does not exist.

- [ ] **Step 3: Update `ClipStore.swift` — designated init, `imagesDirectory`, migration v2**

In `ClipStore.swift`, make these changes:

**Add `imagesDirectory` stored property** (after `let dbQueue: DatabaseQueue`):
```swift
let imagesDirectory: URL
```

**Replace the designated `init(dbQueue:)` with:**
```swift
init(dbQueue: DatabaseQueue, imagesDirectory: URL) throws {
    self.dbQueue = dbQueue
    self.imagesDirectory = imagesDirectory
    try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    try Self.migrate(dbQueue)
    try loadClips()
}
```

**Replace the convenience `init()` with:**
```swift
convenience init() throws {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = appSupport.appendingPathComponent("PasteTrail", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dbURL = dir.appendingPathComponent("clips.sqlite")
    let queue = try DatabaseQueue(path: dbURL.path)
    let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
    try self.init(dbQueue: queue, imagesDirectory: imagesDir)
}
```

**Add migration "v2"** inside `migrate(_:)`, after the `migrator.registerMigration("v1")` block:
```swift
migrator.registerMigration("v2") { db in
    try db.alter(table: "clip_items") { t in
        t.add(column: "contentType", .text).notNull().defaults(to: "text")
        t.add(column: "imagePath", .text)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: add imagesDirectory and v2 migration to ClipStore"
```

---

## Task 3: `ClipStore.insertImage(_:cap:)` + updated `insert` dedup and eviction

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add a `makePNGData()` helper and three new tests to `ClipStoreTests`. Add inside the class:

```swift
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
    try store.insertImage(capture, cap: ClipStore.freeCap)
    let imageFileURL = store.imagesDirectory.appendingPathComponent("\(imageID.uuidString).png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: imageFileURL.path))

    // Push image out of the cap with newer text clips
    for i in 1...ClipStore.freeCap {
        let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test",
                            timestamp: Date(timeIntervalSince1970: Double(i)))
        try store.insert(item, cap: ClipStore.freeCap)
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: imageFileURL.path))
    XCTAssertEqual(store.clips.count, ClipStore.freeCap)
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | tail -20
```

Expected: compile error — `ImageCapture` not defined, `insertImage` not found.

- [ ] **Step 3: Add `ImageCapture` to `ClipboardMonitor.swift`**

Open `PasteTrail/Clipboard/ClipboardMonitor.swift`. Add before the `ClipboardMonitor` class declaration:

```swift
struct ImageCapture {
    let id: UUID
    let pngData: Data
    let sourceApp: String
    let timestamp: Date
}
```

- [ ] **Step 4: Add `insertImage(_:cap:)` to `ClipStore.swift`**

Add this method after the existing `insert(_:cap:)` method:

```swift
func insertImage(_ capture: ImageCapture, cap: Int? = nil) throws {
    let filename = "\(capture.id.uuidString).png"
    let fileURL = imagesDirectory.appendingPathComponent(filename)
    try capture.pngData.write(to: fileURL)

    let item = ClipItem(
        id: capture.id,
        contentType: .image,
        text: "",
        imagePath: filename,
        sourceApp: capture.sourceApp,
        timestamp: capture.timestamp
    )

    let effectiveCap = cap ?? currentCap
    try dbQueue.write { db in
        try item.insert(db)
        let total = try ClipItem.fetchCount(db)
        if total > effectiveCap {
            let overflow = total - effectiveCap
            let oldest = try ClipItem
                .order(ClipItem.Columns.timestamp.asc)
                .limit(overflow)
                .fetchAll(db)
            for old in oldest {
                deleteImageFileIfNeeded(old)
                try old.delete(db)
            }
        }
    }
    try loadClips()
}
```

- [ ] **Step 5: Add `deleteImageFileIfNeeded` helper and update `insert` dedup + eviction**

Add private helper to `ClipStore.swift`:

```swift
private func deleteImageFileIfNeeded(_ item: ClipItem) {
    guard item.contentType == .image, let filename = item.imagePath else { return }
    let fileURL = imagesDirectory.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: fileURL)
}
```

Update the existing `insert(_:cap:)` method — change the dedup guard and the eviction loop:

```swift
func insert(_ item: ClipItem, cap: Int? = nil) throws {
    // Dedup: only skip consecutive identical text clips
    if item.contentType == .text, let latest = clips.first,
       latest.contentType == .text, latest.text == item.text { return }

    let effectiveCap = cap ?? currentCap
    try dbQueue.write { db in
        try item.insert(db)
        let total = try ClipItem.fetchCount(db)
        if total > effectiveCap {
            let overflow = total - effectiveCap
            let oldest = try ClipItem
                .order(ClipItem.Columns.timestamp.asc)
                .limit(overflow)
                .fetchAll(db)
            for old in oldest {
                deleteImageFileIfNeeded(old)
                try old.delete(db)
            }
        }
    }
    try loadClips()
}
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Run full test suite**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add PasteTrail/Clipboard/ClipboardMonitor.swift PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: add insertImage and image file eviction to ClipStore"
```

---

## Task 4: `ClipStore.paste(_:)` — image clip support

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`

No new unit test (requires AXIsProcessTrusted + live pasteboard — integration concern).

- [ ] **Step 1: Replace `paste(_:)` in `ClipStore.swift`**

Replace the existing `paste(_:)` method with:

```swift
func paste(_ item: ClipItem) {
    guard AXIsProcessTrusted() else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    switch item.contentType {
    case .text:
        pasteboard.setString(item.text, forType: .string)
    case .image:
        guard let filename = item.imagePath else { return }
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: fileURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let tiffData = rep.representation(using: .tiff, properties: [:]) else { return }
        pasteboard.setData(tiffData, forType: .tiff)
    }

    monitor?.isPasting = true

    Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
        self?.sendCommandV()
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
        self?.monitor?.isPasting = false
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift
git commit -m "feat: paste image clips via TIFF pasteboard write"
```

---

## Task 5: `ClipboardMonitor` — `ClipEvent` enum, updated publisher, image detection in `poll()`

**Files:**
- Modify: `PasteTrail/Clipboard/ClipboardMonitor.swift`
- Modify: `PasteTrailTests/ClipboardMonitorTests.swift`

- [ ] **Step 1: Write failing test**

Open `PasteTrailTests/ClipboardMonitorTests.swift`. Add one test:

```swift
func testImageExtensionsIncludeCommonFormats() {
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("png"))
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("jpg"))
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("jpeg"))
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("gif"))
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("webp"))
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("heic"))
    XCTAssertTrue(ClipboardMonitor.imageExtensions.contains("tiff"))
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipboardMonitorTests test 2>&1 | tail -20
```

Expected: compile error — `ClipboardMonitor.imageExtensions` not found.

- [ ] **Step 3: Rewrite `ClipboardMonitor.swift`**

Replace the entire file with:

```swift
import AppKit
import Combine

struct ImageCapture {
    let id: UUID
    let pngData: Data
    let sourceApp: String
    let timestamp: Date
}

enum ClipEvent {
    case text(ClipItem)
    case image(ImageCapture)
}

final class ClipboardMonitor {

    // MARK: - Public

    let publisher = PassthroughSubject<ClipEvent, Never>()

    /// Set to true while ClipStore is writing to the pasteboard for a paste action
    /// so the resulting changeCount bump is ignored.
    var isPasting = false

    var excludePasswordManagers: Bool = true

    // MARK: - Excluded bundle IDs

    private static let excludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess"
    ]

    static func isExcluded(bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return excludedBundleIDs.contains(id)
    }

    // MARK: - Image extensions

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"
    ]

    // MARK: - Monitoring

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !isPasting else { return }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if excludePasswordManagers {
            guard !Self.isExcluded(bundleID: frontBundleID) else { return }
        }

        let sourceApp = frontBundleID ?? "unknown"
        let timestamp = Date()

        // 1. TIFF or PNG image data on the pasteboard
        if let rawData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")),
           let image = NSImage(data: rawData),
           let pngData = image.pngRepresentation() {
            let capture = ImageCapture(id: UUID(), pngData: pngData, sourceApp: sourceApp, timestamp: timestamp)
            publisher.send(.image(capture))
            return
        }

        // 2. Finder file copy — first image file in the selection
        if let filePaths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           let firstImagePath = filePaths.first(where: {
               Self.imageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
           }),
           let image = NSImage(contentsOfFile: firstImagePath),
           let pngData = image.pngRepresentation() {
            let capture = ImageCapture(id: UUID(), pngData: pngData, sourceApp: sourceApp, timestamp: timestamp)
            publisher.send(.image(capture))
            return
        }

        // 3. Plain text
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let item = ClipItem(
            id: UUID(),
            contentType: .text,
            text: text,
            imagePath: nil,
            sourceApp: sourceApp,
            timestamp: timestamp
        )
        publisher.send(.text(item))
    }
}

// MARK: - NSImage PNG helper

private extension NSImage {
    func pngRepresentation() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
```

Note: `ImageCapture` and `ClipEvent` now live in this file. Remove the `ImageCapture` struct added to this file in Task 3 (it was a temporary location — it was added to `ClipboardMonitor.swift` in Task 3 Step 3 as a stub, and this task's full rewrite supersedes it).

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipboardMonitorTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add PasteTrail/Clipboard/ClipboardMonitor.swift PasteTrailTests/ClipboardMonitorTests.swift
git commit -m "feat: add ClipEvent enum and image detection to ClipboardMonitor"
```

---

## Task 6: `AppDelegate` — route `ClipEvent` to `insert` vs `insertImage`

**Files:**
- Modify: `PasteTrail/App/AppDelegate.swift`

- [ ] **Step 1: Update the clipboard monitor sink in `AppDelegate.swift`**

Find this block in `applicationDidFinishLaunching`:

```swift
clipboardMonitor.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] item in
        guard let self, settingsStore.isMonitoringEnabled else { return }
        try? clipStore.insert(item)
    }
    .store(in: &cancellables)
```

Replace it with:

```swift
clipboardMonitor.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] event in
        guard let self, settingsStore.isMonitoringEnabled else { return }
        switch event {
        case .text(let item):
            try? clipStore.insert(item)
        case .image(let capture):
            try? clipStore.insertImage(capture)
        }
    }
    .store(in: &cancellables)
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PasteTrail/App/AppDelegate.swift
git commit -m "feat: route ClipEvent to insert/insertImage in AppDelegate"
```

---

## Task 7: `ClipStore.search(_:)` — include image clips by source app

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ClipStoreTests`:

```swift
func testSearchReturnsImageClipsBySourceAppBundleID() throws {
    let store = try makeInMemoryStore()
    // Insert an image clip with a bundleID that contains the query string
    let capture = ImageCapture(
        id: UUID(),
        pngData: makePNGData(),
        sourceApp: "com.figma.agent",
        timestamp: Date()
    )
    try store.insertImage(capture)

    // "figma" matches the bundleID fallback display name "com.figma.agent"
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
    // Image (timestamp 2) comes before text (timestamp 1)
    XCTAssertEqual(results[0].contentType, .image)
    XCTAssertEqual(results[1].contentType, .text)
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | tail -20
```

Expected: FAIL — image clips are not returned by search.

- [ ] **Step 3: Update `search(_:)` and add `resolveAppName` in `ClipStore.swift`**

Add private helper to `ClipStore`:

```swift
private func resolveAppName(for bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
          let name = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName else {
        return bundleID
    }
    return name
}
```

Replace the existing `search(_:)` method:

```swift
/// Case-insensitive search. Text clips match by content; image clips match by source app name.
/// Empty query returns all clips.
func search(_ query: String) throws -> [ClipItem] {
    guard !query.isEmpty else { return clips }
    let escaped = query.lowercased()
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")

    let textMatches = try dbQueue.read { db in
        try ClipItem
            .filter(sql: "lower(text) LIKE ? ESCAPE '\\'", arguments: ["%\(escaped)%"])
            .order(ClipItem.Columns.timestamp.desc)
            .fetchAll(db)
    }

    let queryLower = query.lowercased()
    let imageMatches = clips.filter { clip in
        clip.contentType == .image &&
        resolveAppName(for: clip.sourceApp).lowercased().contains(queryLower)
    }

    return (textMatches + imageMatches).sorted { $0.timestamp > $1.timestamp }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' -only-testing:PasteTrailTests/ClipStoreTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: include image clips in search results by source app name"
```

---

## Task 8: `ClipPopoverView` — image rows with thumbnail and async dimensions

**Files:**
- Modify: `PasteTrail/MenuBar/ClipPopoverView.swift`

No automated test — SwiftUI view changes, verify manually.

- [ ] **Step 1: Update `clipList` to pass `imagesDirectory` to `ClipRowView`**

In `ClipPopoverView`, find the `clipList` computed property:

```swift
private var clipList: some View {
    ScrollView {
        LazyVStack(spacing: 2) {
            ForEach(displayedClips) { clip in
                ClipRowView(clip: clip) {
                    closeAndPaste(clip)
                }
            }
        }
        .padding(8)
    }
    .frame(maxHeight: 360)
}
```

Replace with:

```swift
private var clipList: some View {
    ScrollView {
        LazyVStack(spacing: 2) {
            ForEach(displayedClips) { clip in
                ClipRowView(clip: clip, imagesDirectory: clipStore.imagesDirectory) {
                    closeAndPaste(clip)
                }
            }
        }
        .padding(8)
    }
    .frame(maxHeight: 360)
}
```

- [ ] **Step 2: Replace `ClipRowView` with image-aware version**

Replace the entire `ClipRowView` struct (from `private struct ClipRowView` to the final closing `}`) with:

```swift
private struct ClipRowView: View {

    let clip: ClipItem
    let imagesDirectory: URL
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var imageDimensions: String?

    private var sourceAppName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clip.sourceApp),
              let name = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName else {
            return clip.sourceApp
        }
        return name
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                badge
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    mainContent

                    HStack(spacing: 5) {
                        Text(clip.timestamp, style: .relative)
                        Circle().frame(width: 2, height: 2).foregroundStyle(.quaternary)
                        Text(sourceAppName)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color(hex: "#6D8196").opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .onHover { isHovered = $0 }
        .task(id: clip.id) {
            guard clip.contentType == .image, imageDimensions == nil,
                  let filename = clip.imagePath else { return }
            let fileURL = imagesDirectory.appendingPathComponent(filename)
            let size = await Task.detached(priority: .background) {
                NSImage(contentsOf: fileURL)?.size
            }.value
            if let size {
                imageDimensions = "\(Int(size.width)) × \(Int(size.height))"
            }
        }
    }

    // MARK: - Badge

    @ViewBuilder
    private var badge: some View {
        switch clip.contentType {
        case .text:
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary.opacity(0.5))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                )
        case .image:
            if let filename = clip.imagePath {
                AsyncImage(url: imagesDirectory.appendingPathComponent(filename)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    default:
                        imagePlaceholderBadge
                    }
                }
            } else {
                imagePlaceholderBadge
            }
        }
    }

    private var imagePlaceholderBadge: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.quaternary.opacity(0.5))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        switch clip.contentType {
        case .text:
            Text(clip.text)
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        case .image:
            Text(imageDimensions ?? "Image")
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }
}
```

- [ ] **Step 3: Build to confirm it compiles**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full test suite**

```bash
xcodebuild -scheme PasteTrailTests -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Manual smoke test**

Launch the app. Copy a screenshot (⌘⇧4), open the popover (⌘⇧V), confirm:
- Image row appears inline in the clip list
- Thumbnail badge shows the screenshot
- Dimensions string (e.g. "800 × 600") appears after a moment
- Clicking the row pastes the image into another app (e.g. Pages, Notes)
- Copy a text clip — it appears alongside the image in chronological order

- [ ] **Step 6: Commit**

```bash
git add PasteTrail/MenuBar/ClipPopoverView.swift
git commit -m "feat: render image clip rows with thumbnail badge and async dimensions"
```

---

## Done

All tasks complete. Image clipboard support is fully integrated:
- `ClipItem` carries `contentType` and `imagePath`
- `ClipboardMonitor` detects screenshots, in-app images, and Finder file copies
- `ClipStore` persists PNG files, enforces the unified cap with file cleanup, searches by source app, and pastes via TIFF
- `ClipPopoverView` renders image rows inline with lazy thumbnails and dimension labels

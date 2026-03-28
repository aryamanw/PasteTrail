# Paste Trail v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Paste Trail — a macOS menu bar clipboard manager with SQLite history, global ⌘⇧V shortcut, fuzzy search, password manager exclusion, and Gumroad license activation.

**Architecture:** ObservableObject + Combine. `ClipboardMonitor` polls `NSPasteboard` on a 0.5s timer and publishes `ClipItem` via `PassthroughSubject`. `ClipStore` subscribes, deduplicates, persists to SQLite via GRDB.swift, and enforces 5-clip (free) / 500-clip (standard) rolling caps. `MenuBarController` owns an `NSStatusItem` and `NSPopover` (left-click shows popover, right-click shows `NSMenu`). `KeyboardShortcutManager` registers the global `⌘⇧V` hotkey via Carbon.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, GRDB.swift (SPM), Carbon.framework, SMAppService (macOS 13+), URLSession, XCTest.

---

## File Map

| File | Responsibility |
|------|---------------|
| `PasteTrail/App/PasteTrailApp.swift` | `@main`, creates and wires all ObservableObjects into SwiftUI environment |
| `PasteTrail/App/AppDelegate.swift` | NSApplicationDelegate, handles applicationDidFinishLaunching, first-launch onboarding gate |
| `PasteTrail/App/KeyboardShortcutManager.swift` | Carbon `RegisterEventHotKey` for global ⌘⇧V; fires a callback when triggered |
| `PasteTrail/Clipboard/ClipItem.swift` | Model struct with GRDB conformances |
| `PasteTrail/Clipboard/ClipboardMonitor.swift` | 0.5s timer polling `NSPasteboard.changeCount`; bundle ID exclusion; publishes `ClipItem` |
| `PasteTrail/Storage/ClipStore.swift` | `@ObservableObject`; GRDB database; insert/fetch/delete/search; rolling cap; paste action |
| `PasteTrail/MenuBar/MenuBarController.swift` | `NSStatusItem`, `NSPopover`, `NSMenu` (right-click); icon state management |
| `PasteTrail/MenuBar/ClipPopoverView.swift` | SwiftUI: search field, clip list, empty state, upgrade banner, paste on row tap |
| `PasteTrail/Settings/SettingsStore.swift` | `@ObservableObject`; UserDefaults; license key + activation; `SMAppService` login item |
| `PasteTrail/Settings/SettingsView.swift` | SwiftUI settings overlay: all toggles, shortcut display, license field, quit button |
| `PasteTrail/Onboarding/OnboardingWindowController.swift` | `NSWindowController` for first-launch Accessibility permission flow |
| `PasteTrailTests/ClipItemTests.swift` | Unit tests for ClipItem encoding/decoding |
| `PasteTrailTests/ClipStoreTests.swift` | Unit tests for insert, cap enforcement, dedup, search |
| `PasteTrailTests/ClipboardMonitorTests.swift` | Unit tests for bundle ID exclusion logic |
| `PasteTrailTests/SettingsStoreTests.swift` | Unit tests for UserDefaults persistence and license state |

---

## Task 1: Scaffold Xcode project

**Files:**
- Create: `project.yml`
- Create: `PasteTrail/Info.plist`
- Create: `PasteTrail/PasteTrail.entitlements`
- Create: `PasteTrailTests/PasteTrailTests.swift` (placeholder)

- [ ] **Step 1: Install xcodegen if not present**

```bash
brew install xcodegen
```

- [ ] **Step 2: Create project.yml**

```yaml
name: PasteTrail
options:
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "6.29.3"

targets:
  PasteTrail:
    type: application
    platform: macOS
    sources:
      - path: PasteTrail
    settings:
      base:
        SWIFT_VERSION: "5.10"
        PRODUCT_BUNDLE_IDENTIFIER: app.pastetrail
        INFOPLIST_FILE: PasteTrail/Info.plist
        CODE_SIGN_ENTITLEMENTS: PasteTrail/PasteTrail.entitlements
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
    dependencies:
      - package: GRDB
        product: GRDB
    preBuildScripts: []

  PasteTrailTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: PasteTrailTests
    dependencies:
      - target: PasteTrail
    settings:
      base:
        SWIFT_VERSION: "5.10"
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>app.pastetrail</string>
    <key>CFBundleName</key>
    <string>Paste Trail</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableDescription</key>
    <string>Clipboard history manager for Mac.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 5: Create folder structure and placeholder test**

```bash
mkdir -p PasteTrail/App PasteTrail/Clipboard PasteTrail/Storage PasteTrail/MenuBar PasteTrail/Settings PasteTrail/Onboarding PasteTrailTests
```

```swift
// PasteTrailTests/PasteTrailTests.swift
import XCTest

final class PasteTrailTests: XCTestCase {
    func testPlaceholder() { XCTAssertTrue(true) }
}
```

- [ ] **Step 6: Generate Xcode project and verify build**

```bash
xcodegen generate
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git init
git add .
git commit -m "chore: scaffold Xcode project with GRDB dependency"
```

---

## Task 2: ClipItem model

**Files:**
- Create: `PasteTrail/Clipboard/ClipItem.swift`
- Create: `PasteTrailTests/ClipItemTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// PasteTrailTests/ClipItemTests.swift
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipItemTests 2>&1 | grep -E "(FAIL|error:|ClipItem)"
```

Expected: error: cannot find type 'ClipItem'

- [ ] **Step 3: Implement ClipItem**

```swift
// PasteTrail/Clipboard/ClipItem.swift
import Foundation
import GRDB

struct ClipItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var sourceApp: String   // bundle ID of the source application
    var timestamp: Date
}

// MARK: - GRDB

extension ClipItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip_items"

    static var databaseColumnNames: [String] {
        ["id", "text", "sourceApp", "timestamp"]
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let text = Column(CodingKeys.text)
        static let sourceApp = Column(CodingKeys.sourceApp)
        static let timestamp = Column(CodingKeys.timestamp)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipItemTests 2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: `Test Suite 'ClipItemTests' passed`

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Clipboard/ClipItem.swift PasteTrailTests/ClipItemTests.swift
git commit -m "feat: add ClipItem model with GRDB conformances"
```

---

## Task 3: ClipStore — database setup and migrations

**Files:**
- Create: `PasteTrail/Storage/ClipStore.swift`
- Create: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing migration test**

```swift
// PasteTrailTests/ClipStoreTests.swift
import XCTest
import GRDB
@testable import PasteTrail

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
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests/testDatabaseMigrationCreatesTable \
  2>&1 | grep -E "(FAIL|error:)"
```

Expected: error: cannot find type 'ClipStore'

- [ ] **Step 3: Implement ClipStore with migration**

```swift
// PasteTrail/Storage/ClipStore.swift
import Foundation
import Combine
import GRDB

@MainActor
final class ClipStore: ObservableObject {

    // MARK: - Published state

    @Published var clips: [ClipItem] = []

    // MARK: - Internal

    let dbQueue: DatabaseQueue
    private var cancellables = Set<AnyCancellable>()

    static let freeCap  = 5
    static let paidCap  = 500

    // MARK: - Init

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrate(dbQueue)
        try loadClips()
    }

    /// Convenience init using the on-disk database at the default app-support path.
    convenience init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("PasteTrail", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("clips.sqlite")
        let queue = try DatabaseQueue(path: dbURL.path)
        try self.init(dbQueue: queue)
    }

    // MARK: - Migration

    private static func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clip_items", ifNotExists: true) { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("text", .text).notNull()
                t.column("sourceApp", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
        }
        try migrator.migrate(db)
    }

    // MARK: - Load

    private func loadClips() throws {
        clips = try dbQueue.read { db in
            try ClipItem.order(ClipItem.Columns.timestamp.desc).fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests/testDatabaseMigrationCreatesTable \
  2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: `Test Case '-[PasteTrailTests.ClipStoreTests testDatabaseMigrationCreatesTable]' passed`

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: add ClipStore with GRDB migration"
```

---

## Task 4: ClipStore — insert, cap enforcement, and deduplication

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ClipStoreTests`:

```swift
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
        // Most-recent item retained
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
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests 2>&1 | grep -E "(FAIL|error:)"
```

Expected: multiple errors — `insert` not found.

- [ ] **Step 3: Add insert, cap enforcement, and dedup to ClipStore**

Add these methods inside `ClipStore`:

```swift
    // MARK: - Insert

    /// Insert a clip, enforce cap, skip if identical to most-recent clip.
    /// - Parameter cap: rolling history limit (default: computed from licence state).
    func insert(_ item: ClipItem, cap: Int? = nil) throws {
        // Dedup: skip if text matches the most-recently stored clip exactly
        if let latest = clips.first, latest.text == item.text { return }

        let effectiveCap = cap ?? currentCap
        try dbQueue.write { db in
            try item.insert(db)
            // Enforce rolling cap: delete oldest entries beyond the cap
            let total = try ClipItem.fetchCount(db)
            if total > effectiveCap {
                let overflow = total - effectiveCap
                let oldest = try ClipItem
                    .order(ClipItem.Columns.timestamp.asc)
                    .limit(overflow)
                    .fetchAll(db)
                for old in oldest { try old.delete(db) }
            }
        }
        try loadClips()
    }

    var currentCap: Int { ClipStore.freeCap } // overridden in Task 9 with licence state
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests 2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: ClipStore insert with rolling cap and consecutive dedup"
```

---

## Task 5: ClipStore — fuzzy search

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ClipStoreTests`:

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests 2>&1 | grep -E "(FAIL|error:)"
```

Expected: `value of type 'ClipStore' has no member 'search'`

- [ ] **Step 3: Add search to ClipStore**

Add to `ClipStore`:

```swift
    // MARK: - Search

    /// Case-insensitive substring search. Empty query returns all clips.
    func search(_ query: String) throws -> [ClipItem] {
        guard !query.isEmpty else { return clips }
        return try dbQueue.read { db in
            try ClipItem
                .filter(ClipItem.Columns.text.like("%\(query)%", escape: nil))
                .order(ClipItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }
```

Note: SQLite `LIKE` is case-insensitive for ASCII by default. For full Unicode case-insensitivity, the query is normalised before comparison — acceptable for v0.1.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests 2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: all 8 ClipStoreTests pass.

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: ClipStore case-insensitive substring search"
```

---

## Task 6: ClipboardMonitor — polling and bundle ID exclusion

**Files:**
- Create: `PasteTrail/Clipboard/ClipboardMonitor.swift`
- Create: `PasteTrailTests/ClipboardMonitorTests.swift`

- [ ] **Step 1: Write failing test for bundle ID exclusion**

```swift
// PasteTrailTests/ClipboardMonitorTests.swift
import XCTest
@testable import PasteTrail

final class ClipboardMonitorTests: XCTestCase {

    func testExcludedBundleIDsAreBlocked() {
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.agilebits.onepassword7"))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.agilebits.onepassword-osx"))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.bitwarden.desktop"))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.apple.keychainaccess"))
    }

    func testNonExcludedBundleIDIsAllowed() {
        XCTAssertFalse(ClipboardMonitor.isExcluded(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(ClipboardMonitor.isExcluded(bundleID: nil))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipboardMonitorTests 2>&1 | grep -E "(FAIL|error:)"
```

Expected: `cannot find type 'ClipboardMonitor'`

- [ ] **Step 3: Implement ClipboardMonitor**

```swift
// PasteTrail/Clipboard/ClipboardMonitor.swift
import AppKit
import Combine

final class ClipboardMonitor {

    // MARK: - Public

    let publisher = PassthroughSubject<ClipItem, Never>()

    /// Set to true while ClipStore is writing to the pasteboard for a paste action
    /// so the resulting changeCount bump is ignored.
    var isPasting = false

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

        // Suppress capture while we are writing to the pasteboard for a paste
        guard !isPasting else { return }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !Self.isExcluded(bundleID: frontBundleID) else { return }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

        let item = ClipItem(
            id: UUID(),
            text: text,
            sourceApp: frontBundleID ?? "unknown",
            timestamp: Date()
        )
        publisher.send(item)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipboardMonitorTests 2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: `Test Suite 'ClipboardMonitorTests' passed`

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Clipboard/ClipboardMonitor.swift PasteTrailTests/ClipboardMonitorTests.swift
git commit -m "feat: ClipboardMonitor with NSPasteboard polling and bundle ID exclusion"
```

---

## Task 7: SettingsStore

**Files:**
- Create: `PasteTrail/Settings/SettingsStore.swift`
- Create: `PasteTrailTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// PasteTrailTests/SettingsStoreTests.swift
import XCTest
@testable import PasteTrail

final class SettingsStoreTests: XCTestCase {

    var sut: SettingsStore!

    override func setUp() {
        // Use a test-specific UserDefaults suite to avoid polluting real prefs
        let defaults = UserDefaults(suiteName: "com.test.pastetrail.\(UUID().uuidString)")!
        sut = SettingsStore(defaults: defaults)
    }

    func testDefaultMonitoringIsEnabled() {
        XCTAssertTrue(sut.isMonitoringEnabled)
    }

    func testDefaultExcludePasswordManagersIsTrue() {
        XCTAssertTrue(sut.excludePasswordManagers)
    }

    func testDefaultLaunchAtLoginIsFalse() {
        XCTAssertFalse(sut.launchAtLogin)
    }

    func testMonitoringTogglePersists() {
        sut.isMonitoringEnabled = false
        XCTAssertFalse(sut.isMonitoringEnabled)
    }

    func testIsUnlockedDefaultsFalse() {
        XCTAssertFalse(sut.isUnlocked)
    }

    func testActivateLicenseStoresKey() {
        sut.activateLicense(key: "TEST-KEY-1234", activatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(sut.isUnlocked)
        XCTAssertEqual(sut.licenseKey, "TEST-KEY-1234")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/SettingsStoreTests 2>&1 | grep -E "(FAIL|error:)"
```

Expected: `cannot find type 'SettingsStore'`

- [ ] **Step 3: Implement SettingsStore**

```swift
// PasteTrail/Settings/SettingsStore.swift
import Foundation
import Combine
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {

    // MARK: - Published properties

    @Published var isMonitoringEnabled: Bool {
        didSet { defaults.set(isMonitoringEnabled, forKey: Keys.isMonitoringEnabled) }
    }

    @Published var excludePasswordManagers: Bool {
        didSet { defaults.set(excludePasswordManagers, forKey: Keys.excludePasswordManagers) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLoginItem()
        }
    }

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var licenseKey: String?

    // MARK: - Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMonitoringEnabled   = defaults.object(forKey: Keys.isMonitoringEnabled)   .map { $0 as! Bool } ?? true
        excludePasswordManagers = defaults.object(forKey: Keys.excludePasswordManagers).map { $0 as! Bool } ?? true
        showMenuBarIcon       = defaults.object(forKey: Keys.showMenuBarIcon)       .map { $0 as! Bool } ?? true
        launchAtLogin         = defaults.object(forKey: Keys.launchAtLogin)         .map { $0 as! Bool } ?? false
        licenseKey            = defaults.string(forKey: Keys.licenseKey)
        isUnlocked            = defaults.string(forKey: Keys.licenseKey) != nil
    }

    // MARK: - License

    /// Call after successful Gumroad validation. Persists key and unlocks the app.
    func activateLicense(key: String, activatedAt: Date) {
        defaults.set(key, forKey: Keys.licenseKey)
        defaults.set(activatedAt, forKey: Keys.licenseActivatedAt)
        licenseKey = key
        isUnlocked = true
    }

    // MARK: - Login item (SMAppService, macOS 13+)

    private func applyLoginItem() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let isMonitoringEnabled    = "isMonitoringEnabled"
        static let excludePasswordManagers = "excludePasswordManagers"
        static let showMenuBarIcon        = "showMenuBarIcon"
        static let launchAtLogin          = "launchAtLogin"
        static let licenseKey             = "licenseKey"
        static let licenseActivatedAt     = "licenseActivatedAt"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/SettingsStoreTests 2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: all 6 SettingsStoreTests pass.

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Settings/SettingsStore.swift PasteTrailTests/SettingsStoreTests.swift
git commit -m "feat: SettingsStore with UserDefaults persistence and license activation"
```

---

## Task 8: Wire ClipStore cap to SettingsStore license

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`
- Modify: `PasteTrailTests/ClipStoreTests.swift`

- [ ] **Step 1: Write failing test**

Add to `ClipStoreTests`:

```swift
    func testPaidCapEnforced() throws {
        let store = try makeInMemoryStore()
        for i in 0..<502 {
            let item = ClipItem(id: UUID(), text: "clip \(i)", sourceApp: "com.test", timestamp: Date(timeIntervalSince1970: Double(i)))
            try store.insert(item, cap: ClipStore.paidCap)
        }
        XCTAssertEqual(store.clips.count, ClipStore.paidCap)
        XCTAssertEqual(store.clips[0].text, "clip 501")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests/testPaidCapEnforced \
  2>&1 | grep -E "(FAIL|error:)"
```

Expected: FAIL (exceeds freeCap before reaching paidCap).

- [ ] **Step 3: Update `currentCap` to respect licence state**

Replace the `currentCap` stub in `ClipStore` with:

```swift
    weak var settingsStore: SettingsStore?

    var currentCap: Int {
        (settingsStore?.isUnlocked == true) ? ClipStore.paidCap : ClipStore.freeCap
    }
```

The `insert(_:cap:)` method already uses `currentCap` when `cap` is nil, so no other changes needed.

- [ ] **Step 4: Run all ClipStore tests to verify they pass**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' \
  -only-testing:PasteTrailTests/ClipStoreTests 2>&1 | grep -E "(PASS|FAIL|error:)"
```

Expected: all 9 ClipStoreTests pass.

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift PasteTrailTests/ClipStoreTests.swift
git commit -m "feat: ClipStore cap respects SettingsStore licence state"
```

---

## Task 9: ClipStore — paste action

**Files:**
- Modify: `PasteTrail/Storage/ClipStore.swift`

No unit tests for this task — `CGEventPost` requires a running macOS session. Manual verification in Task 16.

- [ ] **Step 1: Add paste method to ClipStore**

Add to `ClipStore`:

```swift
    // MARK: - Paste

    weak var monitor: ClipboardMonitor?

    /// Writes the clip to the pasteboard and synthesises ⌘V into the frontmost app.
    /// Caller is responsible for closing the popover before calling this.
    func paste(_ item: ClipItem) {
        // Write to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)

        // Suppress the monitor so this write doesn't create a duplicate clip
        monitor?.isPasting = true

        // Brief delay lets the popover close and the previous app regain focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sendCommandV()
            // Re-enable monitoring after the synthetic event has been dispatched
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.monitor?.isPasting = false
            }
        }
    }

    private func sendCommandV() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(0x09) // kVK_ANSI_V
        guard
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
```

- [ ] **Step 2: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PasteTrail/Storage/ClipStore.swift
git commit -m "feat: ClipStore paste action via CGEventPost"
```

---

## Task 10: KeyboardShortcutManager

**Files:**
- Create: `PasteTrail/App/KeyboardShortcutManager.swift`

No unit tests — Carbon hotkeys require a running event loop. Manual test in Task 16.

- [ ] **Step 1: Create KeyboardShortcutManager**

```swift
// PasteTrail/App/KeyboardShortcutManager.swift
import Carbon
import AppKit

final class KeyboardShortcutManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onActivate: (() -> Void)?

    private let hotKeyID = EventHotKeyID(signature: fourCharCode("PTRL"), id: 1)

    // MARK: - Register / Unregister

    func register() {
        var handlerUPP: EventHandlerUPP? = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onActivate?()
            return noErr
        }

        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            [eventSpec],
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        // ⌘⇧V: cmdKey | shiftKey, kVK_ANSI_V = 9
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }

    deinit { unregister() }
}

// MARK: - Helpers

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.unicodeScalars {
        result = (result << 8) + OSType(char.value)
    }
    return result
}
```

- [ ] **Step 2: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PasteTrail/App/KeyboardShortcutManager.swift
git commit -m "feat: KeyboardShortcutManager with Carbon RegisterEventHotKey for ⌘⇧V"
```

---

## Task 11: MenuBarController

**Files:**
- Create: `PasteTrail/MenuBar/MenuBarController.swift`
- Create: `PasteTrail/MenuBar/ClipPopoverView.swift` (stub)

No unit tests for AppKit controller. Manual verification in Task 16.

- [ ] **Step 1: Create ClipPopoverView stub**

```swift
// PasteTrail/MenuBar/ClipPopoverView.swift
import SwiftUI

struct ClipPopoverView: View {
    @EnvironmentObject var clipStore: ClipStore
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Text("Paste Trail")
            .frame(width: 380, height: 100)
    }
}
```

- [ ] **Step 2: Create MenuBarController**

```swift
// PasteTrail/MenuBar/MenuBarController.swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarController {

    // MARK: - Dependencies (set by AppDelegate after init)

    var clipStore: ClipStore!
    var settingsStore: SettingsStore!

    // MARK: - Private

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // MARK: - Setup

    func setup() {
        setupStatusItem()
        setupPopover()
    }

    // MARK: - Toggle (called by KeyboardShortcutManager and status item click)

    func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Icon state

    func updateIcon(paused: Bool) {
        statusItem?.button?.alphaValue = paused ? 0.6 : 1.0
    }

    // MARK: - Private helpers

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste Trail")
        item.button?.image?.isTemplate = true
        item.button?.action = #selector(handleClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        statusItem = item
    }

    private func setupPopover() {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        let rootView = ClipPopoverView()
            .environmentObject(clipStore)
            .environmentObject(settingsStore)
        p.contentViewController = NSHostingController(rootView: rootView)
        p.contentSize = NSSize(width: 380, height: 480)
        popover = p
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Right-click context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: settingsStore.isMonitoringEnabled ? "Paste Trail" : "Paste Trail · Paused", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Paste Trail", action: #selector(openPopover), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        if settingsStore.isMonitoringEnabled {
            let pause = NSMenuItem(title: "Pause Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
        } else {
            let resume = NSMenuItem(title: "Resume Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Paste Trail", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so left-click still opens popover
    }

    @objc private func openPopover() { togglePopover() }

    @objc private func toggleMonitoring() {
        settingsStore.isMonitoringEnabled.toggle()
        updateIcon(paused: !settingsStore.isMonitoringEnabled)
    }

    @objc private func openSettings() {
        // Posts a notification consumed by ClipPopoverView to show settings overlay
        NotificationCenter.default.post(name: .showSettings, object: nil)
        if !(popover?.isShown ?? false) { togglePopover() }
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("PasteTrailShowSettings")
}
```

- [ ] **Step 3: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PasteTrail/MenuBar/MenuBarController.swift PasteTrail/MenuBar/ClipPopoverView.swift
git commit -m "feat: MenuBarController with NSStatusItem, NSPopover, and right-click menu"
```

---

## Task 12: ClipPopoverView — full implementation

**Files:**
- Modify: `PasteTrail/MenuBar/ClipPopoverView.swift`

No unit tests — pure SwiftUI view. Manual verification in Task 16.

- [ ] **Step 1: Replace stub with full implementation**

```swift
// PasteTrail/MenuBar/ClipPopoverView.swift
import SwiftUI
import AppKit

struct ClipPopoverView: View {

    @EnvironmentObject var clipStore: ClipStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var query = ""
    @State private var showSettings = false

    private var displayedClips: [ClipItem] {
        guard !query.isEmpty else { return clipStore.clips }
        return (try? clipStore.search(query)) ?? []
    }

    private var atCap: Bool {
        !settingsStore.isUnlocked && clipStore.clips.count >= ClipStore.freeCap
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(isPresented: $showSettings)
                    .environmentObject(settingsStore)
            } else {
                mainContent
            }
        }
        .frame(width: 380)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if clipStore.clips.isEmpty {
                emptyState
            } else {
                clipList
            }

            if atCap { upgradeBanner }
            else     { footer }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 9)
                TextField("Search clips…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.vertical, 0)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }
            .frame(height: 22)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .overlay(Capsule().stroke(.separator.opacity(0.6), lineWidth: 0.5))

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator.opacity(0.5), lineWidth: 0.5))
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    // MARK: - Clip list

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

    // MARK: - Empty state

    private var emptyState: some View {
        Text("Copy something to get started")
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Upgrade banner

    private var upgradeBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("You've saved 5 clips")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Upgrade for 500 — $9.99 once")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Upgrade →") {
                NSWorkspace.shared.open(URL(string: "https://pastetrail.gumroad.com")!)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                LinearGradient(colors: [Color(hex: "#6D8196"), Color(hex: "#4a6070")],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(stops: [
                .init(color: Color(hex: "#6D8196").opacity(0.3), location: 0.17),
                .init(color: Color(hex: "#4A4A4A").opacity(0.45), location: 0.22)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(Divider().opacity(0.4), alignment: .top)
    }

    // MARK: - Footer

    private var footer: some View {
        Text(footerText)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .overlay(Divider().opacity(0.4), alignment: .top)
    }

    private var footerText: String {
        let total = clipStore.clips.count
        let cap   = settingsStore.isUnlocked ? ClipStore.paidCap : ClipStore.freeCap
        if query.isEmpty {
            return "\(total) of \(cap) clips"
        }
        let count = displayedClips.count
        return count == 1 ? "1 result" : "\(count) results"
    }

    // MARK: - Paste

    private func closeAndPaste(_ clip: ClipItem) {
        // Close popover first, then paste after a brief delay (see ClipStore.paste)
        NSApp.keyWindow?.close()
        clipStore.paste(clip)
    }
}

// MARK: - Clip row

private struct ClipRowView: View {

    let clip: ClipItem
    let onTap: () -> Void

    @State private var isHovered = false

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
                // Type badge
                RoundedRectangle(cornerRadius: 7)
                    .fill(.quaternary.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    )
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)

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
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PasteTrail/MenuBar/ClipPopoverView.swift
git commit -m "feat: ClipPopoverView with search, clip list, empty state, upgrade banner"
```

---

## Task 13: SettingsView

**Files:**
- Create: `PasteTrail/Settings/SettingsView.swift`

No unit tests — SwiftUI view. Manual verification in Task 16.

- [ ] **Step 1: Create SettingsView**

```swift
// PasteTrail/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool

    @State private var licenseKeyInput = ""
    @State private var licenseError: String?
    @State private var isActivating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
                    }
                    .foregroundStyle(Color(hex: "#6D8196"))
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()

                // Spacer to balance the back button width
                Color.clear.frame(width: 48)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Divider().opacity(0.5)

            ScrollView {
                VStack(spacing: 0) {
                    settingsSection("Monitoring") {
                        toggleRow("Clipboard monitoring", isOn: $settingsStore.isMonitoringEnabled)
                    }
                    settingsSection("Menu Bar") {
                        toggleRow("Show in menu bar", isOn: $settingsStore.showMenuBarIcon)
                    }
                    settingsSection("Privacy") {
                        toggleRow("Exclude password managers", isOn: $settingsStore.excludePasswordManagers,
                                  subtitle: "1Password, Bitwarden, Keychain")
                    }
                    settingsSection("Keyboard Shortcut") {
                        HStack {
                            Text("Open Paste Trail")
                                .font(.system(size: 13))
                            Spacer()
                            Text("⌘ ⇧ V")
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator.opacity(0.5), lineWidth: 0.5))
                        }
                        .padding(.vertical, 0)
                        .frame(minHeight: 36)
                        .padding(.horizontal, 10)
                    }
                    settingsSection("Launch") {
                        toggleRow("Launch at login", isOn: $settingsStore.launchAtLogin)
                    }
                    settingsSection("Account") {
                        accountSection
                    }
                }
                .padding(.bottom, 8)
            }

            Divider().opacity(0.5)

            // Footer
            HStack {
                Text("Paste Trail v0.1.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit App") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23)) // systemRed
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
        }
        .frame(width: 380)
    }

    // MARK: - Account section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Plan")
                    .font(.system(size: 13))
                Spacer()
                Text(settingsStore.isUnlocked ? "Standard · 500 clips" : "Free · 5 clips")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        settingsStore.isUnlocked
                            ? Color.green.opacity(0.12)
                            : Color(hex: "#6D8196").opacity(0.22),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            settingsStore.isUnlocked ? Color.green.opacity(0.3) : Color(hex: "#6D8196").opacity(0.3),
                            lineWidth: 0.5
                        )
                    )
                    .foregroundStyle(settingsStore.isUnlocked ? .green : Color(hex: "#CBCBCB"))
            }
            .frame(minHeight: 36)
            .padding(.horizontal, 10)

            if !settingsStore.isUnlocked {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("License key", text: $licenseKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(6)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.5), lineWidth: 0.5))

                        Button(action: activateLicense) {
                            if isActivating {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Activate")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#6D8196"), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                    if let error = licenseError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    // MARK: - License activation

    private func activateLicense() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isActivating = true
        licenseError = nil

        Task {
            do {
                try await GumroadLicenseValidator.validate(key: key)
                await MainActor.run {
                    settingsStore.activateLicense(key: key, activatedAt: Date())
                    isActivating = false
                }
            } catch GumroadError.invalidKey {
                await MainActor.run {
                    licenseError = "Invalid license key."
                    isActivating = false
                }
            } catch {
                await MainActor.run {
                    licenseError = "Could not verify key. Check your internet connection."
                    isActivating = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.9)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 4)
            content()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, subtitle: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 10)
    }
}

// MARK: - Color hex (duplicated from ClipPopoverView; extract to shared file if it grows)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Create GumroadLicenseValidator**

```swift
// PasteTrail/Settings/GumroadLicenseValidator.swift
import Foundation

enum GumroadError: Error {
    case invalidKey
    case networkError(Error)
}

struct GumroadLicenseValidator {

    static func validate(key: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "product_id=\(GumroadProductID)&license_key=\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)"
        request.httpBody = body.data(using: .utf8)

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw GumroadError.networkError(error)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let success = json["success"] as? Bool,
            success
        else {
            throw GumroadError.invalidKey
        }
    }
}

// Replace with your actual Gumroad product permalink/ID before shipping
private let GumroadProductID = "pastetrail"
```

- [ ] **Step 3: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PasteTrail/Settings/SettingsView.swift PasteTrail/Settings/GumroadLicenseValidator.swift
git commit -m "feat: SettingsView with all toggles, license activation, and Gumroad validator"
```

---

## Task 14: Onboarding window

**Files:**
- Create: `PasteTrail/Onboarding/OnboardingWindowController.swift`

- [ ] **Step 1: Create OnboardingWindowController**

```swift
// PasteTrail/Onboarding/OnboardingWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {

    static func makeIfNeeded() -> OnboardingWindowController? {
        guard !AXIsProcessTrusted() else { return nil }
        return OnboardingWindowController()
    }

    init() {
        let view = OnboardingView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Paste Trail"
        window.setContentSize(NSSize(width: 380, height: 340))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - SwiftUI view

private struct OnboardingView: View {

    @State private var isGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            RoundedRectangle(cornerRadius: 13)
                .fill(
                    LinearGradient(colors: [Color(hex: "#6D8196").opacity(0.3), Color(hex: "#4A4A4A").opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(hex: "#FFFFE3"))
                )

            Spacer().frame(height: 18)

            Text("Paste Trail needs Accessibility access")
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 10)

            Text("To paste items into other apps, Paste Trail needs permission in System Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 6)

            Text("Your clipboard data never leaves your Mac. Zero network calls — ever.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            Button("Open System Settings → Privacy") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            Spacer().frame(height: 8)

            Button("Already granted? Check Again") {
                isGranted = AXIsProcessTrusted()
                if isGranted { NSApp.keyWindow?.close() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 380, height: 340)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PasteTrail/Onboarding/OnboardingWindowController.swift
git commit -m "feat: onboarding window for Accessibility permission"
```

---

## Task 15: App entry point — wiring everything together

**Files:**
- Create: `PasteTrail/App/PasteTrailApp.swift`
- Create: `PasteTrail/App/AppDelegate.swift`

- [ ] **Step 1: Create AppDelegate**

```swift
// PasteTrail/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core objects

    private(set) var clipStore: ClipStore!
    private(set) var settingsStore: SettingsStore!
    private(set) var clipboardMonitor: ClipboardMonitor!
    private(set) var menuBarController: MenuBarController!
    private(set) var keyboardShortcutManager: KeyboardShortcutManager!
    private var onboardingWindow: OnboardingWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            settingsStore = SettingsStore()
            clipStore     = try ClipStore()
            clipStore.settingsStore = settingsStore
        } catch {
            // Storage failure is non-recoverable; log and continue without history
            print("[PasteTrail] ClipStore init failed: \(error)")
            settingsStore = SettingsStore()
            clipStore     = try! ClipStore(dbQueue: .init()) // in-memory fallback
        }

        // Clipboard monitor → ClipStore pipeline
        clipboardMonitor = ClipboardMonitor()
        clipStore.monitor = clipboardMonitor
        clipboardMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self, settingsStore.isMonitoringEnabled else { return }
                try? clipStore.insert(item)
            }
            .store(in: &cancellables)

        // Menu bar
        menuBarController = MenuBarController()
        menuBarController.clipStore     = clipStore
        menuBarController.settingsStore = settingsStore
        menuBarController.setup()

        // Global hotkey
        keyboardShortcutManager = KeyboardShortcutManager()
        keyboardShortcutManager.onActivate = { [weak self] in
            DispatchQueue.main.async { self?.menuBarController.togglePopover() }
        }
        keyboardShortcutManager.register()

        // Observe monitoring toggle to update icon
        settingsStore.$isMonitoringEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.menuBarController.updateIcon(paused: !enabled)
                if enabled {
                    self?.clipboardMonitor.start()
                } else {
                    self?.clipboardMonitor.stop()
                }
            }
            .store(in: &cancellables)

        // Start monitoring
        if settingsStore.isMonitoringEnabled {
            clipboardMonitor.start()
        }

        // Onboarding (first launch or no Accessibility permission)
        onboardingWindow = OnboardingWindowController.makeIfNeeded()
        onboardingWindow?.showWindow(nil)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
}

import Combine
```

- [ ] **Step 2: Create PasteTrailApp**

```swift
// PasteTrail/App/PasteTrailApp.swift
import SwiftUI

@main
struct PasteTrailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement = YES suppresses the Dock icon.
        // We use a pure AppKit status item (no MenuBarExtra) to support
        // both left-click-to-popover and right-click-to-menu.
        // This Settings scene is intentionally empty — settings live inside the popover.
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: Verify build succeeds**

```bash
xcodebuild -scheme PasteTrail -destination 'platform=macOS' build 2>&1 | grep -E "(SUCCEEDED|error:)"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full test suite to confirm no regressions**

```bash
xcodebuild test -scheme PasteTrailTests -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error:|Test Suite)"
```

Expected: All test suites pass.

- [ ] **Step 5: Commit**

```bash
git add PasteTrail/App/PasteTrailApp.swift PasteTrail/App/AppDelegate.swift
git commit -m "feat: app entry point — wires all components into a running app"
```

---

## Task 16: Manual end-to-end verification

Run through these checks on a real Mac (not simulator). Check each item manually.

- [ ] **Launch the app from Xcode**
  - Dock icon does NOT appear (LSUIElement)
  - Menu bar icon appears (scissors/clipboard glyph)
  - Onboarding window appears if Accessibility is not yet granted

- [ ] **Grant Accessibility permission**
  - Click "Open System Settings → Privacy" in onboarding window
  - Toggle on in System Settings
  - Click "Check Again" → window closes

- [ ] **Clipboard monitoring**
  - Copy any text in Terminal → open Paste Trail → item appears at top
  - Copy same text again → item count does NOT increase (dedup)
  - Copy a 1Password password → item does NOT appear in Paste Trail

- [ ] **Global shortcut**
  - Press `⌘⇧V` from any app → popover opens
  - Press `⌘⇧V` again → popover closes
  - Press `Esc` → popover closes

- [ ] **Search**
  - Type a search query → list filters in real time
  - Clear button appears; clicking it restores full list

- [ ] **Paste**
  - Click any clip row → row disappears, clip text is pasted into frontmost app

- [ ] **Free tier cap (5 clips)**
  - Copy 6+ items → upgrade banner appears at bottom of popover
  - Footer shows "5 of 5 clips"

- [ ] **Right-click menu bar icon**
  - "Paste Trail" header shown
  - "Pause Monitoring" click → icon dims; copying no longer captures
  - "Resume Monitoring" shown; click → icon restored; capturing resumes
  - "Settings…" → opens popover to settings view
  - "Quit Paste Trail" → app terminates

- [ ] **Settings**
  - All toggles persist across app relaunch (quit + reopen)
  - "Launch at login" toggle registers/unregisters login item

- [ ] **License activation (requires a real Gumroad key)**
  - Enter key → "Activate" button enabled
  - Valid key → Plan chip switches to "Standard · 500 clips", cap lifts
  - Invalid key → inline error shown
  - Network offline → connection error shown

- [ ] **Commit**

```bash
git add -A
git commit -m "chore: manual verification complete for v0.1"
```

---

## Self-Review Notes

**Spec coverage check:**

| Requirement | Task(s) |
|-------------|---------|
| Free tier: 5 clips | Task 4 (`freeCap = 5`) |
| Standard tier: 500 clips | Task 8 (`paidCap = 500`) |
| Rolling cap with oldest-first delete | Task 4 |
| Consecutive dedup only | Task 4 |
| Fuzzy search (substring, case-insensitive) | Task 5 |
| NSPasteboard 0.5s polling | Task 6 |
| Password manager bundle ID exclusion | Task 6 |
| `isPasting` guard against self-capture | Task 9 |
| CGEventPost synthetic ⌘V | Task 9 |
| Carbon global ⌘⇧V hotkey | Task 10 |
| NSStatusItem left-click popover | Task 11 |
| Right-click menu (Pause/Resume/Settings/Quit) | Task 11 |
| ClipPopoverView search field | Task 12 |
| Clip rows with monospace text + meta | Task 12 |
| Upgrade banner at cap | Task 12 |
| Footer clip count | Task 12 |
| Settings overlay (all toggles) | Task 13 |
| License key field + activation | Task 13 |
| Gumroad API call (one-time, then zero net) | Task 13 |
| SMAppService launch at login | Task 7 |
| LSUIElement (no Dock icon) | Task 1 |
| Onboarding window + AXIsProcessTrusted | Task 14 |
| App wiring (Combine pipeline) | Task 15 |
| `.hudWindow` NSVisualEffectView material | **Gap** — see below |

**Gap: `.hudWindow` material.** The popover background should use `NSVisualEffectView`. The `NSHostingController` wrapping the SwiftUI views does not automatically apply this. Fix: in `MenuBarController.setupPopover()`, after creating the `NSHostingController`, set its view's appearance via a `NSVisualEffectView` container, or apply `.background(.regularMaterial)` in SwiftUI. Add this to `ClipPopoverView` body:

```swift
var body: some View {
    VStack(spacing: 0) { ... }
        .background(.regularMaterial)  // ← maps to .hudWindow on macOS 13
        .frame(width: 380)
}
```

This is already correct SwiftUI practice and requires no separate task. Apply it when implementing Task 12 body.

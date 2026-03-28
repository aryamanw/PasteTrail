import Foundation
import Combine
import GRDB
import AppKit

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

    // MARK: - Insert

    /// Insert a clip, enforce rolling cap, skip if identical to the most-recent clip.
    /// - Parameter cap: override for the effective cap (used in tests). Defaults to currentCap.
    func insert(_ item: ClipItem, cap: Int? = nil) throws {
        // Dedup: skip if text matches the most-recently stored clip exactly
        if let latest = clips.first, latest.text == item.text { return }

        let effectiveCap = cap ?? currentCap
        try dbQueue.write { db in
            try item.insert(db)
            // Enforce rolling cap: delete oldest entries beyond the limit
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

    weak var settingsStore: SettingsStore?

    var currentCap: Int {
        (settingsStore?.isUnlocked == true) ? ClipStore.paidCap : ClipStore.freeCap
    }

    // MARK: - Search

    /// Case-insensitive substring search. Empty query returns all clips.
    func search(_ query: String) throws -> [ClipItem] {
        guard !query.isEmpty else { return clips }
        let normalizedQuery = query.lowercased()
        return try dbQueue.read { db in
            try ClipItem
                .filter(sql: "lower(text) LIKE ?", arguments: ["%\(normalizedQuery)%"])
                .order(ClipItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Paste

    weak var monitor: ClipboardMonitor?

    /// Writes the clip to the pasteboard and synthesises ⌘V into the frontmost app.
    /// The popover must be closed by the caller before this is invoked.
    func paste(_ item: ClipItem) {
        guard AXIsProcessTrusted() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)

        monitor?.isPasting = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
            self?.sendCommandV()
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
            self?.monitor?.isPasting = false
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
}

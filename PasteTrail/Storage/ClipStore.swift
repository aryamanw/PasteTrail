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
    let imagesDirectory: URL
    private var cancellables = Set<AnyCancellable>()

    static let freeCap  = 5
    static let paidCap  = 500

    // MARK: - Init

    init(dbQueue: DatabaseQueue, imagesDirectory: URL) throws {
        self.dbQueue = dbQueue
        self.imagesDirectory = imagesDirectory
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
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
        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try self.init(dbQueue: queue, imagesDirectory: imagesDir)
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
        migrator.registerMigration("v2") { db in
            try db.alter(table: "clip_items") { t in
                t.add(column: "contentType", .text).notNull().defaults(to: "text")
                t.add(column: "imagePath", .text)
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
        // Dedup: only skip consecutive identical text clips
        if item.contentType == .text, let latest = clips.first,
           latest.contentType == .text, latest.text == item.text { return }

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
                for old in oldest {
                    deleteImageFileIfNeeded(old)
                    try old.delete(db)
                }
            }
        }
        try loadClips()
    }

    /// Writes PNG data to disk and records an image clip. File is written only after the
    /// DB transaction commits successfully to avoid orphaned files on rollback.
    func insertImage(_ capture: ImageCapture, cap: Int? = nil) throws {
        let filename = "\(capture.id.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(filename)

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
        // Write file after DB commit — a failed write here leaves a dangling row but
        // is recoverable (thumbnail shows placeholder); an orphaned file from a pre-commit
        // write is not bounded and harder to detect.
        try capture.pngData.write(to: fileURL)
        try loadClips()
    }

    private func deleteImageFileIfNeeded(_ item: ClipItem) {
        guard item.contentType == .image, let filename = item.imagePath else { return }
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    weak var settingsStore: SettingsStore?

    var currentCap: Int {
        (settingsStore?.isUnlocked == true) ? ClipStore.paidCap : ClipStore.freeCap
    }

    // MARK: - Search

    /// Case-insensitive substring search. Empty query returns all clips.
    func search(_ query: String) throws -> [ClipItem] {
        guard !query.isEmpty else { return clips }
        let escaped = query.lowercased()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try dbQueue.read { db in
            try ClipItem
                .filter(sql: "lower(text) LIKE ? ESCAPE '\\'", arguments: ["%\(escaped)%"])
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

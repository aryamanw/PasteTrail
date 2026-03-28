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

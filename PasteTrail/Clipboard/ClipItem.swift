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

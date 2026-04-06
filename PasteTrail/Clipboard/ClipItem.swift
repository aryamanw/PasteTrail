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
    var isPinned: Bool = false
}

// MARK: - GRDB

extension ClipItem {
    static let databaseTableName = "clip_items"

    static var databaseColumnNames: [String] {
        ["id", "contentType", "text", "imagePath", "sourceApp", "timestamp", "isPinned"]
    }

    enum Columns {
        static let id          = Column(CodingKeys.id)
        static let contentType = Column(CodingKeys.contentType)
        static let text        = Column(CodingKeys.text)
        static let imagePath   = Column(CodingKeys.imagePath)
        static let sourceApp   = Column(CodingKeys.sourceApp)
        static let timestamp   = Column(CodingKeys.timestamp)
        static let isPinned    = Column(CodingKeys.isPinned)
    }
}

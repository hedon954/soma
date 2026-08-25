import Foundation
import SwiftData

@Model
final class ExternalSyncCursor {
    var id: UUID
    var source: String
    var stream: String
    var cursorData: Data?
    var updatedAt: Date

    init(
        source: String,
        stream: String,
        cursorData: Data? = nil,
        updatedAt: Date = .now
    ) {
        id = UUID()
        self.source = source
        self.stream = stream
        self.cursorData = cursorData
        self.updatedAt = updatedAt
    }
}

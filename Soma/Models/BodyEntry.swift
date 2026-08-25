import Foundation
import SwiftData

@Model
final class BodyEntry: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var date: Date
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var notes: String
    var imagePath: String?
    var mediaAttachmentsData: Data = Data()
    var analysis: String
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    init(
        date: Date = .now,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        waist: Double? = nil,
        notes: String = "",
        imagePath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        analysis: String = "",
        externalSource: String? = nil,
        externalID: String? = nil,
        sourceTurnID: UUID? = nil,
        sourceSessionID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        self.weight = weight
        self.bodyFat = bodyFat
        self.waist = waist
        self.notes = notes
        self.imagePath = imagePath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        self.analysis = analysis
        self.externalSource = externalSource
        self.externalID = externalID
        self.sourceTurnID = sourceTurnID
        self.sourceSessionID = sourceSessionID
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: imagePath == nil ? .none : .image,
                legacyPath: imagePath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            imagePath = newValue.first(where: { $0.kind == .image })?.path
        }
    }
}

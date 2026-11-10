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
    /// HealthKit `HKSourceRevision.source.name`；手动记录为 nil。
    var sourceName: String?
    /// HealthKit `HKSourceRevision.source.bundleIdentifier`；手动记录为 nil。
    var sourceBundleIdentifier: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?
    /// 健康日记录各指标的真实采样证据（UUID、时间、来源）。旧库默认为空。
    var healthDayEvidenceData: Data = Data()

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
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
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
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
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

    /// 来自 Apple 健康的体重或体脂样本（可再同步，不进备份/导出）。
    var isHealthImported: Bool {
        externalSource == BodyMassImportIdentity.externalSource
    }

    var healthDayEvidence: BodyHealthDayEvidence? {
        get { BodyHealthDayEvidence.decode(healthDayEvidenceData) }
        set { healthDayEvidenceData = newValue?.encode() ?? Data() }
    }
}

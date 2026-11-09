import Foundation
import SwiftData

enum BodyMassRecordStore {
    @MainActor
    static func apply(_ delta: BodyMassSyncDelta, in context: ModelContext) throws {
        let source: String? = BodyMassImportIdentity.externalSource
        for uuid in delta.deletedSampleUUIDs {
            let externalID: String? = BodyMassImportIdentity.bodyMassExternalID(sampleUUID: uuid)
            var descriptor = FetchDescriptor<BodyEntry>(
                predicate: #Predicate {
                    $0.externalSource == source && $0.externalID == externalID
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                context.delete(existing)
            }
        }

        for sample in delta.upserts {
            guard sample.weightKilograms.isFinite, sample.weightKilograms > 0 else { continue }
            let externalID: String? = BodyMassImportIdentity.bodyMassExternalID(sampleUUID: sample.sampleUUID)
            var descriptor = FetchDescriptor<BodyEntry>(
                predicate: #Predicate {
                    $0.externalSource == source && $0.externalID == externalID
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.date = sample.date
                existing.weight = sample.weightKilograms
                // 体重样本行不写入/不清空体脂；体脂由独立样本维护。
                existing.sourceName = sample.sourceName
                existing.sourceBundleIdentifier = sample.sourceBundleIdentifier
            } else {
                let entry = BodyEntry(
                    date: sample.date,
                    weight: sample.weightKilograms,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyMassExternalID(sampleUUID: sample.sampleUUID),
                    sourceName: sample.sourceName,
                    sourceBundleIdentifier: sample.sourceBundleIdentifier
                )
                context.insert(entry)
                try BusinessIDAllocator.assign(entry, namespace: "body", in: context)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    static func applyBodyFat(_ delta: BodyFatSyncDelta, in context: ModelContext) throws {
        let source: String? = BodyMassImportIdentity.externalSource
        for uuid in delta.deletedSampleUUIDs {
            let externalID: String? = BodyMassImportIdentity.bodyFatExternalID(sampleUUID: uuid)
            var descriptor = FetchDescriptor<BodyEntry>(
                predicate: #Predicate {
                    $0.externalSource == source && $0.externalID == externalID
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                context.delete(existing)
            }
        }

        for sample in delta.upserts {
            guard sample.bodyFatPercent.isFinite,
                  sample.bodyFatPercent > 0,
                  sample.bodyFatPercent <= 100
            else { continue }
            let externalID: String? = BodyMassImportIdentity.bodyFatExternalID(sampleUUID: sample.sampleUUID)
            var descriptor = FetchDescriptor<BodyEntry>(
                predicate: #Predicate {
                    $0.externalSource == source && $0.externalID == externalID
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.date = sample.date
                existing.bodyFat = sample.bodyFatPercent
                // 体脂样本行不写入/不清空体重。
                existing.sourceName = sample.sourceName
                existing.sourceBundleIdentifier = sample.sourceBundleIdentifier
            } else {
                let entry = BodyEntry(
                    date: sample.date,
                    weight: nil,
                    bodyFat: sample.bodyFatPercent,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyFatExternalID(sampleUUID: sample.sampleUUID),
                    sourceName: sample.sourceName,
                    sourceBundleIdentifier: sample.sourceBundleIdentifier
                )
                context.insert(entry)
                try BusinessIDAllocator.assign(entry, namespace: "body", in: context)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    static func loadAnchorData(in context: ModelContext) throws -> Data? {
        try loadAnchorData(stream: BodyMassImportIdentity.bodyMassStream, in: context)
    }

    @MainActor
    static func saveAnchorData(_ data: Data?, in context: ModelContext) throws {
        try saveAnchorData(data, stream: BodyMassImportIdentity.bodyMassStream, in: context)
    }

    @MainActor
    static func loadBodyFatAnchorData(in context: ModelContext) throws -> Data? {
        try loadAnchorData(stream: BodyMassImportIdentity.bodyFatStream, in: context)
    }

    @MainActor
    static func saveBodyFatAnchorData(_ data: Data?, in context: ModelContext) throws {
        try saveAnchorData(data, stream: BodyMassImportIdentity.bodyFatStream, in: context)
    }

    @MainActor
    private static func loadAnchorData(stream: String, in context: ModelContext) throws -> Data? {
        let source = BodyMassImportIdentity.cursorSource
        let streamValue = stream
        var descriptor = FetchDescriptor<ExternalSyncCursor>(
            predicate: #Predicate {
                $0.source == source && $0.stream == streamValue
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.cursorData
    }

    @MainActor
    private static func saveAnchorData(_ data: Data?, stream: String, in context: ModelContext) throws {
        let source = BodyMassImportIdentity.cursorSource
        let streamValue = stream
        var descriptor = FetchDescriptor<ExternalSyncCursor>(
            predicate: #Predicate {
                $0.source == source && $0.stream == streamValue
            }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.cursorData = data
            existing.updatedAt = .now
        } else {
            context.insert(
                ExternalSyncCursor(
                    source: BodyMassImportIdentity.cursorSource,
                    stream: stream,
                    cursorData: data
                )
            )
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

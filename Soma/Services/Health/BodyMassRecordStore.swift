import Foundation
import SwiftData

enum BodyMassRecordStore {
    @MainActor
    static func apply(_ delta: BodyMassSyncDelta, in context: ModelContext) throws {
        let source: String? = BodyMassImportIdentity.externalSource
        for uuid in delta.deletedSampleUUIDs {
            let externalID: String? = BodyMassImportIdentity.externalID(sampleUUID: uuid)
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
            let externalID: String? = BodyMassImportIdentity.externalID(sampleUUID: sample.sampleUUID)
            var descriptor = FetchDescriptor<BodyEntry>(
                predicate: #Predicate {
                    $0.externalSource == source && $0.externalID == externalID
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.date = sample.date
                existing.weight = sample.weightKilograms
                existing.sourceName = sample.sourceName
                existing.sourceBundleIdentifier = sample.sourceBundleIdentifier
            } else {
                let entry = BodyEntry(
                    date: sample.date,
                    weight: sample.weightKilograms,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.externalID(sampleUUID: sample.sampleUUID),
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
        let source = BodyMassImportIdentity.cursorSource
        let stream = BodyMassImportIdentity.cursorStream
        var descriptor = FetchDescriptor<ExternalSyncCursor>(
            predicate: #Predicate {
                $0.source == source && $0.stream == stream
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.cursorData
    }

    @MainActor
    static func saveAnchorData(_ data: Data?, in context: ModelContext) throws {
        let source = BodyMassImportIdentity.cursorSource
        let stream = BodyMassImportIdentity.cursorStream
        var descriptor = FetchDescriptor<ExternalSyncCursor>(
            predicate: #Predicate {
                $0.source == source && $0.stream == stream
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
                    stream: BodyMassImportIdentity.cursorStream,
                    cursorData: data
                )
            )
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

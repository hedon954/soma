import Foundation
import SwiftData

enum BodyMassRecordStore {
    @MainActor
    static func apply(
        _ delta: BodyMassSyncDelta,
        in context: ModelContext,
        calendar: Calendar = .current,
        resample: BodyMassDayResampleSet = BodyMassDayResampleSet()
    ) throws {
        try BodyMassDailyRecordStore.applyMass(
            delta,
            in: context,
            calendar: calendar,
            resample: resample
        )
    }

    @MainActor
    static func applyBodyFat(
        _ delta: BodyFatSyncDelta,
        in context: ModelContext,
        calendar: Calendar = .current,
        resample: BodyMassDayResampleSet = BodyMassDayResampleSet()
    ) throws {
        try BodyMassDailyRecordStore.applyBodyFat(
            delta,
            in: context,
            calendar: calendar,
            resample: resample
        )
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

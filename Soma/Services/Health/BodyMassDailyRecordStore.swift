import Foundation
import SwiftData

struct BodyMassDayResampleSet: Equatable, Sendable {
    var weightsByDay: [String: [BodyMassSampleImport]] = [:]
    var bodyFatByDay: [String: [BodyFatSampleImport]] = [:]
}

enum BodyMassDailyRecordStore {
    @MainActor
    static func foldLegacySampleRowsIfNeeded(
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let source: String? = BodyMassImportIdentity.externalSource
        let imported = try context.fetch(
            FetchDescriptor<BodyEntry>(
                predicate: #Predicate { $0.externalSource == source }
            )
        )
        let leftovers = imported.filter {
            BodyMassImportIdentity.isLegacySampleExternalID($0.externalID)
        }
        guard !leftovers.isEmpty else { return }

        var grouped: [String: [BodyEntry]] = [:]
        for entry in leftovers {
            let key = BodyMassDayKey.dayKey(for: entry.date, calendar: calendar)
            grouped[key, default: []].append(entry)
        }

        for (dayKey, rows) in grouped {
            let record = try dayRecord(
                dayKey: dayKey,
                in: context,
                calendar: calendar,
                createIfNeeded: true
            )
            var evidence = record.healthDayEvidence ?? emptyEvidence(
                dayKey: dayKey,
                calendar: calendar
            )

            let weightRows = rows.filter {
                $0.externalID?.hasPrefix(BodyMassImportIdentity.bodyMassExternalIDPrefix) == true
                    && validWeight($0.weight)
            }
            if let winner = latestLegacy(weightRows) {
                let candidate = metricEvidence(from: winner, value: winner.weight ?? 0)
                if evidence.weight.map({ !BodyHealthDayEvidenceCodec.isLater(
                    date: candidate.date,
                    uuid: candidate.sampleUUID,
                    than: $0
                ) }) != true {
                    evidence.weight = candidate
                }
            }

            let fatRows = rows.filter {
                $0.externalID?.hasPrefix(BodyMassImportIdentity.bodyFatExternalIDPrefix) == true
                    && validBodyFat($0.bodyFat)
            }
            if let winner = latestLegacy(fatRows) {
                let candidate = metricEvidence(from: winner, value: winner.bodyFat ?? 0)
                if evidence.bodyFat.map({ !BodyHealthDayEvidenceCodec.isLater(
                    date: candidate.date,
                    uuid: candidate.sampleUUID,
                    than: $0
                ) }) != true {
                    evidence.bodyFat = candidate
                }
            }

            apply(evidence, to: record, calendar: calendar)
            for row in rows where row.id != record.id {
                context.delete(row)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    static func applyMass(
        _ delta: BodyMassSyncDelta,
        in context: ModelContext,
        calendar: Calendar = .current,
        resample: BodyMassDayResampleSet = BodyMassDayResampleSet()
    ) throws {
        try foldLegacySampleRowsIfNeeded(in: context, calendar: calendar)
        for sample in delta.upserts {
            try upsertWeight(sample, in: context, calendar: calendar)
        }
        for uuid in delta.deletedSampleUUIDs {
            try applyWeightDeletion(
                uuid,
                in: context,
                calendar: calendar,
                resample: resample
            )
        }
        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    static func applyBodyFat(
        _ delta: BodyFatSyncDelta,
        in context: ModelContext,
        calendar: Calendar = .current,
        resample: BodyMassDayResampleSet = BodyMassDayResampleSet()
    ) throws {
        try foldLegacySampleRowsIfNeeded(in: context, calendar: calendar)
        for sample in delta.upserts {
            try upsertBodyFat(sample, in: context, calendar: calendar)
        }
        for uuid in delta.deletedSampleUUIDs {
            try applyBodyFatDeletion(
                uuid,
                in: context,
                calendar: calendar,
                resample: resample
            )
        }
        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    static func dayKeysNeedingWeightResample(
        deletedSampleUUIDs: [UUID],
        in context: ModelContext
    ) throws -> [String] {
        try dayKeys(
            in: context,
            matching: { evidence, uuid in evidence.weight?.sampleUUID == uuid },
            deletedSampleUUIDs: deletedSampleUUIDs
        )
    }

    @MainActor
    static func dayKeysNeedingBodyFatResample(
        deletedSampleUUIDs: [UUID],
        in context: ModelContext
    ) throws -> [String] {
        try dayKeys(
            in: context,
            matching: { evidence, uuid in evidence.bodyFat?.sampleUUID == uuid },
            deletedSampleUUIDs: deletedSampleUUIDs
        )
    }

    @MainActor
    private static func upsertWeight(
        _ sample: BodyMassSampleImport,
        in context: ModelContext,
        calendar: Calendar
    ) throws {
        guard validWeight(sample.weightKilograms) else { return }
        let dayKey = BodyMassDayKey.dayKey(for: sample.date, calendar: calendar)
        let record = try dayRecord(
            dayKey: dayKey,
            in: context,
            calendar: calendar,
            createIfNeeded: true
        )
        var evidence = record.healthDayEvidence ?? emptyEvidence(
            dayKey: dayKey,
            calendar: calendar
        )
        if let existing = evidence.weight,
           !BodyHealthDayEvidenceCodec.isLater(
               date: sample.date,
               uuid: sample.sampleUUID,
               than: existing
           )
        {
            return
        }
        evidence.weight = BodyHealthDayMetricEvidence(
            sampleUUID: sample.sampleUUID,
            date: sample.date,
            value: sample.weightKilograms,
            sourceName: sample.sourceName,
            sourceBundleIdentifier: sample.sourceBundleIdentifier
        )
        apply(evidence, to: record, calendar: calendar)
    }

    @MainActor
    private static func upsertBodyFat(
        _ sample: BodyFatSampleImport,
        in context: ModelContext,
        calendar: Calendar
    ) throws {
        guard validBodyFat(sample.bodyFatPercent) else { return }
        let dayKey = BodyMassDayKey.dayKey(for: sample.date, calendar: calendar)
        let record = try dayRecord(
            dayKey: dayKey,
            in: context,
            calendar: calendar,
            createIfNeeded: true
        )
        var evidence = record.healthDayEvidence ?? emptyEvidence(
            dayKey: dayKey,
            calendar: calendar
        )
        if let existing = evidence.bodyFat,
           !BodyHealthDayEvidenceCodec.isLater(
               date: sample.date,
               uuid: sample.sampleUUID,
               than: existing
           )
        {
            return
        }
        evidence.bodyFat = BodyHealthDayMetricEvidence(
            sampleUUID: sample.sampleUUID,
            date: sample.date,
            value: sample.bodyFatPercent,
            sourceName: sample.sourceName,
            sourceBundleIdentifier: sample.sourceBundleIdentifier
        )
        apply(evidence, to: record, calendar: calendar)
    }

    @MainActor
    private static func applyWeightDeletion(
        _ uuid: UUID,
        in context: ModelContext,
        calendar: Calendar,
        resample: BodyMassDayResampleSet
    ) throws {
        guard let record = try healthDayRecord(
            in: context,
            where: { $0.weight?.sampleUUID == uuid }
        ), let dayKey = dayKey(for: record), let samples = resample.weightsByDay[dayKey] else { return }
        var evidence = record.healthDayEvidence ?? emptyEvidence(
            dayKey: dayKey,
            calendar: calendar
        )
        let remaining = samples.filter {
            $0.sampleUUID != uuid
                && validWeight($0.weightKilograms)
                && BodyMassDayKey.dayKey(for: $0.date, calendar: calendar) == dayKey
        }
        if let winner = BodyHealthDayEvidenceCodec.latestMetric(
            in: remaining,
            date: { $0.date },
            uuid: { $0.sampleUUID }
        ) {
            evidence.weight = BodyHealthDayMetricEvidence(
                sampleUUID: winner.sampleUUID,
                date: winner.date,
                value: winner.weightKilograms,
                sourceName: winner.sourceName,
                sourceBundleIdentifier: winner.sourceBundleIdentifier
            )
        } else {
            evidence.weight = nil
        }
        try commit(evidence, on: record, in: context, calendar: calendar)
    }

    @MainActor
    private static func applyBodyFatDeletion(
        _ uuid: UUID,
        in context: ModelContext,
        calendar: Calendar,
        resample: BodyMassDayResampleSet
    ) throws {
        guard let record = try healthDayRecord(
            in: context,
            where: { $0.bodyFat?.sampleUUID == uuid }
        ), let dayKey = dayKey(for: record), let samples = resample.bodyFatByDay[dayKey] else { return }
        var evidence = record.healthDayEvidence ?? emptyEvidence(
            dayKey: dayKey,
            calendar: calendar
        )
        let remaining = samples.filter {
            $0.sampleUUID != uuid
                && validBodyFat($0.bodyFatPercent)
                && BodyMassDayKey.dayKey(for: $0.date, calendar: calendar) == dayKey
        }
        if let winner = BodyHealthDayEvidenceCodec.latestMetric(
            in: remaining,
            date: { $0.date },
            uuid: { $0.sampleUUID }
        ) {
            evidence.bodyFat = BodyHealthDayMetricEvidence(
                sampleUUID: winner.sampleUUID,
                date: winner.date,
                value: winner.bodyFatPercent,
                sourceName: winner.sourceName,
                sourceBundleIdentifier: winner.sourceBundleIdentifier
            )
        } else {
            evidence.bodyFat = nil
        }
        try commit(evidence, on: record, in: context, calendar: calendar)
    }

    @MainActor
    private static func commit(
        _ evidence: BodyHealthDayEvidence,
        on record: BodyEntry,
        in context: ModelContext,
        calendar: Calendar
    ) throws {
        if evidence.hasAnyMetric {
            apply(evidence, to: record, calendar: calendar)
        } else {
            context.delete(record)
        }
    }

    @MainActor
    private static func apply(
        _ evidence: BodyHealthDayEvidence,
        to record: BodyEntry,
        calendar: Calendar
    ) {
        record.healthDayEvidence = evidence
        record.weight = evidence.weight?.value
        record.bodyFat = evidence.bodyFat?.value
        if let latest = [evidence.weight?.date, evidence.bodyFat?.date]
            .compactMap({ $0 })
            .max()
        {
            record.date = latest
        } else if let start = BodyMassDayKey.startOfDay(
            for: evidence.dayKey,
            calendar: calendar
        ) {
            record.date = start
        }
        if let unified = evidence.unifiedSource {
            record.sourceName = unified.name
            record.sourceBundleIdentifier = unified.bundle
        } else {
            // 多来源时清空行级品牌字段，避免列表误用单一 Keep 图标。
            record.sourceName = nil
            record.sourceBundleIdentifier = nil
        }
        record.externalSource = BodyMassImportIdentity.externalSource
        record.externalID = BodyMassImportIdentity.bodyDayExternalID(dayKey: evidence.dayKey)
    }

    @MainActor
    private static func dayRecord(
        dayKey: String,
        in context: ModelContext,
        calendar: Calendar,
        createIfNeeded: Bool
    ) throws -> BodyEntry {
        let source: String? = BodyMassImportIdentity.externalSource
        let externalID: String? = BodyMassImportIdentity.bodyDayExternalID(dayKey: dayKey)
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate {
                $0.externalSource == source && $0.externalID == externalID
            }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        guard createIfNeeded else {
            throw CocoaError(.fileNoSuchFile)
        }
        let date = BodyMassDayKey.startOfDay(for: dayKey, calendar: calendar) ?? .now
        let entry = BodyEntry(
            date: date,
            notes: "",
            analysis: "",
            externalSource: BodyMassImportIdentity.externalSource,
            externalID: BodyMassImportIdentity.bodyDayExternalID(dayKey: dayKey)
        )
        entry.healthDayEvidence = emptyEvidence(dayKey: dayKey, calendar: calendar)
        context.insert(entry)
        try BusinessIDAllocator.assign(entry, namespace: "body", in: context)
        return entry
    }

    @MainActor
    private static func healthDayRecord(
        in context: ModelContext,
        where matches: (BodyHealthDayEvidence) -> Bool
    ) throws -> BodyEntry? {
        let source: String? = BodyMassImportIdentity.externalSource
        let imported = try context.fetch(
            FetchDescriptor<BodyEntry>(
                predicate: #Predicate { $0.externalSource == source }
            )
        )
        return imported.first { entry in
            BodyMassImportIdentity.isDayExternalID(entry.externalID)
                && entry.healthDayEvidence.map(matches) == true
        }
    }

    @MainActor
    private static func dayKeys(
        in context: ModelContext,
        matching: (BodyHealthDayEvidence, UUID) -> Bool,
        deletedSampleUUIDs: [UUID]
    ) throws -> [String] {
        let source: String? = BodyMassImportIdentity.externalSource
        let imported = try context.fetch(
            FetchDescriptor<BodyEntry>(
                predicate: #Predicate { $0.externalSource == source }
            )
        )
        var keys: [String] = []
        var seen = Set<String>()
        for uuid in deletedSampleUUIDs {
            if let entry = imported.first(where: { entry in
                BodyMassImportIdentity.isDayExternalID(entry.externalID)
                    && entry.healthDayEvidence.map { matching($0, uuid) } == true
            }), let key = dayKey(for: entry), seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    private static func dayKey(for entry: BodyEntry) -> String? {
        entry.healthDayEvidence?.dayKey
            ?? entry.externalID.flatMap(BodyMassImportIdentity.dayKey(externalID:))
    }

    private static func emptyEvidence(
        dayKey: String,
        calendar: Calendar
    ) -> BodyHealthDayEvidence {
        BodyHealthDayEvidence(
            dayKey: dayKey,
            timeZoneIdentifier: calendar.timeZone.identifier,
            weight: nil,
            bodyFat: nil
        )
    }

    private static func latestLegacy(_ rows: [BodyEntry]) -> BodyEntry? {
        BodyHealthDayEvidenceCodec.latestMetric(
            in: rows,
            date: \.date,
            uuid: { row in
                row.externalID.flatMap(BodyMassImportIdentity.sampleUUID(fromLegacyExternalID:))
                    ?? row.id
            }
        )
    }

    private static func metricEvidence(
        from entry: BodyEntry,
        value: Double
    ) -> BodyHealthDayMetricEvidence {
        BodyHealthDayMetricEvidence(
            sampleUUID: entry.externalID.flatMap(
                BodyMassImportIdentity.sampleUUID(fromLegacyExternalID:)
            ) ?? entry.id,
            date: entry.date,
            value: value,
            sourceName: entry.sourceName ?? "",
            sourceBundleIdentifier: entry.sourceBundleIdentifier ?? ""
        )
    }

    private static func validWeight(_ value: Double?) -> Bool {
        guard let value, value.isFinite, value > 0 else { return false }
        return true
    }

    private static func validBodyFat(_ value: Double?) -> Bool {
        guard let value, value.isFinite, value > 0, value <= 100 else { return false }
        return true
    }
}

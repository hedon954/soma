import Foundation

struct PortableExportPayload: Sendable {
    var createdAt: Date
    var timeZoneIdentifier: String
    var meals: [MealEntryDTO]
    var workouts: [WorkoutEntryDTO]
    var messages: [CoachMessageDTO]
    var traces: [AgentTraceDTO]

    init(
        snapshot: PersonalDataSnapshot,
        timeZone: TimeZone = .current
    ) {
        createdAt = snapshot.createdAt
        timeZoneIdentifier = timeZone.identifier
        meals = snapshot.meals
        workouts = snapshot.workouts
        messages = snapshot.messages
        traces = snapshot.traces
    }
}

struct PortableExportResult: Equatable, Sendable {
    var directoryURL: URL
    var mealCount: Int
    var workoutCount: Int
    var copiedMediaCount: Int
    var missingMediaCount: Int
}

enum DataExportService {
    static let formatVersion = 1

    static func export(
        _ payload: PortableExportPayload,
        to destination: URL,
        mediaURL: (String) -> URL? = MediaStore.url(at:)
    ) throws -> PortableExportResult {
        let fileManager = FileManager.default
        let finalURL = uniqueExportURL(
            in: destination,
            date: payload.createdAt,
            fileManager: fileManager
        )
        let partialURL = destination.appending(
            path: ".\(finalURL.lastPathComponent).partial-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        do {
            try fileManager.createDirectory(
                at: partialURL,
                withIntermediateDirectories: false
            )
            var manifestRecords: [PortableExportManifestRecord] = []
            var missingMedia: [PortableExportMissingMedia] = []
            var copiedMediaCount = 0

            for meal in payload.meals.sorted(by: recordSort) {
                let outcome = try writeMeal(
                    meal,
                    payload: payload,
                    root: partialURL,
                    mediaURL: mediaURL
                )
                manifestRecords.append(outcome.record)
                missingMedia.append(contentsOf: outcome.missingMedia)
                copiedMediaCount += outcome.copiedMediaCount
            }
            for workout in payload.workouts.sorted(by: recordSort) {
                let outcome = try writeWorkout(
                    workout,
                    payload: payload,
                    root: partialURL,
                    mediaURL: mediaURL
                )
                manifestRecords.append(outcome.record)
                missingMedia.append(contentsOf: outcome.missingMedia)
                copiedMediaCount += outcome.copiedMediaCount
            }

            let manifest = PortableExportManifest(
                formatVersion: formatVersion,
                generatedAt: payload.createdAt,
                timeZone: payload.timeZoneIdentifier,
                mealCount: payload.meals.count,
                workoutCount: payload.workouts.count,
                copiedMediaCount: copiedMediaCount,
                missingMedia: missingMedia,
                records: manifestRecords.sorted {
                    if $0.date == $1.date {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.date < $1.date
                }
            )
            try writeJSON(manifest, to: partialURL.appending(path: "manifest.json"))
            try PortableExportText.readme.write(
                to: partialURL.appending(path: "说明.txt"),
                atomically: true,
                encoding: .utf8
            )
            try fileManager.moveItem(at: partialURL, to: finalURL)
            return PortableExportResult(
                directoryURL: finalURL,
                mealCount: payload.meals.count,
                workoutCount: payload.workouts.count,
                copiedMediaCount: copiedMediaCount,
                missingMediaCount: missingMedia.count
            )
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw error
        }
    }

    static func datePath(
        for date: Date,
        timeZone: TimeZone
    ) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return [
            String(format: "%04d", components.year ?? 0),
            String(format: "%02d", components.month ?? 0),
            String(format: "%02d", components.day ?? 0)
        ]
    }

    private static func writeMeal(
        _ meal: MealEntryDTO,
        payload: PortableExportPayload,
        root: URL,
        mediaURL: (String) -> URL?
    ) throws -> RecordWriteOutcome {
        let source = sourceContext(
            turnID: meal.sourceTurnID,
            messages: payload.messages,
            traces: payload.traces
        )
        let attachments = orderedAttachments(
            record: meal.mediaAttachments,
            source: source.message?.mediaAttachments ?? []
        )
        let directory = try recordDirectory(
            root: root,
            date: meal.date,
            timeZoneIdentifier: payload.timeZoneIdentifier,
            typeDirectory: "饮食",
            recordType: "meal",
            id: meal.id
        )
        let mediaOutcome = try copyMedia(
            attachments,
            recordID: meal.id,
            to: directory,
            mediaURL: mediaURL
        )
        let analysis = PortableMealAnalysis(
            formatVersion: formatVersion,
            id: meal.id,
            date: meal.date,
            mealType: meal.mealTypeRaw,
            title: meal.title,
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fat: meal.fat,
            notes: meal.notes.nilIfBlank,
            sourceTurnID: meal.sourceTurnID,
            sourceSessionID: meal.sourceSessionID,
            sourceText: source.message?.text.nilIfBlank,
            agentAnalysis: source.agentAnswer,
            media: mediaOutcome.descriptors
        )
        try writeJSON(analysis, to: directory.appending(path: "分析结果.json"))
        try PortableExportText.meal(
            meal,
            sourceText: source.message?.text.nilIfBlank,
            agentAnswer: source.agentAnswer
        ).write(
            to: directory.appending(path: "原始记录.txt"),
            atomically: true,
            encoding: .utf8
        )
        return RecordWriteOutcome(
            record: PortableExportManifestRecord(
                id: meal.id,
                type: "meal",
                date: meal.date,
                relativeDirectory: relativePath(directory, from: root),
                mediaCount: mediaOutcome.descriptors.count
            ),
            copiedMediaCount: mediaOutcome.descriptors.count,
            missingMedia: mediaOutcome.missing
        )
    }

    private static func writeWorkout(
        _ workout: WorkoutEntryDTO,
        payload: PortableExportPayload,
        root: URL,
        mediaURL: (String) -> URL?
    ) throws -> RecordWriteOutcome {
        let source = sourceContext(
            turnID: workout.sourceTurnID,
            messages: payload.messages,
            traces: payload.traces
        )
        let attachments = orderedAttachments(
            record: workout.mediaAttachments,
            source: source.message?.mediaAttachments ?? []
        )
        let directory = try recordDirectory(
            root: root,
            date: workout.date,
            timeZoneIdentifier: payload.timeZoneIdentifier,
            typeDirectory: "训练",
            recordType: "workout",
            id: workout.id
        )
        let mediaOutcome = try copyMedia(
            attachments,
            recordID: workout.id,
            to: directory,
            mediaURL: mediaURL
        )
        let analysis = PortableWorkoutAnalysis(
            formatVersion: formatVersion,
            id: workout.id,
            date: workout.date,
            exercise: workout.exercise,
            setEntries: workout.setEntries,
            sets: workout.sets,
            reps: workout.reps,
            weight: workout.weight,
            restSeconds: workout.restSeconds,
            durationMinutes: workout.durationMinutes,
            notes: workout.notes.nilIfBlank,
            formScore: workout.formScore,
            intensity: workout.intensity,
            feedback: workout.feedback,
            estimatedCalories: workout.estimatedCalories,
            calorieMET: workout.calorieMET,
            calorieDurationMinutes: workout.calorieDurationMinutes,
            calorieDurationEstimated: workout.calorieDurationEstimated,
            externalSource: workout.externalSource,
            externalID: workout.externalID,
            sourceTurnID: workout.sourceTurnID,
            sourceSessionID: workout.sourceSessionID,
            sourceText: source.message?.text.nilIfBlank,
            agentAnalysis: source.agentAnswer,
            media: mediaOutcome.descriptors
        )
        try writeJSON(analysis, to: directory.appending(path: "分析结果.json"))
        try PortableExportText.workout(
            workout,
            sourceText: source.message?.text.nilIfBlank,
            agentAnswer: source.agentAnswer
        ).write(
            to: directory.appending(path: "原始记录.txt"),
            atomically: true,
            encoding: .utf8
        )
        return RecordWriteOutcome(
            record: PortableExportManifestRecord(
                id: workout.id,
                type: "workout",
                date: workout.date,
                relativeDirectory: relativePath(directory, from: root),
                mediaCount: mediaOutcome.descriptors.count
            ),
            copiedMediaCount: mediaOutcome.descriptors.count,
            missingMedia: mediaOutcome.missing
        )
    }

    private static func recordDirectory(
        root: URL,
        date: Date,
        timeZoneIdentifier: String,
        typeDirectory: String,
        recordType: String,
        id: UUID
    ) throws -> URL {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var directory = root
        for component in datePath(for: date, timeZone: timeZone) {
            directory.append(path: component, directoryHint: .isDirectory)
        }
        directory.append(path: typeDirectory, directoryHint: .isDirectory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HHmmss"
        directory.append(
            path: "\(formatter.string(from: date))_\(recordType)_\(id.uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func copyMedia(
        _ attachments: [MediaAttachmentReference],
        recordID: UUID,
        to recordDirectory: URL,
        mediaURL: (String) -> URL?
    ) throws -> MediaCopyOutcome {
        guard !attachments.isEmpty else {
            return MediaCopyOutcome(descriptors: [], missing: [])
        }
        let directory = recordDirectory.appending(path: "媒体", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var descriptors: [PortableExportMedia] = []
        var missing: [PortableExportMissingMedia] = []
        for (offset, attachment) in attachments.enumerated() {
            let index = offset + 1
            guard let sourceURL = mediaURL(attachment.path),
                  FileManager.default.fileExists(atPath: sourceURL.path)
            else {
                missing.append(PortableExportMissingMedia(
                    recordID: recordID,
                    index: index,
                    kind: attachment.kind.rawValue
                ))
                continue
            }
            let ext = sourceURL.pathExtension.nilIfBlank ?? defaultExtension(for: attachment.kind)
            let filename = String(
                format: "%03d-%@.%@",
                index,
                attachment.kind.rawValue,
                ext.lowercased()
            )
            let destination = directory.appending(path: filename)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            descriptors.append(PortableExportMedia(
                order: index,
                kind: attachment.kind.rawValue,
                filename: "媒体/\(filename)"
            ))
        }
        return MediaCopyOutcome(descriptors: descriptors, missing: missing)
    }

    private static func sourceContext(
        turnID: UUID?,
        messages: [CoachMessageDTO],
        traces: [AgentTraceDTO]
    ) -> SourceContext {
        guard let turnID else { return SourceContext() }
        let source = messages
            .filter { !$0.isFromCoach && $0.turnID == turnID }
            .min { $0.date < $1.date }
        let agentMessage = messages
            .filter {
                $0.isFromCoach
                    && $0.turnID == turnID
                    && $0.agentStatusRaw == AgentTraceStatus.succeeded.rawValue
            }
            .max {
                if $0.attemptNumber == $1.attemptNumber {
                    return $0.date < $1.date
                }
                return $0.attemptNumber < $1.attemptNumber
            }
        let traceAnswer = traces
            .filter {
                $0.turnID == turnID
                    && $0.statusRaw == AgentTraceStatus.succeeded.rawValue
            }
            .max { $0.attemptNumber < $1.attemptNumber }?
            .finalAnswer?
            .nilIfBlank
        return SourceContext(
            message: source,
            agentAnswer: agentMessage?.text.nilIfBlank ?? traceAnswer
        )
    }

    private static func orderedAttachments(
        record: [MediaAttachmentReference],
        source: [MediaAttachmentReference]
    ) -> [MediaAttachmentReference] {
        let candidates = record.isEmpty ? source : record
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    private static func writeJSON(_ value: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func uniqueExportURL(
        in destination: URL,
        date: Date,
        fileManager: FileManager
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let base = "Soma 导出 \(formatter.string(from: date))"
        var candidate = destination.appending(path: base, directoryHint: .isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = destination.appending(
                path: "\(base) \(suffix)",
                directoryHint: .isDirectory
            )
            suffix += 1
        }
        return candidate
    }

    private static func relativePath(_ url: URL, from root: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }

    private static func defaultExtension(for kind: MediaKind) -> String {
        kind == .video ? "mov" : "jpg"
    }

    private static func recordSort(_ lhs: MealEntryDTO, _ rhs: MealEntryDTO) -> Bool {
        if lhs.date == rhs.date {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.date < rhs.date
    }

    private static func recordSort(_ lhs: WorkoutEntryDTO, _ rhs: WorkoutEntryDTO) -> Bool {
        if lhs.date == rhs.date {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.date < rhs.date
    }
}

private struct RecordWriteOutcome {
    var record: PortableExportManifestRecord
    var copiedMediaCount: Int
    var missingMedia: [PortableExportMissingMedia]
}

private struct MediaCopyOutcome {
    var descriptors: [PortableExportMedia]
    var missing: [PortableExportMissingMedia]
}

private struct SourceContext {
    var message: CoachMessageDTO?
    var agentAnswer: String?
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

import Foundation
import SwiftData

struct WorkoutSetEvidence: Codable, Equatable, Hashable, Sendable {
    var logicalSetIndex: Int?
    var side: WorkoutEffortSide?
    var kind: WorkoutSetKind?
    var targetKind: WorkoutTargetKind?
    var reps: Int?
    var durationSeconds: Int?
    var externalWeightKG: Double?
    var restSeconds: Int?
    var recordedVideoPath: String?
    var recordedVideoKind: WorkoutRecordingEvidenceKind?

    init(
        logicalSetIndex: Int? = nil,
        side: WorkoutEffortSide? = nil,
        kind: WorkoutSetKind? = nil,
        targetKind: WorkoutTargetKind? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        externalWeightKG: Double? = nil,
        restSeconds: Int? = nil,
        recordedVideoPath: String? = nil,
        recordedVideoKind: WorkoutRecordingEvidenceKind? = nil
    ) {
        self.logicalSetIndex = logicalSetIndex
        self.side = side
        self.kind = kind
        self.targetKind = targetKind
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.externalWeightKG = externalWeightKG
        self.restSeconds = restSeconds
        self.recordedVideoPath = recordedVideoPath
        self.recordedVideoKind = recordedVideoKind
    }

    var resolvedRecordedVideoKind: WorkoutRecordingEvidenceKind? {
        guard recordedVideoPath != nil else { return nil }
        return recordedVideoKind ?? .complete
    }
}

enum WorkoutSetStorage {
    static func encode(_ entries: [WorkoutSetEvidence]) -> Data {
        (try? JSONEncoder().encode(entries)) ?? Data()
    }

    static func decode(_ data: Data) -> [WorkoutSetEvidence]? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([WorkoutSetEvidence].self, from: data)
    }
}

@Model
final class WorkoutEntry: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var date: Date
    var exercise: String
    var exerciseID: UUID?
    @Relationship(deleteRule: .nullify) var exerciseDefinition: ExerciseDefinition?
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var setEntriesData: Data = Data()
    var restSeconds: Int?
    var durationMinutes: Int?
    var notes: String
    var mediaKindRaw: String
    var mediaPath: String?
    var mediaAttachmentsData: Data = Data()
    var formScore: Int?
    var intensity: String?
    var feedback: String?
    var estimatedCalories: Int?
    var calorieMET: Double?
    var calorieDurationMinutes: Double?
    var calorieDurationEstimated: Bool = false
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?
    var sourceWorkoutSessionID: UUID?
    var sourcePerformanceID: UUID?
    @Attribute(.unique) var projectionKey: String?
    @Relationship(deleteRule: .nullify) var sourcePerformance: ExercisePerformance?

    var setEntries: [WorkoutSetEvidence] {
        get {
            if let stored = WorkoutSetStorage.decode(setEntriesData) {
                return stored
            }
            guard let sets, sets > 0 else { return [] }
            return (0 ..< sets).map { _ in
                WorkoutSetEvidence(reps: reps, externalWeightKG: weight)
            }
        }
        set {
            setEntriesData = WorkoutSetStorage.encode(newValue)
            sets = nil
            reps = nil
            weight = nil
        }
    }

    var setCount: Int? {
        let entries = setEntries
        guard !entries.isEmpty else { return sets }
        let logicalIndexes = Set(entries.compactMap(\.logicalSetIndex))
        return logicalIndexes.isEmpty ? entries.count : logicalIndexes.count
    }

    var representativeReps: Int? {
        let entries = setEntries
        guard !entries.isEmpty else { return reps }
        let values = entries.compactMap(\.reps)
        guard values.count == entries.count, Set(values).count == 1 else {
            return nil
        }
        return values.first
    }

    var representativeWeight: Double? {
        let entries = setEntries
        guard !entries.isEmpty else { return weight }
        let values = entries.compactMap(\.externalWeightKG)
        guard values.count == entries.count, Set(values).count == 1 else {
            return nil
        }
        return values.first
    }

    var estimatedVolume: Double? {
        let entries = setEntries
        if !entries.isEmpty {
            let complete = entries.compactMap { entry -> Double? in
                guard let reps = entry.reps,
                      let weight = entry.externalWeightKG,
                      reps > 0,
                      weight > 0
                else {
                    return nil
                }
                return Double(reps) * weight
            }
            return complete.isEmpty ? nil : complete.reduce(0, +)
        }
        guard setEntriesData.isEmpty,
              let sets,
              let reps,
              let weight
        else {
            return nil
        }
        return Double(sets * reps) * weight
    }

    var volumeIsPartial: Bool {
        let entries = setEntries
        return !entries.isEmpty && entries.contains {
            guard let reps = $0.reps, let weight = $0.externalWeightKG else {
                return true
            }
            return reps <= 0 || weight <= 0
        }
    }

    var setEvidenceSummary: String? {
        let entries = setEntries
        guard !entries.isEmpty else { return nil }
        if let reps = representativeReps,
           let weight = representativeWeight
        {
            let weightText = weight == 0 ? "自重" : "\(weight.formatted())kg"
            return "\(setCount ?? entries.count)组 × \(reps)次 · \(weightText)"
        }
        return entries.enumerated().map { index, entry in
            var parts = ["第\(entry.logicalSetIndex ?? index + 1)组"]
            switch entry.side {
            case .some(.left):
                parts.append("左侧")
            case .some(.right):
                parts.append("右侧")
            case nil, .some(.none):
                break
            }
            if let weight = entry.externalWeightKG {
                parts.append(weight == 0 ? "自重" : "\(weight.formatted())kg")
            }
            if let reps = entry.reps {
                parts.append("\(reps)次")
            } else if let seconds = entry.durationSeconds {
                parts.append("\(seconds)秒")
            }
            return parts.joined(separator: " ")
        }.joined(separator: "，")
    }

    var mediaKind: MediaKind {
        get { MediaKind(rawValue: mediaKindRaw) ?? .none }
        set { mediaKindRaw = newValue.rawValue }
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            mediaKind = newValue.first?.kind ?? .none
            mediaPath = newValue.first?.path
        }
    }

    init(
        date: Date = .now,
        exercise: String,
        exerciseID: UUID? = nil,
        sets: Int? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        setEntries: [WorkoutSetEvidence]? = nil,
        restSeconds: Int? = nil,
        durationMinutes: Int? = nil,
        notes: String = "",
        mediaKind: MediaKind = .none,
        mediaPath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        formScore: Int? = nil,
        intensity: String? = nil,
        feedback: String? = nil,
        estimatedCalories: Int? = nil,
        calorieMET: Double? = nil,
        calorieDurationMinutes: Double? = nil,
        calorieDurationEstimated: Bool = false,
        externalSource: String? = nil,
        externalID: String? = nil,
        sourceTurnID: UUID? = nil,
        sourceSessionID: UUID? = nil,
        sourceWorkoutSessionID: UUID? = nil,
        sourcePerformanceID: UUID? = nil,
        projectionKey: String? = nil
    ) {
        id = UUID()
        self.date = date
        self.exercise = exercise
        self.exerciseID = exerciseID
        if let setEntries {
            self.sets = nil
            self.reps = nil
            self.weight = nil
            setEntriesData = WorkoutSetStorage.encode(setEntries)
        } else {
            self.sets = sets
            self.reps = reps
            self.weight = weight
        }
        self.restSeconds = restSeconds
        self.durationMinutes = durationMinutes
        self.notes = notes
        mediaKindRaw = mediaKind.rawValue
        self.mediaPath = mediaPath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        self.formScore = formScore
        self.intensity = intensity
        self.feedback = feedback
        self.estimatedCalories = estimatedCalories
        self.calorieMET = calorieMET
        self.calorieDurationMinutes = calorieDurationMinutes
        self.calorieDurationEstimated = calorieDurationEstimated
        self.externalSource = externalSource
        self.externalID = externalID
        self.sourceTurnID = sourceTurnID
        self.sourceSessionID = sourceSessionID
        self.sourceWorkoutSessionID = sourceWorkoutSessionID
        self.sourcePerformanceID = sourcePerformanceID
        self.projectionKey = projectionKey ?? SomaDataMigration.entryKey(for: id)
    }
}

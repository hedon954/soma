import Foundation
import SwiftData

struct WorkoutWeightCorrectionPlan: Codable, Equatable, Sendable {
    struct Change: Codable, Equatable, Identifiable, Sendable {
        let workoutID: UUID
        let date: Date
        let name: String
        let effortIndex: Int?
        let setID: UUID?
        let effortID: UUID?
        let group: Int?
        let side: WorkoutEffortSide?
        let previous: Double
        let reps: Int?

        var id: String {
            "\(workoutID):\(effortIndex ?? -1)"
        }

        var corrected: Double {
            previous / 2
        }

        var volumeDifference: Double? {
            reps.map { Double($0) * (corrected - previous) }
        }
    }

    let changes: [Change]
    let conflicts: Int

    private static let catalogAliases = Set(
        BundledExerciseCatalog.entries.filter { matchesCanonicalName($0.canonicalName) }
            .flatMap(\.aliases)
            .map(ExerciseLibraryStore.canonicalNameKey)
    )

    static func matches(_ name: String) -> Bool {
        matchesCanonicalName(name) || catalogAliases.contains(ExerciseLibraryStore.canonicalNameKey(name))
    }

    private static func matchesCanonicalName(_ name: String) -> Bool {
        let cleaned = name.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
        let variants = ["站姿", "坐姿", "单臂", "单侧", "双臂", "双侧", "水平", "平板", "上斜凳", "上斜", "斜板", "交替", "标准", "incline", "alternating"]
        let normalized = variants.reduce(cleaned) { $0.replacingOccurrences(of: $1, with: "") }
        return ["哑铃弯举", "哑铃卧推", "哑铃垂式弯举", "锤式哑铃弯举", "哑铃锤式弯举", "哑铃锤式", "哑铃推胸", "锤式弯举",
                "哑铃锤式屈臂", "dumbbellcurl", "dumbbellbenchpress", "dumbbellhammercurl", "hammercurl"].contains(normalized)
    }
}

@MainActor
enum WorkoutWeightCorrection {
    enum State: Equatable {
        case before, after, conflict
    }

    enum Failure: LocalizedError {
        case dataChanged
        var errorDescription: String? {
            "训练记录已变化，请重新核对。当前操作未提交。"
        }
    }

    private typealias Change = WorkoutWeightCorrectionPlan.Change

    static func loadPlan(in context: ModelContext, journalURL: URL) throws -> (plan: WorkoutWeightCorrectionPlan, state: State) {
        if let saved = try readJournal(at: journalURL) {
            let current = try state(of: saved, in: context)
            if current != .before {
                return (saved, current)
            }
        }
        return try (preview(in: context), .before)
    }

    static func preview(in context: ModelContext) throws -> WorkoutWeightCorrectionPlan {
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        var targetIDs = Set(definitions.filter { WorkoutWeightCorrectionPlan.matches($0.canonicalName) }.map(\.id))
        for definition in definitions {
            if let target = definition.mergedIntoID, targetIDs.contains(definition.id) {
                targetIDs.insert(target)
            }
        }
        var changes: [Change] = []
        var conflicts = 0
        for workout in workouts where !workout.isDailyActivity {
            let matchesIdentity = (workout.exerciseID ?? workout.exerciseDefinition?.id).map(targetIDs.contains) == true
            guard matchesIdentity || WorkoutWeightCorrectionPlan.matches(workout.exercise) else { continue }
            if workout.setEntriesData.isEmpty {
                if let weight = workout.weight, weight.isFinite, weight >= 20 {
                    guard workout.sourcePerformanceID == nil else { conflicts += 1; continue }
                    changes.append(.init(workoutID: workout.id, date: workout.date, name: workout.exercise,
                                         effortIndex: nil, setID: nil, effortID: nil, group: nil, side: nil,
                                         previous: weight, reps: legacyRepetitionCount(workout)))
                }
                continue
            }
            guard let evidence = WorkoutSetStorage.decode(workout.setEntriesData) else { conflicts += 1; continue }
            let sources = try completedSets(for: workout, in: context)
            var workoutChanges: [Change] = []
            var matched = true
            for (index, entry) in evidence.enumerated() {
                guard let weight = entry.externalWeightKG, weight.isFinite, weight >= 20 else { continue }
                var setID: UUID?
                var effortID: UUID?
                if workout.sourcePerformanceID != nil {
                    guard let source = match(entry, in: sources) else { matched = false; break }
                    setID = source.set.id
                    effortID = source.effort?.id
                }
                workoutChanges.append(.init(workoutID: workout.id, date: workout.date, name: workout.exercise,
                                            effortIndex: index, setID: setID, effortID: effortID,
                                            group: entry.logicalSetIndex ?? index + 1, side: entry.side,
                                            previous: weight, reps: entry.reps))
            }
            if matched {
                changes += workoutChanges
            } else {
                conflicts += 1
            }
        }
        return .init(changes: changes, conflicts: conflicts)
    }

    static func state(of plan: WorkoutWeightCorrectionPlan, in context: ModelContext) throws -> State {
        var states: Set<Bool> = []
        do {
            for change in plan.changes {
                let workout = try workout(change.workoutID, in: context)
                guard workout.date == change.date, workout.exercise == change.name else { return .conflict }
                let evidence = try evidenceFor(change, workout: workout)
                let current = change.effortIndex == nil ? workout.weight : evidence?.externalWeightKG
                guard let current, current == change.previous || current == change.corrected else { return .conflict }
                let sources = try sourcesFor(change, in: context)
                if let set = sources.set {
                    guard set.performanceID == workout.sourcePerformanceID,
                          let evidence, let matching = match(evidence, in: [set]), matching.effort?.id == change.effortID
                    else { return .conflict }
                } else if workout.sourcePerformanceID != nil || change.effortID != nil {
                    return .conflict
                }
                states.insert(current == change.corrected)
            }
        } catch Failure.dataChanged {
            return .conflict
        }
        if states.count > 1 {
            return .conflict
        }
        return states.contains(true) ? .after : .before
    }

    static func commit(_ plan: WorkoutWeightCorrectionPlan, undo: Bool, in context: ModelContext, journalURL: URL? = nil) throws {
        guard !plan.changes.isEmpty else { return }
        let saved = try journalURL.flatMap { try readJournal(at: $0) }
        if undo, journalURL != nil, saved != plan {
            throw Failure.dataChanged
        }
        if let saved, saved != plan, try state(of: saved, in: context) != .before {
            throw Failure.dataChanged
        }
        switch try state(of: plan, in: context) {
        case .conflict: throw Failure.dataChanged
        case .after where !undo:
            guard journalURL == nil || saved == plan else { throw Failure.dataChanged }
            return
        case .before where undo: return
        default: break
        }
        if let journalURL, saved != plan {
            try JSONEncoder().encode(plan).write(to: journalURL, options: [.atomic, .completeFileProtection])
        }
        let grouped = Dictionary(grouping: plan.changes, by: \.workoutID)
        do {
            for (id, changes) in grouped {
                let entry = try workout(id, in: context)
                var evidence = entry.setEntries
                var effortSets: [UUID: WorkoutSet] = [:]
                for change in changes {
                    let value = undo ? change.previous : change.corrected
                    if let index = change.effortIndex {
                        evidence[index].externalWeightKG = value
                    } else {
                        entry.weight = value
                    }
                    let sources = try sourcesFor(change, in: context)
                    if let effort = sources.effort {
                        effort.actualWeightKG = value
                        if let set = sources.set {
                            effortSets[set.id] = set
                        }
                    } else {
                        sources.set?.actualWeightKG = value
                    }
                }
                for set in effortSets.values {
                    set.actualWeightKG = completedWeight(for: set)
                }
                if !entry.setEntriesData.isEmpty {
                    entry.setEntries = evidence
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func readJournal(at url: URL) throws -> WorkoutWeightCorrectionPlan? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(WorkoutWeightCorrectionPlan.self, from: Data(contentsOf: url))
    }

    private static func workout(_ id: UUID, in context: ModelContext) throws -> WorkoutEntry {
        let descriptor = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.id == id })
        guard let workout = try context.fetch(descriptor).first else { throw Failure.dataChanged }
        return workout
    }

    private static func evidenceFor(_ change: Change, workout: WorkoutEntry) throws -> WorkoutSetEvidence? {
        guard let index = change.effortIndex else {
            guard workout.setEntriesData.isEmpty, workout.sourcePerformanceID == nil,
                  legacyRepetitionCount(workout) == change.reps
            else { throw Failure.dataChanged }
            return nil
        }
        guard let evidence = WorkoutSetStorage.decode(workout.setEntriesData), evidence.indices.contains(index),
              (evidence[index].logicalSetIndex ?? index + 1) == change.group,
              evidence[index].side == change.side, evidence[index].reps == change.reps
        else { throw Failure.dataChanged }
        return evidence[index]
    }

    private static func legacyRepetitionCount(_ workout: WorkoutEntry) -> Int? {
        guard let reps = workout.reps, let sets = workout.sets, reps > 0, sets > 0 else { return nil }
        let (total, overflow) = reps.multipliedReportingOverflow(by: sets)
        return overflow ? nil : total
    }

    private static func completedSets(for workout: WorkoutEntry, in context: ModelContext) throws -> [WorkoutSet] {
        guard let performanceID = workout.sourcePerformanceID else { return [] }
        return try context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.performanceID == performanceID }))
    }

    private static func match(_ entry: WorkoutSetEvidence, in sets: [WorkoutSet]) -> (set: WorkoutSet, effort: WorkoutEffort?)? {
        let matchingSets = sets.filter { $0.order == entry.logicalSetIndex }
        guard matchingSets.count == 1, let set = matchingSets.first, set.status == .completed || set.status == .partial else { return nil }
        if set.efforts.contains(where: { $0.status != .pending }) {
            let matching = set.efforts.filter { $0.status == .completed && $0.side == entry.side }
            guard matching.count == 1, let effort = matching.first,
                  effort.workoutSetID == set.id, effort.actualWeightKG == entry.externalWeightKG,
                  effort.actualReps == entry.reps, effort.actualDurationSeconds == entry.durationSeconds,
                  set.actualWeightKG == completedWeight(for: set)
            else { return nil }
            return (set, effort)
        }
        guard set.actualWeightKG == entry.externalWeightKG, set.actualReps == entry.reps,
              set.actualDurationSeconds == entry.durationSeconds
        else { return nil }
        return (set, nil)
    }

    private static func completedWeight(for set: WorkoutSet) -> Double? {
        let weights = Set(set.efforts.filter { $0.status == .completed }.compactMap(\.actualWeightKG))
        return weights.count == 1 ? weights.first : nil
    }

    private static func sourcesFor(_ change: Change, in context: ModelContext) throws -> (set: WorkoutSet?, effort: WorkoutEffort?) {
        guard let id = change.setID else { return (nil, nil) }
        let descriptor = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.id == id })
        guard let set = try context.fetch(descriptor).first else { throw Failure.dataChanged }
        guard let effortID = change.effortID else { return (set, nil) }
        guard let effort = set.efforts.first(where: { $0.id == effortID }) else { throw Failure.dataChanged }
        return (set, effort)
    }
}

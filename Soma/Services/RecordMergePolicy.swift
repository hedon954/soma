import Foundation
import SwiftData

enum RecordDeletionPolicy {
    static func hasExplicitIntent(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return [
            "删除", "删掉", "删了", "移除这条", "不要这条记录",
            "delete", "remove this record"
        ].contains(where: normalized.contains)
    }
}

enum RecordMergePolicy {
    static func isCorrectionOrSupplement(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return [
            "不是", "应该是", "其实是", "改成", "更正", "纠正", "刚才", "上一条",
            "前一条", "补充", "再加", "漏了", "这张也是", "同一", "更新一下",
            "not ", "actually", "correction", "update the previous"
        ].contains(where: normalized.contains)
    }

    static func normalizedSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedCharacters(lhs)
        let right = normalizedCharacters(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right {
            return 1
        }
        if left.contains(right) || right.contains(left) {
            return Double(min(left.count, right.count)) / Double(max(left.count, right.count))
        }
        let leftBigrams = bigrams(left)
        let rightBigrams = bigrams(right)
        guard !leftBigrams.isEmpty, !rightBigrams.isEmpty else { return 0 }
        let intersection = leftBigrams.intersection(rightBigrams).count
        let union = leftBigrams.union(rightBigrams).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    static func mergedMedia(
        _ existing: [MediaAttachmentReference],
        _ incoming: [MediaAttachmentReference]
    ) -> [MediaAttachmentReference] {
        var keys = Set(existing.map(mediaKey))
        var result = existing
        for attachment in incoming where keys.insert(mediaKey(attachment)).inserted {
            result.append(attachment)
        }
        return result
    }

    static func mergedText(_ existing: String, _ incoming: String) -> String {
        let old = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return old }
        guard !old.isEmpty else { return new }
        return old == new || old.contains(new) ? old : "\(old)\n\(new)"
    }

    static func mealCandidate(
        for input: MealMergeInput,
        entries: [MealEntry]
    ) -> MealEntry? {
        if let exact = sameTurnCandidate(
            turnID: input.turnID,
            entries: entries,
            sourceTurnID: \.sourceTurnID
        ) {
            return exact
        }
        let eligible = input.isCorrection
            ? entries
            : entries.filter {
                sharesMedia($0.mediaAttachments, input.media)
            }
        return uniqueBestCandidate(
            eligible,
            score: { mealScore($0, input: input) },
            threshold: input.isCorrection ? 7 : 10
        )
    }

    static func workoutCandidate(
        for input: WorkoutMergeInput,
        entries: [WorkoutEntry]
    ) -> WorkoutEntry? {
        let localEntries = entries.filter { $0.externalSource == nil }
        if let exact = sameTurnCandidate(
            turnID: input.turnID,
            entries: localEntries,
            sourceTurnID: \.sourceTurnID
        ) {
            return exact
        }
        let eligible = input.isCorrection
            ? localEntries
            : localEntries.filter {
                sharesMedia($0.mediaAttachments, input.media)
            }
        return uniqueBestCandidate(
            eligible,
            score: { workoutScore($0, input: input) },
            threshold: input.isCorrection ? 8 : 10
        )
    }

    static func bodyCandidate(
        for input: BodyMergeInput,
        entries: [BodyEntry]
    ) -> BodyEntry? {
        let localEntries = entries.filter { $0.externalSource == nil }
        if let exact = sameTurnCandidate(
            turnID: input.turnID,
            entries: localEntries,
            sourceTurnID: \.sourceTurnID
        ) {
            return exact
        }
        let eligible = input.isCorrection
            ? localEntries
            : localEntries.filter {
                sharesMedia($0.mediaAttachments, input.media)
            }
        return uniqueBestCandidate(
            eligible,
            score: { bodyScore($0, input: input) },
            threshold: input.isCorrection ? 7 : 8
        )
    }

    static func mergeMeal(
        _ entry: MealEntry,
        input: MealMergeInput,
        confidence: Double? = nil
    ) {
        if input.isCorrection {
            entry.mealType = input.mealType
            entry.title = input.title
            entry.calories = input.calories
            entry.protein = input.protein
            entry.carbs = input.carbs
            entry.fat = input.fat
            if !input.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.notes = input.sourceText
            }
            if let confidence {
                entry.confidence = confidence
            }
        } else {
            if normalizedSimilarity(entry.title, input.title) >= 0.55,
               input.title.count > entry.title.count
            {
                entry.title = input.title
            }
            entry.notes = mergedText(entry.notes, input.sourceText)
            if let confidence, confidence > entry.confidence {
                entry.calories = input.calories
                entry.protein = input.protein
                entry.carbs = input.carbs
                entry.fat = input.fat
                entry.confidence = confidence
            }
        }
        entry.mediaAttachments = mergedMedia(entry.mediaAttachments, input.media)
        entry.sourceTurnID = entry.sourceTurnID ?? input.turnID
        entry.sourceSessionID = entry.sourceSessionID ?? input.sessionID
    }

    static func mergeWorkout(
        _ entry: WorkoutEntry,
        input: WorkoutMergeInput,
        formScore: Int?,
        intensity: String?,
        feedback: String?,
        calorieEstimate: WorkoutCalorieEstimate?
    ) {
        if input.isCorrection {
            entry.exercise = input.exercise
            entry.exerciseID = input.exerciseID ?? entry.exerciseID
            if let setEntries = input.setEntries {
                entry.setEntries = setEntries
            } else {
                entry.sets = input.sets ?? entry.sets
                entry.reps = input.reps ?? entry.reps
                entry.weight = input.weight ?? entry.weight
            }
            entry.restSeconds = input.restSeconds ?? entry.restSeconds
            entry.durationMinutes = input.durationMinutes ?? entry.durationMinutes
            entry.formScore = formScore ?? entry.formScore
            entry.intensity = intensity ?? entry.intensity
            entry.feedback = feedback ?? entry.feedback
            if !input.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.notes = input.sourceText
            }
        } else {
            entry.exerciseID = entry.exerciseID ?? input.exerciseID
            if entry.setEntriesData.isEmpty, let setEntries = input.setEntries {
                entry.setEntries = setEntries
            } else if entry.setEntriesData.isEmpty {
                entry.sets = entry.sets ?? input.sets
                entry.reps = entry.reps ?? input.reps
                entry.weight = entry.weight ?? input.weight
            }
            entry.restSeconds = entry.restSeconds ?? input.restSeconds
            entry.durationMinutes = entry.durationMinutes ?? input.durationMinutes
            entry.formScore = entry.formScore ?? formScore
            entry.intensity = entry.intensity ?? intensity
            entry.feedback = entry.feedback ?? feedback
            entry.notes = mergedText(entry.notes, input.sourceText)
        }
        if let calorieEstimate {
            entry.estimatedCalories = calorieEstimate.calories
            entry.calorieMET = calorieEstimate.met
            entry.calorieDurationMinutes = calorieEstimate.durationMinutes
            entry.calorieDurationEstimated = calorieEstimate.durationWasEstimated
        }
        entry.mediaAttachments = mergedMedia(entry.mediaAttachments, input.media)
        entry.sourceTurnID = entry.sourceTurnID ?? input.turnID
        entry.sourceSessionID = entry.sourceSessionID ?? input.sessionID
    }

    static func mergeBody(
        _ entry: BodyEntry,
        input: BodyMergeInput,
        analysis: String
    ) {
        if input.isCorrection {
            entry.weight = input.weight ?? entry.weight
            entry.bodyFat = input.bodyFat ?? entry.bodyFat
            entry.waist = input.waist ?? entry.waist
            if !input.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.notes = input.sourceText
            }
            if !analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.analysis = analysis
            }
        } else {
            entry.weight = entry.weight ?? input.weight
            entry.bodyFat = entry.bodyFat ?? input.bodyFat
            entry.waist = entry.waist ?? input.waist
            entry.notes = mergedText(entry.notes, input.sourceText)
            entry.analysis = mergedText(entry.analysis, analysis)
        }
        entry.mediaAttachments = mergedMedia(entry.mediaAttachments, input.media)
        entry.sourceTurnID = entry.sourceTurnID ?? input.turnID
        entry.sourceSessionID = entry.sourceSessionID ?? input.sessionID
    }

    static func isObviousLegacyMealDuplicate(
        _ lhs: MealEntry,
        _ rhs: MealEntry
    ) -> Bool {
        guard lhs.sourceTurnID == nil, rhs.sourceTurnID == nil else {
            return false
        }
        let input = MealMergeInput(
            date: rhs.date,
            sessionID: rhs.sourceSessionID,
            turnID: rhs.sourceTurnID,
            mealType: rhs.mealType,
            title: rhs.title,
            calories: rhs.calories,
            protein: rhs.protein,
            carbs: rhs.carbs,
            fat: rhs.fat,
            sourceText: rhs.notes,
            media: rhs.mediaAttachments,
            isCorrection: false
        )
        return mealScore(lhs, input: input) >= 10
            && abs(lhs.date.timeIntervalSince(rhs.date)) <= 30 * 60
    }

    static func isObviousLegacyWorkoutDuplicate(
        _ lhs: WorkoutEntry,
        _ rhs: WorkoutEntry
    ) -> Bool {
        guard lhs.sourceTurnID == nil, rhs.sourceTurnID == nil else {
            return false
        }
        let input = WorkoutMergeInput(
            date: rhs.date,
            sessionID: rhs.sourceSessionID,
            turnID: rhs.sourceTurnID,
            exercise: rhs.exercise,
            exerciseID: rhs.exerciseID,
            setEntries: rhs.setEntriesData.isEmpty ? nil : rhs.setEntries,
            sets: rhs.sets,
            reps: rhs.reps,
            weight: rhs.weight,
            restSeconds: rhs.restSeconds,
            durationMinutes: rhs.durationMinutes,
            sourceText: rhs.notes,
            media: rhs.mediaAttachments,
            isCorrection: false
        )
        return workoutScore(lhs, input: input) >= 11
            && abs(lhs.date.timeIntervalSince(rhs.date)) <= 15 * 60
    }

    static func isObviousLegacyBodyDuplicate(
        _ lhs: BodyEntry,
        _ rhs: BodyEntry
    ) -> Bool {
        guard lhs.sourceTurnID == nil, rhs.sourceTurnID == nil else {
            return false
        }
        let input = BodyMergeInput(
            date: rhs.date,
            sessionID: rhs.sourceSessionID,
            turnID: rhs.sourceTurnID,
            weight: rhs.weight,
            bodyFat: rhs.bodyFat,
            waist: rhs.waist,
            sourceText: rhs.notes,
            media: rhs.mediaAttachments,
            isCorrection: false
        )
        return bodyScore(lhs, input: input) >= 9
            && abs(lhs.date.timeIntervalSince(rhs.date)) <= 15 * 60
    }

    private static func mealScore(
        _ entry: MealEntry,
        input: MealMergeInput
    ) -> Int {
        if let turnID = input.turnID, entry.sourceTurnID == turnID {
            return 100
        }
        let interval = abs(entry.date.timeIntervalSince(input.date))
        guard interval <= 2 * 60 * 60, entry.mealType == input.mealType else {
            return 0
        }
        var score = timeScore(interval)
        score += sessionScore(entry.sourceSessionID, input.sessionID)
        let similarity = normalizedSimilarity(entry.title, input.title)
        score += similarity >= 0.75 ? 4 : similarity >= 0.4 ? 3 : similarity >= 0.22 ? 1 : 0
        score += abs(entry.calories - input.calories) <= 5
            ? 2 : abs(entry.calories - input.calories) <= 80 ? 1 : 0
        score += numericCloseness(entry.protein, input.protein, tolerance: 3)
        score += numericCloseness(entry.carbs, input.carbs, tolerance: 5)
        score += numericCloseness(entry.fat, input.fat, tolerance: 3)
        score += mediaScore(entry.mediaAttachments, input.media)
        if input.isCorrection {
            score += 3
        }
        return score
    }

    private static func workoutScore(
        _ entry: WorkoutEntry,
        input: WorkoutMergeInput
    ) -> Int {
        if let turnID = input.turnID, entry.sourceTurnID == turnID {
            return 100
        }
        let interval = abs(entry.date.timeIntervalSince(input.date))
        guard interval <= 2 * 60 * 60 else { return 0 }
        if let entryExerciseID = entry.exerciseID,
           let inputExerciseID = input.exerciseID,
           entryExerciseID != inputExerciseID,
           !input.isCorrection
        {
            return 0
        }
        let similarity = normalizedSimilarity(entry.exercise, input.exercise)
        let minimumSimilarity = input.isCorrection ? 0.15 : 0.35
        guard similarity >= minimumSimilarity else { return 0 }
        var score = timeScore(interval)
        if let exerciseID = input.exerciseID, entry.exerciseID == exerciseID {
            score += 5
        }
        score += sessionScore(entry.sourceSessionID, input.sessionID)
        score += similarity >= 0.8 ? 4 : similarity >= 0.55 ? 3 : 1
        if let setEntries = input.setEntries {
            score += entry.setEntries == setEntries ? 3 : 0
        } else {
            score += optionalEquality(entry.sets, input.sets)
            score += optionalEquality(entry.reps, input.reps)
            score += optionalCloseness(entry.weight, input.weight, tolerance: 0.5)
        }
        score += optionalEquality(entry.restSeconds, input.restSeconds)
        score += optionalEquality(entry.durationMinutes, input.durationMinutes)
        score += mediaScore(entry.mediaAttachments, input.media)
        if input.isCorrection {
            score += 3
        }
        return score
    }

    private static func bodyScore(
        _ entry: BodyEntry,
        input: BodyMergeInput
    ) -> Int {
        if let turnID = input.turnID, entry.sourceTurnID == turnID {
            return 100
        }
        let interval = abs(entry.date.timeIntervalSince(input.date))
        guard interval <= 6 * 60 * 60 else { return 0 }
        var score = timeScore(interval)
        score += sessionScore(entry.sourceSessionID, input.sessionID)
        score += optionalCloseness(entry.weight, input.weight, tolerance: 0.2) * 2
        score += optionalCloseness(entry.bodyFat, input.bodyFat, tolerance: 0.3) * 2
        score += optionalCloseness(entry.waist, input.waist, tolerance: 0.5) * 2
        score += mediaScore(entry.mediaAttachments, input.media)
        if input.isCorrection {
            score += 3
        }
        return score
    }

    private static func uniqueBestCandidate<T>(
        _ values: [T],
        score: (T) -> Int,
        threshold: Int
    ) -> T? {
        let ranked = values
            .map { ($0, score($0)) }
            .filter { $0.1 >= threshold }
            .sorted { $0.1 > $1.1 }
        guard let first = ranked.first else { return nil }
        guard ranked.count == 1 || first.1 - ranked[1].1 >= 2 else { return nil }
        return first.0
    }

    private static func sameTurnCandidate<T>(
        turnID: UUID?,
        entries: [T],
        sourceTurnID: KeyPath<T, UUID?>
    ) -> T? {
        guard let turnID else { return nil }
        return entries.first { $0[keyPath: sourceTurnID] == turnID }
    }

    private static func timeScore(_ interval: TimeInterval) -> Int {
        if interval <= 15 * 60 {
            return 3
        }
        if interval <= 60 * 60 {
            return 2
        }
        if interval <= 2 * 60 * 60 {
            return 1
        }
        return 0
    }

    private static func sessionScore(_ lhs: UUID?, _ rhs: UUID?) -> Int {
        guard let lhs, let rhs else { return 0 }
        return lhs == rhs ? 2 : -4
    }

    private static func numericCloseness(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double
    ) -> Int {
        abs(lhs - rhs) <= tolerance ? 1 : 0
    }

    private static func optionalCloseness(
        _ lhs: Double?,
        _ rhs: Double?,
        tolerance: Double
    ) -> Int {
        guard let lhs, let rhs else { return 0 }
        return abs(lhs - rhs) <= tolerance ? 1 : 0
    }

    private static func optionalEquality<T: Equatable>(_ lhs: T?, _ rhs: T?) -> Int {
        guard let lhs, let rhs else { return 0 }
        return lhs == rhs ? 1 : 0
    }

    private static func mediaScore(
        _ existing: [MediaAttachmentReference],
        _ incoming: [MediaAttachmentReference]
    ) -> Int {
        guard !existing.isEmpty, !incoming.isEmpty else { return 0 }
        let existingKeys = Set(existing.map(mediaKey))
        return incoming.contains(where: { existingKeys.contains(mediaKey($0)) }) ? 4 : 1
    }

    private static func sharesMedia(
        _ existing: [MediaAttachmentReference],
        _ incoming: [MediaAttachmentReference]
    ) -> Bool {
        guard !existing.isEmpty, !incoming.isEmpty else { return false }
        let existingKeys = Set(existing.map(mediaKey))
        return incoming.contains { existingKeys.contains(mediaKey($0)) }
    }

    private static func mediaKey(_ attachment: MediaAttachmentReference) -> String {
        "\(attachment.kind.rawValue)|\(attachment.path)"
    }

    private static func normalizedCharacters(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func bigrams(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else { return Set([value]) }
        return Set((0 ..< characters.count - 1).map {
            String(characters[$0 ... ($0 + 1)])
        })
    }
}

struct MealMergeInput {
    var date: Date
    var sessionID: UUID?
    var turnID: UUID?
    var mealType: MealType
    var title: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var sourceText: String
    var media: [MediaAttachmentReference]
    var isCorrection: Bool
}

struct WorkoutMergeInput {
    var date: Date
    var sessionID: UUID?
    var turnID: UUID?
    var exercise: String
    var exerciseID: UUID?
    var setEntries: [WorkoutSetEvidence]?
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationMinutes: Int?
    var sourceText: String
    var media: [MediaAttachmentReference]
    var isCorrection: Bool
}

struct BodyMergeInput {
    var date: Date
    var sessionID: UUID?
    var turnID: UUID?
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var sourceText: String
    var media: [MediaAttachmentReference]
    var isCorrection: Bool
}

extension DataIntegrityRepair {
    @MainActor
    static func mergeObviousDuplicateRecords(in context: ModelContext) {
        var changed = false
        changed = mergeMeals(in: context) || changed
        changed = mergeWorkouts(in: context) || changed
        changed = mergeBodyEntries(in: context) || changed
        if changed {
            try? context.save()
        }
    }

    @MainActor
    private static func mergeMeals(in context: ModelContext) -> Bool {
        let entries = (
            try? context.fetch(
                FetchDescriptor<MealEntry>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        var retained: [MealEntry] = []
        var changed = false
        for entry in entries {
            guard let existing = retained.last(where: {
                RecordMergePolicy.isObviousLegacyMealDuplicate($0, entry)
            }) else {
                retained.append(entry)
                continue
            }
            RecordMergePolicy.mergeMeal(
                existing,
                input: MealMergeInput(
                    date: entry.date,
                    sessionID: entry.sourceSessionID,
                    turnID: entry.sourceTurnID,
                    mealType: entry.mealType,
                    title: entry.title,
                    calories: entry.calories,
                    protein: entry.protein,
                    carbs: entry.carbs,
                    fat: entry.fat,
                    sourceText: entry.notes,
                    media: entry.mediaAttachments,
                    isCorrection: true
                ),
                confidence: entry.confidence
            )
            context.delete(entry)
            changed = true
        }
        return changed
    }

    @MainActor
    private static func mergeWorkouts(in context: ModelContext) -> Bool {
        let entries = (
            try? context.fetch(
                FetchDescriptor<WorkoutEntry>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        var retained: [WorkoutEntry] = []
        var changed = false
        for entry in entries {
            guard let existing = retained.last(where: {
                RecordMergePolicy.isObviousLegacyWorkoutDuplicate($0, entry)
            }) else {
                retained.append(entry)
                continue
            }
            let estimate = entry.estimatedCalories.map {
                WorkoutCalorieEstimate(
                    calories: $0,
                    met: entry.calorieMET ?? 0,
                    activityLabel: "已有记录",
                    durationMinutes: entry.calorieDurationMinutes ?? 0,
                    durationWasEstimated: entry.calorieDurationEstimated
                )
            }
            RecordMergePolicy.mergeWorkout(
                existing,
                input: WorkoutMergeInput(
                    date: entry.date,
                    sessionID: entry.sourceSessionID,
                    turnID: entry.sourceTurnID,
                    exercise: entry.exercise,
                    exerciseID: entry.exerciseID,
                    setEntries: entry.setEntriesData.isEmpty ? nil : entry.setEntries,
                    sets: entry.sets,
                    reps: entry.reps,
                    weight: entry.weight,
                    restSeconds: entry.restSeconds,
                    durationMinutes: entry.durationMinutes,
                    sourceText: entry.notes,
                    media: entry.mediaAttachments,
                    isCorrection: true
                ),
                formScore: entry.formScore,
                intensity: entry.intensity,
                feedback: entry.feedback,
                calorieEstimate: estimate
            )
            context.delete(entry)
            changed = true
        }
        return changed
    }

    @MainActor
    private static func mergeBodyEntries(in context: ModelContext) -> Bool {
        let entries = (
            try? context.fetch(
                FetchDescriptor<BodyEntry>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        var retained: [BodyEntry] = []
        var changed = false
        for entry in entries {
            guard let existing = retained.last(where: {
                RecordMergePolicy.isObviousLegacyBodyDuplicate($0, entry)
            }) else {
                retained.append(entry)
                continue
            }
            RecordMergePolicy.mergeBody(
                existing,
                input: BodyMergeInput(
                    date: entry.date,
                    sessionID: entry.sourceSessionID,
                    turnID: entry.sourceTurnID,
                    weight: entry.weight,
                    bodyFat: entry.bodyFat,
                    waist: entry.waist,
                    sourceText: entry.notes,
                    media: entry.mediaAttachments,
                    isCorrection: true
                ),
                analysis: entry.analysis
            )
            context.delete(entry)
            changed = true
        }
        return changed
    }
}

private extension Array {
    func last(where predicate: (Element) -> Bool) -> Element? {
        reversed().first(where: predicate)
    }
}

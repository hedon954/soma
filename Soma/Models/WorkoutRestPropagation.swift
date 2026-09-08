import Foundation

/// 把用户明确给出的组间间歇落到非最后逻辑组。
/// 0 是零秒休息；nil 才是未记录。模型若把正数写在训练级或最后一组，仍回填到非最后组。
enum WorkoutRestPropagation {
    static func recorded(_ seconds: Int?) -> Int? {
        seconds
    }

    static func propagate(
        _ entries: [WorkoutSetEvidence],
        workoutRestSeconds: Int?
    ) -> [WorkoutSetEvidence] {
        guard !entries.isEmpty else {
            return entries
        }
        var draft = WorkoutRecordDraft(evidence: entries)
        let workoutFill = workoutRestSeconds.flatMap { $0 > 0 ? $0 : nil }
        let lastGroupRest = draft.groups.last?.efforts.last?.restSeconds
        let lastPositive = lastGroupRest.flatMap { $0 > 0 ? $0 : nil }
        let nonFinalHasPositive = draft.groups.dropLast().contains { group in
            (group.efforts.last?.restSeconds ?? 0) > 0
        }
        let migratedLastRest = !nonFinalHasPositive ? lastPositive : nil

        for index in draft.groups.indices {
            guard let lastEffort = draft.groups[index].efforts.indices.last else {
                continue
            }
            let isFinal = index == draft.groups.indices.last
            if isFinal {
                draft.groups[index].efforts[lastEffort].restSeconds = nil
                continue
            }
            let current = draft.groups[index].efforts[lastEffort].restSeconds
            if current != nil {
                continue
            }
            if let fill = workoutFill ?? migratedLastRest {
                draft.groups[index].efforts[lastEffort].restSeconds = fill
            } else {
                draft.groups[index].efforts[lastEffort].restSeconds = 0
            }
        }
        return draft.evidence
    }
}

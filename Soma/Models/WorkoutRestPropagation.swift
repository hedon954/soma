import Foundation

/// 把用户明确给出的组间间歇落到非最后逻辑组。模型常把 120 写在训练级或最后一组，
/// 却给前面的组写 0；卡片读的是逐组 evidence，所以会显示「间歇 0 秒」。
enum WorkoutRestPropagation {
    /// 0 是模型常写的“未知”，不是用户说的零秒休息。
    static func recorded(_ seconds: Int?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        return seconds
    }

    static func propagate(
        _ entries: [WorkoutSetEvidence],
        workoutRestSeconds: Int?
    ) -> [WorkoutSetEvidence] {
        guard !entries.isEmpty else {
            return entries
        }
        var draft = WorkoutRecordDraft(evidence: entries)
        guard draft.groups.count >= 2 else {
            return entries
        }
        let nonFinalHasPositive = draft.groups.dropLast().contains { group in
            (group.efforts.last?.restSeconds ?? 0) > 0
        }
        let fill: Int? = if let workoutRestSeconds, workoutRestSeconds > 0 {
            workoutRestSeconds
        } else if !nonFinalHasPositive,
                  let last = draft.groups.last?.efforts.last?.restSeconds,
                  last > 0
        {
            last
        } else {
            nil
        }
        guard let fill else {
            return entries
        }

        for index in draft.groups.indices {
            guard let lastEffort = draft.groups[index].efforts.indices.last else {
                continue
            }
            let isFinal = index == draft.groups.indices.last
            if isFinal {
                if !nonFinalHasPositive,
                   draft.groups[index].efforts[lastEffort].restSeconds == fill
                {
                    draft.groups[index].efforts[lastEffort].restSeconds = nil
                }
                continue
            }
            let current = draft.groups[index].efforts[lastEffort].restSeconds
            if current == nil || current == 0 {
                draft.groups[index].efforts[lastEffort].restSeconds = fill
            }
        }
        return draft.evidence
    }
}

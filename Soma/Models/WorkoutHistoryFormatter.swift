import Foundation

/// 训练历史的紧凑只读投影。它只压缩显示，不改变逐组、左右、间歇或录像事实。
enum WorkoutHistoryFormatter {
    static func text(for workout: WorkoutEntry) -> String {
        text(
            for: workout.setEntries,
            fallbackRestSeconds: workout.restSeconds
        )
    }

    static func text(for sets: [WorkoutSet]) -> String {
        let completed = sets
            .filter { $0.status == .completed }
            .sorted { $0.order < $1.order }
        let evidence = completed.flatMap { set -> [WorkoutSetEvidence] in
            let completedEfforts = set.efforts
                .filter { $0.status == .completed }
                .sorted { $0.order < $1.order }
            if !completedEfforts.isEmpty {
                return completedEfforts.map { effort in
                    WorkoutSetEvidence(
                        logicalSetIndex: set.order,
                        side: effort.side,
                        kind: set.kind,
                        targetKind: effort.targetKind,
                        reps: effort.actualReps,
                        durationSeconds: effort.actualDurationSeconds,
                        externalWeightKG: effort.actualWeightKG,
                        restSeconds: effort.actualRestSeconds,
                        recordedVideoPath: effort.recordedVideoPath,
                        recordedVideoKind: effort.recordedVideoKind
                    )
                }
            }
            return [WorkoutSetEvidence(
                logicalSetIndex: set.order,
                side: WorkoutEffortSide.none,
                kind: set.kind,
                targetKind: set.actualDurationSeconds == nil
                    ? .repetitions
                    : .duration,
                reps: set.actualReps,
                durationSeconds: set.actualDurationSeconds,
                externalWeightKG: set.actualWeightKG,
                restSeconds: set.actualRestSeconds,
                recordedVideoPath: set.recordedVideoPath,
                recordedVideoKind: set.recordedVideoKind
            )]
        }
        return text(for: evidence, fallbackRestSeconds: nil)
    }

    static func text(
        for evidence: [WorkoutSetEvidence],
        fallbackRestSeconds: Int?
    ) -> String {
        let draft = WorkoutRecordDraft(evidence: evidence)
        guard !draft.groups.isEmpty else { return "尚无完成数据" }

        var values = draft.displayRuns.map(runText)
        if let rest = commonRestSeconds(
            in: draft,
            fallback: fallbackRestSeconds
        ) {
            values.append("间歇 \(durationText(seconds: rest))")
        }
        return values.joined(separator: " · ")
    }

    private static func runText(_ run: WorkoutLogicalGroupRun) -> String {
        let group = run.representative
        let orderedEfforts = group.efforts.sorted { $0.sourceOrder < $1.sourceOrder }
        let details = orderedEfforts.compactMap(effortText)
        if details.isEmpty {
            return "\(run.count)组"
        }

        var values: [String] = []
        if group.sideMode != .simultaneous {
            values.append(group.sideMode.displayName)
        }
        if orderedEfforts.count == 2,
           group.sideMode == .alternating,
           effortValuesMatchIgnoringSide(orderedEfforts[0], orderedEfforts[1]),
           let detail = details.first
        {
            values.append("\(run.count)×每侧\(detail)")
        } else if details.count == 1, let detail = details.first {
            values.append("\(run.count)×\(detail)")
        } else {
            let sideDetails = orderedEfforts.compactMap { effort in
                effortText(effort).map {
                    "\(sideLabel(effort.side))\($0)"
                }
            }
            values.append("\(run.count)×\(sideDetails.joined(separator: "/"))")
        }
        return values.joined(separator: " ")
    }

    private static func effortText(_ effort: WorkoutEffortDraft) -> String? {
        var values: [String] = []
        switch effort.targetKind {
        case .repetitions:
            if let reps = effort.reps {
                values.append("\(reps)次")
            }
        case .duration:
            if let seconds = effort.durationSeconds {
                values.append("\(seconds)秒")
            }
        }
        if let weight = effort.externalWeightKG {
            values.append(weight == 0 ? "自重" : "\(number(weight))kg")
        }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private static func effortValuesMatchIgnoringSide(
        _ lhs: WorkoutEffortDraft,
        _ rhs: WorkoutEffortDraft
    ) -> Bool {
        lhs.kind == rhs.kind
            && lhs.targetKind == rhs.targetKind
            && lhs.reps == rhs.reps
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.externalWeightKG == rhs.externalWeightKG
    }

    private static func commonRestSeconds(
        in draft: WorkoutRecordDraft,
        fallback: Int?
    ) -> Int? {
        let groups = draft.groups.sorted { $0.sourceOrder < $1.sourceOrder }
        guard groups.count > 1 else { return nil }
        let rests = groups.dropLast().compactMap { group in
            group.efforts.max { $0.sourceOrder < $1.sourceOrder }?.restSeconds
        }
        if rests.count == groups.count - 1,
           let first = rests.first,
           rests.allSatisfy({ $0 == first })
        {
            return first
        }
        return fallback
    }

    private static func sideLabel(_ side: WorkoutEffortSide?) -> String {
        switch side {
        case .some(.left): "左"
        case .some(.right): "右"
        case nil, .some(.none): ""
        }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private static func durationText(seconds: Int) -> String {
        if seconds > 0, seconds.isMultiple(of: 60) {
            return "\(seconds / 60)min"
        }
        return "\(seconds)s"
    }
}

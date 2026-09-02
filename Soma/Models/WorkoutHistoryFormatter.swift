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

        return formattedRuns(
            in: draft,
            fallbackRestSeconds: fallbackRestSeconds
        )
        .map(runText)
        .joined(separator: " · ")
    }

    private struct FormattedGroup {
        let group: LogicalWorkoutGroupDraft
        /// The final set has no meaningful post-set rest. For run comparison it
        /// inherits the preceding interval so five identical sets still become
        /// one run, while its own singleton presentation stays rest-free.
        let comparisonRestSeconds: Int?
        let displayRestSeconds: Int?
    }

    private struct FormattedRun {
        var groups: [FormattedGroup]

        var count: Int {
            groups.count
        }

        var representative: FormattedGroup {
            groups[0]
        }

        var displayedRestSeconds: Int? {
            groups.compactMap(\.displayRestSeconds).last
                ?? (groups.count > 1 ? representative.comparisonRestSeconds : nil)
        }
    }

    private static func formattedRuns(
        in draft: WorkoutRecordDraft,
        fallbackRestSeconds: Int?
    ) -> [FormattedRun] {
        let groups = draft.groups.sorted { $0.sourceOrder < $1.sourceOrder }
        var priorInterval: Int?
        let formatted = groups.enumerated().map { index, group in
            let explicit = group.restPresentation.afterGroupSeconds
            let isFinal = index == groups.indices.last
            let displayRest = isFinal ? nil : (explicit ?? fallbackRestSeconds)
            let comparisonRest = displayRest
                ?? fallbackRestSeconds
                ?? priorInterval
            if let displayRest {
                priorInterval = displayRest
            }
            return FormattedGroup(
                group: group,
                comparisonRestSeconds: comparisonRest,
                displayRestSeconds: displayRest
            )
        }

        var runs: [FormattedRun] = []
        for group in formatted {
            if let last = runs.indices.last,
               groupsMatch(runs[last].representative, group)
            {
                runs[last].groups.append(group)
            } else {
                runs.append(FormattedRun(groups: [group]))
            }
        }
        return runs
    }

    private static func groupsMatch(
        _ lhs: FormattedGroup,
        _ rhs: FormattedGroup
    ) -> Bool {
        let left = lhs.group.efforts.sorted { $0.sourceOrder < $1.sourceOrder }
        let right = rhs.group.efforts.sorted { $0.sourceOrder < $1.sourceOrder }
        guard left.count == right.count,
              lhs.comparisonRestSeconds == rhs.comparisonRestSeconds,
              lhs.group.restPresentation.betweenSidesSeconds
              == rhs.group.restPresentation.betweenSidesSeconds
        else {
            return false
        }
        return zip(left, right).allSatisfy { lhsEffort, rhsEffort in
            lhsEffort.side == rhsEffort.side
                && effortValuesMatchIgnoringSide(lhsEffort, rhsEffort)
        }
    }

    private static func runText(_ run: FormattedRun) -> String {
        let group = run.representative.group
        let orderedEfforts = group.efforts.sorted { $0.sourceOrder < $1.sourceOrder }
        var values: [String] = []
        if orderedEfforts.count == 2,
           group.sideMode == .alternating,
           effortValuesMatchIgnoringSide(orderedEfforts[0], orderedEfforts[1])
        {
            values.append("左右分别")
            if let weight = weightText(orderedEfforts[0].externalWeightKG) {
                values.append(weight)
            }
            if let target = targetText(orderedEfforts[0], perSide: true) {
                values.append("\(target)×\(run.count)组")
            } else {
                values.append("\(run.count)组")
            }
        } else if orderedEfforts.count == 1, let effort = orderedEfforts.first {
            if group.sideMode != .simultaneous {
                values.append(sideModeText(group.sideMode))
            }
            if let weight = weightText(effort.externalWeightKG) {
                values.append(weight)
            }
            if let target = targetText(effort, perSide: false) {
                values.append("\(target)×\(run.count)组")
            } else {
                values.append("\(run.count)组")
            }
        } else {
            let sideDetails = orderedEfforts.compactMap { effort in
                compactEffortText(effort).map {
                    "\(sideLabel(effort.side))\($0)"
                }
            }
            if !sideDetails.isEmpty {
                values.append("\(sideDetails.joined(separator: "/"))×\(run.count)组")
            } else {
                values.append("\(run.count)组")
            }
        }
        if let between = group.restPresentation.betweenSidesSeconds {
            values.append("换侧\(durationText(seconds: between))")
        }
        if let rest = run.displayedRestSeconds {
            values.append("间歇\(durationText(seconds: rest))")
        }
        return values.joined(separator: " ")
    }

    private static func targetText(
        _ effort: WorkoutEffortDraft,
        perSide: Bool
    ) -> String? {
        let prefix = perSide ? "每侧" : ""
        switch effort.targetKind {
        case .repetitions:
            return effort.reps.map { "\(prefix)\($0)" }
        case .duration:
            return effort.durationSeconds.map { "\(prefix)\($0)秒" }
        }
    }

    private static func compactEffortText(_ effort: WorkoutEffortDraft) -> String? {
        var values: [String] = []
        if let weight = weightText(effort.externalWeightKG) {
            values.append(weight)
        }
        if let target = targetText(effort, perSide: false) {
            values.append(target)
        }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private static func weightText(_ weight: Double?) -> String? {
        weight.map { $0 == 0 ? "自重" : "\(number($0))kg" }
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
        "\(seconds)s"
    }

    private static func sideModeText(_ mode: WorkoutRecordSideMode) -> String {
        switch mode {
        case .simultaneous: "双侧同时"
        case .alternating: "左右分别"
        case .leftOnly: "仅左"
        case .rightOnly: "仅右"
        }
    }
}

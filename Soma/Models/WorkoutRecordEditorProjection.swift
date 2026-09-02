import Foundation

enum WorkoutRecordSideMode: String, CaseIterable, Identifiable, Sendable {
    case simultaneous
    case alternating
    case leftOnly
    case rightOnly

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .simultaneous: "双侧同时"
        case .alternating: "左右各做"
        case .leftOnly: "仅左"
        case .rightOnly: "仅右"
        }
    }

    /// 只有左右各做需要在数据块里区分两条 effort；单侧信息已由标题标签表达。
    var showsEffortSideLabel: Bool {
        self == .alternating
    }
}

private extension ExerciseLaterality {
    var workoutRecordLabel: String {
        switch self {
        case .none: "双侧同时"
        case .both: "左右各做"
        case .left: "仅左"
        case .right: "仅右"
        }
    }
}

private extension WorkoutTargetKind {
    var workoutRecordLabel: String {
        switch self {
        case .repetitions: "次数"
        case .duration: "时长"
        }
    }
}

/// 次数/时长和左右方式属于动作定义。记录只保存当次完成证据；旧记录若带错单位，
/// 编辑投影按动作定义解释同一个数值，不继续让记录形成第二套配置源。
struct ExerciseLoggingProfileSnapshot: Equatable, Sendable {
    var laterality: ExerciseLaterality
    var targetKind: WorkoutTargetKind

    init(laterality: ExerciseLaterality, targetKind: WorkoutTargetKind) {
        self.laterality = laterality
        self.targetKind = targetKind
    }

    init(_ exercise: ExerciseDefinition) {
        laterality = exercise.laterality
        targetKind = exercise.targetKind
    }
}

struct WorkoutEffortDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var sourceOrder: Int
    var side: WorkoutEffortSide?
    var kind: WorkoutSetKind?
    var targetKind: WorkoutTargetKind
    var persistsTargetKind: Bool
    var reps: Int?
    var durationSeconds: Int?
    var externalWeightKG: Double?
    var restSeconds: Int?
    var recordedVideoPath: String?
    var recordedVideoKind: WorkoutRecordingEvidenceKind?

    init(
        id: UUID = UUID(),
        sourceOrder: Int,
        evidence: WorkoutSetEvidence
    ) {
        self.id = id
        self.sourceOrder = sourceOrder
        side = evidence.side
        kind = evidence.kind
        targetKind = evidence.targetKind
            ?? (evidence.durationSeconds == nil ? .repetitions : .duration)
        persistsTargetKind = evidence.targetKind != nil
        reps = evidence.reps
        durationSeconds = evidence.durationSeconds
        externalWeightKG = evidence.externalWeightKG
        restSeconds = evidence.restSeconds
        recordedVideoPath = evidence.recordedVideoPath
        recordedVideoKind = evidence.recordedVideoKind
    }

    init(
        id: UUID = UUID(),
        sourceOrder: Int,
        side: WorkoutEffortSide? = nil,
        kind: WorkoutSetKind? = nil,
        targetKind: WorkoutTargetKind = .repetitions,
        persistsTargetKind: Bool = true,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        externalWeightKG: Double? = nil,
        restSeconds: Int? = nil,
        recordedVideoPath: String? = nil,
        recordedVideoKind: WorkoutRecordingEvidenceKind? = nil
    ) {
        self.id = id
        self.sourceOrder = sourceOrder
        self.side = side
        self.kind = kind
        self.targetKind = targetKind
        self.persistsTargetKind = persistsTargetKind
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.externalWeightKG = externalWeightKG
        self.restSeconds = restSeconds
        self.recordedVideoPath = recordedVideoPath
        self.recordedVideoKind = recordedVideoKind
    }

    func evidence(logicalSetIndex: Int?) -> WorkoutSetEvidence {
        WorkoutSetEvidence(
            logicalSetIndex: logicalSetIndex,
            side: side,
            kind: kind,
            targetKind: persistsTargetKind ? targetKind : nil,
            reps: targetKind == .repetitions ? reps : nil,
            durationSeconds: targetKind == .duration ? durationSeconds : nil,
            externalWeightKG: externalWeightKG,
            restSeconds: restSeconds,
            recordedVideoPath: recordedVideoPath,
            recordedVideoKind: recordedVideoKind
        )
    }
}

struct LogicalWorkoutGroupDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var logicalSetIndex: Int?
    var sourceOrder: Int
    var efforts: [WorkoutEffortDraft]

    init(
        id: UUID = UUID(),
        logicalSetIndex: Int?,
        sourceOrder: Int,
        efforts: [WorkoutEffortDraft]
    ) {
        self.id = id
        self.logicalSetIndex = logicalSetIndex
        self.sourceOrder = sourceOrder
        self.efforts = efforts
    }

    var sideMode: WorkoutRecordSideMode {
        let sides = Set(efforts.compactMap(\.side))
        if sides.contains(.left), sides.contains(.right) {
            return .alternating
        }
        if sides == [.left] {
            return .leftOnly
        }
        if sides == [.right] {
            return .rightOnly
        }
        return .simultaneous
    }

    var targetKind: WorkoutTargetKind? {
        let kinds = Set(efforts.map(\.targetKind))
        return kinds.count == 1 ? kinds.first : nil
    }

    var targetKindLabel: String {
        switch targetKind {
        case .some(.duration): "时长"
        case .some(.repetitions): "次数"
        case nil: "混合"
        }
    }

    var restPresentation: WorkoutGroupRestPresentation {
        let ordered = efforts.sorted { $0.sourceOrder < $1.sourceOrder }
        guard sideMode == .alternating, ordered.count >= 2 else {
            return WorkoutGroupRestPresentation(
                betweenSidesSeconds: nil,
                afterGroupSeconds: ordered.last?.restSeconds,
                isAmbiguous: false
            )
        }
        let between = ordered.first?.restSeconds
        let after = ordered.last?.restSeconds
        return WorkoutGroupRestPresentation(
            betweenSidesSeconds: between,
            afterGroupSeconds: after,
            isAmbiguous: between == nil || after == nil
        )
    }

    fileprivate var displaySignature: WorkoutGroupDisplaySignature {
        WorkoutGroupDisplaySignature(
            efforts: efforts
                .sorted { $0.sourceOrder < $1.sourceOrder }
                .map {
                    WorkoutEffortDisplaySignature(
                        side: $0.side,
                        kind: $0.kind,
                        targetKind: $0.targetKind,
                        reps: $0.reps,
                        durationSeconds: $0.durationSeconds,
                        externalWeightKG: $0.externalWeightKG
                    )
                }
        )
    }
}

struct WorkoutGroupRestPresentation: Equatable, Sendable {
    var betweenSidesSeconds: Int?
    var afterGroupSeconds: Int?
    var isAmbiguous: Bool
}

struct WorkoutLogicalGroupRun: Identifiable, Equatable, Sendable {
    var id: UUID {
        groups[0].id
    }

    var groups: [LogicalWorkoutGroupDraft]
    var count: Int {
        groups.count
    }

    var representative: LogicalWorkoutGroupDraft {
        groups[0]
    }

    func restTargetGroupIDs(
        effortIndex: Int,
        effortCount: Int,
        finalGroupID: UUID?
    ) -> Set<UUID> {
        Set(groups.compactMap { group in
            let isAfterGroupRest = effortIndex == effortCount - 1
            return isAfterGroupRest && group.id == finalGroupID ? nil : group.id
        })
    }
}

struct WorkoutRecordDraft: Equatable, Sendable {
    var groups: [LogicalWorkoutGroupDraft]
    var loggingProfile: ExerciseLoggingProfileSnapshot?

    init(
        evidence: [WorkoutSetEvidence],
        loggingProfile: ExerciseLoggingProfileSnapshot? = nil
    ) {
        enum GroupKey: Hashable {
            case logical(Int)
            case legacy(Int)
        }

        var keys: [GroupKey] = []
        var grouped: [GroupKey: [WorkoutEffortDraft]] = [:]
        var indexes: [GroupKey: Int?] = [:]

        for (sourceOrder, item) in evidence.enumerated() {
            let key = item.logicalSetIndex.map(GroupKey.logical)
                ?? GroupKey.legacy(sourceOrder)
            if grouped[key] == nil {
                keys.append(key)
                grouped[key] = []
                indexes[key] = item.logicalSetIndex
            }
            grouped[key, default: []].append(
                WorkoutEffortDraft(sourceOrder: sourceOrder, evidence: item)
            )
        }

        groups = keys.enumerated().map { sourceOrder, key in
            LogicalWorkoutGroupDraft(
                logicalSetIndex: indexes[key] ?? nil,
                sourceOrder: sourceOrder,
                efforts: grouped[key] ?? []
            )
        }
        self.loggingProfile = nil
        if let loggingProfile {
            applyLoggingProfile(loggingProfile)
        }
    }

    init(
        groups: [LogicalWorkoutGroupDraft],
        loggingProfile: ExerciseLoggingProfileSnapshot? = nil
    ) {
        self.groups = groups
        self.loggingProfile = loggingProfile
    }

    var evidence: [WorkoutSetEvidence] {
        groups
            .sorted { $0.sourceOrder < $1.sourceOrder }
            .flatMap { group in
                group.efforts
                    .sorted { $0.sourceOrder < $1.sourceOrder }
                    .map { $0.evidence(logicalSetIndex: group.logicalSetIndex) }
            }
    }

    var displayRuns: [WorkoutLogicalGroupRun] {
        var runs: [WorkoutLogicalGroupRun] = []
        for group in groups.sorted(by: { $0.sourceOrder < $1.sourceOrder }) {
            if let last = runs.indices.last,
               runs[last].representative.displaySignature == group.displaySignature
            {
                runs[last].groups.append(group)
            } else {
                runs.append(WorkoutLogicalGroupRun(groups: [group]))
            }
        }
        return runs
    }

    var finalGroupID: UUID? {
        groups.max { $0.sourceOrder < $1.sourceOrder }?.id
    }

    var headerTargetKindLabel: String? {
        let explicitEfforts = groups.flatMap(\.efforts).filter(\.persistsTargetKind)
        if explicitEfforts.isEmpty, let loggingProfile {
            return loggingProfile.targetKind.workoutRecordLabel
        }
        let kinds = Set(groups.flatMap(\.efforts).map(\.targetKind))
        if kinds.count == 1 {
            return kinds.first?.workoutRecordLabel
        }
        return kinds.isEmpty ? nil : "混合"
    }

    var headerSideLabel: String? {
        let hasExplicitSide = groups.flatMap(\.efforts).contains { $0.side != nil }
        if !hasExplicitSide, let loggingProfile {
            return loggingProfile.laterality.workoutRecordLabel
        }
        let modes = Set(groups.map(\.sideMode))
        if modes.count == 1 {
            return modes.first?.displayName
        }
        return modes.isEmpty ? nil : "混合侧别"
    }

    func sideLabel(for group: LogicalWorkoutGroupDraft) -> String {
        group.efforts.contains { $0.side != nil }
            ? group.sideMode.displayName
            : loggingProfile?.laterality.workoutRecordLabel ?? group.sideMode.displayName
    }

    mutating func applyLoggingProfile(_ profile: ExerciseLoggingProfileSnapshot) {
        loggingProfile = profile
        for groupIndex in groups.indices {
            for effortIndex in groups[groupIndex].efforts.indices {
                var effort = groups[groupIndex].efforts[effortIndex]
                if !effort.persistsTargetKind {
                    if profile.targetKind == .duration {
                        if effort.durationSeconds == nil {
                            effort.durationSeconds = effort.reps
                        }
                        effort.reps = nil
                    } else {
                        if effort.reps == nil {
                            effort.reps = effort.durationSeconds
                        }
                        effort.durationSeconds = nil
                    }
                    effort.targetKind = profile.targetKind
                    effort.persistsTargetKind = true
                }
                if effort.side == nil, groups[groupIndex].efforts.count == 1 {
                    switch profile.laterality {
                    case .none:
                        effort.side = WorkoutEffortSide.none
                    case .left:
                        effort.side = .left
                    case .right:
                        effort.side = .right
                    case .both:
                        break
                    }
                }
                groups[groupIndex].efforts[effortIndex] = effort
            }
        }
    }

    var isValid: Bool {
        groups.count <= 100
            && groups.allSatisfy { group in
                group.logicalSetIndex.map { (1 ... 100).contains($0) } ?? true
                    && group.efforts.allSatisfy { effort in
                        let targetIsValid = switch effort.targetKind {
                        case .repetitions:
                            effort.reps.map { (1 ... 1000).contains($0) } ?? true
                        case .duration:
                            effort.durationSeconds.map { (1 ... 86400).contains($0) } ?? true
                        }
                        return targetIsValid
                            && (effort.externalWeightKG.map { (0 ... 1000).contains($0) } ?? true)
                            && (effort.restSeconds.map { (0 ... 3600).contains($0) } ?? true)
                    }
            }
    }

    mutating func updateEffortValue<Value>(
        in groupIDs: Set<UUID>,
        effortIndex: Int,
        keyPath: WritableKeyPath<WorkoutEffortDraft, Value>,
        value: Value
    ) {
        for groupIndex in groups.indices where groupIDs.contains(groups[groupIndex].id) {
            guard groups[groupIndex].efforts.indices.contains(effortIndex) else {
                continue
            }
            groups[groupIndex].efforts[effortIndex][keyPath: keyPath] = value
        }
    }

    mutating func appendGroup(copying groupID: UUID? = nil) {
        let explicitlyCopiedSource = groupID.flatMap { selectedID in
            groups.first { $0.id == selectedID }
        }
        let source = explicitlyCopiedSource ?? groups.max { $0.sourceOrder < $1.sourceOrder }
        let copiesValues = explicitlyCopiedSource != nil
        let nextIndex = (groups.compactMap(\.logicalSetIndex).max() ?? 0) + 1
        let nextOrder = (groups.map(\.sourceOrder).max() ?? -1) + 1
        let nextEffortOrder = (groups.flatMap(\.efforts).map(\.sourceOrder).max() ?? -1) + 1

        let efforts: [WorkoutEffortDraft] = if let source {
            source.efforts.enumerated().map { offset, effort in
                WorkoutEffortDraft(
                    sourceOrder: nextEffortOrder + offset,
                    side: effort.side,
                    kind: effort.kind,
                    targetKind: effort.targetKind,
                    persistsTargetKind: true,
                    reps: copiesValues ? effort.reps : nil,
                    durationSeconds: copiesValues ? effort.durationSeconds : nil,
                    externalWeightKG: copiesValues ? effort.externalWeightKG : nil,
                    restSeconds: copiesValues ? effort.restSeconds : nil
                )
            }
        } else {
            defaultEfforts(startingAt: nextEffortOrder)
        }

        groups.append(LogicalWorkoutGroupDraft(
            logicalSetIndex: nextIndex,
            sourceOrder: nextOrder,
            efforts: efforts
        ))
    }

    private func defaultEfforts(startingAt sourceOrder: Int) -> [WorkoutEffortDraft] {
        guard let loggingProfile else {
            return [WorkoutEffortDraft(sourceOrder: sourceOrder)]
        }
        let sides: [WorkoutEffortSide] = switch loggingProfile.laterality {
        case .none: [.none]
        case .both: [.left, .right]
        case .left: [.left]
        case .right: [.right]
        }
        return sides.enumerated().map { offset, side in
            WorkoutEffortDraft(
                sourceOrder: sourceOrder + offset,
                side: side,
                targetKind: loggingProfile.targetKind
            )
        }
    }

    mutating func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }
}

struct WorkoutRecordEditorProjection: Equatable, Sendable {
    var draft: WorkoutRecordDraft

    init(
        evidence: [WorkoutSetEvidence],
        loggingProfile: ExerciseLoggingProfileSnapshot? = nil
    ) {
        draft = WorkoutRecordDraft(
            evidence: evidence,
            loggingProfile: loggingProfile
        )
    }

    var displayRuns: [WorkoutLogicalGroupRun] {
        draft.displayRuns
    }

    var evidence: [WorkoutSetEvidence] {
        draft.evidence
    }
}

private struct WorkoutGroupDisplaySignature: Equatable, Sendable {
    var efforts: [WorkoutEffortDisplaySignature]
}

private struct WorkoutEffortDisplaySignature: Equatable, Sendable {
    var side: WorkoutEffortSide?
    var kind: WorkoutSetKind?
    var targetKind: WorkoutTargetKind
    var reps: Int?
    var durationSeconds: Int?
    var externalWeightKG: Double?
}

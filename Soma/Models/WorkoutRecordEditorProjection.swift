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

    init(evidence: [WorkoutSetEvidence]) {
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
    }

    init(groups: [LogicalWorkoutGroupDraft]) {
        self.groups = groups
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
            [WorkoutEffortDraft(sourceOrder: nextEffortOrder)]
        }

        groups.append(LogicalWorkoutGroupDraft(
            logicalSetIndex: nextIndex,
            sourceOrder: nextOrder,
            efforts: efforts
        ))
    }

    mutating func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }
}

struct WorkoutRecordEditorProjection: Equatable, Sendable {
    var draft: WorkoutRecordDraft

    init(evidence: [WorkoutSetEvidence]) {
        draft = WorkoutRecordDraft(evidence: evidence)
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

import Foundation

enum WorkoutPrescriptionFormatter {
    static func exerciseAnnouncement(
        name: String,
        prescription: TemplateExercisePrescription
    ) -> String {
        let sets = prescription.plannedSets.sorted { $0.order < $1.order }
        guard !sets.isEmpty else {
            return "接下来，\(name)，请按状态完成"
        }

        let sideCue = prescription.laterality == .both
            ? "，左右各做，左侧先开始"
            : ""
        return "接下来，\(name)，\(announcementGroups(sets))\(sideCue)"
    }

    static func exerciseSummary(
        _ prescription: TemplateExercisePrescription,
        includesLaterality: Bool = true
    ) -> String {
        let sets = prescription.plannedSets.sorted { $0.order < $1.order }
        if sets.isEmpty {
            return legacySummary(prescription)
        }

        var tokens: [String] = []
        if includesLaterality {
            tokens.append(contentsOf: lateralityToken(prescription.laterality))
        }
        let mixedKinds = Set(sets.map(\.kind)).count > 1
        let clusters = TrainingPrescriptionClustering.clusters(in: sets)
        tokens.append(contentsOf: clusters.map { cluster in
            compactCluster(
                sets[cluster.startIndex],
                count: cluster.count,
                laterality: prescription.laterality,
                includeKind: mixedKinds || sets[cluster.startIndex].kind != .working
            )
        })
        return tokens.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func setTarget(
        set: WorkoutSet?,
        effort: WorkoutEffort? = nil
    ) -> String {
        guard let set else { return "按状态完成" }
        let targetKind = effort?.targetKind ?? set.plannedTargetKind
        let reps = effort?.plannedReps ?? set.plannedReps
        let duration = effort?.plannedDurationSeconds
            ?? set.plannedDurationSeconds
        let weight = effort?.plannedWeightKG ?? set.plannedWeightKG
        var tokens: [String] = []
        if let effort, effort.side != .none {
            tokens.append(sideName(effort.side))
        }
        if let weight {
            tokens.append(weight == 0 ? "自重" : "\(number(weight)) kg")
        }
        switch targetKind {
        case .repetitions:
            if let reps {
                tokens.append("\(reps) 次")
            }
        case .duration:
            if let duration {
                tokens.append("\(duration) 秒")
            }
        }
        return tokens.isEmpty ? "按状态完成" : tokens.joined(separator: " · ")
    }

    static func effortAnnouncement(
        set: WorkoutSet,
        effort: WorkoutEffort?
    ) -> String {
        let side = effort.map { sideName($0.side) + "，" } ?? ""
        return "开始第 \(set.order) 组，\(side)\(setTarget(set: set, effort: effort))"
    }

    static func sideName(_ side: WorkoutEffortSide) -> String {
        switch side {
        case .none: ""
        case .left: "左侧"
        case .right: "右侧"
        }
    }

    static func kindTitle(_ kind: WorkoutSetKind) -> String {
        switch kind {
        case .warmup: "热身组"
        case .working: "工作组"
        case .drop: "递减组"
        case .failure: "力竭组"
        case .custom: "自定义组"
        }
    }

    private static func announcementGroups(
        _ sets: [TemplateSetPrescriptionValue]
    ) -> String {
        let clusters = TrainingPrescriptionClustering.clusters(in: sets)
        let mixedKinds = Set(sets.map(\.kind)).count > 1
        if clusters.count == 1 {
            return "共 \(sets.count) 组，每组 \(targetToken(for: sets[0]))"
        }
        if !mixedKinds, clusters.allSatisfy({ $0.count == 1 }) {
            let detail = sets.map(targetToken(for:)).joined(separator: "、")
            return "共 \(sets.count) 组：\(detail)"
        }
        return clusters.map { cluster in
            let sample = sets[cluster.startIndex]
            let target = targetToken(for: sample)
            let kind = kindPhrase(sample.kind, includeWorking: mixedKinds)
            let prefix = kind.isEmpty ? "" : "\(kind) "
            if cluster.count == 1 {
                return "\(prefix)1 组 \(target)"
            }
            return "\(prefix)\(cluster.count) 组每组 \(target)"
        }.joined(separator: "，")
    }

    private static func compactCluster(
        _ set: TemplateSetPrescriptionValue,
        count: Int,
        laterality: ExerciseLaterality,
        includeKind: Bool
    ) -> String {
        var parts: [String] = []
        if includeKind {
            parts.append(kindPhrase(set.kind, includeWorking: true))
        }
        if let target = compactTarget(set) {
            parts.append("\(count)×\(target)")
        } else if count > 1 {
            parts.append("\(count)组")
        }
        parts.append(contentsOf: weightTokens(set, laterality: laterality))
        if let rest = set.restAfterSetSeconds {
            parts.append("歇\(rest)秒")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func compactTarget(
        _ set: TemplateSetPrescriptionValue
    ) -> String? {
        switch set.targetKind {
        case .repetitions:
            set.targetReps.map { "\($0)次" }
        case .duration:
            set.targetDurationSeconds.map { "\($0)秒" }
        }
    }

    private static func weightTokens(
        _ set: TemplateSetPrescriptionValue,
        laterality: ExerciseLaterality
    ) -> [String] {
        switch laterality {
        case .both:
            [
                set.leftWeightKG.map { weightToken($0, prefix: "左") },
                set.rightWeightKG.map { weightToken($0, prefix: "右") }
            ].compactMap { $0 }
        case .left:
            (set.leftWeightKG ?? set.targetWeightKG).map {
                weightToken($0, prefix: "左")
            }.map { [$0] } ?? []
        case .right:
            (set.rightWeightKG ?? set.targetWeightKG).map {
                weightToken($0, prefix: "右")
            }.map { [$0] } ?? []
        case .none:
            set.targetWeightKG.map { [weightToken($0, prefix: "")] } ?? []
        }
    }

    private static func weightToken(_ value: Double, prefix: String) -> String {
        let amount = value == 0 ? "自重" : "\(number(value))kg"
        return prefix.isEmpty ? amount : "\(prefix)\(amount)"
    }

    private static func lateralityToken(_ laterality: ExerciseLaterality) -> [String] {
        switch laterality {
        case .none: []
        case .both: ["左右分开"]
        case .left: ["只做左侧"]
        case .right: ["只做右侧"]
        }
    }

    private static func kindPhrase(
        _ kind: WorkoutSetKind,
        includeWorking: Bool
    ) -> String {
        switch kind {
        case .warmup: "热身"
        case .working: includeWorking ? "工作" : ""
        case .drop: "递减"
        case .failure: "力竭"
        case .custom: "自定义"
        }
    }

    private static func legacySummary(
        _ prescription: TemplateExercisePrescription
    ) -> String {
        var values: [String] = []
        values.append(contentsOf: lateralityToken(prescription.laterality))
        if let sets = prescription.targetSets {
            values.append("\(sets)组")
        }
        if let reps = prescription.targetReps {
            values.append("每组 \(reps) 次")
        }
        if let weight = prescription.targetWeightKG {
            values.append("\(number(weight))kg")
        }
        if let rest = prescription.targetRestSeconds {
            values.append("歇\(rest)秒")
        }
        if prescription.firstSetIsWarmup {
            values.append("首组热身")
        }
        return values.isEmpty ? "处方值未记录" : values.joined(separator: " · ")
    }

    private static func targetToken(
        for set: TemplateSetPrescriptionValue
    ) -> String {
        switch set.targetKind {
        case .repetitions:
            set.targetReps.map { "\($0) 次" } ?? "按状态完成"
        case .duration:
            set.targetDurationSeconds.map { "\($0) 秒" }
                ?? "按状态完成"
        }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }
}

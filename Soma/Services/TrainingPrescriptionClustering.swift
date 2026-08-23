import Foundation

struct TrainingPrescriptionCluster: Equatable {
    var startIndex: Int
    var count: Int
}

enum TrainingPrescriptionClustering {
    static func clusters(
        in sets: [TemplateSetPrescriptionValue]
    ) -> [TrainingPrescriptionCluster] {
        consecutiveGroups(sets) { lhs, rhs in
            lhs.clusterSignature == rhs.clusterSignature
        }
    }

    static func consecutiveGroups<T>(
        _ items: [T],
        same: (T, T) -> Bool
    ) -> [TrainingPrescriptionCluster] {
        guard !items.isEmpty else { return [] }
        var groups: [TrainingPrescriptionCluster] = [
            TrainingPrescriptionCluster(startIndex: 0, count: 1)
        ]
        for index in 1 ..< items.count {
            if same(items[index - 1], items[index]) {
                groups[groups.count - 1].count += 1
            } else {
                groups.append(
                    TrainingPrescriptionCluster(startIndex: index, count: 1)
                )
            }
        }
        return groups
    }
}

extension TemplateSetPrescriptionValue {
    var clusterSignature: TemplateSetPrescriptionClusterSignature {
        TemplateSetPrescriptionClusterSignature(
            kind: kind,
            targetKind: targetKind,
            targetReps: targetReps,
            targetDurationSeconds: targetDurationSeconds,
            targetWeightKG: targetWeightKG,
            leftWeightKG: leftWeightKG,
            rightWeightKG: rightWeightKG,
            notes: notes
        )
    }
}

struct TemplateSetPrescriptionClusterSignature: Equatable {
    var kind: WorkoutSetKind
    var targetKind: WorkoutTargetKind
    var targetReps: Int?
    var targetDurationSeconds: Int?
    var targetWeightKG: Double?
    var leftWeightKG: Double?
    var rightWeightKG: Double?
    var notes: String
}

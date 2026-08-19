import Foundation

enum TrainingPrescriptionDraftClustering {
    static func clusters(
        in drafts: [TrainingSetPrescriptionDraft]
    ) -> [TrainingPrescriptionCluster] {
        TrainingPrescriptionClustering.consecutiveGroups(drafts) { lhs, rhs in
            lhs.clusterSignature == rhs.clusterSignature
        }
    }

    static func resize(
        _ drafts: [TrainingSetPrescriptionDraft],
        startIndex: Int,
        count: Int,
        newCount: Int
    ) -> [TrainingSetPrescriptionDraft] {
        let clamped = min(max(newCount, 1), 100)
        guard drafts.indices.contains(startIndex),
              count >= 1,
              startIndex + count <= drafts.count
        else {
            return drafts
        }
        if clamped == count {
            return drafts
        }

        var result = drafts
        let end = startIndex + count
        if clamped < count {
            let removing = count - clamped
            guard result.count - removing >= 1 else { return drafts }
            result.removeSubrange((end - removing) ..< end)
        } else {
            let template = result[end - 1]
            let additions = (0 ..< (clamped - count)).map { _ -> TrainingSetPrescriptionDraft in
                var copy = template
                copy.id = UUID()
                return copy
            }
            result.insert(contentsOf: additions, at: end)
        }
        return normalized(result)
    }

    static func moveCluster(
        _ drafts: [TrainingSetPrescriptionDraft],
        startIndex: Int,
        count: Int,
        direction: Int
    ) -> [TrainingSetPrescriptionDraft] {
        let groups = clusters(in: drafts)
        guard let index = groups.firstIndex(where: {
            $0.startIndex == startIndex && $0.count == count
        })
        else {
            return drafts
        }
        let destination = index + direction
        guard groups.indices.contains(destination) else { return drafts }

        let first = groups[min(index, destination)]
        let second = groups[max(index, destination)]
        let lower = Array(
            drafts[first.startIndex ..< first.startIndex + first.count]
        )
        let upper = Array(
            drafts[second.startIndex ..< second.startIndex + second.count]
        )
        var result = drafts
        result.replaceSubrange(
            first.startIndex ..< second.startIndex + second.count,
            with: upper + lower
        )
        return normalized(result)
    }

    static func removeCluster(
        _ drafts: [TrainingSetPrescriptionDraft],
        startIndex: Int,
        count: Int
    ) -> [TrainingSetPrescriptionDraft] {
        guard drafts.indices.contains(startIndex),
              count >= 1,
              startIndex + count <= drafts.count,
              drafts.count - count >= 1
        else {
            return drafts
        }
        var result = drafts
        result.removeSubrange(startIndex ..< startIndex + count)
        return normalized(result)
    }

    private static func normalized(
        _ drafts: [TrainingSetPrescriptionDraft]
    ) -> [TrainingSetPrescriptionDraft] {
        drafts.enumerated().map { index, draft in
            var copy = draft
            copy.order = index + 1
            return copy
        }
    }
}

extension TrainingSetPrescriptionDraft {
    var clusterSignature: TrainingSetDraftClusterSignature {
        TrainingSetDraftClusterSignature(
            kind: kind,
            targetKind: targetKind,
            reps: reps.trimmingCharacters(in: .whitespacesAndNewlines),
            durationSeconds: durationSeconds.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            weight: weight.trimmingCharacters(in: .whitespacesAndNewlines),
            leftWeight: leftWeight.trimmingCharacters(in: .whitespacesAndNewlines),
            rightWeight: rightWeight.trimmingCharacters(in: .whitespacesAndNewlines),
            restBetweenSidesSeconds: restBetweenSidesSeconds.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            restAfterSetSeconds: restAfterSetSeconds.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct TrainingSetDraftClusterSignature: Equatable {
    var kind: WorkoutSetKind
    var targetKind: WorkoutTargetKind
    var reps: String
    var durationSeconds: String
    var weight: String
    var leftWeight: String
    var rightWeight: String
    var restBetweenSidesSeconds: String
    var restAfterSetSeconds: String
    var notes: String
}

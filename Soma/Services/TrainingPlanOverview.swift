import Foundation

/// 训练计划的确定性效果总览：由当前模板的处方（动作 × 肌群 × 组数）
/// 本地聚合生成，不依赖 AI，也不是个人受力测量。
enum TrainingPlanOverview {
    struct ExerciseInput {
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let targetSets: Int?

        init(
            primaryMuscles: [String],
            secondaryMuscles: [String],
            targetSets: Int?
        ) {
            self.primaryMuscles = primaryMuscles
            self.secondaryMuscles = secondaryMuscles
            self.targetSets = targetSets
        }
    }

    struct Summary: Equatable {
        let exerciseCount: Int
        let totalSets: Int
        let intensities: [MuscleGroup: Double]
        let primaryFocus: [MuscleGroup]
        let secondaryFocus: [MuscleGroup]

        var overviewText: String {
            guard !intensities.isEmpty else {
                return "动作还没有肌群标注，补充主要肌群后即可生成总览。"
            }
            var parts: [String] = []
            var scale = "\(exerciseCount) 个动作"
            if totalSets > 0 {
                scale += " · 共 \(totalSets) 组"
            }
            parts.append(scale)
            parts.append("覆盖 \(intensities.count) 个肌群")
            if !primaryFocus.isEmpty {
                parts.append(
                    "主要刺激"
                        + primaryFocus.map(\.displayName).joined(separator: "、")
                )
            }
            if !secondaryFocus.isEmpty {
                parts.append(
                    "辅助"
                        + secondaryFocus.map(\.displayName).joined(separator: "、")
                )
            }
            return parts.joined(separator: "，") + "。"
        }
    }

    static func summarize(_ exercises: [ExerciseInput]) -> Summary {
        let primaryMaps = exercises.map { exercise in
            let weight = Double(max(exercise.targetSets ?? 1, 1))
            return MuscleGroupMapping.intensityMap(
                primary: exercise.primaryMuscles,
                secondary: [],
                primaryWeight: weight,
                secondaryWeight: 0
            )
        }
        let secondaryMaps = exercises.map { exercise in
            let weight = Double(max(exercise.targetSets ?? 1, 1))
            return MuscleGroupMapping.intensityMap(
                primary: [],
                secondary: exercise.secondaryMuscles,
                primaryWeight: 0,
                secondaryWeight: weight
            )
        }
        let primaryScores = MuscleGroupMapping.merge(primaryMaps)
        let secondaryScores = MuscleGroupMapping.merge(secondaryMaps)
        let weightedMaps = [
            primaryScores,
            secondaryScores.mapValues { $0 * 0.45 }
        ]
        let intensities = MuscleGroupMapping.normalized(
            MuscleGroupMapping.merge(weightedMaps)
        )
        let primaryFocus = ranked(primaryScores)
            .prefix(3)
            .map(\.key)
        let primaryGroups = Set(primaryScores.keys)
        let secondaryFocus = ranked(secondaryScores)
            .filter { !primaryGroups.contains($0.key) }
            .prefix(3)
            .map(\.key)
        return Summary(
            exerciseCount: exercises.count,
            totalSets: exercises.compactMap(\.targetSets).reduce(0, +),
            intensities: intensities,
            primaryFocus: Array(primaryFocus),
            secondaryFocus: Array(secondaryFocus)
        )
    }

    private static func ranked(
        _ scores: [MuscleGroup: Double]
    ) -> [(key: MuscleGroup, value: Double)] {
        scores.sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key.rawValue < $1.key.rawValue
        }
    }
}

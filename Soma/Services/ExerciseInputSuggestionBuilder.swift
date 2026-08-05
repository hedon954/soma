import Foundation

struct ExerciseInputSuggestion: Identifiable, Equatable {
    let id: UUID
    let exerciseName: String
    let recentSummary: String?
    let recentDate: Date?

    /// 点一次就写入输入框的完整草稿。没有历史时只给动作名，不补默认数值。
    var draftText: String {
        guard let recentSummary, !recentSummary.isEmpty else {
            return exerciseName
        }
        return "\(exerciseName)：\(recentSummary)"
    }
}

/// ADR 0046：把「动作名」与「最近一次训练容量」合并成一条建议，
/// 让聊天记录草稿从两步选择降为一次点击。合并规则是本地确定性的，
/// 不引入 AI，也不为缺失历史编造数值。
enum ExerciseInputSuggestionBuilder {
    static let defaultLimit = 5

    struct ExerciseInput: Equatable {
        let id: UUID
        let name: String
        let isArchived: Bool

        init(id: UUID, name: String, isArchived: Bool = false) {
            self.id = id
            self.name = name
            self.isArchived = isArchived
        }
    }

    struct RecentCapacityInput: Equatable {
        let exerciseID: UUID
        let date: Date
        let text: String
    }

    static func suggestions(
        query: String,
        exercises: [ExerciseInput],
        recentCapacities: [RecentCapacityInput],
        limit: Int = defaultLimit
    ) -> [ExerciseInputSuggestion] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

        let latestByExercise = latestCapacities(recentCapacities)
        let matches = exercises
            .filter {
                !$0.isArchived
                    && $0.name.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .map { exercise -> ExerciseInputSuggestion in
                let latest = latestByExercise[exercise.id]
                return ExerciseInputSuggestion(
                    id: exercise.id,
                    exerciseName: exercise.name,
                    recentSummary: latest?.text,
                    recentDate: latest?.date
                )
            }

        return matches
            .sorted { lhs, rhs in
                let leftPrefix = hasPrefix(lhs.exerciseName, normalizedQuery)
                let rightPrefix = hasPrefix(rhs.exerciseName, normalizedQuery)
                if leftPrefix != rightPrefix {
                    return leftPrefix
                }
                switch (lhs.recentDate, rhs.recentDate) {
                case let (left?, right?) where left != right:
                    return left > right
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    break
                }
                return lhs.exerciseName.localizedStandardCompare(rhs.exerciseName)
                    == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func latestCapacities(
        _ values: [RecentCapacityInput]
    ) -> [UUID: RecentCapacityInput] {
        var latest: [UUID: RecentCapacityInput] = [:]
        for value in values where !value.text.isEmpty {
            guard let current = latest[value.exerciseID] else {
                latest[value.exerciseID] = value
                continue
            }
            if value.date > current.date {
                latest[value.exerciseID] = value
            }
        }
        return latest
    }

    private static func hasPrefix(_ name: String, _ query: String) -> Bool {
        name.range(of: query, options: [.caseInsensitive, .anchored]) != nil
    }
}

import Foundation

enum PortableExportText {
    static func meal(
        _ meal: MealEntryDTO,
        sourceText: String?,
        agentAnswer: String?
    ) -> String {
        [
            "记录类型：饮食 · \(meal.mealTypeRaw)",
            "记录时间：\(displayDate(meal.date))",
            "标题：\(meal.title)",
            meal.glycemicSpeedRaw.flatMap(MealGlycemicSpeed.init(rawValue:)).map {
                "食物组成升糖速度估算：\($0.displayName)（不是个体血糖预测）"
            },
            meal.glycemicAssessment?.nilIfBlank.map { "估算依据：\n\($0)" },
            meal.recommendedEatingOrder?.nilIfBlank.map { "建议食用顺序：\n\($0)" },
            sourceText.map { "原始文字：\n\($0)" },
            meal.notes.nilIfBlank.map { "记录备注：\n\($0)" },
            agentAnswer.map { "Agent 分析：\n\($0)" }
        ].compactMap { $0 }.joined(separator: "\n\n") + "\n"
    }

    static func workout(
        _ workout: WorkoutEntryDTO,
        sourceText: String?,
        agentAnswer: String?
    ) -> String {
        [
            "记录类型：训练",
            "记录时间：\(displayDate(workout.date))",
            "项目：\(workout.exercise)",
            workout.setEntries?.enumerated().map { index, entry in
                let reps = entry.reps.map { "\($0)次" } ?? "次数未记录"
                let weight = entry.externalWeightKG.map { "\($0.formatted())kg" } ?? "重量未记录"
                return "第\(index + 1)组：\(reps)，\(weight)"
            }.joined(separator: "\n").nilIfBlank.map { "逐组数据：\n\($0)" },
            sourceText.map { "原始文字：\n\($0)" },
            workout.notes.nilIfBlank.map { "记录备注：\n\($0)" },
            workout.feedback?.nilIfBlank.map { "动作反馈：\n\($0)" },
            agentAnswer.map { "Agent 分析：\n\($0)" }
        ].compactMap { $0 }.joined(separator: "\n\n") + "\n"
    }

    static let readme = """
    这是 Soma 生成的开放数据导出，不需要 Soma 也可以阅读。

    - 饮食和训练按本地时间归入 年/月/日。
    - 每条记录包含原始记录.txt、分析结果.json，以及存在时的媒体目录。
    - manifest.json 记录本次导出的版本、数量和缺失媒体。
    - 空字段表示用户没有提供或 Soma 无法可靠识别，不能按常见值补齐。
    - 此目录是明文副本，请自行保管并留意云盘或共享目录的访问权限。
    """

    private static func displayDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

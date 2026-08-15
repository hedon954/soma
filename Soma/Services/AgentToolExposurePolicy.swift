import Foundation

enum AgentToolGroup: String, CaseIterable, Sendable {
    case core
    case exercises
    case workouts
    case meals
    case body
    /// 仅供旧 Checkpoint 恢复；新请求不再暴露通用 mutate_user_data。
    case records
    case plans
    case gym
    case review
    case feedback

    static var expandableCases: [AgentToolGroup] {
        [.exercises, .workouts, .meals, .body, .plans, .gym, .review, .feedback]
    }

    var tools: [AgentToolName] {
        switch self {
        case .core:
            [.loadSkill]
        case .exercises:
            [
                .searchExercises,
                .createExercise,
                .updateExercise,
                .archiveExercise,
                .mergeExercises
            ]
        case .workouts:
            [.listWorkouts, .getWorkout, .createWorkout, .updateWorkout, .deleteWorkout]
        case .meals:
            [.listMeals, .getMeal, .createMeal, .updateMeal, .deleteMeal]
        case .body:
            [
                .listBodyEntries,
                .getBodyEntry,
                .createBodyEntry,
                .updateBody,
                .deleteBodyEntry
            ]
        case .records:
            [.queryUserData, .mutateUserData]
        case .plans:
            [
                .listPrograms,
                .getProgram,
                .createProgram,
                .createProgramVersion,
                .archiveProgram,
                .deleteProgram,
                .startProgram
            ]
        case .gym:
            [.updateGym, .switchGym]
        case .review:
            [.recordPerformanceAnalysis]
        case .feedback:
            [.submitFeedback]
        }
    }
}

struct AgentToolExposureSignals: Equatable, Sendable {
    var text: String
    var hasVideo: Bool
    var hasActiveProgram: Bool
    var hasActiveGuidedSession: Bool
}

enum AgentToolExposurePolicy {
    static func initialGroups(signals: AgentToolExposureSignals) -> Set<AgentToolGroup> {
        var groups = Set<AgentToolGroup>()
        let lowered = signals.text.lowercased()
        if hasRecordMutationIntent(lowered) {
            if containsAny(lowered, ["吃", "喝", "餐", "饮食", "热量", "蛋白", "碳水", "脂肪"]) {
                groups.insert(.meals)
            }
            if containsAny(lowered, ["体重", "体脂", "腰围", "体态", "围度"]) {
                groups.insert(.body)
            }
            if containsAny(lowered, ["训练", "练", "组", "次数", "动作", "重量", "kg", "公斤"]) {
                groups.formUnion([.exercises, .workouts])
            }
        }
        if containsAny(lowered, ["训练趋势", "训练量", "容量", "训练历史"]) {
            groups.insert(.workouts)
        }
        if containsAny(lowered, ["饮食趋势", "摄入趋势", "饮食历史"]) {
            groups.insert(.meals)
        }
        if containsAny(lowered, ["体重趋势", "体态变化", "体脂趋势", "腰围趋势"]) {
            groups.insert(.body)
        }
        if signals.hasActiveProgram
            || signals.hasActiveGuidedSession
            || containsAny(
                lowered,
                [
                    "计划", "模板", "带练", "训练计划", "开始练", "执行计划",
                    "program", "template"
                ]
            )
        {
            groups.formUnion([.exercises, .plans])
        }
        if containsAny(lowered, ["健身房", "器械", "场馆", "换馆", "gym"]) {
            groups.insert(.gym)
        }
        if signals.hasVideo
            || containsAny(lowered, ["复盘", "视频分析", "动作分析", "review"])
        {
            groups.insert(.review)
        }
        if containsAny(
            lowered,
            [
                "提交反馈", "发送反馈", "反馈给 soma", "产品反馈", "问题反馈",
                "我要反馈", "想反馈", "帮我反馈", "反馈一下", "反馈问题",
                "功能建议", "bug 反馈", "report feedback", "submit feedback",
                "feedback"
            ]
        ) {
            groups.insert(.feedback)
        }
        if !groups.isEmpty {
            groups.insert(.core)
        }
        return groups
    }

    static func tools(for groups: Set<AgentToolGroup>) -> [AgentToolName] {
        var seen = Set<AgentToolName>()
        var ordered: [AgentToolName] = []
        for group in AgentToolGroup.allCases where groups.contains(group) {
            for tool in group.tools where seen.insert(tool).inserted {
                ordered.append(tool)
            }
        }
        return ordered
    }

    static func expanding(
        _ groupRaw: String?,
        into groups: inout Set<AgentToolGroup>
    ) -> AgentToolResult {
        guard let groupRaw,
              let group = AgentToolGroup(rawValue: groupRaw),
              AgentToolGroup.expandableCases.contains(group)
        else {
            return .failure("tool_group 不在 App 允许展开的白名单中。")
        }
        if groups.contains(group) {
            return .success("工具组 \(group.rawValue) 已经展开。")
        }
        groups.insert(group)
        let names = group.tools.map(\.rawValue).joined(separator: ", ")
        return .success("已展开工具组 \(group.rawValue)：\(names)。后续步骤可使用这些工具。")
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func hasRecordMutationIntent(_ text: String) -> Bool {
        let explicitWrite = [
            "记录", "新增", "保存", "修改", "更新", "删除", "撤回", "更正", "补充"
        ]
        if containsAny(text, explicitWrite) {
            return true
        }
        if containsAny(text, ["刚做", "做完", "练完", "吃了", "喝了", "完成了"]) {
            return true
        }

        // 问建议、问知识不等于授权写入；即使句子里出现“体重”“晚餐”或“几次”。
        if containsAny(
            text,
            ["怎么", "如何", "多少", "合适", "建议", "应该", "能否", "可以吗", "吗", "？", "?"]
        ) {
            return false
        }

        let factualPatterns = [
            #"(?:体重|体脂|腰围)\s*[:：]?\s*\d"#,
            #"\d+(?:\.\d+)?\s*(?:kg|公斤|组|次|g|克|kcal|千卡)"#
        ]
        if factualPatterns.contains(where: {
            text.range(of: $0, options: .regularExpression) != nil
        }) {
            return true
        }

        // 无疑问语气的餐次短句通常就是聊天式快速记录，例如“午餐 两个鸡蛋”。
        return containsAny(text, ["早餐", "午餐", "晚餐", "加餐"])
    }
}

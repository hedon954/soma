import Foundation

enum AgentToolGroup: String, CaseIterable, Sendable {
    case core
    case records
    case plans
    case gym
    case review
    case feedback

    static var expandableCases: [AgentToolGroup] {
        [.records, .plans, .gym, .review, .feedback]
    }

    var tools: [AgentToolName] {
        switch self {
        case .core:
            [
                .loadSkill,
                .queryUserData,
                .expandToolGroup
            ]
        case .records:
            [.mutateUserData]
        case .plans:
            [
                .createTrainingProgram,
                .createWorkoutTemplateVersion,
                .archiveTrainingProgram,
                .deleteTrainingProgram,
                .startGuidedWorkout
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
        var groups: Set<AgentToolGroup> = [.core]
        let lowered = signals.text.lowercased()
        if containsAny(
            lowered,
            [
                "记录", "新增", "保存", "修改", "更新", "删除", "撤回",
                "刚做", "做完", "吃了", "喝了", "体重", "体脂", "腰围",
                "kg", "公斤", "组", "次", "早餐", "午餐", "晚餐", "加餐"
            ]
        ) {
            groups.insert(.records)
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
            groups.insert(.plans)
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
            return .failure("tool_group 仅支持 records、plans、gym、review、feedback。")
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
}

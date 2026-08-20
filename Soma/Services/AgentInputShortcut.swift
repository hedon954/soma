import Foundation

/// PRD 033：输入框快捷按钮是用户可完整增删改的实体。它决定一次发送要走哪个 Skill、
/// 以及本次允许模型看到哪些 Tool；Skill 只提供专业方法，不再自带工具权限。
struct AgentInputShortcut: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var iconSystemName: String
    /// 绑定的 Skill；为空表示只做工具收窄，不注入 Skill 正文。
    var skillID: String?
    /// 允许暴露的 Tool 名（`AgentToolName.rawValue`）。空数组表示不收窄，全量暴露。
    var toolNames: [String]
    var isVisible: Bool
    var order: Int

    init(
        id: String = "shortcut_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        iconSystemName: String = AgentInputShortcut.defaultIconSystemName,
        skillID: String? = nil,
        toolNames: [String] = AgentToolName.allToolNames,
        isVisible: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.skillID = skillID
        self.toolNames = toolNames
        self.isVisible = isVisible
        self.order = order
    }

    static let defaultIconSystemName = "sparkles"

    /// 可选图标，覆盖当前几类高频场景，避免让用户手写 SF Symbol 名。
    static let iconChoices = [
        "sparkles",
        "fork.knife",
        "dumbbell",
        "figure.run",
        "chart.line.uptrend.xyaxis",
        "figure.stand",
        "list.bullet.clipboard",
        "calendar",
        "camera",
        "heart.text.square",
        "building.2",
        "scalemass"
    ]

    /// 图标选择器只显示符号本身，VoiceOver 需要一个能读出来的中文名。
    static func iconLabel(_ systemName: String) -> String {
        iconLabels[systemName] ?? "图标"
    }

    private static let iconLabels = [
        "sparkles": "闪光",
        "fork.knife": "餐具",
        "dumbbell": "哑铃",
        "figure.run": "跑步",
        "chart.line.uptrend.xyaxis": "趋势图",
        "figure.stand": "体态",
        "list.bullet.clipboard": "清单",
        "calendar": "日历",
        "camera": "相机",
        "heart.text.square": "健康记录",
        "building.2": "健身房",
        "scalemass": "体重秤"
    ]

    /// 去掉未知工具名并保持工具目录顺序，避免设置页写入无法识别的权限。
    var normalizedToolNames: [String] {
        AgentToolExposurePolicy.normalize(toolNames: toolNames)
    }
}

enum AgentInputShortcutStore {
    static let storageKey = "ai.react.input-shortcuts.v1"
    static let maximumVisibleCount = 6

    /// 默认只保留三个：饮食分析、训练记录、近期分析。其余内置 Skill 仍可在设置里绑定，
    /// 但不占用聊天输入区。
    static var defaultShortcuts: [AgentInputShortcut] {
        [
            AgentInputShortcut(
                id: "shortcut_nutrition",
                title: "饮食分析",
                iconSystemName: "fork.knife",
                skillID: AgentSkill.nutritionAnalysis.rawValue,
                toolNames: AgentToolExposurePolicy.toolNames(
                    for: [.core, .meals]
                ),
                isVisible: true,
                order: 0
            ),
            AgentInputShortcut(
                id: "shortcut_workout_log",
                title: "训练记录",
                iconSystemName: "dumbbell",
                skillID: AgentSkill.workoutLogging.rawValue,
                toolNames: AgentToolExposurePolicy.toolNames(
                    for: [.core, .exercises, .workouts]
                ),
                isVisible: true,
                order: 1
            ),
            AgentInputShortcut(
                id: "shortcut_recent_review",
                title: "近期分析",
                iconSystemName: "chart.line.uptrend.xyaxis",
                skillID: AgentSkill.trendAnalysis.rawValue,
                toolNames: AgentToolExposurePolicy.toolNames(
                    for: [.core, .workouts, .meals, .body]
                ),
                isVisible: true,
                order: 2
            )
        ]
    }

    static func shortcuts(
        defaults: UserDefaults = .standard
    ) -> [AgentInputShortcut] {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(
                  [AgentInputShortcut].self,
                  from: data
              )
        else {
            return defaultShortcuts
        }
        return stored.sorted { $0.order < $1.order }
    }

    static func visibleShortcuts(
        defaults: UserDefaults = .standard
    ) -> [AgentInputShortcut] {
        Array(
            shortcuts(defaults: defaults)
                .filter(\.isVisible)
                .prefix(maximumVisibleCount)
        )
    }

    static func shortcut(
        id: String,
        defaults: UserDefaults = .standard
    ) -> AgentInputShortcut? {
        shortcuts(defaults: defaults).first { $0.id == id }
    }

    static func save(
        _ shortcut: AgentInputShortcut,
        defaults: UserDefaults = .standard
    ) {
        var values = shortcuts(defaults: defaults)
        if let index = values.firstIndex(where: { $0.id == shortcut.id }) {
            values[index] = shortcut
        } else {
            var appended = shortcut
            appended.order = (values.map(\.order).max() ?? -1) + 1
            values.append(appended)
        }
        replaceAll(values, defaults: defaults)
    }

    static func delete(id: String, defaults: UserDefaults = .standard) {
        replaceAll(
            shortcuts(defaults: defaults).filter { $0.id != id },
            defaults: defaults
        )
    }

    /// 设置页拖动排序后整体落盘，`order` 由数组下标重排，保证与展示顺序一致。
    static func replaceAll(
        _ values: [AgentInputShortcut],
        defaults: UserDefaults = .standard
    ) {
        var seen = Set<String>()
        let normalized = values
            .filter { seen.insert($0.id).inserted }
            .enumerated()
            .map { index, shortcut in
                var value = shortcut
                value.order = index
                value.toolNames = shortcut.normalizedToolNames
                return value
            }
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// 恢复到内置三个按钮，用于设置页的重置入口。
    static func resetToDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

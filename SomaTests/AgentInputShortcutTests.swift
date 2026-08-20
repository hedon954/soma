@testable import Soma
import XCTest

/// PRD 033 / ADR 0082：快捷按钮持有 Skill 绑定与工具白名单，是曝光边界的唯一来源。
final class AgentInputShortcutTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    func testDefaultsShipThreeVisibleShortcuts() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortcuts = AgentInputShortcutStore.shortcuts(defaults: defaults)
        XCTAssertEqual(shortcuts.map(\.title), ["饮食分析", "训练记录", "近期分析"])
        XCTAssertEqual(
            AgentInputShortcutStore.visibleShortcuts(defaults: defaults).count,
            3
        )
        XCTAssertEqual(
            shortcuts.compactMap(\.skillID),
            [
                AgentSkill.nutritionAnalysis.rawValue,
                AgentSkill.workoutLogging.rawValue,
                AgentSkill.trendAnalysis.rawValue
            ]
        )
    }

    func testDefaultWorkoutShortcutExposesExerciseAndWorkoutTools() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortcut = try XCTUnwrap(AgentInputShortcutStore.shortcut(
            id: "shortcut_workout_log",
            defaults: defaults
        ))
        let tools = AgentToolExposurePolicy.tools(selectedShortcut: shortcut)
        XCTAssertTrue(tools.contains(.createWorkout))
        XCTAssertTrue(tools.contains(.searchExercises))
        XCTAssertTrue(tools.contains(.loadSkill))
        XCTAssertFalse(tools.contains(.createMeal))
        XCTAssertFalse(tools.contains(.submitFeedback))
    }

    func testCrudKeepsOrderContiguousAndHiddenShortcutsStayConfigured() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AgentInputShortcutStore.save(
            AgentInputShortcut(
                id: "shortcut_custom",
                title: "体态记录",
                skillID: AgentSkill.postureAnalysis.rawValue,
                toolNames: AgentToolExposurePolicy.toolNames(for: [.body]),
                isVisible: false
            ),
            defaults: defaults
        )
        var shortcuts = AgentInputShortcutStore.shortcuts(defaults: defaults)
        XCTAssertEqual(shortcuts.count, 4)
        XCTAssertEqual(shortcuts.map(\.order), [0, 1, 2, 3])
        XCTAssertFalse(try XCTUnwrap(shortcuts.last).isVisible)
        XCTAssertEqual(
            AgentInputShortcutStore.visibleShortcuts(defaults: defaults).count,
            3
        )

        shortcuts.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        AgentInputShortcutStore.replaceAll(shortcuts, defaults: defaults)
        XCTAssertEqual(
            AgentInputShortcutStore.shortcuts(defaults: defaults).first?.id,
            "shortcut_custom"
        )
        XCTAssertEqual(
            AgentInputShortcutStore.shortcuts(defaults: defaults).map(\.order),
            [0, 1, 2, 3]
        )

        AgentInputShortcutStore.delete(id: "shortcut_custom", defaults: defaults)
        XCTAssertEqual(
            AgentInputShortcutStore.shortcuts(defaults: defaults).count,
            3
        )
    }

    func testUnknownToolNamesAreDroppedOnPersist() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AgentInputShortcutStore.save(
            AgentInputShortcut(
                id: "shortcut_custom",
                title: "旧配置",
                toolNames: ["create_meal", "delete_everything", "records"]
            ),
            defaults: defaults
        )

        let shortcut = try XCTUnwrap(AgentInputShortcutStore.shortcut(
            id: "shortcut_custom",
            defaults: defaults
        ))
        XCTAssertEqual(shortcut.toolNames, ["create_meal"])
    }

    /// 空清单不能被解释成“没有工具”，否则模型一个工具都拿不到。
    func testEmptyToolListFallsBackToFullExposure() {
        let shortcut = AgentInputShortcut(title: "空配置", toolNames: [])
        XCTAssertEqual(
            AgentToolExposurePolicy.tools(selectedShortcut: shortcut),
            AgentToolExposurePolicy.orderedTools
        )
    }

    func testNewShortcutDefaultsToEveryTool() {
        let shortcut = AgentInputShortcut(title: "新按钮")
        XCTAssertEqual(
            shortcut.normalizedToolNames.count,
            AgentToolName.allCases.count
        )
    }

    /// ADR 0082：在盘的旧 checkpoint 只有分组，恢复时必须展开成同一批工具。
    func testLegacyCheckpointGroupsRestoreAsToolNames() throws {
        let legacy = """
        {
          "lastCompletedStep": 2,
          "assistantPassages": [],
          "observations": [],
          "exposedGroups": ["core", "meals"]
        }
        """
        let checkpoint = try JSONDecoder().decode(
            AgentLoopCheckpoint.self,
            from: XCTUnwrap(legacy.data(using: .utf8))
        )

        XCTAssertEqual(
            checkpoint.restoredToolNames,
            AgentToolExposurePolicy.toolNames(for: [.core, .meals])
        )
    }

    func testCurrentCheckpointRoundTripsToolNames() throws {
        let checkpoint = AgentLoopCheckpoint(
            lastCompletedStep: 1,
            assistantPassages: ["草稿"],
            observations: [],
            exposedToolNames: ["load_skill", "create_meal"]
        )
        let decoded = try JSONDecoder().decode(
            AgentLoopCheckpoint.self,
            from: JSONEncoder().encode(checkpoint)
        )

        XCTAssertEqual(decoded.restoredToolNames, ["load_skill", "create_meal"])
        XCTAssertEqual(decoded, checkpoint)
    }

    func testRecommendationParsingKeepsOnlyKnownTools() throws {
        let recommendation = try XCTUnwrap(AgentToolRecommendationService.parse("""
        这是我的建议：
        {"tools":["load_skill","create_meal","delete_everything"],"reason":"写饮食需要读写餐食工具。"}
        """))

        XCTAssertEqual(recommendation.toolNames, ["load_skill", "create_meal"])
        XCTAssertEqual(recommendation.reason, "写饮食需要读写餐食工具。")
    }

    func testRecommendationParsingRejectsUnusableOutput() {
        XCTAssertNil(AgentToolRecommendationService.parse("我不知道"))
        XCTAssertNil(AgentToolRecommendationService.parse(
            #"{"tools":["delete_everything"],"reason":"x"}"#
        ))
    }
}

import Foundation
import SwiftData

enum AppTestRuntime {
    static let uiTestEnvironmentKey = "SOMA_UI_TEST_PROCESS"

    static var isRunning: Bool {
        isRunning(in: ProcessInfo.processInfo.environment)
    }

    static func isRunning(in environment: [String: String]) -> Bool {
        environment[uiTestEnvironmentKey] == "1"
            || DevicePerformanceHarness.isRequested(in: environment)
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}

/// 真机 Instruments 自动化不依赖 XCTest Runner。只有 `devicectl` 显式注入
/// mode 时才启用；此时 AppTestRuntime 同时切到内存数据库，绝不读取或修改个人数据。
enum DevicePerformanceHarness {
    static let modeEnvironmentKey = "SOMA_DEVICE_PERFORMANCE_MODE"
    static let roundsEnvironmentKey = "SOMA_DEVICE_PERFORMANCE_ROUNDS"
    static let delayEnvironmentKey = "SOMA_DEVICE_PERFORMANCE_DELAY_SECONDS"

    enum Mode: String {
        case tabs
        case sessions
        case scroll
    }

    static var mode: Mode? {
        Mode(rawValue: ProcessInfo.processInfo.environment[modeEnvironmentKey] ?? "")
    }

    static var rounds: Int {
        let rawValue = ProcessInfo.processInfo.environment[roundsEnvironmentKey] ?? "30"
        return min(max(Int(rawValue) ?? 30, 1), 100)
    }

    static var delay: Duration {
        let rawValue = ProcessInfo.processInfo.environment[delayEnvironmentKey] ?? "8"
        return .milliseconds(Int((Double(rawValue) ?? 8) * 1000))
    }

    static func isRequested(in environment: [String: String]) -> Bool {
        Mode(rawValue: environment[modeEnvironmentKey] ?? "") != nil
    }
}

extension Notification.Name {
    static let performanceSelectCoachSession = Notification.Name(
        "Soma.performanceSelectCoachSession"
    )
    static let performanceScrollCoach = Notification.Name(
        "Soma.performanceScrollCoach"
    )
}

/// 只为自动化性能录制提供可重复、虚构且不落个人数据库的增长场景。
/// App 进程必须同时处于 XCTest 环境并显式请求 fixture，普通安装永远不会进入。
enum PerformanceTestFixture {
    static let environmentKey = "SOMA_UI_PERFORMANCE_FIXTURE"
    static let longStream = "long-stream"

    static var requestedLongStream: Bool {
        requestsLongStream(in: ProcessInfo.processInfo.environment)
    }

    static func requestsLongStream(in environment: [String: String]) -> Bool {
        AppTestRuntime.isRunning(in: environment)
            && environment[environmentKey] == longStream
    }

    @MainActor
    static func seedLongStreamIfRequested(
        in context: ModelContext
    ) -> ConversationSession? {
        guard requestedLongStream else { return nil }

        let title = "性能测试：虚构长对话"
        var existing = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.title == title }
        )
        existing.fetchLimit = 1
        if let session = try? context.fetch(existing).first {
            return session
        }

        let startedAt = Date.now.addingTimeInterval(-3600)
        let session = ConversationSession(
            startedAt: startedAt,
            updatedAt: .now,
            title: title,
            titleSource: .manual
        )
        context.insert(session)

        let olderSession = ConversationSession(
            startedAt: startedAt.addingTimeInterval(-3600),
            updatedAt: startedAt.addingTimeInterval(-3600),
            title: "性能测试：可切换旧对话",
            titleSource: .manual
        )
        context.insert(olderSession)
        context.insert(CoachMessage(
            date: olderSession.startedAt,
            sessionID: olderSession.id,
            isFromCoach: false,
            text: "已成功切换到旧会话。"
        ))

        // 回归真机大会话故障：最后一条回复引用一份十项饮食记录。旧实现会在页面
        // 出现时一次性创建几十个 TextField，并由 ViewThatFits 重复构建候选布局。
        let mealTurnID = UUID()
        let mealItems = (1 ... 10).map { index in
            MealItem(
                name: "虚构菜品 \(index)",
                portionDescription: "虚构份量",
                calories: 50 + index,
                protein: Double(index),
                carbs: Double(index * 2),
                fat: Double(index) / 2,
                totalSugar: Double(index) / 3
            )
        }
        let meal = MealEntry(
            date: olderSession.startedAt.addingTimeInterval(1),
            mealType: .breakfast,
            title: "虚构十项早餐",
            items: mealItems,
            sourceTurnID: mealTurnID,
            sourceSessionID: olderSession.id
        )
        context.insert(meal)
        try? BusinessIDAllocator.assign(meal, namespace: "meal", in: context)
        if let businessID = meal.businessID {
            context.insert(CoachMessage(
                date: olderSession.startedAt.addingTimeInterval(2),
                sessionID: olderSession.id,
                isFromCoach: true,
                text: "虚构饮食记录已保存。",
                agentStatus: .succeeded,
                agentTurnItems: [
                    AgentTurnItem(
                        sequence: 1,
                        kind: .tool,
                        status: .succeeded,
                        title: "创建饮食记录",
                        startedAt: olderSession.startedAt.addingTimeInterval(1),
                        endedAt: olderSession.startedAt.addingTimeInterval(2),
                        output: AgentTraceText.json(AgentToolResult.success(
                            "虚构饮食记录已保存。",
                            recordRefs: [AgentRecordReference(
                                recordType: ConversationIntent.meal.rawValue,
                                recordID: businessID,
                                title: "虚构十项早餐"
                            )]
                        ))
                    )
                ],
                turnID: mealTurnID
            ))
        }

        for index in 0 ..< 39 {
            let turnID = UUID()
            let userDate = startedAt.addingTimeInterval(Double(index * 80))
            context.insert(CoachMessage(
                date: userDate,
                sessionID: session.id,
                isFromCoach: false,
                text: "第 \(index + 1) 轮虚构输入：今天完成了常规训练，请给出简短复盘。",
                turnID: turnID
            ))
            let response = """
            ## 虚构训练复盘

            这是一段只用于自动化性能测试的内容，不代表任何真实训练或身体数据。动作节奏保持稳定，下一次仍以可控幅度逐步增加。

            - 训练量：保持当前安排
            - 恢复：按主观状态调整
            - 下一步：记录完成度后再决定是否加量
            """
            context.insert(CoachMessage(
                date: userDate.addingTimeInterval(1),
                sessionID: session.id,
                isFromCoach: true,
                text: response,
                agentStatus: .succeeded,
                agentTurnItems: [
                    AgentTurnItem(
                        sequence: 1,
                        kind: .text,
                        status: .succeeded,
                        text: response,
                        startedAt: userDate,
                        endedAt: userDate.addingTimeInterval(1)
                    )
                ],
                turnID: turnID
            ))
        }

        let liveTurnID = UUID()
        context.insert(CoachMessage(
            date: .now.addingTimeInterval(-1),
            sessionID: session.id,
            isFromCoach: false,
            text: "继续生成一份完全虚构的长篇训练总结，用于性能测试。",
            turnID: liveTurnID
        ))
        context.insert(CoachMessage(
            date: .now,
            sessionID: session.id,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: liveTurnID
        ))
        try? context.save()
        return session
    }

    static func streamParagraph(_ index: Int) -> String {
        "第 \(index + 1) 段虚构总结：保持动作节奏、训练容量与恢复安排的可审查记录；这段文字不包含真实用户数据。\n"
    }
}

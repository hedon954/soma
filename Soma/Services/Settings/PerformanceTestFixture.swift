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
    static let waitForFixtureCompletionEnvironmentKey =
        "SOMA_DEVICE_PERFORMANCE_WAIT_FOR_FIXTURE_COMPLETION"

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

    static var waitsForFixtureCompletion: Bool {
        waitsForFixtureCompletion(in: ProcessInfo.processInfo.environment)
    }

    static func waitsForFixtureCompletion(in environment: [String: String]) -> Bool {
        environment[waitForFixtureCompletionEnvironmentKey] == "1"
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
    static let fastStreamEnvironmentKey = "SOMA_UI_PERFORMANCE_FAST_STREAM"
    static let longStream = "long-stream"
    static let longStreamNoNewline = "long-stream-no-newline"
    static let longStreamMarkdownCompletion = "long-stream-markdown-completion"
    static let coachTabBehavior = "coach-tab-behavior"

    enum StreamScenario: String, Sendable {
        case paragraphs = "long-stream"
        case noNewline = "long-stream-no-newline"
        case markdownCompletion = "long-stream-markdown-completion"
        case coachTabBehavior = "coach-tab-behavior"

        var completes: Bool {
            self != .paragraphs
        }

        var streamRange: Range<Int> {
            switch self {
            case .paragraphs:
                160 ..< 1060
            case .noNewline, .markdownCompletion:
                1 ..< 240
            case .coachTabBehavior:
                1 ..< 4
            }
        }
    }

    struct LongStreamSeed {
        let session: ConversationSession
        let responseMessageID: UUID
    }

    static var requestedStreamScenario: StreamScenario? {
        guard AppTestRuntime.isRunning else { return nil }
        return StreamScenario(
            rawValue: ProcessInfo.processInfo.environment[environmentKey] ?? ""
        )
    }

    static var streamInterval: Duration {
        ProcessInfo.processInfo.environment[fastStreamEnvironmentKey] == "1"
            ? .milliseconds(10)
            : .milliseconds(200)
    }

    static var requestedLongStream: Bool {
        requestsLongStream(in: ProcessInfo.processInfo.environment)
    }

    static func requestsLongStream(in environment: [String: String]) -> Bool {
        AppTestRuntime.isRunning(in: environment)
            && StreamScenario(rawValue: environment[environmentKey] ?? "") != nil
    }

    @MainActor
    static func seedLongStreamIfRequested(
        in context: ModelContext
    ) -> LongStreamSeed? {
        guard requestedLongStream, let scenario = requestedStreamScenario else { return nil }

        let title = "性能测试：虚构长对话（\(scenario.rawValue)）"
        var existing = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.title == title }
        )
        existing.fetchLimit = 1
        if let session = try? context.fetch(existing).first {
            let fixtureSessionID: UUID? = session.id
            let runningStatus: String? = AgentTraceStatus.running.rawValue
            var response = FetchDescriptor<CoachMessage>(
                predicate: #Predicate {
                    $0.sessionID == fixtureSessionID
                        && $0.isFromCoach
                        && $0.agentStatusRaw == runningStatus
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            response.fetchLimit = 1
            guard let message = try? context.fetch(response).first else { return nil }
            return LongStreamSeed(session: session, responseMessageID: message.id)
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
                fat: Double(index) / 2
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

        // Markdown 完成态场景专门压单条 18k 正文，保持消息页在 eager 边界内，
        // 避免把外层历史分页的惰性实例化混入后台解析断言。其余场景继续保留
        // 39 轮大会话，覆盖消息级 LazyVStack 与分页。
        let historicalTurnCount = scenario == .markdownCompletion ? 3 : 39
        for index in 0 ..< historicalTurnCount {
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
        let responseMessage = CoachMessage(
            date: .now,
            sessionID: session.id,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: liveTurnID
        )
        context.insert(responseMessage)
        try? context.save()
        return LongStreamSeed(
            session: session,
            responseMessageID: responseMessage.id
        )
    }

    static func streamParagraph(_ index: Int) -> String {
        "第 \(index + 1) 段虚构总结：保持动作节奏、训练容量与恢复安排的可审查记录；这段文字不包含真实用户数据。\n"
    }

    static func streamDelta(_ index: Int, scenario: StreamScenario) -> String {
        switch scenario {
        case .paragraphs, .coachTabBehavior:
            streamParagraph(index)
        case .noNewline:
            "第\(index + 1)段连续虚构训练建议只用于验证无换行正文的增量排版成本不随全文长度增长且不会插入额外字符"
        case .markdownCompletion:
            """
            ## 第 \(index + 1) 段虚构复盘

            这段内容只用于验证完成态 Markdown 的后台解析和渐进布局。

            - 训练容量：保持可审查
            - 恢复安排：依据用户事实

            """
        }
    }

    /// 在非 MainActor 侧生成碎片，并复用真实 SSE 的单飞投影 Pump。这样性能夹具
    /// 能施加持续输入压力，却不会因为 UI 一次变慢就退化成逐碎片主线程刷新。
    static func projectStreamDeltas(
        from startIndex: Int,
        to endIndex: Int,
        scenario: StreamScenario,
        project: @escaping @MainActor (String) -> Void
    ) async {
        let pump = AgentTextProjectionPump(project: project)
        for index in startIndex ..< endIndex {
            do {
                try await Task.sleep(for: streamInterval)
            } catch {
                break
            }
            guard !Task.isCancelled else { break }
            await pump.append(streamDelta(index, scenario: scenario))
        }
        _ = await pump.finish()
    }
}

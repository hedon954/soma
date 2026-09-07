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
    static let longStreamAppend = "long-stream-append"
    static let longStreamNoNewline = "long-stream-no-newline"
    static let longStreamMarkdownCompletion = "long-stream-markdown-completion"
    static let coachTabBehavior = "coach-tab-behavior"
    static let recordOptimizations = "record-optimizations"
    static let agentStages = "agent-stages"

    enum StreamScenario: String, Sendable {
        case paragraphs = "long-stream"
        case append = "long-stream-append"
        case noNewline = "long-stream-no-newline"
        case markdownCompletion = "long-stream-markdown-completion"
        case productionCompletion = "long-stream-production-completion"
        case coachTabBehavior = "coach-tab-behavior"
        case recordOptimizations = "record-optimizations"
        case agentStages = "agent-stages"

        var completes: Bool {
            self != .paragraphs
        }

        var streamRange: Range<Int> {
            switch self {
            case .paragraphs:
                160 ..< 1060
            case .append:
                160 ..< 240
            case .noNewline, .markdownCompletion, .productionCompletion:
                1 ..< 240
            case .coachTabBehavior:
                1 ..< 4
            case .recordOptimizations:
                1 ..< 2
            case .agentStages:
                0 ..< 0
            }
        }

        var usesStaticAgentStage: Bool {
            self == .agentStages
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
            title: title
        )
        context.insert(session)

        let olderSession = ConversationSession(
            startedAt: startedAt.addingTimeInterval(-3600),
            updatedAt: startedAt.addingTimeInterval(-3600),
            title: "性能测试：可切换旧对话"
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
        var mealItems: [MealItem] = []
        mealItems.reserveCapacity(10)
        for index in 1 ... 10 {
            let item = MealItem(
                name: "虚构菜品 \(index)",
                portionDescription: "虚构份量",
                calories: 50 + index,
                protein: Double(index),
                carbs: Double(index * 2),
                fat: Double(index) / 2
            )
            mealItems.append(item)
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

        if scenario == .recordOptimizations {
            seedRecordOptimizationTurn(
                in: session,
                startedAt: startedAt,
                context: context
            )
            seedResumableWorkout(
                startedAt: startedAt,
                context: context
            )
            seedCompletedWorkoutReview(
                startedAt: startedAt,
                context: context
            )
        }

        // Markdown 完成态场景专门压单条 18k 正文，避免把外层历史分页混入
        // 后台解析断言。其余场景继续保留 39 轮大会话，覆盖 30 条分页与
        // 已加载页的即时 VStack。
        let historicalTurnCount = switch scenario {
        case .markdownCompletion: 3
        case .recordOptimizations, .agentStages: 0
        default: 39
        }
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
        let liveUserDate = scenario == .recordOptimizations
            ? startedAt.addingTimeInterval(1.5)
            : .now.addingTimeInterval(-1)
        let liveResponseDate = scenario == .recordOptimizations
            ? startedAt.addingTimeInterval(2)
            : .now
        context.insert(CoachMessage(
            date: liveUserDate,
            sessionID: session.id,
            isFromCoach: false,
            text: "继续生成一份完全虚构的长篇训练总结，用于性能测试。",
            turnID: liveTurnID
        ))
        let responseMessage = CoachMessage(
            date: liveResponseDate,
            sessionID: session.id,
            isFromCoach: true,
            text: "",
            agentStatus: agentStageStatus,
            agentTurnItems: agentStageItems(startedAt: liveResponseDate),
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
        case .paragraphs, .append, .coachTabBehavior, .recordOptimizations, .agentStages:
            streamParagraph(index)
        case .noNewline:
            "第\(index + 1)段连续虚构训练建议只用于验证无换行正文的增量排版成本不随全文长度增长且不会插入额外字符"
        case .markdownCompletion, .productionCompletion:
            """
            ## 第 \(index + 1) 段虚构复盘

            这段内容只用于验证完成态 Markdown 的后台解析和渐进布局。

            - 训练容量：保持可审查
            - 恢复安排：依据用户事实

            """
        }
    }

    private static var requestedAgentStage: String {
        ProcessInfo.processInfo.environment["SOMA_UI_AGENT_STAGE"] ?? "received"
    }

    private static var agentStageStatus: AgentTraceStatus {
        switch requestedAgentStage {
        case "completed", "reasoning-completed": .succeeded
        case "failed": .failed
        default: .running
        }
    }

    private static func agentStageItems(startedAt: Date) -> [AgentTurnItem] {
        guard requestedStreamScenario == .agentStages else { return [] }
        let operationID = "fixture-operation"
        switch requestedAgentStage {
        case "model":
            return [AgentTurnItem(
                kind: .activity,
                status: .running,
                phase: .modelRunning,
                title: "正在处理请求…",
                text: "正在处理请求…",
                startedAt: startedAt
            )]
        case "preparing", "running", "waiting", "completed", "failed":
            let phase: AgentTurnPhase = switch requestedAgentStage {
            case "preparing": .preparing
            case "running": .running
            case "waiting": .waitingForDevice
            case "completed": .completed
            default: .failed
            }
            let status: AgentTraceStatus = switch phase {
            case .completed: .succeeded
            case .failed: .failed
            default: .running
            }
            return [AgentTurnItem(
                kind: .tool,
                status: status,
                operationID: operationID,
                phase: phase,
                title: "创建训练记录",
                startedAt: startedAt,
                endedAt: status == .running ? nil : startedAt.addingTimeInterval(1),
                output: status == .succeeded
                    ? AgentTraceText.json(AgentToolResult.success("虚构训练记录已保存。"))
                    : nil,
                errorMessage: status == .failed ? "虚构参数错误" : nil
            )]
        case "skill":
            return [AgentTurnItem(
                kind: .skill,
                status: .running,
                operationID: operationID,
                phase: .preparing,
                title: "训练记录 Skill",
                startedAt: startedAt
            )]
        case "reasoning-running", "reasoning-completed":
            let completed = requestedAgentStage == "reasoning-completed"
            return [AgentTurnItem(
                kind: .reasoning,
                status: completed ? .succeeded : .running,
                phase: completed ? .completed : .modelRunning,
                title: completed ? "思考过程" : "正在思考…",
                text: "先核对训练事实，再组织最终答复。",
                startedAt: startedAt,
                endedAt: completed ? startedAt.addingTimeInterval(1) : nil
            )]
        default:
            return [AgentTurnItem(
                kind: .activity,
                status: .running,
                phase: .queued,
                title: "已收到，正在准备处理…",
                text: "已收到，正在准备处理…",
                startedAt: startedAt
            )]
        }
    }

    /// 只用于 UI 回归：动作定义与本次逐组 evidence 都明确为按时长，验证聊天卡
    /// 使用 v4 的显式记录证据，并完整呈现时长、自重、间歇与组数。
    @MainActor
    private static func seedRecordOptimizationTurn(
        in session: ConversationSession,
        startedAt: Date,
        context: ModelContext
    ) {
        let turnID = UUID()
        let exerciseName = ProcessInfo.processInfo.environment[
            "SOMA_UI_WORKOUT_NAME"
        ] ?? "单杠悬吊"
        let definition = ExerciseDefinition(
            canonicalName: exerciseName,
            primaryMuscles: ["前臂"],
            secondaryMuscles: ["上背"]
        )
        definition.targetKind = .duration
        definition.laterality = ExerciseLaterality(
            rawValue: ProcessInfo.processInfo.environment[
                "SOMA_UI_WORKOUT_LATERALITY"
            ] ?? ""
        ) ?? .none
        context.insert(definition)

        let recordedSide: WorkoutEffortSide? = switch definition.laterality {
        case .left: .left
        case .right: .right
        case .none: WorkoutEffortSide.none
        case .both: nil
        }

        let requestedStressCount = Int(
            ProcessInfo.processInfo.environment["SOMA_UI_EXERCISE_STRESS_COUNT"]
                ?? "0"
        ) ?? 0
        for index in 0 ..< min(max(requestedStressCount, 0), 2000) {
            context.insert(ExerciseDefinition(
                canonicalName: String(format: "%04d 编辑回归动作", index)
            ))
        }

        var durationSetEntries: [WorkoutSetEvidence] = []
        durationSetEntries.reserveCapacity(3)
        for index in 1 ... 3 {
            let evidence = WorkoutSetEvidence(
                logicalSetIndex: index,
                side: recordedSide,
                targetKind: .duration,
                durationSeconds: 20,
                externalWeightKG: 0,
                restSeconds: index < 3 ? 30 : nil
            )
            durationSetEntries.append(evidence)
        }

        let workout = WorkoutEntry(
            date: startedAt.addingTimeInterval(2),
            exercise: definition.canonicalName,
            exerciseID: definition.id,
            setEntries: durationSetEntries,
            restSeconds: 30,
            sourceTurnID: turnID,
            sourceSessionID: session.id
        )
        workout.exerciseDefinition = definition
        workout.estimatedCalories = 23
        workout.calorieMET = 6
        workout.calorieDurationMinutes = 2.5
        workout.calorieDurationEstimated = true
        context.insert(workout)
        try? BusinessIDAllocator.assign(workout, namespace: "workout", in: context)

        let trace = AgentTrace(
            startedAt: startedAt.addingTimeInterval(1),
            provider: "UI Test",
            model: "fixture",
            endpoint: "local://fixture",
            dataSpaceRaw: DataSpace.personal.rawValue,
            userInput: "单杠悬吊 20 秒 × 3 组，间歇 30 秒",
            contextSnapshot: "只包含虚构 UI 测试数据。",
            mediaKind: .none,
            imageCount: 0
        )
        trace.apply(.completed(
            answer: "已记录虚构训练。",
            at: startedAt.addingTimeInterval(3)
        ))
        context.insert(trace)

        context.insert(CoachMessage(
            date: startedAt,
            sessionID: session.id,
            isFromCoach: false,
            text: "单杠悬吊 20 秒 × 3 组，间歇 30 秒",
            turnID: turnID
        ))
        if let businessID = workout.businessID {
            context.insert(CoachMessage(
                date: startedAt.addingTimeInterval(3),
                sessionID: session.id,
                isFromCoach: true,
                text: "已记录虚构训练。",
                agentTraceID: trace.id,
                agentStatus: .succeeded,
                agentTurnItems: [
                    AgentTurnItem(
                        sequence: 1,
                        kind: .tool,
                        status: .succeeded,
                        title: "创建训练记录",
                        startedAt: startedAt.addingTimeInterval(1),
                        endedAt: startedAt.addingTimeInterval(2),
                        output: AgentTraceText.json(AgentToolResult.success(
                            "虚构训练记录已保存。",
                            recordRefs: [AgentRecordReference(
                                recordType: ConversationIntent.workout.rawValue,
                                recordID: businessID,
                                title: definition.canonicalName
                            )]
                        ))
                    )
                ],
                turnID: turnID
            ))
        }
    }

    /// 训练根页 UI 回归夹具：验证继续训练卡的真实高度和系统左滑删除样式。
    @MainActor
    private static func seedResumableWorkout(
        startedAt: Date,
        context: ModelContext
    ) {
        let names = ["杠铃卧推", "坐姿推肩", "上斜哑铃卧推", "侧平举", "绳索下压", "俯卧撑"]
        let prescriptions = names.enumerated().map { index, name in
            TemplateExercisePrescription(
                exerciseID: UUID(),
                exerciseName: name,
                order: index + 1,
                targetSets: 3,
                targetReps: 10,
                targetWeightKG: index == 5 ? 0 : 20
            )
        }
        let session = WorkoutSession(
            startedAt: startedAt.addingTimeInterval(10),
            programNameSnapshot: "虚构胸肩三头",
            prescriptionSnapshot: prescriptions,
            status: .paused,
            guidedPhase: .exerciseIntroduction
        )
        context.insert(session)

        for (index, prescription) in prescriptions.enumerated() {
            let performance = ExercisePerformance(
                sessionID: session.id,
                exerciseID: prescription.exerciseID,
                exerciseName: prescription.exerciseName,
                order: prescription.order,
                prescriptionSnapshot: prescription,
                status: index == 0 ? .completed : (index == 1 ? .active : .pending)
            )
            performance.session = session
            context.insert(performance)
            if index == 1 {
                session.currentPerformanceID = performance.id
            }
        }
    }

    /// 训练复盘 UI 回归夹具：Performance 顺序与来源 WorkoutEntry 使用稳定 ID 对齐，
    /// 复盘应复用进展页最近记录行而不是只显示“几组已确认”。
    @MainActor
    private static func seedCompletedWorkoutReview(
        startedAt: Date,
        context: ModelContext
    ) {
        let definition = ExerciseDefinition(
            canonicalName: "虚构复盘深蹲",
            primaryMuscles: ["股四头肌"],
            secondaryMuscles: ["臀大肌"]
        )
        context.insert(definition)
        let prescription = TemplateExercisePrescription(
            exerciseID: definition.id,
            exerciseName: definition.canonicalName,
            order: 1,
            targetSets: 5,
            targetReps: 5,
            targetWeightKG: 50,
            targetRestSeconds: 60
        )
        let session = WorkoutSession(
            startedAt: startedAt.addingTimeInterval(20),
            endedAt: startedAt.addingTimeInterval(1220),
            programNameSnapshot: "虚构复盘计划",
            prescriptionSnapshot: [prescription],
            status: .completed,
            guidedPhase: .completed
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: definition.id,
            exerciseName: definition.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        performance.session = session
        performance.exerciseDefinition = definition
        session.performances = [performance]
        context.insert(session)
        context.insert(performance)

        var repetitionSetEntries: [WorkoutSetEvidence] = []
        repetitionSetEntries.reserveCapacity(5)
        for index in 1 ... 5 {
            let evidence = WorkoutSetEvidence(
                logicalSetIndex: index,
                side: WorkoutEffortSide.none,
                targetKind: .repetitions,
                reps: 5,
                externalWeightKG: 50,
                restSeconds: index < 5 ? 60 : nil
            )
            repetitionSetEntries.append(evidence)
        }

        let entry = WorkoutEntry(
            date: session.startedAt,
            exercise: definition.canonicalName,
            exerciseID: definition.id,
            setEntries: repetitionSetEntries,
            restSeconds: 60,
            sourceWorkoutSessionID: session.id,
            sourcePerformanceID: performance.id,
            projectionKey: SomaDataMigration.projectionKey(for: performance.id)
        )
        entry.exerciseDefinition = definition
        entry.sourcePerformance = performance
        performance.projectedWorkout = entry
        context.insert(entry)
        try? BusinessIDAllocator.assign(entry, namespace: "workout", in: context)
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

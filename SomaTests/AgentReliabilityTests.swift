@testable import Soma
import SwiftData
import XCTest

final class AgentReliabilityTests: XCTestCase {
    func testMaxStepsPreferenceDefaultsAndClamps() throws {
        let suiteName = "AgentReliabilityTests.maxSteps.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            ReActAgentPreference.maxSteps(defaults: defaults),
            ReActAgentPreference.defaultMaxSteps
        )
        ReActAgentPreference.setMaxSteps(0, defaults: defaults)
        XCTAssertEqual(
            ReActAgentPreference.maxSteps(defaults: defaults),
            ReActAgentPreference.minimumMaxSteps
        )
        ReActAgentPreference.setMaxSteps(9999, defaults: defaults)
        XCTAssertEqual(
            ReActAgentPreference.maxSteps(defaults: defaults),
            ReActAgentPreference.maximumMaxSteps
        )
        ReActAgentPreference.setMaxSteps(42, defaults: defaults)
        XCTAssertEqual(ReActAgentPreference.maxSteps(defaults: defaults), 42)
    }

    @MainActor
    func testJobBusinessTimestampFreezesAtFirstLoopStart() {
        let sentAt = Date(timeIntervalSince1970: 1_786_000_000)
        let startedAt = sentAt.addingTimeInterval(120)
        let job = AgentJob(
            turnID: UUID(),
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            userText: "跨日记录",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "",
                includeLocation: false
            ),
            createdAt: sentAt
        )

        XCTAssertEqual(job.frozenExecutionDate, sentAt)
        job.freezeLoopStartIfNeeded(at: startedAt)
        job.freezeLoopStartIfNeeded(at: startedAt.addingTimeInterval(86400))
        XCTAssertEqual(job.frozenExecutionDate, startedAt)
    }

    func testNormalizedSignaturesCollapseSynonymsAndNilDefaults() {
        let withExercise = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(exercise: " 深蹲 ", sets: 4, reps: 8)
        )
        let withExerciseName = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(exerciseName: "深蹲", sets: 4, reps: 8)
        )
        let withExplicitNilNote = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(
                exerciseName: "深蹲",
                sets: 4,
                reps: 8,
                note: nil
            )
        )
        XCTAssertEqual(withExercise.signature, withExerciseName.signature)
        XCTAssertEqual(withExerciseName.signature, withExplicitNilNote.signature)
    }

    func testNormalizedSignaturesPreserveSetEntryOrder() {
        let ascending = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(
                exerciseName: "卧推",
                setEntries: [
                    AgentWorkoutSetInput(reps: 8, externalWeightKG: 60),
                    AgentWorkoutSetInput(reps: 6, externalWeightKG: 70)
                ]
            )
        )
        let descending = AgentToolCall(
            name: .recordWorkout,
            arguments: AgentToolArguments(
                exerciseName: "卧推",
                setEntries: [
                    AgentWorkoutSetInput(reps: 6, externalWeightKG: 70),
                    AgentWorkoutSetInput(reps: 8, externalWeightKG: 60)
                ]
            )
        )
        XCTAssertNotEqual(ascending.signature, descending.signature)
    }

    @MainActor
    func testMutationReceiptFailedDoesNotBlockRetry() throws {
        let context = try makeContext()
        let turnID = UUID()
        let call = AgentToolCall(
            name: .recordMeal,
            arguments: AgentToolArguments(title: "鸡胸", calories: 300)
        )
        var attempts = 0
        let first = AgentMutationStore.execute(call, turnID: turnID, in: context) {
            attempts += 1
            return .failure("临时失败")
        }
        let second = AgentMutationStore.execute(call, turnID: turnID, in: context) {
            attempts += 1
            return ConversationRecorder.executeAgentTool(
                call,
                sourceText: "午餐鸡胸",
                sourceTurnID: turnID,
                mediaKind: .none,
                mediaPath: nil,
                in: context
            )
        }
        XCTAssertFalse(first.ok)
        XCTAssertTrue(second.ok)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 1)
    }

    @MainActor
    func testAsyncMutationReceiptCommitsSuccessAndSkipsReplay() async throws {
        let context = try makeContext()
        let turnID = UUID()
        let call = AgentToolCall(
            name: .submitFeedback,
            arguments: AgentToolArguments()
        )
        var attempts = 0

        let first = try await AgentMutationStore.executeAsync(
            call,
            turnID: turnID,
            in: context
        ) {
            attempts += 1
            return .success("反馈已发送。")
        }
        let replay = try await AgentMutationStore.executeAsync(
            call,
            turnID: turnID,
            in: context
        ) {
            attempts += 1
            return .failure("不应再次执行")
        }

        XCTAssertTrue(first.ok)
        XCTAssertEqual(replay, first)
        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    func testAsyncMutationReceiptRemovesCancellationForRetry() async throws {
        let context = try makeContext()
        let turnID = UUID()
        let call = AgentToolCall(
            name: .submitFeedback,
            arguments: AgentToolArguments()
        )

        do {
            _ = try await AgentMutationStore.executeAsync(
                call,
                turnID: turnID,
                in: context
            ) {
                throw CancellationError()
            }
            XCTFail("取消必须向上抛出")
        } catch is CancellationError {
            // Expected.
        }

        let retry = try await AgentMutationStore.executeAsync(
            call,
            turnID: turnID,
            in: context
        ) {
            .success("反馈已发送。")
        }
        XCTAssertTrue(retry.ok)
    }

    @MainActor
    func testBusinessKeyFlagsCrossTurnDuplicateWithoutMerging() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_785_386_220)
        let first = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(
                    exerciseName: "深蹲",
                    sets: 4,
                    reps: 8,
                    weight: 60
                )
            ),
            sourceText: "深蹲 4x8 60kg",
            sourceDate: date,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let second = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(
                    exerciseName: "深蹲",
                    sets: 4,
                    reps: 8,
                    weight: 60
                )
            ),
            sourceText: "深蹲 4x8 60kg",
            sourceDate: date.addingTimeInterval(600),
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(first.ok)
        XCTAssertTrue(second.ok)
        XCTAssertTrue(second.observation.contains("疑似重复"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
    }

    func testToolExposureKeepsCoreAndExpandsPlansOnKeyword() {
        let groups = AgentToolExposurePolicy.initialGroups(
            signals: AgentToolExposureSignals(
                text: "开始执行今天的训练计划",
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            )
        )
        XCTAssertTrue(groups.contains(.core))
        XCTAssertTrue(groups.contains(.plans))
        let tools = AgentToolExposurePolicy.tools(for: groups)
        XCTAssertTrue(tools.contains(.expandToolGroup))
        XCTAssertTrue(tools.contains(.startGuidedWorkout))
        XCTAssertFalse(tools.contains(.updateGym))
    }

    func testGeneralAdviceDoesNotExposeMutationToolUntilNeeded() {
        let advice = AgentToolExposurePolicy.initialGroups(
            signals: AgentToolExposureSignals(
                text: "深蹲时怎样保持躯干稳定？",
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            )
        )
        XCTAssertFalse(advice.contains(.records))
        XCTAssertFalse(
            AgentToolExposurePolicy.tools(for: advice).contains(.mutateUserData)
        )

        let recording = AgentToolExposurePolicy.initialGroups(
            signals: AgentToolExposureSignals(
                text: "记录深蹲 4组8次60kg",
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            )
        )
        XCTAssertTrue(recording.contains(.records))
        XCTAssertTrue(
            AgentToolExposurePolicy.tools(for: recording).contains(.mutateUserData)
        )
    }

    func testQuestionKeywordsDoNotAccidentallyExposeMutationTools() {
        for text in [
            "每周练几次比较好？",
            "体重怎么下降？",
            "晚餐吃什么？",
            "体重 70kg 正常吗？"
        ] {
            let groups = AgentToolExposurePolicy.initialGroups(signals: .init(
                text: text,
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            ))
            XCTAssertFalse(groups.contains(.records), text)
        }

        for text in ["深蹲 4组8次60kg", "体重 70kg", "午餐 两个鸡蛋"] {
            let groups = AgentToolExposurePolicy.initialGroups(signals: .init(
                text: text,
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            ))
            XCTAssertTrue(groups.contains(.records), text)
        }
    }

    @MainActor
    func testChatCardsLockAsSoonAsUserSendsANewerMessage() {
        let sessionID = UUID()
        let assistant = CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: "已记录"
        )
        let user = CoachMessage(
            sessionID: sessionID,
            isFromCoach: false,
            text: "下一条消息"
        )

        XCTAssertEqual(
            ChatRecordEditPolicy.latestEditableAssistantMessageID(in: [assistant]),
            assistant.id
        )
        XCTAssertNil(
            ChatRecordEditPolicy.latestEditableAssistantMessageID(in: [assistant, user])
        )
        XCTAssertTrue(ConversationStarterPolicy.shouldShow(for: []))
        XCTAssertFalse(ConversationStarterPolicy.shouldShow(for: [user]))
    }

    func testCustomStarterPromptsAreTrimmedDeduplicatedAndCapped() {
        let raw = "  记录晨起体重  \n\n记录午餐\n记录晨起体重"
        XCTAssertEqual(
            ConversationStarterPolicy.customPrompts(from: raw),
            ["记录晨起体重", "记录午餐"]
        )
        XCTAssertEqual(
            ConversationStarterPolicy.customPrompts(
                from: (1 ... 7).map { "旧快捷语\($0)" }.joined(separator: "\n")
            ),
            (2 ... 7).map { "旧快捷语\($0)" }
        )
        let values = (1 ... 7).reduce(into: [String]()) { result, index in
            result = ConversationStarterPolicy.adding(" 快捷语\(index) ", to: result)
        }
        XCTAssertEqual(values.count, 6)
        XCTAssertEqual(values.first, "快捷语2")
        XCTAssertEqual(
            ConversationStarterPolicy.adding("快捷语7", to: values).last,
            "快捷语7"
        )
    }

    func testResumeProjectionRemovesRunningAndFailedStepStyles() {
        let items = [
            AgentTurnItem(kind: .tool, status: .succeeded, title: "已完成"),
            AgentTurnItem(kind: .tool, status: .failed, title: "旧失败"),
            AgentTurnItem(kind: .tool, status: .running, title: "旧运行"),
            AgentTurnItem(kind: .error, status: .failed, title: "旧错误")
        ]

        XCTAssertEqual(
            ConversationResumeProjection.completedItems(from: items).map(\.title),
            ["已完成"]
        )
    }

    func testLaterFailureReplacesCancellationAndCompletionClearsFailureStyle() {
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentStatus: .running
        )
        message.applyAgentEvent(.failed(
            message: "已取消",
            cancelled: true,
            at: Date(timeIntervalSince1970: 100)
        ))
        message.applyAgentEvent(.failed(
            message: "整个 ReAct Loop 超过 180 秒",
            cancelled: false,
            at: Date(timeIntervalSince1970: 101)
        ))

        XCTAssertEqual(message.agentTurnItems.count, 1)
        XCTAssertEqual(
            message.agentTurnItems.first?.errorMessage,
            "整个 ReAct Loop 超过 180 秒"
        )

        message.applyAgentEvent(.completed(
            answer: "已完成",
            at: Date(timeIntervalSince1970: 102)
        ))
        XCTAssertFalse(message.agentTurnItems.contains { $0.kind == .error })
    }

    @MainActor
    func testPersistentAttemptStartClearsPriorFailureButKeepsSuccessfulStep() {
        let jobID = UUID()
        let turnID = UUID()
        let completedAt = Date(timeIntervalSince1970: 100)
        let completedTool = AgentTraceSpan(
            kind: .tool,
            title: "保存训练记录",
            status: .succeeded,
            startedAt: completedAt,
            endedAt: completedAt
        )
        let events = [
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 1,
                attemptNumber: 1,
                kind: .attemptStarted,
                createdAt: completedAt
            ),
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 2,
                attemptNumber: 1,
                kind: .span,
                payload: .init(span: completedTool),
                createdAt: completedAt
            ),
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 3,
                attemptNumber: 1,
                kind: .cancelled,
                payload: .init(message: "已取消", cancelled: true),
                createdAt: completedAt
            ),
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 4,
                attemptNumber: 1,
                kind: .attemptStarted,
                createdAt: completedAt.addingTimeInterval(1)
            )
        ]
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentStatus: .failed,
            turnID: turnID
        )

        PersistentAgentEventProjection.replayChat(events: events, onto: message)

        XCTAssertEqual(message.agentStatus, .running)
        XCTAssertEqual(message.agentTurnItems.map(\.title), ["保存训练记录"])
        XCTAssertEqual(message.agentTurnItems.first?.status, .succeeded)
    }

    func testCurrentTurnPromptSeparatesStableContractFromDynamicInput() {
        let prompt = ReActAgentPrompt.user(
            text: "记录深蹲",
            context: "可信摘要",
            imageCount: 0,
            hasVideo: false
        )
        XCTAssertTrue(prompt.hasPrefix("[SOMA CURRENT TURN v1]"))
        XCTAssertTrue(prompt.contains("[TRUSTED LOCAL CONTEXT]\n可信摘要"))
        XCTAssertTrue(prompt.contains("[CURRENT USER INPUT]\n记录深蹲"))
        XCTAssertTrue(prompt.contains("一般建议直接回答"))
    }

    func testToolExposureSelectsProductFeedbackButNotWorkoutFeedback() {
        let productGroups = AgentToolExposurePolicy.initialGroups(
            signals: AgentToolExposureSignals(
                text: "我想反馈一个问题：这个按钮无法点击",
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            )
        )
        XCTAssertTrue(productGroups.contains(.feedback))
        XCTAssertTrue(
            AgentToolExposurePolicy.tools(for: productGroups)
                .contains(.submitFeedback)
        )

        let workoutGroups = AgentToolExposurePolicy.initialGroups(
            signals: AgentToolExposureSignals(
                text: "请给我的深蹲动作一些反馈",
                hasVideo: false,
                hasActiveProgram: false,
                hasActiveGuidedSession: false
            )
        )
        XCTAssertFalse(workoutGroups.contains(.feedback))
    }

    func testPrefixStabilityForExposedTools() {
        let signals = AgentToolExposureSignals(
            text: "记录深蹲",
            hasVideo: false,
            hasActiveProgram: false,
            hasActiveGuidedSession: false
        )
        let first = AgentToolExposurePolicy.tools(
            for: AgentToolExposurePolicy.initialGroups(signals: signals)
        ).map(\.rawValue)
        let second = AgentToolExposurePolicy.tools(
            for: AgentToolExposurePolicy.initialGroups(signals: signals)
        ).map(\.rawValue)
        XCTAssertEqual(first, second)
    }

    @MainActor
    func testContextPackMarksMissingAsAbsent() throws {
        let context = try makeContext()
        let pack = AgentContextPackBuilder.build(
            gyms: [],
            equipment: [],
            in: context
        )
        XCTAssertTrue(pack.contains("身体信息：未填写"))
        XCTAssertTrue(pack.contains("健身房：无"))
        XCTAssertFalse(pack.contains("70kg"))
    }

    @MainActor
    func testInterruptedWithoutCheckpointFailsJobAndDoesNotStayRunnable() throws {
        let context = try makeContext()
        let turnID = UUID()
        let session = ConversationSession()
        context.insert(session)
        let response = CoachMessage(
            sessionID: session.id,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: 1
        )
        context.insert(response)
        let job = AgentJob(
            turnID: turnID,
            sessionID: session.id,
            userMessageID: UUID(),
            dataSpace: .personal,
            backend: .local,
            state: .running,
            userText: "记录深蹲",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "",
                includeLocation: false
            ),
            createdAt: .now
        )
        job.responseMessageID = response.id
        job.leaseOwner = "test"
        job.leaseExpiresAt = .now.addingTimeInterval(-1)
        context.insert(job)
        try context.save()

        DataIntegrityRepair.finalizeInterruptedAgentTraces(in: context)

        XCTAssertEqual(response.agentStatus, .failed)
        XCTAssertEqual(job.state, .failed)
        XCTAssertFalse(job.state.isRunnable)

        let resumed = try AgentJobStore.resumeForegroundJobs(
            dataSpace: .personal,
            in: context
        )
        XCTAssertTrue(resumed.isEmpty)
        XCTAssertEqual(job.state, .failed)
    }

    @MainActor
    func testAggregateQueryGroupsByDay() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_785_386_220)
        context.insert(WorkoutEntry(
            date: day,
            exercise: "深蹲",
            sets: 3,
            reps: 8,
            weight: 60
        ))
        context.insert(WorkoutEntry(
            date: day.addingTimeInterval(86400),
            exercise: "卧推",
            sets: 4,
            reps: 6,
            weight: 50
        ))
        try context.save()
        let result = AgentUserDataAggregator.aggregate(
            arguments: AgentToolArguments(
                scope: "aggregate",
                dateFrom: "2026-07-01",
                dateTo: "2026-08-01",
                groupBy: "day",
                metric: "sets"
            ),
            in: context
        )
        XCTAssertTrue(result.ok)
        guard case let .object(data)? = result.data,
              case let .array(items)? = data["items"]
        else {
            return XCTFail("聚合结果应返回 Tool v2 items。")
        }
        let values = items.compactMap { item -> Double? in
            guard case let .object(fields) = item,
                  case let .number(value)? = fields["value"]
            else { return nil }
            return value
        }
        XCTAssertEqual(Set(values), Set([3, 4]))
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CoachMessage.self,
            ConversationSession.self,
            WorkoutEntry.self,
            MealEntry.self,
            BodyEntry.self,
            UserProfile.self,
            GymProfile.self,
            GymEquipment.self,
            ExerciseDefinition.self,
            TrainingProgram.self,
            WorkoutTemplateVersion.self,
            TemplateExercise.self,
            WorkoutSession.self,
            AgentMutationReceipt.self,
            AgentJob.self,
            PersistentAgentEvent.self,
            AgentTrace.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}

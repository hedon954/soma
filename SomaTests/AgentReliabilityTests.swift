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

    func testRuntimeTimeoutPreferencesDefaultPerMediaAndClampIndependently() throws {
        let suiteName = "AgentReliabilityTests.runtimeTimeout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let base = AgentStreamDeadlinePolicy()

        XCTAssertEqual(ReActAgentPreference.textRuntimeTimeoutMinutes(defaults: defaults), 3)
        XCTAssertEqual(ReActAgentPreference.imageRuntimeTimeoutMinutes(defaults: defaults), 5)
        XCTAssertEqual(ReActAgentPreference.videoRuntimeTimeoutMinutes(defaults: defaults), 10)

        ReActAgentPreference.setRuntimeTimeoutMinutes(
            text: 1,
            image: 17,
            video: 999,
            defaults: defaults
        )
        XCTAssertEqual(ReActAgentPreference.textRuntimeTimeoutMinutes(defaults: defaults), 3)
        XCTAssertEqual(ReActAgentPreference.imageRuntimeTimeoutMinutes(defaults: defaults), 17)
        XCTAssertEqual(ReActAgentPreference.videoRuntimeTimeoutMinutes(defaults: defaults), 60)
        let configured = ReActAgentPreference.deadlinePolicy(base, defaults: defaults)
        XCTAssertEqual(configured.textLoopTotal, 180)
        XCTAssertEqual(configured.imageLoopTotal, 1020)
        XCTAssertEqual(configured.videoLoopTotal, 3600)

        defaults.removeObject(forKey: ReActAgentPreference.textRuntimeTimeoutMinutesKey)
        defaults.removeObject(forKey: ReActAgentPreference.imageRuntimeTimeoutMinutesKey)
        defaults.removeObject(forKey: ReActAgentPreference.videoRuntimeTimeoutMinutesKey)
        defaults.set(12, forKey: "agent.react.runtimeTimeoutMinutes")
        XCTAssertEqual(ReActAgentPreference.textRuntimeTimeoutMinutes(defaults: defaults), 12)
        XCTAssertEqual(ReActAgentPreference.imageRuntimeTimeoutMinutes(defaults: defaults), 12)
        XCTAssertEqual(ReActAgentPreference.videoRuntimeTimeoutMinutes(defaults: defaults), 12)
        ReActAgentPreference.migrateLegacyRuntimeTimeoutIfNeeded(defaults: defaults)
        XCTAssertEqual(
            defaults.object(forKey: ReActAgentPreference.textRuntimeTimeoutMinutesKey) as? Int,
            12
        )
        XCTAssertEqual(
            defaults.object(forKey: ReActAgentPreference.imageRuntimeTimeoutMinutesKey) as? Int,
            12
        )
        XCTAssertEqual(
            defaults.object(forKey: ReActAgentPreference.videoRuntimeTimeoutMinutesKey) as? Int,
            12
        )
        XCTAssertNil(defaults.object(forKey: "agent.react.runtimeTimeoutMinutes"))
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
            name: .createWorkout,
            arguments: AgentToolArguments(exercise: " 深蹲 ", sets: 4, reps: 8)
        )
        let withExerciseName = AgentToolCall(
            name: .createWorkout,
            arguments: AgentToolArguments(exerciseName: "深蹲", sets: 4, reps: 8)
        )
        let withExplicitNilNote = AgentToolCall(
            name: .createWorkout,
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
            name: .createWorkout,
            arguments: AgentToolArguments(
                exerciseName: "卧推",
                setEntries: [
                    AgentWorkoutSetInput(reps: 8, externalWeightKG: 60),
                    AgentWorkoutSetInput(reps: 6, externalWeightKG: 70)
                ]
            )
        )
        let descending = AgentToolCall(
            name: .createWorkout,
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
            name: .createMeal,
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
        let first = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exerciseName: "深蹲",
                sets: 4,
                reps: 8,
                weight: 60
            ),
            sourceText: "深蹲 4x8 60kg",
            sourceDate: date,
            sourceTurnID: UUID(),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let second = ConversationRecorder.recordWorkout(
            AgentToolArguments(
                exerciseName: "深蹲",
                sets: 4,
                reps: 8,
                weight: 60
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

    func testUnselectedShortcutRegistersFullCurrentProtocol() {
        let tools = AgentToolExposurePolicy.tools(selectedShortcut: nil)
        XCTAssertEqual(tools.count, AgentToolName.allCases.count)
        XCTAssertTrue(tools.contains(.loadSkill))
        XCTAssertTrue(tools.contains(.startProgram))
        XCTAssertTrue(tools.contains(.updateGym))
        XCTAssertTrue(tools.contains(.createWorkout))
    }

    func testGeneralAdviceWithoutShortcutStillRegistersCurrentMutationTools() {
        let tools = AgentToolExposurePolicy.tools(selectedShortcut: nil)
        XCTAssertTrue(tools.contains(.createWorkout))
        XCTAssertTrue(tools.contains(.createMeal))
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
        XCTAssertEqual(
            message.agentTurnItems.map(\.title),
            ["保存训练记录", "已收到，正在准备处理…"]
        )
        XCTAssertEqual(message.agentTurnItems.first?.status, .succeeded)
        XCTAssertEqual(message.agentTurnItems.last?.kind, .activity)
    }

    func testUnselectedShortcutIncludesFeedbackWhileNarrowedShortcutDoesNot() {
        let defaultTools = AgentToolExposurePolicy.tools(selectedShortcut: nil)
        XCTAssertTrue(defaultTools.contains(.submitFeedback))

        let shortcut = AgentInputShortcut(
            title: "动作分析",
            skillID: AgentSkill.movementAnalysis.rawValue,
            toolNames: AgentToolExposurePolicy.toolNames(
                for: [.exercises, .workouts, .review]
            )
        )
        let selectedTools = AgentToolExposurePolicy.tools(
            selectedShortcut: shortcut
        )
        XCTAssertFalse(selectedTools.contains(.submitFeedback))
        XCTAssertFalse(selectedTools.contains(.loadSkill))
        XCTAssertTrue(selectedTools.contains(.recordPerformanceAnalysis))
    }

    func testPrefixStabilityForExposedTools() {
        let first = AgentToolExposurePolicy.tools(selectedShortcut: nil)
            .map(\.rawValue)
        let second = AgentToolExposurePolicy.tools(selectedShortcut: nil)
            .map(\.rawValue)
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
        XCTAssertTrue(pack.contains("Int64 record_id"))
        XCTAssertFalse(pack.contains("未填写"))
        XCTAssertFalse(pack.contains("健身房：无"))
        XCTAssertFalse(pack.contains("70kg"))
    }

    @MainActor
    func testContextPackExposesInt64RecordIDsInsteadOfUUIDs() throws {
        let context = try makeContext()
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_788_883_200)
        let meal = MealEntry(
            date: now,
            mealType: .snack,
            title: "猕猴桃",
            calories: 80,
            sourceSessionID: sessionID
        )
        meal.businessID = 54
        context.insert(meal)
        let workout = WorkoutEntry(
            date: now,
            exercise: "虚构深蹲",
            sourceSessionID: sessionID
        )
        workout.businessID = 12
        context.insert(workout)
        let olderMeal = MealEntry(
            date: now.addingTimeInterval(-6 * 24 * 3600),
            mealType: .snack,
            title: "猕猴桃",
            calories: 90,
            sourceSessionID: sessionID
        )
        olderMeal.businessID = 7
        context.insert(olderMeal)
        try context.save()

        let pack = AgentContextPackBuilder.build(
            gyms: [],
            equipment: [],
            in: context,
            sessionID: sessionID,
            businessDate: now,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        XCTAssertTrue(pack.contains("record_id: 54"))
        XCTAssertTrue(pack.contains("Int64 record_id"))
        XCTAssertTrue(pack.contains("record_id: 12"))
        XCTAssertTrue(pack.contains("[record_id:54]"))
        XCTAssertFalse(pack.contains(meal.id.uuidString))
        XCTAssertFalse(pack.contains(workout.id.uuidString))

        let facts = try XCTUnwrap(
            AgentCrossTurnFactSummary.recentMutationFacts(
                sessionID: sessionID,
                excludingTurnID: UUID(),
                in: context
            )
        )
        XCTAssertTrue(facts.contains("record_id=54"))
        XCTAssertTrue(facts.contains("record_id=7"))
        XCTAssertFalse(facts.contains(meal.id.uuidString.lowercased()))
    }

    @MainActor
    func testContextPackAssignsMissingInt64RecordIDsInsteadOfPlaceholders() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_788_883_200)
        let meal = MealEntry(date: now, mealType: .snack, title: "猕猴桃", calories: 80)
        context.insert(meal)
        try context.save()
        XCTAssertNil(meal.businessID)

        let pack = AgentContextPackBuilder.build(
            gyms: [],
            equipment: [],
            in: context,
            businessDate: now,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        XCTAssertNotNil(meal.businessID)
        XCTAssertTrue(pack.contains("record_id: \(meal.businessID!)"))
        XCTAssertFalse(pack.contains(meal.id.uuidString))
    }

    @MainActor
    func testMealItemJSONOmitsUUIDSoModelsCannotTreatItAsRecordID() {
        let item = MealItem(id: UUID(), name: "猕猴桃", calories: 80, protein: 1)
        let json = ConversationRecorder.mealItemJSON(item, includeNutrition: true)
        guard case let .object(object) = json else {
            return XCTFail("meal item JSON must be an object")
        }
        XCTAssertNil(object["id"])
        XCTAssertEqual(object["name"], .string("猕猴桃"))
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
    func testAggregateMuscleGroupUsesWorkoutExerciseRelationship() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_785_386_220)
        let exercise = ExerciseDefinition(
            canonicalName: "虚构深蹲",
            primaryMuscles: ["股四头肌"]
        )
        let workout = WorkoutEntry(
            date: day,
            exercise: exercise.canonicalName,
            exerciseID: exercise.id,
            sets: 3,
            reps: 8,
            weight: 60
        )
        workout.exerciseDefinition = exercise
        context.insert(exercise)
        context.insert(workout)
        try context.save()

        let result = AgentUserDataAggregator.aggregate(
            arguments: AgentToolArguments(
                scope: "aggregate",
                dateFrom: "2026-07-01",
                dateTo: "2026-08-01",
                groupBy: "muscle_group",
                metric: "sets"
            ),
            in: context
        )

        XCTAssertTrue(result.ok)
        guard case let .object(data)? = result.data,
              case let .array(items)? = data["items"],
              case let .object(fields)? = items.first,
              case let .string(group)? = fields["group"],
              case let .number(value)? = fields["value"]
        else {
            return XCTFail("肌群聚合应返回关系中动作定义对应的分组。")
        }
        XCTAssertNotEqual(group, "未映射")
        XCTAssertEqual(value, 3)
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

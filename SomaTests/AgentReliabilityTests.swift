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

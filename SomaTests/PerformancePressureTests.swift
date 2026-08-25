@testable import Soma
import SwiftData
import XCTest

private final class SendableNotificationBox: @unchecked Sendable {
    var value: Notification?
}

final class PerformancePressureTests: XCTestCase {
    @MainActor
    func testSaveImpactIgnoresChatForCoachButInvalidatesInsights() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let message = CoachMessage(
            sessionID: UUID(),
            isFromCoach: true,
            text: "虚构流式回复"
        )
        let notification = try notificationWhenSaving(context) {
            context.insert(message)
        }

        XCTAssertFalse(
            ModelContextSaveImpact.affectsCoachSuggestions(
                notification,
                in: context
            )
        )
        XCTAssertTrue(
            ModelContextSaveImpact.affectsInsights(notification, in: context)
        )
        XCTAssertFalse(
            ModelContextSaveImpact.affectsExerciseHistory(
                notification,
                exerciseID: UUID(),
                in: context
            )
        )
    }

    @MainActor
    func testExerciseHistoryInvalidatesOnlyForMatchingExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let matchingID = UUID()
        let notification = try notificationWhenSaving(context) {
            context.insert(WorkoutEntry(
                exercise: "虚构匹配动作",
                exerciseID: matchingID
            ))
        }

        XCTAssertTrue(
            ModelContextSaveImpact.affectsExerciseHistory(
                notification,
                exerciseID: matchingID,
                in: context
            )
        )
        XCTAssertFalse(
            ModelContextSaveImpact.affectsExerciseHistory(
                notification,
                exerciseID: UUID(),
                in: context
            )
        )
        XCTAssertTrue(
            ModelContextSaveImpact.affectsExerciseLibraryRecents(
                notification,
                in: context
            )
        )
    }

    @MainActor
    func testSaveImpactIgnoresAgentEventForEveryBusinessSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let notification = try notificationWhenSaving(context) {
            context.insert(PersistentAgentEvent(
                jobID: UUID(),
                turnID: UUID(),
                sequence: 1,
                attemptNumber: 1,
                kind: .assistantTextDelta
            ))
        }

        XCTAssertFalse(
            ModelContextSaveImpact.affectsCoachSuggestions(
                notification,
                in: context
            )
        )
        XCTAssertFalse(
            ModelContextSaveImpact.affectsInsights(
                notification,
                in: context
            )
        )
        XCTAssertFalse(
            ModelContextSaveImpact.affectsExerciseHistory(
                notification,
                exerciseID: UUID(),
                in: context
            )
        )
        XCTAssertFalse(
            ModelContextSaveImpact.affectsExerciseLibraryRecents(
                notification,
                in: context
            )
        )
    }

    @MainActor
    func testInsightsSaveImpactAcceptsBackgroundContextInSameContainer() throws {
        let container = try makeContainer()
        let background = ModelContext(container)
        let notification = try notificationWhenSaving(background) {
            background.insert(BodyEntry(weight: 70, notes: "虚构后台写入"))
        }

        XCTAssertTrue(
            ModelContextSaveImpact.affectsInsights(
                notification,
                in: container.mainContext
            )
        )
    }

    @MainActor
    func testInsightsSaveImpactRejectsAnotherContainer() throws {
        let target = try makeContainer()
        let unrelated = try makeContainer()
        let notification = try notificationWhenSaving(unrelated.mainContext) {
            unrelated.mainContext.insert(WorkoutEntry(exercise: "虚构其他空间记录"))
        }

        XCTAssertFalse(
            ModelContextSaveImpact.affectsInsights(
                notification,
                in: target.mainContext
            )
        )
    }

    @MainActor
    func testInsightsSnapshotRejectsStaleCompletionAndRequestsLatestRevision() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let state = InsightsSnapshotRevisionState()
        let first = state.requestKey(
            excluding: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertNotNil(first)

        state.markDataChanged()

        XCTAssertFalse(
            try state.acceptsCompletion(
                for: XCTUnwrap(first),
                now: now,
                calendar: calendar
            )
        )
        let latest = state.requestKey(
            excluding: first,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(latest?.dataRevision, 1)
        XCTAssertTrue(
            try state.acceptsCompletion(
                for: XCTUnwrap(latest),
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testInsightsCountsDoNotMaterializeOrCapSuccessfulMessages() throws {
        let container = try makeContainer()
        let context = container.mainContext
        for index in 0 ..< 1005 {
            context.insert(CoachMessage(
                date: Date(timeIntervalSince1970: Double(index)),
                sessionID: UUID(),
                isFromCoach: true,
                text: "虚构回复 \(index)",
                agentStatus: .succeeded,
                turnID: UUID()
            ))
        }
        context.insert(CoachMessage(
            isFromCoach: false,
            text: "不计入足迹",
            agentStatus: .succeeded,
            turnID: UUID()
        ))
        try context.save()

        XCTAssertEqual(
            try InsightsCountQueries.successfulFootprintCount(in: context),
            1005
        )
    }

    @MainActor
    func testCoachSuggestionSnapshotBuildsPureValuesOffViewPath() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = ExerciseDefinition(canonicalName: "虚构深蹲")
        let workout = WorkoutEntry(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            exercise: exercise.canonicalName,
            exerciseID: exercise.id,
            setEntries: [WorkoutSetEvidence(reps: 8, externalWeightKG: 40)]
        )
        context.insert(exercise)
        context.insert(workout)
        try context.save()

        let loader = CoachSuggestionSnapshotLoader(modelContainer: container)
        let snapshot = try await loader.load()

        XCTAssertEqual(snapshot.exercises.map(\.name), ["虚构深蹲"])
        XCTAssertEqual(snapshot.latestWorkoutExerciseName, "虚构深蹲")
        XCTAssertEqual(snapshot.recentCapacities.count, 1)
        XCTAssertEqual(snapshot.recentCapacities.first?.recordDraft?.setEntries.count, 1)
    }

    @MainActor
    func testCoachSuggestionSnapshotReadsOnlyRecentSessionRelationshipGraph() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = ExerciseDefinition(canonicalName: "虚构硬拉")
        let prescription = TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            targetSets: 1,
            targetReps: 5
        )
        let session = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            prescriptionSnapshot: [prescription],
            status: .completed
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        performance.session = session
        performance.exerciseDefinition = exercise
        let set = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            actualReps: 5,
            actualWeightKG: 80,
            status: .completed
        )
        set.performance = performance

        // 全库噪音不属于最近会话，不能抢占建议查询的固定配额。
        let unrelated = ExercisePerformance(
            sessionID: UUID(),
            exerciseID: exercise.id,
            exerciseName: "虚构无关记录",
            order: 9999,
            prescriptionSnapshot: prescription,
            status: .completed
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(performance)
        context.insert(set)
        context.insert(unrelated)
        try context.save()

        let loader = CoachSuggestionSnapshotLoader(modelContainer: container)
        let snapshot = try await loader.load()

        XCTAssertEqual(snapshot.recentCapacities.count, 1)
        XCTAssertEqual(snapshot.recentCapacities.first?.recordDraft?.exerciseName, "虚构硬拉")
        XCTAssertEqual(
            snapshot.recentCapacities.first?.recordDraft?.setEntries.first?.externalWeightKG,
            80
        )
    }

    @MainActor
    func testAgentProjectionCountsSpanEventsOffTheRootViewPath() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let jobID = UUID()
        let turnID = UUID()
        context.insert(PersistentAgentEvent(
            jobID: jobID,
            turnID: turnID,
            sequence: 1,
            attemptNumber: 1,
            kind: .span
        ))
        context.insert(PersistentAgentEvent(
            jobID: jobID,
            turnID: turnID,
            sequence: 2,
            attemptNumber: 1,
            kind: .span
        ))
        context.insert(PersistentAgentEvent(
            jobID: jobID,
            turnID: turnID,
            sequence: 3,
            attemptNumber: 1,
            kind: .assistantTextDelta
        ))
        try context.save()

        let loader = AgentProjectionOperationCountLoader(
            modelContainer: container
        )
        let counts = try await loader.load(jobIDs: [jobID, UUID()])

        XCTAssertEqual(counts[jobID], 2)
        XCTAssertEqual(counts.values.sorted(), [0, 2])
    }

    @MainActor
    func testStreamingTextDoesNotRewriteSwiftDataUntilSegmentCompletes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let turnID = UUID()
        let itemID = UUID()
        let job = AgentJob(
            turnID: turnID,
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            backend: .local,
            state: .running,
            userText: "虚构长流式请求",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "虚构上下文",
                includeLocation: false
            )
        )
        let message = CoachMessage(
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID
        )
        let trace = AgentTrace(
            provider: "fixture",
            model: "fixture",
            endpoint: "local://fixture",
            dataSpaceRaw: DataSpace.personal.rawValue,
            userInput: "虚构长流式请求",
            contextSnapshot: "虚构上下文",
            mediaKind: .none,
            imageCount: 0,
            turnID: turnID
        )
        context.insert(job)
        context.insert(message)
        context.insert(trace)
        try context.save()

        PersistentAgentEventProjection.persistAndProject(
            .assistantTextDelta(itemID: itemID, delta: "前半段"),
            job: job,
            responseMessage: message,
            trace: trace,
            in: context
        )

        XCTAssertEqual(job.responseTextSnapshot, "")
        XCTAssertEqual(message.text, "")
        XCTAssertTrue(message.agentTurnItems.isEmpty)

        PersistentAgentEventProjection.persistAndProject(
            .assistantTextCompleted(itemID: itemID, at: .now),
            job: job,
            responseMessage: message,
            trace: trace,
            liveText: LiveAgentTextSnapshot(
                itemID: itemID,
                text: "前半段后半段"
            ),
            in: context
        )

        XCTAssertEqual(job.responseTextSnapshot, "前半段后半段")
        XCTAssertEqual(message.text, "前半段后半段")
        XCTAssertEqual(message.agentTurnItems.count, 1)
        XCTAssertEqual(message.agentTurnItems.first?.text, "前半段后半段")
        XCTAssertEqual(message.agentTurnItems.first?.status, .succeeded)
    }

    @MainActor
    func testExerciseLibraryLoadsOneRecentWorkoutSnapshotForAllRows() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exerciseID = UUID()
        context.insert(WorkoutEntry(
            date: Date(timeIntervalSince1970: 100),
            exercise: "虚构划船",
            exerciseID: exerciseID,
            setEntries: [WorkoutSetEvidence(reps: 8, externalWeightKG: 30)]
        ))
        context.insert(WorkoutEntry(
            date: Date(timeIntervalSince1970: 200),
            exercise: "虚构划船",
            exerciseID: exerciseID,
            setEntries: [WorkoutSetEvidence(reps: 6, externalWeightKG: 40)]
        ))
        try context.save()

        let loader = ExerciseRecentWorkoutSnapshotLoader(
            modelContainer: container
        )
        let snapshot = try await loader.load()

        XCTAssertEqual(snapshot[exerciseID]?.date, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(snapshot[exerciseID]?.summary.contains("40") == true)
    }

    @MainActor
    func testTenThousandMessageProjectionKeepsNewestCompleteTurns() {
        let sessionID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        var messages: [CoachMessage] = []
        messages.reserveCapacity(10000)

        for index in 0 ..< 5000 {
            let turnID = UUID()
            messages.append(CoachMessage(
                date: baseDate.addingTimeInterval(Double(index * 2)),
                sessionID: sessionID,
                isFromCoach: false,
                text: "虚构用户消息 \(index)",
                turnID: turnID
            ))
            messages.append(CoachMessage(
                date: baseDate.addingTimeInterval(Double(index * 2 + 1)),
                sessionID: sessionID,
                isFromCoach: true,
                text: "虚构回复 \(index)",
                agentStatus: .succeeded,
                turnID: turnID,
                attemptNumber: 1
            ))
        }

        let projection = ConversationContextProjection.make(
            messages: messages,
            sessionID: sessionID,
            excludingTurnID: nil,
            maximumEstimatedTokens: 100_000
        )

        XCTAssertEqual(projection.exchanges.count, 10)
        XCTAssertEqual(projection.exchanges.first?.userText, "虚构用户消息 4990")
        XCTAssertEqual(projection.exchanges.last?.assistantText, "虚构回复 4999")
    }

    @MainActor
    func testFiveThousandWorkoutVolumeAggregationIsStable() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let workouts = (0 ..< 5000).map { index in
            WorkoutEntry(
                date: calendar.date(byAdding: .day, value: index % 100, to: start) ?? start,
                exercise: "虚构动作 \(index % 12)",
                sets: 1,
                reps: 10,
                weight: 20
            )
        }

        let points = TrainingVolumeAnalytics.dailyPoints(
            from: workouts,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 100)
        XCTAssertEqual(points.reduce(0) { $0 + $1.volume }, 1_000_000)
    }

    func testOneThousandMediaReferencesSelectOnlyUnretainedOrphans() {
        let stored = Set((0 ..< 1000).map { "PrivateMedia/fixture-\($0).jpg" })
        let retained = Set((0 ..< 500).map {
            "/old/container/PrivateMedia/fixture-\($0).jpg"
        })

        let orphans = MediaStore.orphanedStoredPaths(stored, retaining: retained)

        XCTAssertEqual(orphans.count, 500)
        XCTAssertFalse(orphans.contains("PrivateMedia/fixture-0.jpg"))
        XCTAssertTrue(orphans.contains("PrivateMedia/fixture-999.jpg"))
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func notificationWhenSaving(
        _ context: ModelContext,
        mutation: () -> Void
    ) throws -> Notification {
        let received = SendableNotificationBox()
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { notification in
            received.value = notification
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        mutation()
        try context.save()
        return try XCTUnwrap(received.value)
    }
}

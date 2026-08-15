@testable import Soma
import SwiftData
import XCTest

final class AgentPromptMigrationRefactorTests: XCTestCase {
    func testTurnBusinessDateOverrideDoesNotMutateSessionDefault() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let turnSentAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-15T18:42:10+08:00")
        )
        let sessionDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-05T09:00:00+08:00")
        )

        XCTAssertEqual(
            day(BusinessDateResolver.turnBusinessDate(
                in: "记录今天的训练",
                sessionBusinessDate: sessionDate,
                turnSentAt: turnSentAt,
                timeZone: zone
            ), in: zone),
            "2026-08-15"
        )
        XCTAssertEqual(
            day(BusinessDateResolver.turnBusinessDate(
                in: "补记昨天的晚餐",
                sessionBusinessDate: sessionDate,
                turnSentAt: turnSentAt,
                timeZone: zone
            ), in: zone),
            "2026-08-14"
        )
        XCTAssertEqual(
            day(BusinessDateResolver.turnBusinessDate(
                in: "补记 8月8日 的体重",
                sessionBusinessDate: sessionDate,
                turnSentAt: turnSentAt,
                timeZone: zone
            ), in: zone),
            "2026-08-08"
        )
        XCTAssertEqual(
            day(BusinessDateResolver.turnBusinessDate(
                in: "记录训练",
                sessionBusinessDate: sessionDate,
                turnSentAt: turnSentAt,
                timeZone: zone
            ), in: zone),
            "2026-08-05"
        )
        XCTAssertEqual(day(sessionDate, in: zone), "2026-08-05")
    }

    @MainActor
    func testConversationProcessingContinuesWithoutCoachView() async throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.demoContainer)
        let service = ConversationProcessingService()
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "深蹲",
            in: context
        )
        let exerciseID = try XCTUnwrap(exercise.businessID)
        let transport = MockAgentStreamTransport(responses: [
            .toolCall(
                name: "create_workout",
                argumentsFragments: [
                    #"{"exercise_id":\#(exerciseID),"set_entries":["#,
                    #"{"reps":8,"external_weight_kg":60},{"reps":8,"external_weight_kg":60},"#,
                    #"{"reps":8,"external_weight_kg":60},{"reps":8,"external_weight_kg":60}]}"#
                ]
            ),
            .text(["已记录这次深蹲。"])
        ])
        let ai = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        ai.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        let session = ConversationSession()
        context.insert(session)

        XCTAssertTrue(service.submit(
            text: "刚做完深蹲 4组8次 60kg",
            attachments: [],
            context: ConversationProcessingContext(
                structuredContext: "测试上下文",
                session: session,
                dataSpace: .demo,
                gyms: [],
                equipment: [],
                ai: ai,
                modelContext: context
            ),
            includeLocation: false,
            locationService: LocationContextService()
        ))
        XCTAssertTrue(service.isProcessing)

        for _ in 0 ..< 100 where service.isProcessing {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertFalse(service.isProcessing)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkoutEntry>()).count,
            1
        )
        let jobs = try context.fetch(FetchDescriptor<AgentJob>())
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.state, .succeeded)
        XCTAssertGreaterThan(jobs.first?.lastEventSequence ?? 0, 3)
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<PersistentAgentEvent>()).isEmpty
        )
        let messages = try context.fetch(FetchDescriptor<CoachMessage>())
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.allSatisfy { $0.sessionID == session.id })
    }

    func testPromptV2OmitsEmptyBlocksAndKeepsToolSchemasOutOfSystem() {
        let system = ReActAgentPrompt.system
        let user = ReActAgentPrompt.user(
            text: "怎样安排今天的恢复？",
            context: "",
            imageCount: 0,
            hasVideo: false
        )

        XCTAssertTrue(system.hasPrefix("[SOMA SYSTEM v2]"))
        XCTAssertTrue(system.contains("## 固定安全、真实性与授权契约"))
        XCTAssertFalse(system.contains("create_workout"))
        XCTAssertFalse(system.contains("query_user_data"))
        XCTAssertFalse(system.contains("additionalProperties"))
        XCTAssertTrue(user.hasPrefix("[SOMA CURRENT TURN v2]"))
        XCTAssertFalse(user.contains("## 可信本机上下文"))
        XCTAssertFalse(user.contains("## 当前媒体"))
        XCTAssertFalse(user.contains("未填写"))
    }

    func testAdviceUsesNoToolsAndSelectedSkillUsesExactMinimalTools() throws {
        let adviceGroups = AgentToolExposurePolicy.initialGroups(signals: .init(
            text: "怎样安排今天的恢复？",
            hasVideo: false,
            hasActiveProgram: false,
            hasActiveGuidedSession: false
        ))
        XCTAssertTrue(adviceGroups.isEmpty)
        XCTAssertTrue(AgentToolExposurePolicy.tools(for: adviceGroups).isEmpty)

        let selected = try XCTUnwrap(
            AgentSkillRegistry.descriptor(id: AgentSkill.nutritionAnalysis.rawValue)
        )
        let tools = AgentToolExposurePolicy.tools(for: selected.toolGroups)
        XCTAssertEqual(Set(tools), [
            .listMeals, .getMeal, .createMeal, .updateMeal, .deleteMeal
        ])
        XCTAssertFalse(tools.contains(.queryUserData))
        XCTAssertFalse(tools.contains(.mutateUserData))
        XCTAssertFalse(tools.contains(.loadSkill))
    }

    func testToolEnvelopeUsesStrictClosedSchemaAndOnlyActiveDefinitions() throws {
        let input = try AgentModelInputBuilder.build(
            systemPrompt: "system",
            history: [],
            userPrompt: "user",
            currentImages: [],
            currentVideos: [],
            skills: [],
            tools: [.createWorkout],
            maxSteps: 3,
            deadlinePolicy: .init()
        )
        let data = try JSONEncoder().encode(input.envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(input.envelope.activeTools, [.createWorkout])
        XCTAssertEqual(input.envelope.tools.map(\.name), [.createWorkout])
        XCTAssertTrue(json.contains(#""strict":true"#))
        XCTAssertTrue(json.contains(#""additionalProperties":false"#))
        XCTAssertTrue(json.contains(#""exercise_id""#))
        XCTAssertTrue(json.contains(#""required":["exercise_id"]"#))
    }

    func testCustomSkillPermissionsAndQuickButtonsStayInsideAllowedGroups() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = AgentCustomSkill(
            id: "my_workout",
            name: "我的训练",
            description: "快速记录训练",
            whenToUse: "用户选择快捷按钮时",
            content: "只记录用户明确给出的组次。",
            toolGroupIDs: [
                AgentToolGroup.exercises.rawValue,
                AgentToolGroup.workouts.rawValue,
                AgentToolGroup.records.rawValue,
                AgentToolGroup.feedback.rawValue,
                AgentToolGroup.core.rawValue
            ]
        )
        AgentSkillRegistry.save(custom, defaults: defaults)
        let descriptor = try XCTUnwrap(
            AgentSkillRegistry.descriptor(id: custom.id, defaults: defaults)
        )

        XCTAssertEqual(descriptor.toolGroups, [.exercises, .workouts])
        XCTAssertTrue(descriptor.markdown.contains("when_to_use:"))
        AgentSkillRegistry.setQuickSkillIDs(
            [custom.id] + AgentSkill.allCases.map(\.rawValue),
            defaults: defaults
        )
        XCTAssertEqual(AgentSkillRegistry.quickSkillIDs(defaults: defaults).count, 6)
        XCTAssertEqual(AgentSkillRegistry.quickSkillIDs(defaults: defaults).first, custom.id)
    }

    @MainActor
    func testOccurredAtUsesStableSourceDefaultAndAllowsExplicitOverride() throws {
        let (context, container, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defer { withExtendedLifetime(container) {} }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )
        let exerciseID = try XCTUnwrap(exercise.businessID)
        let frozenDefault = Date(timeIntervalSince1970: 1_786_311_000)
        let explicitText = "2026-08-08T06:30:00+08:00"
        let explicitDate = try XCTUnwrap(ISO8601DateFormatter().date(from: explicitText))

        let defaultResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createWorkout,
                arguments: .init(exerciseID: exerciseID, sets: 3, reps: 5)
            ),
            sourceText: "记录训练",
            sourceDate: frozenDefault,
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let explicitResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createWorkout,
                arguments: .init(
                    occurredAt: explicitText,
                    exerciseID: exerciseID,
                    sets: 2,
                    reps: 8
                )
            ),
            sourceText: "补记之前的训练",
            sourceDate: Date(timeIntervalSince1970: 1_786_900_000),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())

        XCTAssertTrue(defaultResult.ok)
        XCTAssertTrue(explicitResult.ok)
        XCTAssertTrue(workouts.contains { $0.date == frozenDefault })
        XCTAssertTrue(workouts.contains { $0.date == explicitDate })
    }

    @MainActor
    func testLaunchMigrationBackfillsBothSpacesBeforeUse() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let containers: [(DataSpace, ModelContainer)] = try [
            (.personal, XCTUnwrap(spaces.personalContainer)),
            (.demo, XCTUnwrap(spaces.demoContainer))
        ]
        for (space, container) in containers {
            let context = container.mainContext
            let session = ConversationSession(
                startedAt: Date(timeIntervalSince1970: 1_786_300_000)
            )
            session.businessDate = nil
            session.businessTimeZoneIdentifier = nil
            let job = AgentJob(
                turnID: UUID(),
                sessionID: session.id,
                userMessageID: UUID(),
                dataSpace: space,
                userText: "旧任务",
                mediaAttachments: [],
                contextSnapshot: .init(structuredContext: "", includeLocation: false),
                createdAt: Date(timeIntervalSince1970: 1_786_300_100)
            )
            job.turnSentAt = nil
            job.effectiveBusinessDate = nil
            job.defaultOccurredAt = nil
            let definition = ExerciseDefinition(canonicalName: "杠铃深蹲")
            definition.businessID = 50
            let pendingBody = BodyEntry(weight: 70)
            let existingBody = BodyEntry(weight: 71)
            existingBody.businessID = 50
            let workout = WorkoutEntry(exercise: "杠铃深蹲", sets: 3, reps: 5)
            context.insert(session)
            context.insert(job)
            context.insert(definition)
            context.insert(pendingBody)
            context.insert(existingBody)
            context.insert(workout)
            try context.save()

            try SomaDataMigration.migrateIfNeeded(
                container: container,
                dataSpace: space,
                now: Date(timeIntervalSince1970: 1_786_400_000),
                timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
            )

            XCTAssertNotNil(session.businessDate)
            XCTAssertEqual(session.businessTimeZoneIdentifier, "Asia/Shanghai")
            XCTAssertNotNil(job.turnSentAt)
            XCTAssertNotNil(job.effectiveBusinessDate)
            XCTAssertNotNil(job.defaultOccurredAt)
            XCTAssertEqual(workout.exerciseDefinition?.id, definition.id)
            XCTAssertEqual(workout.exerciseDefinition?.businessID, 50)
            XCTAssertEqual(pendingBody.businessID, 51)
            XCTAssertEqual(
                try context.fetch(FetchDescriptor<DataMigrationMarker>()).count,
                1
            )
        }
    }

    @MainActor
    func testRollingCompactionKeepsNewestTenPairsAndReplacesOlderSummary() async throws {
        let (context, container, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defer { withExtendedLifetime(container) {} }
        let session = ConversationSession()
        context.insert(session)
        var turnIDs: [UUID] = []
        for index in 1 ... 11 {
            let turnID = UUID()
            turnIDs.append(turnID)
            context.insert(CoachMessage(
                date: Date(timeIntervalSince1970: Double(index * 2)),
                sessionID: session.id,
                isFromCoach: false,
                text: "用户事实 \(index)",
                turnID: turnID
            ))
            context.insert(CoachMessage(
                date: Date(timeIntervalSince1970: Double(index * 2 + 1)),
                sessionID: session.id,
                isFromCoach: true,
                text: "教练回复 \(index)",
                agentStatus: .succeeded,
                turnID: turnID
            ))
        }
        try context.save()
        let ai = AIService(defaults: defaults, apiKeyOverride: "")
        let first = await ConversationCompactionMiddleware.prepare(
            sessionID: session.id,
            excludingTurnID: UUID(),
            ai: ai,
            in: context
        )

        XCTAssertTrue(first.didUpdate)
        XCTAssertEqual(first.strategy, .deterministic)
        XCTAssertTrue(first.summary?.contains(turnIDs[0].uuidString.lowercased()) == true)
        XCTAssertFalse(first.summary?.contains(turnIDs[1].uuidString.lowercased()) == true)

        let twelfthTurnID = UUID()
        context.insert(CoachMessage(
            date: Date(timeIntervalSince1970: 24),
            sessionID: session.id,
            isFromCoach: false,
            text: "用户事实 12",
            turnID: twelfthTurnID
        ))
        context.insert(CoachMessage(
            date: Date(timeIntervalSince1970: 25),
            sessionID: session.id,
            isFromCoach: true,
            text: "教练回复 12",
            agentStatus: .succeeded,
            turnID: twelfthTurnID
        ))
        try context.save()
        let second = await ConversationCompactionMiddleware.prepare(
            sessionID: session.id,
            excludingTurnID: UUID(),
            ai: ai,
            in: context
        )
        let stored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationCompactionSummary>()).first
        )

        XCTAssertTrue(second.didUpdate)
        XCTAssertTrue(second.summary?.contains(turnIDs[0].uuidString.lowercased()) == true)
        XCTAssertTrue(second.summary?.contains(turnIDs[1].uuidString.lowercased()) == true)
        XCTAssertEqual(stored.coveredTurnIDs, Array(turnIDs.prefix(2)))
    }

    @MainActor
    private func makeContext() throws -> (
        ModelContext,
        ModelContainer,
        UserDefaults,
        String
    ) {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        return (
            ModelContext(spaces.personalContainer),
            spaces.personalContainer,
            defaults,
            suiteName
        )
    }

    private func day(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

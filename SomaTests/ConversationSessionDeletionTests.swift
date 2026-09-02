@testable import Soma
import SwiftData
import XCTest

final class ConversationSessionDeletionTests: XCTestCase {
    @MainActor
    func testDeletingSessionRemovesChatGraphAndKeepsOtherSession() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixture = try insertTwoSessions(in: context)

        let outcome = try ConversationSessionDeletion.delete(
            sessionID: fixture.deleted.id,
            processingSessionID: nil,
            in: context
        )

        XCTAssertEqual(outcome, .deleted)
        let sessions = try context.fetch(FetchDescriptor<ConversationSession>())
        XCTAssertEqual(sessions.map(\.id), [fixture.kept.id])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CoachMessage>()).map(\.sessionID),
            [fixture.kept.id]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<AgentJob>()).map(\.sessionID),
            [fixture.kept.id]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PersistentAgentEvent>()).map(\.turnID),
            [fixture.keptTurnID]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<AgentTrace>()).compactMap(\.turnID),
            [fixture.keptTurnID]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<AgentMutationReceipt>()).map(\.turnID),
            [fixture.keptTurnID]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationCompactionSummary>())
                .map(\.sessionID),
            [fixture.kept.id]
        )
    }

    @MainActor
    func testDeletingSessionKeepsBusinessRecordsAndTrainingWorkoutSession() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixture = try insertTwoSessions(in: context)
        context.insert(MealEntry(
            mealType: .lunch,
            title: "虚构午餐",
            sourceTurnID: fixture.deletedTurnID,
            sourceSessionID: fixture.deleted.id
        ))
        context.insert(WorkoutEntry(
            exercise: "虚构深蹲",
            sourceTurnID: fixture.deletedTurnID,
            sourceSessionID: fixture.deleted.id
        ))
        context.insert(BodyEntry(
            notes: "虚构晨起",
            sourceTurnID: fixture.deletedTurnID,
            sourceSessionID: fixture.deleted.id
        ))
        context.insert(GymProfile(name: "虚构健身房"))
        context.insert(WorkoutSession(sourceTurnID: fixture.deletedTurnID))
        try context.save()

        let outcome = try ConversationSessionDeletion.delete(
            sessionID: fixture.deleted.id,
            processingSessionID: nil,
            in: context
        )

        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GymProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MealEntry>()).first?.sourceSessionID,
            fixture.deleted.id
        )
    }

    @MainActor
    func testDeletingCurrentSessionActivatesNewestRemaining() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let older = ConversationSession(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "较早对话"
        )
        let newer = ConversationSession(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            title: "较新对话"
        )
        let current = ConversationSession(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            title: "当前对话"
        )
        context.insert(older)
        context.insert(newer)
        context.insert(current)
        try context.save()
        let controller = ConversationSessionController(defaults: defaults)
        controller.select(current, dataSpace: .personal)

        let outcome = try ConversationSessionDeletion.delete(
            current,
            dataSpace: .personal,
            processingSessionID: nil,
            controller: controller,
            in: context
        )

        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(controller.activeSessionID, newer.id)
    }

    @MainActor
    func testDeletingLastEmptySessionCreatesANewEmptyOne() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let empty = ConversationSession(title: "新对话")
        context.insert(empty)
        try context.save()
        let controller = ConversationSessionController(defaults: defaults)
        controller.select(empty, dataSpace: .personal)
        let deletedID = empty.id

        let outcome = try ConversationSessionDeletion.delete(
            empty,
            dataSpace: .personal,
            processingSessionID: nil,
            controller: controller,
            in: context
        )

        XCTAssertEqual(outcome, .deleted)
        let remaining = try context.fetch(FetchDescriptor<ConversationSession>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotEqual(remaining.first?.id, deletedID)
        XCTAssertEqual(controller.activeSessionID, remaining.first?.id)
        let replacement = try XCTUnwrap(remaining.first)
        XCTAssertEqual(
            replacement.title,
            ConversationSession.dateTitle(
                for: replacement.startedAt,
                in: replacement.businessTimeZone
            )
        )
    }

    @MainActor
    func testNonTerminalJobRefusesDeleteAndLeavesDataIntact() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixture = try insertTwoSessions(in: context, deletedJobState: .running)

        let outcome = try ConversationSessionDeletion.delete(
            sessionID: fixture.deleted.id,
            processingSessionID: nil,
            in: context
        )

        XCTAssertEqual(outcome, .refusedBusy)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationSession>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CoachMessage>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AgentJob>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistentAgentEvent>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AgentTrace>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AgentMutationReceipt>()).count, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationCompactionSummary>()).count,
            2
        )
    }

    @MainActor
    func testProcessorBusyWithSessionRefusesDeleteEvenIfJobsAreTerminal() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixture = try insertTwoSessions(in: context)

        let outcome = try ConversationSessionDeletion.delete(
            sessionID: fixture.deleted.id,
            processingSessionID: fixture.deleted.id,
            in: context
        )

        XCTAssertEqual(outcome, .refusedBusy)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationSession>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CoachMessage>()).count, 2)
    }

    @MainActor
    func testChatOnlyMediaIsReclaimedWhileSharedMealMediaRemains() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let chatOnlyPath = try MediaStore.saveRestoredMedia(
            Data("chat-only".utf8),
            fileExtension: "jpg"
        )
        let sharedPath = try MediaStore.saveRestoredMedia(
            Data("shared-meal".utf8),
            fileExtension: "jpg"
        )
        defer {
            MediaStore.removeStoredFile(at: chatOnlyPath)
            MediaStore.removeStoredFile(at: sharedPath)
        }
        let fixture = try insertTwoSessions(
            in: context,
            deletedMedia: [
                MediaAttachmentReference(kind: .image, path: chatOnlyPath),
                MediaAttachmentReference(kind: .image, path: sharedPath)
            ]
        )
        context.insert(MealEntry(
            mealType: .lunch,
            title: "虚构午餐",
            mediaAttachments: [
                MediaAttachmentReference(kind: .image, path: sharedPath)
            ],
            sourceTurnID: fixture.deletedTurnID,
            sourceSessionID: fixture.deleted.id
        ))
        try context.save()

        let outcome = try ConversationSessionDeletion.delete(
            sessionID: fixture.deleted.id,
            processingSessionID: nil,
            in: context
        )

        XCTAssertEqual(outcome, .deleted)
        XCTAssertNil(MediaStore.url(at: chatOnlyPath))
        XCTAssertNotNil(MediaStore.url(at: sharedPath))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MealEntry>()).first?.mediaAttachments
                .map(\.path),
            [sharedPath]
        )
    }

    @MainActor
    private func insertTwoSessions(
        in context: ModelContext,
        deletedJobState: AgentJobState = .succeeded,
        deletedMedia: [MediaAttachmentReference] = []
    ) throws -> SessionPair {
        let deleted = ConversationSession(title: "待删对话")
        let kept = ConversationSession(title: "保留对话")
        context.insert(deleted)
        context.insert(kept)
        let deletedTurnID = UUID()
        let keptTurnID = UUID()
        insertChatGraph(
            session: deleted,
            turnID: deletedTurnID,
            jobState: deletedJobState,
            media: deletedMedia,
            in: context
        )
        insertChatGraph(
            session: kept,
            turnID: keptTurnID,
            jobState: .succeeded,
            in: context
        )
        try context.save()
        return SessionPair(
            deleted: deleted,
            kept: kept,
            deletedTurnID: deletedTurnID,
            keptTurnID: keptTurnID
        )
    }

    @MainActor
    private func insertChatGraph(
        session: ConversationSession,
        turnID: UUID,
        jobState: AgentJobState,
        media: [MediaAttachmentReference] = [],
        in context: ModelContext
    ) {
        let message = CoachMessage(
            sessionID: session.id,
            isFromCoach: false,
            text: "虚构训练",
            mediaAttachments: media,
            turnID: turnID
        )
        context.insert(message)
        let job = AgentJob(
            turnID: turnID,
            sessionID: session.id,
            userMessageID: message.id,
            dataSpace: .personal,
            state: jobState,
            userText: "虚构训练",
            mediaAttachments: media,
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "虚构上下文",
                includeLocation: false
            )
        )
        context.insert(job)
        context.insert(PersistentAgentEvent(
            jobID: job.id,
            turnID: turnID,
            sequence: 1,
            attemptNumber: 1,
            kind: .completed
        ))
        context.insert(AgentTrace(
            provider: "test",
            model: "test-model",
            endpoint: "https://example.invalid",
            dataSpaceRaw: DataSpace.personal.rawValue,
            userInput: "虚构训练",
            contextSnapshot: "虚构快照",
            mediaKind: .none,
            imageCount: 0,
            turnID: turnID
        ))
        context.insert(AgentMutationReceipt(
            turnID: turnID,
            signature: "create_workout|\(turnID.uuidString)",
            status: .committed
        ))
        context.insert(ConversationCompactionSummary(
            sessionID: session.id,
            summary: "虚构摘要",
            coveredTurnIDs: [turnID],
            strategy: .deterministic
        ))
    }

    @MainActor
    private func makeContext() throws -> (ModelContext, UserDefaults, String) {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let schema = Schema(SomaDataSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )]
        )
        return (ModelContext(container), defaults, suiteName)
    }
}

private struct SessionPair {
    var deleted: ConversationSession
    var kept: ConversationSession
    var deletedTurnID: UUID
    var keptTurnID: UUID
}

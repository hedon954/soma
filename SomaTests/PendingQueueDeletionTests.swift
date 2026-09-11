@testable import Soma
import SwiftData
import XCTest

@MainActor
final class PendingQueueDeletionTests: XCTestCase {
    func testRemoteCancellationFailureKeepsMessagesAndQueueBarrier() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanDefaults() }
        let head = try fixture.enqueue(state: .waitingForUser, remoteID: "synthetic-remote-job")
        let tail = try fixture.enqueue(state: .queued)
        var cancelled: [String] = []
        do {
            try await fixture.processor.discardPendingTurn(
                turnID: head.turnID, context: fixture.processingContext, locationService: LocationContextService()
            ) { id in
                XCTAssertTrue(fixture.processor.isProcessing)
                cancelled.append(id)
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Must retain the job until remote cancellation succeeds")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("检查网络"))
        }
        XCTAssertEqual(cancelled, ["synthetic-remote-job"])
        XCTAssertFalse(fixture.processor.isProcessing)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AgentJob>()).count, 2)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<CoachMessage>()).count, 4)
        XCTAssertEqual(head.state, .waitingForUser)
        XCTAssertEqual(tail.state, .queued)
    }

    func testDeletingRemoteHeadResumesNextDeterministicJob() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanDefaults() }
        let head = try fixture.enqueue(state: .waitingForUser, remoteID: "synthetic-remote-job")
        let next = try fixture.enqueue(state: .staged)
        let exercise = ExerciseDefinition(canonicalName: "虚构深蹲")
        fixture.context.insert(exercise)
        next.executionKind = .deterministicWorkout
        next.deterministicWorkoutDraft = ExerciseQuickRecordDraft(
            exerciseID: exercise.id, exerciseName: exercise.canonicalName,
            setEntries: [WorkoutSetEvidence(reps: 8, externalWeightKG: 20)],
            restSeconds: 60, durationMinutes: nil
        )
        try fixture.context.save()
        var cancelled: [String] = []
        try await fixture.processor.discardPendingTurn(
            turnID: head.turnID, context: fixture.processingContext, locationService: LocationContextService()
        ) { id in cancelled.append(id) }
        await fixture.processor.processingTask?.value
        XCTAssertEqual(cancelled, ["synthetic-remote-job"])
        XCTAssertEqual(next.state, .succeeded)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AgentJob>()).map(\.id), [next.id])
    }

    func testDeletingLaterMessageDoesNotRetryFailedHead() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanDefaults() }
        let head = try fixture.enqueue(state: .waitingForUser)
        let tail = try fixture.enqueue(state: .queued)
        try await fixture.processor.discardPendingTurn(
            turnID: tail.turnID, context: fixture.processingContext, locationService: LocationContextService()
        )
        XCTAssertEqual(head.state, .waitingForUser)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AgentJob>()).map(\.id), [head.id])
        XCTAssertFalse(fixture.processor.isProcessing)
    }

    func testMediaProtectedByOtherDataSpaceIsNotReclaimed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanDefaults() }
        let job = try fixture.enqueue(state: .staged)
        let path = try MediaStore.saveRestoredMedia(Data("synthetic other space".utf8), fileExtension: "bin")
        defer { MediaStore.removeStoredFile(at: path) }
        job.mediaAttachments = [.init(kind: .image, path: path)]
        try fixture.context.save()
        try PendingConversationDeletion.remove([job], in: fixture.context, protectedMediaPaths: [path])
        XCTAssertNotNil(MediaStore.url(at: path))
    }

    @MainActor
    private final class Fixture {
        let suite = "SomaTests.pending-delete.\(UUID().uuidString)"
        let defaults: UserDefaults
        let context: ModelContext
        let session = ConversationSession()
        let processor = ConversationProcessingService(backgroundLease: Lease())
        let ai: AIService
        var nextDate = Date(timeIntervalSince1970: 1_700_000_000)

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let schema = Schema(SomaDataSchema.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            context = ModelContext(container)
            context.insert(session)
            ai = AIService(defaults: defaults, apiKeyOverride: "")
            try context.save()
        }

        var processingContext: ConversationProcessingContext {
            .init(structuredContext: "", session: session, dataSpace: .personal, gyms: [], equipment: [], ai: ai, modelContext: context)
        }

        func cleanDefaults() {
            defaults.removePersistentDomain(forName: suite)
        }

        func enqueue(state: AgentJobState, remoteID: String? = nil) throws -> AgentJob {
            let turnID = UUID()
            let message = CoachMessage(date: nextDate, sessionID: session.id, isFromCoach: false, text: "虚构暂存消息", turnID: turnID)
            let job = AgentJob(
                turnID: turnID, sessionID: session.id, userMessageID: message.id, dataSpace: .personal,
                backend: remoteID == nil ? .local : .remote, state: state, userText: message.text,
                mediaAttachments: [], contextSnapshot: .init(structuredContext: "", includeLocation: false), createdAt: nextDate
            )
            job.remoteJobID = remoteID
            try ConversationTurnPersistence.enqueue(job, userMessage: message, in: context, at: nextDate)
            nextDate.addTimeInterval(1)
            return job
        }
    }

    @MainActor
    private final class Lease: BackgroundExecutionLease {
        var isActive = false
        func begin(expiration _: @escaping @MainActor () -> Void) {
            isActive = true
        }

        func end() {
            isActive = false
        }
    }
}

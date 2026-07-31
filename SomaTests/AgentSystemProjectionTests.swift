import Foundation
@testable import Soma
import SwiftData
import XCTest

final class AgentSystemProjectionTests: XCTestCase {
    func testActivityContentContainsOnlyGenericStatusFields() throws {
        let state = SomaAgentJobAttributes.ContentState(
            phaseRaw: "waitingForForeground",
            operationCount: 3,
            queuedCount: 1,
            sequence: 7,
            isStale: false
        )

        let data = try JSONEncoder().encode(state)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(state.phaseTitle, "等待返回 Soma")
        XCTAssertTrue(text.contains("waitingForForeground"))
        XCTAssertFalse(text.contains("深蹲"))
        XCTAssertFalse(text.contains("30kg"))
        XCTAssertFalse(text.contains("体重"))
        XCTAssertFalse(text.contains("media"))
    }

    @MainActor
    func testDisabledSystemSurfacesStillAdvanceIndependentCursors() async throws {
        let suite = "AgentSystemProjectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.personalContainer)
        let sessionID = UUID()
        let message = CoachMessage(
            sessionID: sessionID,
            isFromCoach: false,
            text: "虚构任务"
        )
        let job = AgentJob(
            turnID: UUID(),
            sessionID: sessionID,
            userMessageID: message.id,
            dataSpace: .personal,
            userText: "虚构任务",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "",
                includeLocation: false
            )
        )
        try AgentJobStore.enqueue(job, userMessage: message, in: context)
        let events = try context.fetch(
            FetchDescriptor<PersistentAgentEvent>()
        )

        await AgentSystemProjectionCoordinator().project(
            jobs: [job],
            events: events,
            defaults: defaults
        )

        XCTAssertEqual(
            job.liveActivityProjectionCursor,
            job.lastEventSequence
        )
        XCTAssertEqual(job.notificationProjectionCursor, 0)
        XCTAssertEqual(job.chatProjectionCursor, 0)
        XCTAssertEqual(job.traceProjectionCursor, 0)
    }

    @MainActor
    func testAgentTurnDeepLinkRoutesStableTurnID() throws {
        let turnID = UUID()
        let url = try XCTUnwrap(
            URL(string: "soma://agent/turn/\(turnID.uuidString)")
        )

        SomaCaptureRouter.shared.route(url)

        XCTAssertEqual(
            SomaCaptureRouter.shared.pendingAgentTurn?.turnID,
            turnID
        )
        if let route = SomaCaptureRouter.shared.pendingAgentTurn {
            SomaCaptureRouter.shared.clearAgentTurn(route.id)
        }
    }

    @MainActor
    func testActivityPushTokenIsRetainedUntilRemoteJobIDExists() {
        let coordinator = AgentSystemProjectionCoordinator()
        let jobID = UUID()

        coordinator.cachePushToken("0102abcd", jobID: jobID)

        XCTAssertEqual(
            coordinator.activityPushTokens[jobID],
            "0102abcd"
        )
    }
}

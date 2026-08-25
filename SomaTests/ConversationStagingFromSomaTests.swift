@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

final class ConversationStagingFromSomaTests: XCTestCase {
    @MainActor
    func testConversationProcessingStagesTurnWhenAPIKeyMissing() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.demoContainer)
        let session = ConversationSession()
        context.insert(session)
        let service = ConversationProcessingService()

        XCTAssertTrue(service.submit(
            text: "记录今天的训练",
            attachments: [],
            context: ConversationProcessingContext(
                structuredContext: "",
                session: session,
                dataSpace: .demo,
                gyms: [],
                equipment: [],
                ai: AIService(defaults: defaults, apiKeyOverride: ""),
                modelContext: context
            ),
            includeLocation: false,
            locationService: LocationContextService()
        ))
        XCTAssertFalse(service.isProcessing)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CoachMessage>()).count,
            1
        )
        let job = try XCTUnwrap(
            context.fetch(FetchDescriptor<AgentJob>()).first
        )
        XCTAssertEqual(job.state, .staged)
        XCTAssertEqual(
            AgentJobStore.stagedJobCount(dataSpace: .demo, in: context),
            1
        )
        // 暂存期间不产生 Trace，也就没有伪造的解析结果。
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<AgentTrace>()).isEmpty
        )
    }
}

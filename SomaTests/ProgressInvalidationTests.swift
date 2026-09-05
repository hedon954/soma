@testable import Soma
import SwiftData
import XCTest

@MainActor
final class ProgressInvalidationTests: XCTestCase {
    func testProfileChangesRefreshProgressButStreamingTextDoesNot() throws {
        let schema = Schema(SomaDataSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile()
        let message = CoachMessage(isFromCoach: true, text: "虚构正文")
        container.mainContext.insert(profile)
        container.mainContext.insert(message)
        try container.mainContext.save()
        let profileEvent = Notification(name: ModelContext.didSave, object: container.mainContext,
                                        userInfo: [ModelContext.NotificationKey.updatedIdentifiers.rawValue: [profile.persistentModelID]])
        let messageEvent = Notification(name: ModelContext.didSave, object: container.mainContext,
                                        userInfo: [ModelContext.NotificationKey.updatedIdentifiers.rawValue: [message.persistentModelID]])
        XCTAssertTrue(ModelContextSaveImpact.affectsInsights(profileEvent, in: container.mainContext))
        XCTAssertFalse(ModelContextSaveImpact.affectsInsights(messageEvent, in: container.mainContext))
    }
}

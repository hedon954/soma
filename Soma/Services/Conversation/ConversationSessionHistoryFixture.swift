import Foundation
import SwiftData

@MainActor
enum ConversationSessionHistoryFixture {
    static func seedIfRequested(in context: ModelContext) {
        guard AppTestRuntime.isRunning,
              ProcessInfo.processInfo.environment["SOMA_UI_SESSION_HISTORY_FIXTURE"] == "1"
        else { return }
        let now = Date.now
        for index in 1 ... 35 {
            let session = ConversationSession(
                startedAt: now.addingTimeInterval(Double(-index) * 86400),
                title: String(format: "虚构分页对话 %02d", index)
            )
            context.insert(session)
            context.insert(CoachMessage(sessionID: session.id, isFromCoach: false, text: "虚构分页验证消息"))
        }
        try? context.save()
    }
}

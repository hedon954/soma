import Foundation
import SwiftData

@MainActor
enum RecordCorrectionReceipt {
    static func record(_ summary: String, sessionID: UUID?, recordDate: Date, in context: ModelContext, now: Date = .now) throws {
        let session: ConversationSession
        if let sessionID, let existing = try context.fetch(FetchDescriptor<ConversationSession>(predicate: #Predicate { $0.id == sessionID })).first {
            session = existing
        } else {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: recordDate)
            guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return }
            var request = FetchDescriptor<ConversationSession>(
                predicate: #Predicate { ($0.businessDate ?? $0.startedAt) >= day && ($0.businessDate ?? $0.startedAt) < end },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                session = existing
            } else {
                session = ConversationSession(startedAt: day, updatedAt: now, businessDate: day)
                context.insert(session)
            }
        }

        let id = session.id
        var tail = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.sessionID == id },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        tail.fetchLimit = 1
        if let previous = try context.fetch(tail).first, previous.isManualCorrectionReceipt {
            previous.recordManualCorrection(summary)
        } else {
            let receipt = CoachMessage(date: now, sessionID: id, isFromCoach: true, text: "")
            receipt.recordManualCorrection(summary)
            context.insert(receipt)
        }
        session.touch(at: now)
    }
}

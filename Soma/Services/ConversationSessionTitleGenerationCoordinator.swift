import Foundation
import SwiftData

/// PRD 037 / ADR 0088：标题生成不阻塞主 Job，也不进入 Agent Tool 或聊天事件流。
@MainActor
final class SessionTitleGenerator {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func request(context: ConversationProcessingContext) {
        request(
            sessionID: context.session.id,
            ai: context.ai,
            modelContext: context.modelContext
        )
    }

    func request(
        sessionID: UUID,
        ai: AIService,
        modelContext: ModelContext
    ) {
        guard tasks[sessionID] == nil else { return }
        var sessionDescriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(sessionDescriptor).first,
              session.canGenerateTitle
        else {
            return
        }
        let messages = (
            try? modelContext.fetch(
                FetchDescriptor<CoachMessage>(
                    predicate: #Predicate { $0.sessionID == sessionID },
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        guard let input = ConversationSessionTitleService.firstSuccessfulInput(
            sessionID: sessionID,
            messages: messages
        ) else {
            return
        }

        tasks[sessionID] = Task { [weak self] in
            defer { self?.tasks[sessionID] = nil }
            guard let generated = await ConversationSessionTitleService.generate(
                input: input,
                ai: ai
            ), !Task.isCancelled
            else {
                return
            }
            guard let target = try? modelContext.fetch(sessionDescriptor).first else {
                return
            }
            let previousTitle = target.title
            let previousSourceRaw = target.titleSourceRaw
            guard target.applyGeneratedTitle(generated.title) else { return }
            do {
                try modelContext.save()
            } catch {
                target.title = previousTitle
                target.titleSourceRaw = previousSourceRaw
            }
        }
    }
}

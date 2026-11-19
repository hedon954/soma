import Foundation

@MainActor
extension ConversationProcessingService {
    func executeAgentTool(
        _ call: AgentToolCall,
        turnID: UUID,
        userMessage: CoachMessage,
        sourceDate: Date,
        mediaAttachments: [MediaAttachmentReference],
        preferredGymID: UUID?,
        context: ConversationProcessingContext
    ) async throws -> AgentToolResult {
        if call.name == .getDailyEnergy {
            do {
                return try await AgentDailyEnergyRead.load(in: context.modelContext.container)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .failure("进展日账暂时无法读取，可稍后重试。", code: "energy_unavailable")
            }
        }
        if call.name == .submitFeedback {
            return try await AgentMutationStore.executeAsync(
                call,
                turnID: turnID,
                in: context.modelContext
            ) {
                try await AgentFeedbackTool.submit(
                    id: turnID,
                    sourceText: userMessage.text,
                    mediaAttachments: mediaAttachments
                )
            }
        }

        return AgentMutationStore.execute(
            call,
            turnID: turnID,
            in: context.modelContext
        ) {
            ConversationRecorder.executeAgentTool(
                call,
                sourceText: userMessage.text,
                sourceDate: sourceDate,
                sourceSessionID: context.session.id,
                sourceTurnID: turnID,
                mediaKind: mediaAttachments.first?.kind ?? .none,
                mediaPath: mediaAttachments.first?.path,
                mediaAttachments: mediaAttachments,
                preferredGymID: preferredGymID,
                in: context.modelContext
            )
        }
    }
}

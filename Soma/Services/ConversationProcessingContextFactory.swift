import Foundation
import SwiftData

@MainActor
enum ConversationProcessingContextFactory {
    static func make(
        sessionID: UUID,
        dataSpace: DataSpace,
        ai: AIService,
        in context: ModelContext
    ) -> ConversationProcessingContext? {
        let sessions = (try? context.fetch(FetchDescriptor<ConversationSession>())) ?? []
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return nil
        }
        let gyms = (
            try? context.fetch(
                FetchDescriptor<GymProfile>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let equipment = (
            try? context.fetch(
                FetchDescriptor<GymEquipment>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        return ConversationProcessingContext(
            structuredContext: structuredContext(
                gyms: gyms,
                equipment: equipment,
                sessionID: session.id,
                in: context
            ),
            session: session,
            dataSpace: dataSpace,
            gyms: gyms,
            equipment: equipment,
            ai: ai,
            modelContext: context
        )
    }

    static func structuredContext(in context: ModelContext) -> String {
        let gyms = (
            try? context.fetch(
                FetchDescriptor<GymProfile>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let equipment = (
            try? context.fetch(
                FetchDescriptor<GymEquipment>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        return structuredContext(
            gyms: gyms,
            equipment: equipment,
            sessionID: nil,
            in: context
        )
    }

    private static func structuredContext(
        gyms: [GymProfile],
        equipment: [GymEquipment],
        sessionID: UUID?,
        in context: ModelContext
    ) -> String {
        AgentContextPackBuilder.build(
            gyms: gyms,
            equipment: equipment,
            in: context,
            sessionID: sessionID
        )
    }
}

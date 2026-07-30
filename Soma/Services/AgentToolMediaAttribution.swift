import Foundation

enum AgentToolMediaAttribution {
    static let recentGymTurn = "recent_gym_turn"

    static func attachments(
        for call: AgentToolCall,
        current: [MediaAttachmentReference],
        history: ConversationContextProjection
    ) -> [MediaAttachmentReference] {
        guard call.name == .updateGym else {
            return current
        }

        let currentImages = current.filter { $0.kind == .image }
        guard currentImages.isEmpty else {
            return currentImages
        }

        let explicitlyReferencesRecentGymTurn =
            call.arguments.mediaSource == recentGymTurn
        let carriesVisualEquipmentEvidence =
            call.arguments.equipment?.isEmpty == false
        guard explicitlyReferencesRecentGymTurn || carriesVisualEquipmentEvidence,
              let immediatelyPreviousExchange = history.exchanges.last
        else {
            return []
        }

        return immediatelyPreviousExchange.mediaAttachments.filter {
            $0.kind == .image
        }
    }
}

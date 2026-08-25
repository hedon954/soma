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

        guard call.arguments.mediaSource == recentGymTurn,
              let immediatelyPreviousExchange = history.exchanges.last
        else {
            return []
        }

        return immediatelyPreviousExchange.mediaAttachments.filter {
            $0.kind == .image
        }
    }
}

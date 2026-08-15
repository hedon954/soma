import Foundation
import SwiftData

@MainActor
extension ConversationRecorder {
    static func apply(
        _ result: ConversationResult,
        sourceText: String,
        sourceDate: Date = .now,
        sourceSessionID: UUID? = nil,
        sourceTurnID: UUID? = nil,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference] = [],
        gyms: [GymProfile],
        equipment: [GymEquipment],
        in context: ModelContext
    ) -> String {
        switch result.intent {
        case .gym:
            recordGym(
                result,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                gyms: gyms,
                equipment: equipment,
                in: context
            )
        case .meal:
            recordMeal(
                result,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .body:
            recordBody(
                result,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .workout:
            recordWorkout(
                result,
                sourceText: sourceText,
                sourceDate: sourceDate,
                sourceSessionID: sourceSessionID,
                sourceTurnID: sourceTurnID,
                mediaKind: mediaKind,
                mediaPath: mediaPath,
                mediaAttachments: mediaAttachments,
                in: context
            )
        case .switchGym:
            switchGym(result, gyms: gyms, in: context)
        case .coach:
            break
        }
        try? context.save()
        return result.reply
    }
}

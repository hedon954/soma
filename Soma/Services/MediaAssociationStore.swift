import SwiftData

@MainActor
enum MediaAssociationStore {
    @discardableResult
    static func detach(
        _ attachment: MediaAttachmentReference,
        from workout: WorkoutEntry,
        in context: ModelContext
    ) -> Bool {
        detach(attachment, from: &workout.mediaAttachments, in: context)
    }

    @discardableResult
    static func detach(
        _ attachment: MediaAttachmentReference,
        from meal: MealEntry,
        in context: ModelContext
    ) -> Bool {
        detach(attachment, from: &meal.mediaAttachments, in: context)
    }

    @discardableResult
    static func detach(
        _ attachment: MediaAttachmentReference,
        from body: BodyEntry,
        in context: ModelContext
    ) -> Bool {
        detach(attachment, from: &body.mediaAttachments, in: context)
    }

    @discardableResult
    static func detachGymPhoto(
        at path: String,
        from gym: GymProfile,
        equipment: [GymEquipment],
        media: [GymMedia],
        in context: ModelContext
    ) -> Bool {
        let matchingMedia = media.filter {
            $0.gymID == gym.id && $0.path == path
        }
        let matchingEquipment = equipment.filter {
            $0.gymID == gym.id && $0.imagePath == path
        }
        let isCover = gym.coverImagePath == path
        guard !matchingMedia.isEmpty || !matchingEquipment.isEmpty || isCover else {
            return false
        }

        matchingMedia.forEach(context.delete)
        let replacementPath = media
            .filter { $0.gymID == gym.id && $0.path != path }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .path
        if isCover {
            gym.coverImagePath = replacementPath
        }
        let equipmentReplacement = gym.coverImagePath ?? replacementPath
        matchingEquipment.forEach { $0.imagePath = equipmentReplacement }
        try? context.save()
        return true
    }

    private static func detach(
        _ attachment: MediaAttachmentReference,
        from attachments: inout [MediaAttachmentReference],
        in context: ModelContext
    ) -> Bool {
        let originalCount = attachments.count
        attachments.removeAll { $0.id == attachment.id }
        guard attachments.count != originalCount else {
            return false
        }
        try? context.save()
        return true
    }
}

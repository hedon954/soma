import Foundation

extension PersonalDataSnapshot {
    func contentFingerprint() throws -> String {
        var normalized = self
        normalized.createdAt = .distantPast
        normalized.externalSyncCursors.sort(by: stableIDSort)
        normalized.userProfiles.sort(by: stableIDSort)
        normalized.gymProfiles.sort(by: stableIDSort)
        normalized.gymEquipment.sort(by: stableIDSort)
        normalized.gymMedia.sort(by: stableIDSort)
        normalized.meals.sort(by: stableIDSort)
        normalized.bodyEntries.sort(by: stableIDSort)
        normalized.workouts.sort(by: stableIDSort)
        normalized.sessions.sort(by: stableIDSort)
        normalized.messages.sort(by: stableIDSort)
        normalized.traces.sort(by: stableIDSort)
        normalized.mutationReceipts.sort { $0.key < $1.key }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try DataBackupCrypto.sha256(encoder.encode(normalized))
    }
}

private func stableIDSort<T: StableArchiveIdentifiable>(
    _ lhs: T,
    _ rhs: T
) -> Bool {
    lhs.id.uuidString < rhs.id.uuidString
}

private protocol StableArchiveIdentifiable {
    var id: UUID { get }
}

extension ExternalSyncCursorDTO: StableArchiveIdentifiable {}
extension UserProfileDTO: StableArchiveIdentifiable {}
extension GymProfileDTO: StableArchiveIdentifiable {}
extension GymEquipmentDTO: StableArchiveIdentifiable {}
extension GymMediaDTO: StableArchiveIdentifiable {}
extension MealEntryDTO: StableArchiveIdentifiable {}
extension BodyEntryDTO: StableArchiveIdentifiable {}
extension WorkoutEntryDTO: StableArchiveIdentifiable {}
extension ConversationSessionDTO: StableArchiveIdentifiable {}
extension CoachMessageDTO: StableArchiveIdentifiable {}
extension AgentTraceDTO: StableArchiveIdentifiable {}

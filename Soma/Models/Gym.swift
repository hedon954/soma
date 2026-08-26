import Foundation
import SwiftData

@Model
final class GymProfile: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var name: String
    var createdAt: Date
    var notes: String
    var coverImagePath: String?
    var isCurrent: Bool = false
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?
    var locationAccuracy: Double?
    var locationUpdatedAt: Date?
    var matchRadiusMeters: Double = 180

    init(
        name: String,
        notes: String = "",
        coverImagePath: String? = nil,
        isCurrent: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationLabel: String? = nil,
        locationAccuracy: Double? = nil,
        locationUpdatedAt: Date? = nil,
        matchRadiusMeters: Double = 180
    ) {
        id = UUID()
        self.name = name
        createdAt = .now
        self.notes = notes
        self.coverImagePath = coverImagePath
        self.isCurrent = isCurrent
        self.latitude = latitude
        self.longitude = longitude
        self.locationLabel = locationLabel
        self.locationAccuracy = locationAccuracy
        self.locationUpdatedAt = locationUpdatedAt
        self.matchRadiusMeters = matchRadiusMeters
    }
}

enum GymSelection {
    static func current(in gyms: [GymProfile]) -> GymProfile? {
        gyms.first(where: \.isCurrent) ?? gyms.first
    }

    static func activate(_ target: GymProfile, among gyms: [GymProfile]) {
        gyms.forEach { $0.isCurrent = $0.id == target.id }
        target.isCurrent = true
    }

    static func ensureCurrent(in gyms: [GymProfile]) {
        guard !gyms.isEmpty, !gyms.contains(where: \.isCurrent), let first = gyms.first else { return }
        activate(first, among: gyms)
    }
}

@MainActor
enum StructuredDataStore {
    static func activateGym(
        _ gym: GymProfile,
        in context: ModelContext
    ) {
        let gyms = allGymsForMutation(in: context)
        GymSelection.activate(gym, among: gyms)
        try? context.save()
    }

    static func deleteGym(
        _ gym: GymProfile,
        in context: ModelContext
    ) {
        let gymID = gym.id
        let equipment = (try? context.fetch(FetchDescriptor<GymEquipment>(
            predicate: #Predicate { $0.gymID == gymID }
        ))) ?? []
        let media = (try? context.fetch(FetchDescriptor<GymMedia>(
            predicate: #Predicate { $0.gymID == gymID }
        ))) ?? []
        equipment.forEach(context.delete)
        media.forEach(context.delete)

        let gyms = allGymsForMutation(in: context)
        let remainingGyms = gyms.filter { $0.id != gym.id }
        context.delete(gym)
        if let nextGym = GymSelection.current(in: remainingGyms) {
            GymSelection.activate(nextGym, among: remainingGyms)
        }
        try? context.save()
    }

    private static func allGymsForMutation(in context: ModelContext) -> [GymProfile] {
        let descriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

@Model
final class GymEquipment: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var gymID: UUID
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double
    var imagePath: String?
    var createdAt: Date

    init(
        gymID: UUID,
        name: String,
        category: String,
        capabilities: String,
        confidence: Double = 0.9,
        imagePath: String? = nil
    ) {
        id = UUID()
        self.gymID = gymID
        self.name = name
        self.category = category
        self.capabilities = capabilities
        self.confidence = confidence
        self.imagePath = imagePath
        createdAt = .now
    }
}

@Model
final class GymMedia {
    var id: UUID
    var gymID: UUID
    var path: String
    var createdAt: Date

    init(gymID: UUID, path: String, createdAt: Date = .now) {
        id = UUID()
        self.gymID = gymID
        self.path = path
        self.createdAt = createdAt
    }
}

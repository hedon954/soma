import Foundation

struct EnergyTrainingAssociation: Codable, Equatable, Sendable {
    let localID: String
    let healthID: String
}

struct EnergyTrainingAssociations: Codable, Equatable, Sendable {
    let date: Date
    let timeZoneIdentifier: String
    var links: [EnergyTrainingAssociation]

    func applying(to events: [EnergyTrainingEvent]) -> [EnergyTrainingEvent] {
        let identifiers = Set(events.map(\.id))
        return events.map { event in
            var result = event
            // A missing member never causes the remaining actions to collapse into one record.
            if let link = links.first(where: { $0.localID == event.id && identifiers.contains($0.healthID) }) {
                result.linkedIdentity = link.healthID
            }
            return result
        }
    }
}

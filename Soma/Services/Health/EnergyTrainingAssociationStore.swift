import Foundation
import SwiftData

@MainActor
enum EnergyTrainingAssociationStore {
    static func load(on date: Date, in context: ModelContext, calendar: Calendar = .current) throws -> EnergyTrainingAssociations {
        let day = calendar.startOfDay(for: date)
        var query = FetchDescriptor<EnergyEvidenceEntry>(predicate: #Predicate { $0.kindRaw == "association" && $0.date == day },
                                                         sortBy: [SortDescriptor(\.revision, order: .reverse)])
        query.fetchLimit = 1
        if let row = try context.fetch(query).first {
            let value = try JSONDecoder().decode(EnergyTrainingAssociations.self, from: row.payload)
            if value.timeZoneIdentifier == calendar.timeZone.identifier {
                return value
            }
        }
        return .init(date: day, timeZoneIdentifier: calendar.timeZone.identifier, links: [])
    }

    @discardableResult
    static func set(localID: String, healthID: String?, on date: Date, in context: ModelContext,
                    calendar: Calendar = .current) throws -> EnergyTrainingAssociations
    {
        guard localID.hasPrefix("soma:") || localID.hasPrefix("soma-session:"),
              healthID == nil || healthID?.hasPrefix("health:") == true else { throw EnergyCalculationError.invalidInput }
        var value = try load(on: date, in: context, calendar: calendar)
        value.links.removeAll { $0.localID == localID }
        if let healthID {
            guard !value.links.contains(where: { $0.healthID == healthID }) else { throw EnergyCalculationError.invalidInput }
            value.links.append(.init(localID: localID, healthID: healthID))
        }
        value.links.sort { $0.localID < $1.localID }
        try EnergyEvidenceStore.append(value, kind: .association, date: value.date,
                                       reason: healthID == nil ? "本人解除同场训练关联" : "本人确认 Soma 与健康记录属于同一场训练",
                                       in: context)
        return value
    }
}

import Foundation
import SwiftData

enum EnergyLifestyleError: LocalizedError {
    case invalidFactor
    case futureDate

    var errorDescription: String? {
        switch self {
        case .invalidFactor: "活动系数请输入 1 到 4 之间的数值。"
        case .futureDate: "生效日期不能晚于今天。"
        }
    }
}

enum EnergyLifestyleStorage {
    static func decode(_ data: Data?) throws -> [EnergyLifestyleBaseline] {
        guard let data else { return [] }
        return try JSONDecoder().decode([EnergyLifestyleBaseline].self, from: data)
    }
}

@MainActor
enum EnergyLifestyleStore {
    /// A new dated setting is explicit user input, not a reconstructed historic activity fact.
    static func save(
        factor: Double, label: String, effectiveFrom: Date,
        in context: ModelContext, now: Date = .now, calendar: Calendar = .current
    ) throws {
        guard factor.isFinite, (1 ... 4).contains(factor) else { throw EnergyLifestyleError.invalidFactor }
        let day = calendar.startOfDay(for: effectiveFrom)
        guard day <= calendar.startOfDay(for: now) else { throw EnergyLifestyleError.futureDate }
        var descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        let profile = existing ?? UserProfile()
        var values = try EnergyLifestyleStorage.decode(profile.energyBaselinesData)
        values.removeAll { calendar.isDate($0.effectiveFrom, inSameDayAs: day) }
        values.append(.init(effectiveFrom: day, factor: factor, label: label))
        let data = try JSONEncoder().encode(values.sorted { $0.effectiveFrom < $1.effectiveFrom })
        if existing == nil {
            context.insert(profile)
        }
        profile.energyBaselinesData = data
        profile.updatedAt = now
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

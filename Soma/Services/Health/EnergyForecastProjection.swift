import Foundation

enum EnergyForecastProjection {
    static func upcoming(calculations: [Date: EnergyDayCalculation], plans: [EnergyPlannedTrainingDay],
                         on date: Date, calendar: Calendar) -> [EnergyForecast]
    {
        let today = calendar.startOfDay(for: date)
        guard let latest = calculations[today] else { return [] }
        return (1 ... 7).compactMap { offset in
            guard let future = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let delta: Double?, source: String, evidence: [Date]
            if let plan = plans.first(where: { $0.date == future }) {
                if let events = plan.eventsPerKilogram {
                    let values = events.compactMap { event -> Double? in
                        guard let net = event.netEnergy(resting: latest.input.resting / latest.input.weightKG),
                              let hours = event.durationHours, hours.isFinite, hours > 0 else { return nil }
                        return max(0, net * latest.input.weightKG - latest.displacedActivityPerHour * hours)
                    }
                    delta = values.count == events.count ? values.reduce(0, +) : nil
                } else {
                    delta = nil
                }
                source = plan.source + (delta == nil ? " · 目标或时长待补充" : " · 按计划估算")
                evidence = []
            } else {
                let samples = (1 ... 4).compactMap { week -> EnergyDayCalculation? in
                    guard let prior = calendar.date(byAdding: .day, value: -7 * week, to: future), prior < today,
                          let value = calculations[prior], value.canCalibrate else { return nil }
                    return value
                }
                delta = samples.count >= 3 ? samples.reduce(0) { $0 + $1.trainingDelta } / Double(samples.count) : nil
                source = delta == nil ? "同星期训练记录不足" : "近四周同星期的已完成训练"
                evidence = samples.map(\.input.date).sorted()
            }
            return .init(date: future, total: delta.map { latest.baseline + latest.input.correction + $0 },
                         trainingDelta: delta, source: source, evidenceDates: evidence)
        }
    }
}

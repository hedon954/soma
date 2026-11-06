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
                        event.netEnergy(resting: latest.input.resting / latest.input.weightKG)
                            .map { $0 * latest.input.weightKG }
                    }
                    delta = values.count == events.count ? values.reduce(0, +) : nil
                } else {
                    delta = nil
                }
                source = plan.source + (delta == nil ? " · 目标或能量待补充" : " · 按计划估算")
                evidence = []
            } else {
                let samples = (1 ... 4).compactMap { week -> EnergyDayCalculation? in
                    guard let prior = calendar.date(byAdding: .day, value: -7 * week, to: future), prior < today,
                          let value = calculations[prior], value.canCalibrate else { return nil }
                    return value
                }
                delta = samples.count >= 3 ? samples.reduce(0.0) { $0 + adoptedNet($1) } / Double(samples.count) : nil
                source = delta == nil ? "同星期训练记录不足" : "近四周同星期的已完成训练"
                evidence = samples.map(\.input.date).sorted()
            }
            let coefficient = ResidualEnergyCoefficient.current()
            return .init(date: future, total: delta.map { latest.input.resting * coefficient.value + $0 },
                         trainingDelta: delta, source: source, evidenceDates: evidence)
        }
    }

    /// 已采用训练的活动能量，不按被替代时段扣减。
    private static func adoptedNet(_ calculation: EnergyDayCalculation) -> Double {
        let adopted = Set(calculation.adoptedTrainingIDs)
        return calculation.input.training.filter { adopted.contains($0.id) }
            .compactMap { $0.netEnergy(resting: calculation.input.resting) }
            .reduce(0, +)
    }
}

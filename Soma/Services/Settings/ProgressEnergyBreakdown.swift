import Foundation

struct ProgressEnergyBreakdown: Equatable, Sendable {
    enum Kind: String, Sendable {
        case intake, expenditure
    }

    enum Tone: Equatable, Sendable {
        case meal, resting, activity, factor, total, intakeTotal
        case mealType(MealType)
    }

    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let value: String
        let tone: Tone
    }

    let rows: [Row]

    init(snapshot: ProgressHistorySnapshot, kind: Kind) {
        // The summary excludes unfinished days outside day mode, exactly like the dashboard.
        let daily = snapshot.window.period == .day
        let days = snapshot.days.filter { daily ? !$0.isFuture : $0.isCompleteDay }
        switch kind {
        case .intake:
            var items: [Row] = []
            if daily, let day = days.first {
                items = day.records.filter { $0.activity.kind == .meal }.map { record in
                    let calories = record.calories.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                    let mealType = MealType(rawValue: record.activity.detail)
                    return Row(
                        id: record.activity.id.uuidString,
                        label: (mealType?.rawValue ?? "餐次未记录") + " · " + record.activity.title,
                        value: calories.map(Self.energy) ?? "未估算",
                        tone: mealType.map(Tone.mealType) ?? .meal
                    )
                }
            } else {
                items = days.filter { $0.intake.knownCount > 0 }.map { day in
                    Row(
                        id: "day-\(day.date.timeIntervalSinceReferenceDate)", label: day.date.formatted(.dateTime.month().day()),
                        value: Self.energy(day.intake.value), tone: .meal
                    )
                }
            }
            items.append(Row(
                id: "summary", label: daily ? "已记录摄入" : "日均摄入",
                value: Self.energy(daily ? days.first?.intake.value ?? 0 : snapshot.averageIntake ?? 0), tone: .intakeTotal
            ))
            rows = items
        case .expenditure:
            let estimates = days.compactMap(\.energy.estimate)
            guard !estimates.isEmpty else {
                rows = [Row(id: "missing", label: "预估总消耗", value: "缺少静息资料", tone: .total)]
                return
            }
            let count = Double(estimates.count)
            let resting = estimates.reduce(0) { $0 + $1.restingKilocalories } / count
            let total = estimates.reduce(0) { $0 + $1.totalKilocalories } / count
            let prefix = daily ? "" : "日均"
            rows = [
                Row(id: "resting", label: prefix + "静息消耗", value: Self.energy(resting), tone: .resting),
                Row(id: "activity", label: prefix + "活动等消耗", value: Self.energy(total - resting), tone: .activity),
                Row(
                    id: "factor", label: daily ? "活动系数" : "综合活动系数",
                    value: (total / resting).formatted(.number.precision(.fractionLength(2))), tone: .factor
                ),
                Row(id: "summary", label: prefix + "预估总消耗", value: Self.energy(total), tone: .total)
            ]
        }
    }

    private static func energy(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " kcal"
    }
}

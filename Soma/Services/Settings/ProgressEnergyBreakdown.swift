import Foundation

struct ProgressEnergyBreakdown: Equatable, Sendable {
    enum Kind: String, Sendable {
        case intake, expenditure, protein, carbs, fat
    }

    enum Tone: Equatable, Sendable {
        case meal, resting, activity, factor, total, intakeTotal, workout
        case mealType(MealType)
        case protein, carbs, fat
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
                items = day.records.filter { $0.activity.kind == .meal }.compactMap { record in
                    let calories = record.calories.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                    guard !Self.isDisplayedZero(calories) else { return nil }
                    let mealType = MealType(rawValue: record.activity.detail)
                    return Row(
                        id: record.activity.id.uuidString,
                        label: (mealType?.rawValue ?? "餐次未记录") + " · " + record.activity.title,
                        value: calories.map(Self.energy) ?? "未估算",
                        tone: mealType.map(Tone.mealType) ?? .meal
                    )
                }
            } else {
                items = days.filter { $0.intake.knownCount > 0 && !Self.isDisplayedZero($0.intake.value) }.map { day in
                    Row(
                        id: "day-\(day.date.timeIntervalSinceReferenceDate)", label: day.date.formatted(.dateTime.month().day()),
                        value: Self.energy(day.intake.value), tone: .meal
                    )
                }
            }
            rows = items
        case .expenditure:
            rows = daily ? Self.dayExpenditureRows(days.first) : Self.periodExpenditureRows(days: days)
        case .protein:
            rows = Self.nutrientRows(
                days: days,
                daily: daily,
                grams: \.protein,
                dayTotal: \.protein,
                tone: .protein
            )
        case .carbs:
            rows = Self.nutrientRows(
                days: days,
                daily: daily,
                grams: \.carbs,
                dayTotal: \.carbs,
                tone: .carbs
            )
        case .fat:
            rows = Self.nutrientRows(
                days: days,
                daily: daily,
                grams: \.fat,
                dayTotal: \.fat,
                tone: .fat
            )
        }
    }

    static func dayExpenditureRows(_ day: ProgressDailyMetrics?) -> [Row] {
        guard let day else { return [missingExpenditure] }
        guard let components = day.energy.estimate?.components else { return [missingExpenditure] + workoutRows(in: day) }
        let displayed = EnergyKilocalorieDisplay.parts(components)
        return breakdownRows(displayed, prefix: "") + workoutRows(in: day, includesTraining: components.trainingKilocalories > 0)
    }

    private static let missingExpenditure = Row(id: "missing", label: "预估总消耗", value: "缺少静息资料", tone: .total)

    private static func periodExpenditureRows(days: [ProgressDailyMetrics]) -> [Row] {
        let estimates = days.compactMap(\.energy.estimate)
        let components = estimates.compactMap(\.components)
        guard !components.isEmpty, components.count == estimates.count else { return [missingExpenditure] }
        let displayed = EnergyKilocalorieDisplay.averaged(components)
        var rows = breakdownRows(displayed, prefix: "日均")
        if displayed.training != 0 {
            rows.append(Row(id: "training", label: "日均训练消耗", value: EnergyKilocalorieDisplay.kcal(displayed.training), tone: .workout))
        }
        return rows
    }

    private static func breakdownRows(_ displayed: EnergyKilocalorieDisplay.Parts, prefix: String) -> [Row] {
        let components: [(id: String, label: String, value: Int, tone: Tone)] = [
            ("resting", "静息消耗", displayed.resting, .resting),
            ("baseline-extra", "基准额外消耗", displayed.baselineExtra, .factor)
        ]
        let rows = components.filter { $0.value != 0 }.map {
            Row(id: $0.id, label: prefix + $0.label, value: EnergyKilocalorieDisplay.kcal($0.value), tone: $0.tone)
        }
        return rows + activityRows(displayed.activity, prefix: prefix)
    }

    private static func activityRows(_ activity: DailyEnergyTotal.Activity, prefix: String) -> [Row] {
        switch activity {
        case .absent:
            [Row(id: "activity", label: prefix + "活动消耗", value: "未记录", tone: .activity)]
        case .selected(0):
            []
        case let .selected(value):
            [Row(id: "activity", label: prefix + "活动消耗", value: energy(value), tone: .activity)]
        }
    }

    private static func workoutRows(in day: ProgressDailyMetrics, includesTraining: Bool = true) -> [Row] {
        DailyEnergyTotal.listTrainingContributions(in: day.records).compactMap { record, calories in
            guard !isDisplayedZero(calories) else { return nil }
            let title = record.activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(
                id: record.activity.id.uuidString,
                label: title.isEmpty ? "训练记录" : title,
                value: calories.map { includesTraining ? energy($0) : "未计入" } ?? "未估算",
                tone: .workout
            )
        }
    }

    private static func nutrientRows(
        days: [ProgressDailyMetrics],
        daily: Bool,
        grams: (ProgressHistoryRecord) -> Double?,
        dayTotal: (ProgressDailyMetrics) -> ProgressRecordedTotal,
        tone: Tone
    ) -> [Row] {
        if daily, let day = days.first {
            return day.records.filter { $0.activity.kind == .meal }.compactMap { record in
                let mealType = MealType(rawValue: record.activity.detail)
                let value = grams(record).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                guard !isDisplayedZero(value) else { return nil }
                return Row(
                    id: record.activity.id.uuidString,
                    label: (mealType?.rawValue ?? "餐次未记录") + " · " + record.activity.title,
                    value: value.map(gramsText) ?? "未记录",
                    tone: tone
                )
            }
        }
        return days.filter { dayTotal($0).knownCount > 0 && !isDisplayedZero(dayTotal($0).value) }.map { day in
            Row(
                id: "day-\(day.date.timeIntervalSinceReferenceDate)",
                label: day.date.formatted(.dateTime.month().day()),
                value: gramsText(dayTotal(day).value),
                tone: tone
            )
        }
    }

    private static func isDisplayedZero(_ value: Double?) -> Bool {
        value?.rounded() == 0
    }

    private static func energy(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0))) + " kcal"
    }

    private static func gramsText(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0))) + " g"
    }
}

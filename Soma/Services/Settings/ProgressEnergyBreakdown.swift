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
            rows = items
        case .expenditure:
            rows = Self.expenditureRows(days: days, daily: daily)
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

    private static func expenditureRows(days: [ProgressDailyMetrics], daily: Bool) -> [Row] {
        let estimates = days.compactMap(\.energy.estimate)
        guard !estimates.isEmpty, estimates.allSatisfy({ $0.components != nil }) else {
            var items = [Row(id: "missing", label: "预估总消耗", value: "缺少静息资料", tone: .total)]
            if daily, let day = days.first {
                items.append(contentsOf: workoutRows(in: day))
            }
            return items
        }
        let components = estimates.compactMap(\.components)
        let displayed: EnergyKilocalorieDisplay.Parts
        if daily {
            guard let day = components.first else {
                return [Row(id: "missing", label: "预估总消耗", value: "缺少静息资料", tone: .total)]
            }
            displayed = EnergyKilocalorieDisplay.parts(day)
        } else {
            displayed = EnergyKilocalorieDisplay.averaged(components)
        }
        let prefix = daily ? "" : "日均"
        return [
            Row(id: "resting", label: prefix + "静息消耗", value: EnergyKilocalorieDisplay.kcal(displayed.resting), tone: .resting),
            Row(id: "baseline-extra", label: prefix + "基准额外消耗", value: EnergyKilocalorieDisplay.kcal(displayed.baselineExtra), tone: .factor)
        ] + activityRows(displayed.activity, prefix: prefix)
    }

    private static func activityRows(_ activity: DailyEnergyTotal.Activity, prefix: String) -> [Row] {
        switch activity {
        case .absent:
            [Row(id: "activity", label: prefix + "活动消耗", value: "未记录", tone: .activity)]
        case let .selected(value), let .recordedTraining(value):
            [Row(id: "activity", label: prefix + "活动消耗", value: energy(value), tone: .activity)]
        case let .disaggregated(training, remaining):
            [
                Row(id: "activity-training", label: prefix + "训练活动消耗", value: energy(training), tone: .workout),
                Row(id: "activity-remaining", label: prefix + "其余活动消耗", value: energy(remaining), tone: .activity)
            ]
        }
    }

    private static func workoutRows(in day: ProgressDailyMetrics) -> [Row] {
        day.records.filter { $0.activity.kind == .workout }.map { record in
            let calories = record.calories.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let title = record.activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(
                id: record.activity.id.uuidString,
                label: title.isEmpty ? "训练记录" : title,
                value: calories.map(energy) ?? "未估算",
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
            return day.records.filter { $0.activity.kind == .meal }.map { record in
                let mealType = MealType(rawValue: record.activity.detail)
                let value = grams(record).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                return Row(
                    id: record.activity.id.uuidString,
                    label: (mealType?.rawValue ?? "餐次未记录") + " · " + record.activity.title,
                    value: value.map(gramsText) ?? "未记录",
                    tone: tone
                )
            }
        }
        return days.filter { dayTotal($0).knownCount > 0 }.map { day in
            Row(
                id: "day-\(day.date.timeIntervalSinceReferenceDate)",
                label: day.date.formatted(.dateTime.month().day()),
                value: gramsText(dayTotal(day).value),
                tone: tone
            )
        }
    }

    private static func energy(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " kcal"
    }

    private static func gramsText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " g"
    }
}

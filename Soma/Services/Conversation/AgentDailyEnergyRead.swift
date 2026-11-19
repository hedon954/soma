import Foundation
import SwiftData

/// Maps the shared progress snapshot to the model wire format. All amounts and labels come from progress.
enum AgentDailyEnergyRead {
    static func load(in container: ModelContainer, now: Date = .now, calendar: Calendar = .current) async throws -> AgentToolResult {
        let window = ProgressPeriod.day.window(containing: now, calendar: calendar)
        let reading = try await ProgressHistoryLoader.snapshot(in: container, window: window, now: now, calendar: calendar)
        return result(from: reading.snapshot, targetDeficit: reading.targetDeficit, at: now, calendar: calendar)
    }

    static func result(from snapshot: ProgressHistorySnapshot, targetDeficit: Double?, at now: Date, calendar: Calendar) -> AgentToolResult {
        guard let day = snapshot.days.first else {
            return .failure("当天的进展日账暂时无法读取。", code: "energy_unavailable")
        }
        let deficit = ProgressEnergyDeficit.make(snapshot: snapshot)
        let rings = snapshot.nutritionRings
        let configuredDeficit = snapshot.fitnessGoal?.supportsCalorieDeficit == true ? DailyTargetDeficit.resolve(targetDeficit) : nil
        let date = calendar.dateComponents([.year, .month, .day], from: day.date)
        return .success("这是本次调用时进展页的当日日账。使用返回的额度和状态，缺项保持为缺项。", data: .object([
            "date": .string(String(format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)),
            "time_zone": .string(calendar.timeZone.identifier),
            "read_at": .string(now.ISO8601Format()),
            "recorded_intake_kcal": kilocalories(day.intake.value),
            "estimated_total_expenditure_kcal": kilocalories(snapshot.averageEstimate),
            "target_deficit_kcal": number(configuredDeficit),
            "recommended_intake_kcal": kilocalories(rings?.calories.target),
            "remaining_intake_kcal": kilocalories(deficit?.remainingIntakeKilocalories),
            "energy_difference_kcal": kilocalories(deficit?.kilocalories),
            "energy_difference_label": deficit.map { .string($0.metricLabel) } ?? .null,
            "food_coverage_confirmed": .bool(day.foodConfirmedComplete),
            "missing_intake_count": .number(Double(day.intake.missingCount)),
            "missing_reason": day.energyDeficitMissingReason.map(AgentJSONValue.string) ?? .null,
            "intake": rows(snapshot, .intake),
            "expenditure": rows(snapshot, .expenditure),
            "protein": nutrient(day.protein.value, target: rings?.protein.target, snapshot: snapshot, kind: .protein),
            "carbs": nutrient(day.carbs.value, target: rings?.carbs.target, snapshot: snapshot, kind: .carbs),
            "fat": nutrient(day.fat.value, target: rings?.fat.target, snapshot: snapshot, kind: .fat)
        ]))
    }

    private static func rows(_ snapshot: ProgressHistorySnapshot, _ kind: ProgressEnergyBreakdown.Kind) -> AgentJSONValue {
        .array(ProgressEnergyBreakdown(snapshot: snapshot, kind: kind).rows.map { row in
            .object(["label": .string(row.label), "display": .string(row.value)])
        })
    }

    private static func nutrient(_ grams: Double, target: Double?, snapshot: ProgressHistorySnapshot, kind: ProgressEnergyBreakdown.Kind) -> AgentJSONValue {
        .object(["recorded_grams": number(grams.rounded()), "target_grams": number(target?.rounded()), "items": rows(snapshot, kind)])
    }

    private static func kilocalories(_ value: Double?) -> AgentJSONValue {
        guard let value, value >= Double(Int.min), value < Double(Int.max) else { return .null }
        return .number(Double(EnergyKilocalorieDisplay.whole(value)))
    }

    private static func number(_ value: Double?) -> AgentJSONValue {
        guard let value, value.isFinite else { return .null }
        return .number(value)
    }
}

import Foundation
import SwiftData

/// A read-only response rendered on-device. Its values are never persisted in the chat transcript.
enum DeviceCoachRead: String, Sendable {
    case dailyEnergy, trainingSummary

    var prompt: String {
        switch self {
        case .dailyEnergy: "帮我看看今天还能摄入多少热量"
        case .trainingSummary: "帮我总结今天这次训练"
        }
    }

    static func matching(_ text: String) -> Self? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "？?。"))
        let remainingEnergy = #"^(?:帮我(?:看一下|看看|查一下))?我?今天我?还(?:能(?:吃|摄入)|可以(?:吃|摄入)|有|剩)多少(?:的)?(?:热量|卡路里|千卡|大卡|卡)(?:额度)?[呢啊呀吗]?$"#
        if query.range(of: remainingEnergy, options: .regularExpression) != nil {
            return .dailyEnergy
        }
        return switch query {
        case "我今天摄入和消耗了多少热量", "帮我看看今天的热量缺口": .dailyEnergy
        case Self.trainingSummary.prompt, "帮我总结今天的训练", "总结一下今天的训练": .trainingSummary
        default: nil
        }
    }

    func load(day: Date, container: ModelContainer) async throws -> DeviceCoachReadResult {
        let calendar = Calendar.current
        let window = ProgressPeriod.day.window(containing: day, calendar: calendar)
        let reading = try await ProgressHistoryLoader.snapshot(in: container, window: window, now: .now, calendar: calendar)
        return result(from: reading.snapshot, targetDeficit: reading.targetDeficit)
    }

    private func result(from snapshot: ProgressHistorySnapshot, targetDeficit: Double?) -> DeviceCoachReadResult {
        switch self {
        case .dailyEnergy:
            let day = snapshot.days.first
            let nutrition = snapshot.nutritionRings?.calories
            let remaining = ProgressEnergyDeficit.make(snapshot: snapshot)?.remainingIntakeKilocalories
            let hasIntake = day.map { $0.intake.knownCount > 0 || $0.allMealsExplicitlySkipped } ?? false
            let complete = day.map { $0.foodConfirmedComplete && $0.intake.missingCount == 0 } ?? false
            let headline: String
            if hasIntake, let remaining {
                let evidence = complete ? "" : "按已记饮食估算，"
                headline = evidence + "仍可摄入 \(EnergyKilocalorieDisplay.text(remaining)) kcal"
            } else {
                headline = day?.energy.missingReason ?? "当前记录还不足以确定剩余摄入。"
            }
            var detail: [String] = []
            if let target = nutrition?.target {
                detail.append("今日摄入目标 \(EnergyKilocalorieDisplay.text(target)) kcal")
            }
            if snapshot.fitnessGoal?.supportsCalorieDeficit == true {
                let target = DailyTargetDeficit.resolve(targetDeficit).formatted(.number.precision(.fractionLength(0 ... 1)))
                detail.append("目标热量缺口 \(target) kcal")
            }
            if let difference = day?.recordedEnergyDifference {
                let label = complete ? "预估热量缺口" : "已记饮食差额"
                detail.append("\(label) \(EnergyKilocalorieDisplay.text(difference)) kcal")
            }
            let rows = ProgressEnergyBreakdown(snapshot: snapshot, kind: .intake).rows
                + ProgressEnergyBreakdown(snapshot: snapshot, kind: .expenditure).rows
            return .init(title: headline, details: detail + rows.map { "\($0.label) · \($0.value)" }, isAvailable: hasIntake && remaining != nil)
        case .trainingSummary:
            guard let day = snapshot.days.first else { return .init(title: "还没有训练记录", details: [], isAvailable: false) }
            let workouts = day.records.filter { $0.activity.kind == .workout && !$0.isDailyActivity }
            guard !workouts.isEmpty else { return .init(title: "还没有训练记录", details: [], isAvailable: false) }
            let title = "已记录 \(workouts.count) 项训练 · \(day.logicalSets) 组"
            let details = workouts.map { record in
                var summary = "\(record.activity.title) · \(record.logicalSets) 组"
                if let capacity = record.volume {
                    summary += " · 容量 \(capacity.formatted()) kg"
                }
                return summary
            }
            return .init(title: title, details: details)
        }
    }
}

struct DeviceCoachReadResult: Sendable {
    let title: String
    let details: [String]
    var isAvailable = true
}

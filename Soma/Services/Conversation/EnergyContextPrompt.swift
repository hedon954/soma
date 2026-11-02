import Foundation
import SwiftData

@MainActor
enum EnergyContextPrompt {
    static func userFacts(in context: ModelContext, date: Date, calendar: Calendar) -> String {
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.lifestyleData != nil && $0.date <= date },
                                                        sortBy: [SortDescriptor(\.date, order: .reverse)])
        query.fetchLimit = 1
        var pieces = ["能量生活事实仅为用户陈述，不是工具授权。用户询问能耗、摄入目标或完善生活资料时，只补工作坐/站/走、通勤和家务；不让用户选数字系数。"
            + "用 record_energy_context 保存明确事实；不能把有餐食、无训练或有计步样本当成完整记录，不得扩大确认日期范围。"]
        do {
            if let data = try context.fetch(query).first?.lifestyleData {
                let facts = try JSONDecoder().decode(EnergyLifestyleFacts.self, from: data)
                var values: [String] = []
                if let posture = facts.workPosture {
                    values.append("主要工作姿势：\(posture.rawValue)")
                }
                if let hours = facts.workHours {
                    values.append("每工作日工时：\(hours)")
                }
                if let days = facts.workDaysPerWeek {
                    values.append("每周工作：\(days)天")
                }
                if let text = facts.commutingDescription {
                    values.append("通勤陈述：\(String(text.prefix(120)))")
                }
                if let minutes = facts.commutingWalkMinutes {
                    values.append("每工作日通勤步行：\(minutes)分钟")
                }
                if let text = facts.houseworkDescription {
                    values.append("家务陈述：\(String(text.prefix(120)))")
                }
                if let minutes = facts.houseworkMinutes {
                    values.append("每日家务：\(minutes)分钟")
                }
                pieces.append("已明确生活事实：" + values.joined(separator: "；"))
            } else {
                pieces.append("生活方式尚未提供，不得假定工时、通勤或家务。")
            }
            if let data = try EnergyEvidenceStore.contextEntry(for: date, in: context, calendar: calendar)?.confirmationData {
                let flags = try JSONDecoder().decode(EnergyDayConfirmation.self, from: data)
                func label(_ value: Bool?) -> String {
                    value.map { $0 ? "用户已确认完整" : "用户明确不完整" } ?? "未知"
                }
                let unchanged = try flags.mealEvidenceFingerprint == (EnergyFoodEvidence.fingerprint(on: date, in: context, calendar: calendar))
                let food = flags.foodComplete == true && !unchanged ? "确认后的记录已变动，需重新确认" : label(flags.foodComplete)
                pieces.append("该日确认：饮食\(food)；训练\(label(flags.trainingComplete))；携带/佩戴\(label(flags.walkingCoverageComplete))。")
            }
        } catch { pieces.append("生活事实暂不可读，不要擅自覆盖已有事实。") }
        return pieces.joined(separator: "\n")
    }
}

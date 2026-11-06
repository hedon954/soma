import Foundation
import SwiftData

@MainActor
enum EnergyRuntimePersistence {
    static func apply(_ updates: [EnergyHistoryUpdate], in context: ModelContext, now: Date = .now) throws {
        do {
            for update in updates {
                switch update {
                case let .reference(reference):
                    try EnergyEvidenceStore.append(reference, kind: .reference, date: reference.effectiveFrom,
                                                   reason: reference.reason, in: context, now: now, saveImmediately: false)
                case let .daily(calculation):
                    let explanation = calculation.presentedTotal == nil
                        ? "生活参考、非训练步行差额、去重训练与长期修正共同计算"
                        : "静息 × 残差系数 + 所选日活动能量"
                    try EnergyEvidenceStore.append(calculation, kind: .daily, date: calculation.input.date,
                                                   reason: explanation, in: context, now: now, saveImmediately: false)
                case let .calibration(review):
                    try EnergyEvidenceStore.append(review, kind: .calibration, date: review.date,
                                                   reason: review.reason, in: context, now: now, saveImmediately: false)
                }
            }
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}

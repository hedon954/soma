import Foundation

struct TemplateVersionChangeLog: Equatable, Identifiable, Sendable {
    var id: String {
        summary + "\n" + details
    }

    var summary: String
    var details: String

    static let initial = TemplateVersionChangeLog(
        summary: "初始版本",
        details: "创建训练模板的第一版。"
    )
}

enum TemplateVersionDiff {
    static func changeLog(
        from previous: [TemplateExercisePrescription]?,
        to current: [TemplateExercisePrescription]
    ) -> TemplateVersionChangeLog {
        guard let previous else {
            return .initial
        }

        let previousByID = Dictionary(
            uniqueKeysWithValues: previous.map { ($0.exerciseID, $0) }
        )
        let currentByID = Dictionary(
            uniqueKeysWithValues: current.map { ($0.exerciseID, $0) }
        )
        let previousIDs = Set(previousByID.keys)
        let currentIDs = Set(currentByID.keys)

        var summaryParts: [String] = []
        var detailLines: [String] = []

        let added = currentIDs.subtracting(previousIDs)
            .compactMap { currentByID[$0] }
            .sorted { $0.order < $1.order }
        for item in added {
            summaryParts.append("新增 \(item.exerciseName)")
            detailLines.append("新增 \(item.exerciseName)（顺序 \(item.order)）")
        }

        let removed = previousIDs.subtracting(currentIDs)
            .compactMap { previousByID[$0] }
            .sorted { $0.order < $1.order }
        for item in removed {
            summaryParts.append("移除 \(item.exerciseName)")
            detailLines.append("移除 \(item.exerciseName)")
        }

        let shared = previousIDs.intersection(currentIDs)
            .compactMap { id -> (TemplateExercisePrescription, TemplateExercisePrescription)? in
                guard let old = previousByID[id], let new = currentByID[id] else {
                    return nil
                }
                return (old, new)
            }
            .sorted { $0.1.order < $1.1.order }

        for (old, new) in shared {
            var fieldChanges: [String] = []
            if old.order != new.order {
                fieldChanges.append("顺序 \(old.order)→\(new.order)")
            }
            appendNumericChange(
                label: "组数",
                old: old.targetSets.map(String.init),
                new: new.targetSets.map(String.init),
                into: &fieldChanges
            )
            appendNumericChange(
                label: "次数",
                old: old.targetReps.map(String.init),
                new: new.targetReps.map(String.init),
                into: &fieldChanges
            )
            appendNumericChange(
                label: "重量",
                old: formatWeight(old.targetWeightKG),
                new: formatWeight(new.targetWeightKG),
                into: &fieldChanges
            )
            appendNumericChange(
                label: "间歇",
                old: old.targetRestSeconds.map { "\($0)s" },
                new: new.targetRestSeconds.map { "\($0)s" },
                into: &fieldChanges
            )
            if old.firstSetIsWarmup != new.firstSetIsWarmup {
                fieldChanges.append(
                    new.firstSetIsWarmup ? "首组改为热身" : "取消首组热身"
                )
            }
            if !fieldChanges.isEmpty {
                let joined = fieldChanges.joined(separator: "，")
                summaryParts.append("\(new.exerciseName) \(fieldChanges[0])")
                detailLines.append("\(new.exerciseName)：\(joined)")
            }
        }

        if summaryParts.isEmpty {
            if previous.map(\.exerciseID) != current.map(\.exerciseID)
                || previous.map(\.order) != current.map(\.order)
            {
                return TemplateVersionChangeLog(
                    summary: "调整动作顺序",
                    details: "模板动作顺序或组成已调整。"
                )
            }
            return TemplateVersionChangeLog(
                summary: "更新模板",
                details: "模板内容已更新。"
            )
        }

        let summary = summaryParts.prefix(3).joined(separator: "；")
            + (summaryParts.count > 3 ? "等" : "")
        return TemplateVersionChangeLog(
            summary: summary,
            details: detailLines.joined(separator: "\n")
        )
    }

    private static func appendNumericChange(
        label: String,
        old: String?,
        new: String?,
        into changes: inout [String]
    ) {
        guard old != new else { return }
        switch (old, new) {
        case let (nil, .some(value)):
            changes.append("\(label) →\(value)")
        case (.some, nil):
            changes.append("清除\(label)")
        case let (.some(before), .some(after)):
            changes.append("\(label) \(before)→\(after)")
        case (nil, nil):
            break
        }
    }

    private static func formatWeight(_ value: Double?) -> String? {
        guard let value else { return nil }
        if value == 0 {
            return "自重"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
    }
}

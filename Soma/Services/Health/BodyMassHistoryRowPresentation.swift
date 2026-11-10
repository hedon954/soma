import Foundation

/// 体重历史行的可测文案策略：Accessibility 字号下数值与单位必须同属一行字符串，避免窄列把小数点后数字拆到下一行。
enum BodyMassHistoryRowPresentation {
    struct AccessibilityLines: Equatable, Sendable {
        var sampleTime: String
        var sourceCaption: String?
        var weightLine: String?
        var bodyFatLine: String?
    }

    static func accessibilityLines(
        date: Date,
        weight: Double?,
        bodyFat: Double?,
        source: BodyMassKnownSource?,
        unknownSourceName: String? = nil,
        isHealthImported: Bool = false
    ) -> AccessibilityLines {
        AccessibilityLines(
            sampleTime: listDateText(date),
            sourceCaption: sourceCaption(
                source: source,
                unknownSourceName: unknownSourceName,
                isHealthImported: isHealthImported
            ),
            weightLine: weight.map(weightLine(for:)),
            bodyFatLine: bodyFat.map(bodyFatLine(for:))
        )
    }

    /// 列表已无日卡，行内只展示一次自然日，不用时钟时间冒充双指标采样时点。
    static func listDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func sampleTimeText(_ date: Date) -> String {
        listDateText(date)
    }

    static func weightLine(for weight: Double) -> String {
        let value = weight.formatted(.number.precision(.fractionLength(1)))
        // 不间断空格绑定数值与单位，避免「70.9」与「kg」被拆到两行。
        return "\(value)\u{00A0}kg"
    }

    static func bodyFatLine(for bodyFat: Double) -> String {
        let value = bodyFat.formatted(.number.precision(.fractionLength(1)))
        return "体脂率\u{00A0}\(value)%"
    }

    static func sourceCaption(
        source: BodyMassKnownSource?,
        unknownSourceName: String?,
        isHealthImported: Bool
    ) -> String? {
        if let source {
            return source.listCaption
        }
        if isHealthImported {
            let name = unknownSourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "未知来源" : name
        }
        return "手动"
    }
}

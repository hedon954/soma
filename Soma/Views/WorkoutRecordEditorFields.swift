import SwiftUI

struct WorkoutNumericField: View {
    @Binding var text: String
    let accessibilityLabel: String
    let unit: String
    let decimal: Bool
    var emptyPrompt = "—"
    var compact = false
    var flat = false
    let validRange: ClosedRange<Double>
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                TextField(
                    accessibilityLabel,
                    text: $text,
                    prompt: Text(emptyPrompt)
                )
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(.subheadline.monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($focused)
                .frame(minWidth: compact ? 32 : 50)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(
                    isInvalid ? "请修改为\(rangeDescription)" : ""
                )
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, compact ? 6 : 9)
            .frame(minHeight: AppTheme.minimumTapTarget)
            .background(
                flat ? Color.clear : AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isInvalid
                            ? AppTheme.destructive
                            : focused
                            ? AppTheme.tint
                            : flat
                            ? Color.clear
                            : AppTheme.separator,
                        lineWidth: focused || isInvalid ? 1.5 : 0.5
                    )
            }
            if isInvalid {
                Text("请输入\(rangeDescription)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isInvalid: Bool {
        guard !text.isEmpty else { return false }
        guard let value = decimal ? Double(text) : Int(text).map(Double.init) else {
            return true
        }
        return !validRange.contains(value)
    }

    private var rangeDescription: String {
        let lower = validRange.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let upper = validRange.upperBound.formatted(.number.precision(.fractionLength(0)))
        return "\(lower)–\(upper) \(unit)"
    }

    private var accessibilityValue: String {
        if isInvalid {
            return "输入无效，\(rangeDescription)"
        }
        if text.isEmpty {
            return emptyPrompt == "自重" ? "自重" : "未记录"
        }
        return "\(text) \(unit)"
    }
}

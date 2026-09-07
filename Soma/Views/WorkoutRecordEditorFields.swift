import SwiftUI

struct WorkoutNumericField: View {
    @Binding var text: String
    let accessibilityLabel: String
    let unit: String
    let decimal: Bool
    var emptyPrompt = "—"
    var prefix = ""
    var compact = false
    var flat = false
    var inline = false
    var parsesDuration = false
    let validRange: ClosedRange<Double>
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(inline ? .subheadline : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                ZStack(alignment: inline ? .leading : .center) {
                    Text(sizingText)
                        .font(.subheadline.monospacedDigit())
                        .hidden()
                        .fixedSize()
                    TextField(
                        accessibilityLabel,
                        text: $text,
                        prompt: Text(emptyPrompt)
                    )
                    .keyboardType(
                        parsesDuration
                            ? .default
                            : (decimal ? .decimalPad : .numberPad)
                    )
                    .font(.subheadline.monospacedDigit())
                    .multilineTextAlignment(inline ? .leading : .center)
                    .focused($focused)
                    .frame(minWidth: inline ? nil : (compact ? 32 : 50))
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(accessibilityValue)
                    .accessibilityHint(
                        isInvalid ? "请修改为\(rangeDescription)" : ""
                    )
                }
                if !unit.isEmpty {
                    Text(unit)
                        .font(inline ? .subheadline : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, inline ? 0 : (compact ? 6 : 9))
            .frame(minHeight: AppTheme.minimumTapTarget)
            .background(
                inline || flat ? Color.clear : AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isInvalid
                            ? AppTheme.destructive
                            : focused && !inline
                            ? AppTheme.tint
                            : Color.clear,
                        lineWidth: focused || isInvalid ? 1.5 : 0
                    )
            }
            .overlay(alignment: .bottom) {
                if inline, focused || isInvalid {
                    Rectangle()
                        .fill(isInvalid ? AppTheme.destructive : AppTheme.tint)
                        .frame(height: 1)
                }
            }
            if isInvalid {
                Text("请输入\(rangeDescription)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: inline && !isInvalid, vertical: false)
    }

    private var sizingText: String {
        if text.isEmpty {
            return emptyPrompt.isEmpty ? "0" : emptyPrompt
        }
        return text
    }

    private var isInvalid: Bool {
        guard !text.isEmpty else { return false }
        if parsesDuration {
            guard let seconds = DurationSecondsFormat.parse(text) else {
                return true
            }
            return !validRange.contains(Double(seconds))
        }
        guard let value = decimal ? Double(text) : Int(text).map(Double.init) else {
            return true
        }
        return !validRange.contains(value)
    }

    private var rangeDescription: String {
        let lower = validRange.lowerBound.formatted(.number.precision(.fractionLength(0)))
        let upper = validRange.upperBound.formatted(.number.precision(.fractionLength(0)))
        let unitLabel = parsesDuration ? "秒" : unit
        return unitLabel.isEmpty
            ? "\(lower)–\(upper)"
            : "\(lower)–\(upper) \(unitLabel)"
    }

    private var accessibilityValue: String {
        if isInvalid {
            return "输入无效，\(rangeDescription)"
        }
        if text.isEmpty {
            return emptyPrompt == "自重" ? "自重" : "未记录"
        }
        if unit.isEmpty {
            return text
        }
        return "\(text) \(unit)"
    }
}

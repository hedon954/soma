import SwiftUI

struct InlineRecordShell<Content: View>: View {
    let title: String
    var titleText: Binding<String>?
    let icon: String
    let isEditable: Bool
    var onSave: (() -> Bool)?
    var onDelete: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.tint)
                if isEditable, let titleText {
                    TextField("名称", text: titleText)
                        .font(.subheadline.weight(.semibold))
                        .textFieldStyle(.plain)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if isEditable {
                    if let onSave {
                        InlineRecordActions(save: onSave)
                    }
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除")
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("已锁定")
                }
            }
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

func compactMetric(
    _ unit: String,
    text: Binding<String>,
    decimal: Bool = false
) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
        TextField("-", text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 28)
            .accessibilityLabel(unit)
        Text(unit)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
    .background(
        Color.primary.opacity(0.05),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
}

struct InlineRecordActions: View {
    let save: () -> Bool
    @State private var didSave = false
    @State private var savePulse = 0
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: confirmSave) {
            Image(systemName: didSave ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(didSave ? AppTheme.tint : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(didSave)
        .sensoryFeedback(.success, trigger: savePulse)
        .accessibilityLabel(didSave ? "已保存" : "保存")
        .accessibilityHint(didSave ? "记录已写入本机" : "保存当前修改")
        .animation(.easeInOut(duration: 0.18), value: didSave)
        .onDisappear {
            resetTask?.cancel()
        }
    }

    private func confirmSave() {
        guard save() else { return }
        resetTask?.cancel()
        didSave = true
        savePulse += 1
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            didSave = false
        }
    }
}

import SwiftUI

struct InlineRecordShell<Content: View, Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var titleText: Binding<String>?
    let icon: String
    var iconTint: Color = AppTheme.tint
    var iconSoftTint: Color = AppTheme.softTint
    let isEditable: Bool
    var onSave: (() -> Bool)?
    var onDelete: (() -> Void)?
    /// 派生卡片本来就没有编辑入口，不该显示锁标记，否则会被读成“暂时不能改”。
    var showsLockWhenReadOnly = true
    /// 标题右侧的补充控件，例如饮食卡的餐次选择。
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 36, height: 36)
                    .background(iconSoftTint, in: Circle())
                    .accessibilityHidden(true)
                if isEditable, let titleText {
                    TextField("名称", text: titleText)
                        .font(.subheadline.weight(.semibold))
                        .textFieldStyle(.plain)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    accessory
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
                                .frame(
                                    width: AppTheme.minimumTapTarget,
                                    height: AppTheme.minimumTapTarget
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除")
                    }
                } else if showsLockWhenReadOnly {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("已锁定")
                }
            }
            // 辅助字号下标题会换行，配件挤在同一行会把标题撕成两段，改为单独一行。
            if dynamicTypeSize.isAccessibilitySize {
                accessory
            }
            content
        }
        .padding(14)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 0.5)
        }
    }
}

extension InlineRecordShell where Accessory == EmptyView {
    init(
        title: String,
        titleText: Binding<String>? = nil,
        icon: String,
        iconTint: Color = AppTheme.tint,
        iconSoftTint: Color = AppTheme.softTint,
        isEditable: Bool,
        onSave: (() -> Bool)? = nil,
        onDelete: (() -> Void)? = nil,
        showsLockWhenReadOnly: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            titleText: titleText,
            icon: icon,
            iconTint: iconTint,
            iconSoftTint: iconSoftTint,
            isEditable: isEditable,
            onSave: onSave,
            onDelete: onDelete,
            showsLockWhenReadOnly: showsLockWhenReadOnly,
            accessory: { EmptyView() },
            content: content
        )
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
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
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

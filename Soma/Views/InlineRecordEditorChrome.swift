import SwiftUI

enum InlineRecordSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed
}

enum InlineRecordReadOnlyStatus {
    case saved
}

struct InlineRecordShell<Content: View, Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var titleText: Binding<String>?
    let icon: String
    var iconTint: Color = AppTheme.tint
    var iconSoftTint: Color = AppTheme.softTint
    let isEditable: Bool
    var saveState: Binding<InlineRecordSaveState> = .constant(.idle)
    var onSave: (() -> Bool)?
    var onDelete: (() -> Void)?
    var readOnlyStatus: InlineRecordReadOnlyStatus?
    /// 派生卡片本来就没有编辑入口，不该显示锁标记，否则会被读成“暂时不能改”。
    var showsLockWhenReadOnly = true
    var contentPadding: CGFloat = 14
    /// 标题右侧的补充控件，例如饮食卡的餐次选择。
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 36, height: 36)
                    .background(iconSoftTint, in: Circle())
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                if isEditable, let titleText {
                    TextField("名称", text: titleText, axis: .vertical)
                        .font(.subheadline.weight(.semibold))
                        .textFieldStyle(.plain)
                        .lineLimit(1 ... 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapTarget, alignment: .leading)
                        .accessibilityIdentifier("inline-record-title")
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1 ... 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapTarget, alignment: .leading)
                        .accessibilityIdentifier("inline-record-title")
                }
                HStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        accessory
                    }
                    trailingActions
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            // 辅助字号下标题会换行，配件挤在同一行会把标题撕成两段，改为单独一行。
            if dynamicTypeSize.isAccessibilitySize {
                accessory
            }
            content
        }
        .padding(contentPadding)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 0.5)
        }
        .overlay(alignment: .top) {
            if saveState.wrappedValue == .saved {
                Text("已保存")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.success, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityLabel("已保存")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: saveState.wrappedValue)
    }

    @ViewBuilder
    private var trailingActions: some View {
        if isEditable {
            if let onSave {
                InlineRecordActions(
                    state: saveState,
                    placement: .first,
                    save: onSave
                )
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    CompactActionLabel(placement: onSave == nil ? .first : .following) {
                        Image(systemName: "trash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.destructive)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
            }
        } else if readOnlyStatus == .saved {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
                .accessibilityLabel("已保存")
                .accessibilityIdentifier("workout-record-saved")
        } else if showsLockWhenReadOnly {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("已锁定")
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
        saveState: Binding<InlineRecordSaveState> = .constant(.idle),
        onSave: (() -> Bool)? = nil,
        onDelete: (() -> Void)? = nil,
        readOnlyStatus: InlineRecordReadOnlyStatus? = nil,
        showsLockWhenReadOnly: Bool = true,
        contentPadding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            titleText: titleText,
            icon: icon,
            iconTint: iconTint,
            iconSoftTint: iconSoftTint,
            isEditable: isEditable,
            saveState: saveState,
            onSave: onSave,
            onDelete: onDelete,
            readOnlyStatus: readOnlyStatus,
            showsLockWhenReadOnly: showsLockWhenReadOnly,
            contentPadding: contentPadding,
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
    @Binding var state: InlineRecordSaveState
    var placement: CompactActionVisualPlacement = .first
    let save: () -> Bool

    var body: some View {
        Button(action: confirmSave) {
            CompactActionLabel(placement: placement) {
                Group {
                    if state == .saving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(iconColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .saving || state == .saved)
        .sensoryFeedback(.success, trigger: state == .saved)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(state == .failed ? "再次尝试保存" : "修改后会自动保存")
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    private func confirmSave() {
        state = .saving
        Task { @MainActor in
            await Task.yield()
            state = save() ? .saved : .failed
            if state == .saved {
                NotificationCenter.default.post(name: .inlineRecordDidSave, object: nil)
            }
            guard state == .saved else { return }
            try? await Task.sleep(for: .milliseconds(2800))
            guard state == .saved else { return }
            state = .idle
        }
    }

    private var iconName: String {
        switch state {
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .idle, .saving: "checkmark.circle"
        }
    }

    private var iconColor: Color {
        switch state {
        case .saved: AppTheme.success
        case .failed: AppTheme.warning
        case .idle, .saving: .secondary
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "自动保存已就绪"
        case .saving: "正在自动保存"
        case .saved: "自动保存成功"
        case .failed: "自动保存失败"
        }
    }
}

private struct InlineRecordAutosaveModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let isEnabled: Bool
    @Binding var state: InlineRecordSaveState
    let save: @MainActor () -> Bool

    @State private var pendingTask: Task<Void, Never>?
    @State private var hasPendingChanges = false

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, _ in
                guard isEnabled else { return }
                pendingTask?.cancel()
                hasPendingChanges = true
                state = .saving
                pendingTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(550))
                    guard !Task.isCancelled else { return }
                    state = save() ? .saved : .failed
                    hasPendingChanges = state == .failed
                    if state == .saved {
                        NotificationCenter.default.post(name: .inlineRecordDidSave, object: nil)
                    }
                    guard state == .saved else { return }
                    try? await Task.sleep(for: .milliseconds(2800))
                    guard !Task.isCancelled else { return }
                    state = .idle
                }
            }
            .onDisappear {
                pendingTask?.cancel()
                guard isEnabled, hasPendingChanges else { return }
                state = save() ? .saved : .failed
                hasPendingChanges = state == .failed
            }
    }
}

extension View {
    func inlineRecordAutosave(
        value: some Equatable,
        isEnabled: Bool,
        state: Binding<InlineRecordSaveState>,
        save: @escaping @MainActor () -> Bool
    ) -> some View {
        modifier(
            InlineRecordAutosaveModifier(
                value: value,
                isEnabled: isEnabled,
                state: state,
                save: save
            )
        )
    }
}

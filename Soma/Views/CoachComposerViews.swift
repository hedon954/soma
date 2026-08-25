import SwiftData
import SwiftUI

struct CoachComposer: View {
    @Binding var draft: String
    @Binding var attachments: [PendingAttachment]
    let gyms: [GymProfile]
    let currentGym: GymProfile?
    let exerciseSuggestions: [ExerciseInputSuggestion]
    let pendingCount: Int
    let showsExecutionChoice: Bool
    @Binding var useLocalForNextMessage: Bool
    @Binding var selectedShortcutID: String?
    let shortcuts: [AgentInputShortcut]
    let isSending: Bool
    let isListening: Bool
    let speechMessage: String?
    let focusRequest: UUID
    let dismissRequest: UUID
    let onAddMedia: () -> Void
    let onSelectGym: (GymProfile) -> Void
    let onManageGyms: () -> Void
    let onApplySuggestion: (ExerciseInputSuggestion) -> Void
    let onManagePending: () -> Void
    let onToggleVoice: () -> Void
    let onSend: () -> Void
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @FocusState var focused: Bool

    /// PRD 020：输入区同一时间最多一层内容上下文条，附件预览优先于动作建议。
    /// PRD 037：场馆切换与快捷按钮同属发送前控制，固定在同一个横向滚动行。
    enum ContextStrip {
        case attachments, suggestions
    }

    var contextStrip: ContextStrip? {
        if !attachments.isEmpty {
            return .attachments
        }
        if !exerciseSuggestions.isEmpty {
            return .suggestions
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            composerContextControls

            // ADR 0045：暂存计数常驻在输入区上方，与上下文条互不挤占。
            if pendingCount > 0 {
                PendingQueueBanner(
                    count: pendingCount,
                    onManage: onManagePending
                )
            }

            switch contextStrip {
            case .attachments:
                AttachmentPreview(
                    attachments: attachments,
                    onRemove: { id in
                        attachments.removeAll { $0.id == id }
                    }
                )
            case .suggestions:
                InputSuggestionList(
                    items: exerciseSuggestions.map(Self.suggestionItem),
                    selectionHint: "把动作与最近一次训练数据填入输入框"
                ) { item in
                    guard let suggestion = exerciseSuggestions.first(where: {
                        $0.id.uuidString == item.id
                    }) else {
                        return
                    }
                    onApplySuggestion(suggestion)
                }
            case nil:
                EmptyView()
            }

            if isListening {
                Label("正在听写…", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else if let speechMessage {
                Text(speechMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    composerTextField
                    HStack(spacing: 12) {
                        addMediaButton
                        Spacer(minLength: 8)
                        voiceButton
                        sendControl
                    }
                    .padding(.horizontal, 6)
                }
            } else {
                HStack(alignment: .bottom, spacing: 9) {
                    addMediaButton
                    composerTextField
                    voiceButton
                    sendControl
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.pageBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 0.5)
        }
        .onChange(of: focusRequest) {
            focused = true
        }
        .onChange(of: dismissRequest) {
            focused = false
        }
        .onChange(of: isSending) {
            if isSending {
                focused = false
            }
        }
    }

    /// PRD 033 / 037：可见快捷按钮与多场馆切换在一个水平行内，窄屏只滚动不换行。
    var composerContextControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    let isSelected = selectedShortcutID == shortcut.id
                    Button {
                        selectedShortcutID = isSelected ? nil : shortcut.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: shortcut.iconSystemName)
                                .foregroundStyle(
                                    isSelected
                                        ? AppTheme.onAccent
                                        : shortcutColor(shortcut)
                                )
                            Text(shortcut.title)
                                .foregroundStyle(
                                    isSelected ? AppTheme.onAccent : Color.secondary
                                )
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected
                                ? AppTheme.accentEmphasis
                                : AppTheme.insetBackground,
                            in: Capsule()
                        )
                        .frame(minHeight: AppTheme.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("快捷按钮：\(shortcut.title)")
                    .accessibilityValue(isSelected ? "已选择" : "未选择")
                }
                if gyms.count >= 2 {
                    gymStrip
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
    }

    var gymStrip: some View {
        Menu {
            ForEach(gyms) { gym in
                Button {
                    onSelectGym(gym)
                } label: {
                    if gym.id == currentGym?.id {
                        Label(gym.name, systemImage: "checkmark")
                    } else {
                        Text(gym.name)
                    }
                }
            }

            Divider()

            Button {
                onManageGyms()
            } label: {
                Label("管理健身房…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(currentGym?.name ?? "选择健身房")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                AppTheme.insetBackground,
                in: Capsule()
            )
            .frame(minHeight: AppTheme.minimumTapTarget)
        }
        .accessibilityLabel("当前健身房 \(currentGym?.name ?? "未选择")，点击切换")
    }

    var addMediaButton: some View {
        Button(action: onAddMedia) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(AppTheme.insetBackground, in: Circle())
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
        }
        .disabled(attachments.count >= MediaPicker.maximumSelectionCount)
        .accessibilityLabel("添加照片或视频，可多选")
    }

    var composerTextField: some View {
        TextField("说点什么，或添加照片与视频…", text: $draft, axis: .vertical)
            .lineLimit(1 ... 5)
            .focused($focused)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(minHeight: AppTheme.minimumTapTarget)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 19)
            )
    }

    var voiceButton: some View {
        Button(action: onToggleVoice) {
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isListening ? AppTheme.onAccent : AppTheme.tint)
                .background(
                    isListening ? AppTheme.accentEmphasis : AppTheme.insetBackground,
                    in: Circle()
                )
                .frame(
                    width: AppTheme.minimumTapTarget,
                    height: AppTheme.minimumTapTarget
                )
        }
        .disabled(isSending)
        .accessibilityLabel(isListening ? "停止语音输入" : "开始语音输入")
    }

    static func suggestionItem(
        _ suggestion: ExerciseInputSuggestion
    ) -> InputSuggestionItem {
        InputSuggestionItem(
            id: suggestion.id.uuidString,
            title: suggestion.draftText,
            detail: suggestion.recentDate.map {
                "上次 " + $0.formatted(date: .abbreviated, time: .omitted)
            },
            icon: "figure.strengthtraining.traditional"
        )
    }

    /// ADR 0045：任务在途时仍可继续发送，队列按 FIFO 消费。
    var sendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
    }

    var sendLabel: some View {
        let foreground = useLocalForNextMessage ? Color.white : AppTheme.onAccent
        return Group {
            if isSending {
                ProgressView().tint(foreground)
            } else {
                Image(systemName: useLocalForNextMessage ? "iphone" : "arrow.up")
                    .fontWeight(.bold)
            }
        }
        .frame(width: 40, height: 40)
        .foregroundStyle(foreground)
        .background(
            useLocalForNextMessage ? AppTheme.warningEmphasis : AppTheme.accentEmphasis,
            in: Circle()
        )
        .frame(
            width: AppTheme.minimumTapTarget,
            height: AppTheme.minimumTapTarget
        )
    }

    func shortcutColor(_ shortcut: AgentInputShortcut) -> Color {
        switch shortcut.id {
        case "shortcut_nutrition":
            AppTheme.mealAccent
        case "shortcut_workout_log":
            AppTheme.trainingAccent
        case "shortcut_recent_review":
            AppTheme.trendAccent
        default:
            AppTheme.tint
        }
    }

    /// PRD 020：远程执行方式不再常驻输入区，改为发送按钮长按菜单按条覆盖。
    @ViewBuilder
    var sendControl: some View {
        if showsExecutionChoice {
            Menu {
                Toggle(isOn: $useLocalForNextMessage) {
                    Label("本次仅本机", systemImage: "iphone")
                }
                .appToggleStyle()
            } label: {
                sendLabel
            } primaryAction: {
                onSend()
            }
            .disabled(sendDisabled)
            .accessibilityLabel(
                useLocalForNextMessage ? "发送，本次仅本机" : "发送"
            )
            .accessibilityHint("长按选择这条消息是仅在本机执行还是可后台继续")
        } else {
            Button(action: onSend) {
                sendLabel
            }
            .disabled(sendDisabled)
            .accessibilityLabel("发送")
        }
    }
}

/// ADR 0062：输入区只保留计数入口，完整队列操作进入可审查的管理列表。
struct PendingQueueBanner: View {
    let count: Int
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.footnote)
                .foregroundStyle(AppTheme.warning)
            Text("\(count) 条待处理，按发送顺序等待")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onManage) {
                Text("管理")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tint)
            }
            .accessibilityHint("查看暂存列表并重试或删除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.warning.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) 条消息待处理，按发送顺序等待")
    }
}

struct AttachmentPreview: View {
    let attachments: [PendingAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let data = attachment.imageData {
                                PendingImagePreview(id: attachment.id, data: data)
                            } else {
                                ZStack {
                                    Color.black.opacity(0.82)
                                    Image(systemName: "play.fill").foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(width: 64, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 11))

                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.65))
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityLabel(
                            attachment.kind == .video ? "移除视频" : "移除图片"
                        )
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

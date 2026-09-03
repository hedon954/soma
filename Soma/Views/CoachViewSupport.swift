import SwiftUI

enum CoachSheet: Identifiable {
    case media
    case pendingQueue

    var id: String {
        switch self {
        case .media:
            "media"
        case .pendingQueue:
            "pending-queue"
        }
    }
}

/// 教练 Tab 是否为当前选中项。由 RootView 写入一次布尔环境值，只有实时转写
/// 观察者和激活滚底驱动这两枚叶子读取；教练子树的其余部分不因 Tab 切换重算，
/// `@Query` 也不会随选中态变化重建。
private struct CoachTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var coachTabIsActive: Bool {
        get { self[CoachTabIsActiveKey.self] }
        set { self[CoachTabIsActiveKey.self] = newValue }
    }
}

extension Notification.Name {
    /// 发送链路发现缺少必需 API Key 时，请求 RootView 打开 LLM 配置 sheet。
    /// 用通知替代逐层闭包，避免教练子树携带每次渲染都变化的入参。
    static let coachRequiresAIConfiguration = Notification.Name(
        "Soma.coachRequiresAIConfiguration"
    )

    static let coachDoubleReselected = Notification.Name(
        "Soma.coachDoubleReselected"
    )

    static let focusCoachComposer = Notification.Name(
        "Soma.focusCoachComposer"
    )
}

/// 消息尾部滚动的唯一可变 owner。发送、流式增长、回到教练和显式回底都先进入
/// 这里，再由同一 generation 取消旧请求。测量值与 5 Hz 节流不属于界面状态，
/// 因此正文每批增长不会让 Coach 根视图失效。
@MainActor
final class CoachTailScrollCoordinator {
    var followState = CoachTailFollowState()
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var pendingMessageID: UUID?
    var lastScrollAt = Date.distantPast
    var task: Task<Void, Never>?
    private(set) var generation: UInt64 = 0

    var contentFitsViewport: Bool? {
        guard contentHeight > 0, viewportHeight > 0 else { return nil }
        return contentHeight <= viewportHeight + 1
    }

    @discardableResult
    func recordContentHeight(_ height: CGFloat) -> Bool {
        let didGrow = height > contentHeight + 0.5
        contentHeight = height
        return didGrow
    }

    func recordViewportHeight(_ height: CGFloat) {
        viewportHeight = height
    }

    func enqueueMessage(_ messageID: UUID) {
        pendingMessageID = messageID
    }

    func consumePendingMessageID() -> UUID? {
        defer { pendingMessageID = nil }
        return pendingMessageID
    }

    func startRequest(replacingExisting: Bool) -> UInt64? {
        if replacingExisting {
            cancelRequest()
        } else if task != nil {
            return nil
        }
        generation &+= 1
        return generation
    }

    func install(_ task: Task<Void, Never>, generation: UInt64) {
        guard self.generation == generation else {
            task.cancel()
            return
        }
        self.task = task
    }

    func owns(_ generation: UInt64) -> Bool {
        self.generation == generation
    }

    func finish(_ generation: UInt64) {
        guard self.generation == generation else { return }
        task = nil
    }

    func cancelRequest() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}

/// 输入区的全部可变状态。会话页只持有引用、在事件回调里读写，
/// 绝不在 body 里读取任何字段；`CoachComposer` 经 `@Bindable` 成为
/// 唯一的渲染消费者。打字与听写因此只重渲染输入区，不再让消息列表、
/// 投影和 toolbar 随每个字符失效。
@MainActor
@Observable
final class CoachComposerState {
    var draft = ""
    var attachments: [PendingAttachment] = []
    var useLocalForNextMessage = false
    var selectedShortcutID: String?
    var selectedExerciseSuggestion: ExerciseInputSuggestion?
    var isPersistingSubmission = false
    var focusRequest = UUID()
    var dismissRequest = UUID()
    /// 语音服务只在用户第一次点麦克风时创建。
    var speechInput: SpeechInputService?
    /// 听写基线不影响渲染，只在合成草稿时读取。
    @ObservationIgnored var draftBeforeSpeech = ""

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func requestFocus() {
        focusRequest = UUID()
    }

    func dismissKeyboard() {
        dismissRequest = UUID()
    }

    /// 发送被接受后的收口：清空草稿与选择，收起键盘。
    func clearAfterSubmission() {
        draft = ""
        attachments = []
        useLocalForNextMessage = false
        selectedExerciseSuggestion = nil
        selectedShortcutID = nil
        dismissKeyboard()
    }

    /// 切换 Session 前的收口：不保留上一个会话的草稿、附件和语音。
    func prepareForSessionChange() {
        draft = ""
        attachments = []
        useLocalForNextMessage = false
        stopVoice()
        dismissKeyboard()
    }

    func appendPickedMedia(_ media: [PickedMedia]) {
        let available = max(
            MediaPicker.maximumSelectionCount - attachments.count,
            0
        )
        attachments.append(
            contentsOf: media.prefix(available).map(PendingAttachment.init)
        )
    }

    func toggleVoice() {
        if let speechInput, speechInput.isListening {
            speechInput.stop()
            syncDraftFromSpeech()
            return
        }
        // A stopped recognizer can still hold the last committed transcript.
        // Merge it before replacing the baseline for a new listening cycle.
        syncDraftFromSpeech()
        draftBeforeSpeech = trimmedDraft
        let service = speechInput ?? SpeechInputService()
        speechInput = service
        Task {
            await service.start()
        }
    }

    func stopVoice() {
        speechInput?.stop()
    }

    /// 听写增量合入草稿：保留听写开始前的文字，后接最新转写。
    func syncDraftFromSpeech() {
        guard let speechInput else { return }
        let transcript = speechInput.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        draft = [draftBeforeSpeech, transcript]
            .filter { !$0.isEmpty }
            .joined(separator: draftBeforeSpeech.isEmpty ? "" : " ")
    }

    /// 草稿一旦偏离所选建议文本，精确快捷记录立即失效，
    /// 发送时不会把旧结构化草稿误配到新文字上。
    func reconcileSelectedSuggestion() {
        guard let selectedExerciseSuggestion else { return }
        if trimmedDraft != selectedExerciseSuggestion.draftText {
            self.selectedExerciseSuggestion = nil
        }
    }
}

/// Tab 显隐只决定是否允许刷新后台建议，不属于界面状态。
/// 使用非 Observation 引用，避免每次回到 Coach 都先触发一次无内容变化的 body。
@MainActor
final class CoachVisibilityState {
    var isVisible = false
    var autoScrollGate = CoachMessageAutoScrollGate()
    var tailMessageID: UUID?
    let tailScroll = CoachTailScrollCoordinator()
}

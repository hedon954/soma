import SwiftUI

/// 高级设置中的 ReAct 步数与按媒体类型独立配置的活动执行时间上限。
struct ReActLoopSettingsSection: View {
    @AppStorage(ReActAgentPreference.maxStepsKey)
    private var maxSteps = ReActAgentPreference.defaultMaxSteps
    @AppStorage(ReActAgentPreference.textRuntimeTimeoutMinutesKey)
    private var textTimeout = ReActAgentPreference.defaultTextRuntimeTimeoutMinutes
    @AppStorage(ReActAgentPreference.imageRuntimeTimeoutMinutesKey)
    private var imageTimeout = ReActAgentPreference.defaultImageRuntimeTimeoutMinutes
    @AppStorage(ReActAgentPreference.videoRuntimeTimeoutMinutesKey)
    private var videoTimeout = ReActAgentPreference.defaultVideoRuntimeTimeoutMinutes

    var body: some View {
        Section {
            Stepper(
                value: clampedBinding(
                    $maxSteps,
                    range: ReActAgentPreference.minimumMaxSteps
                        ... ReActAgentPreference.maximumMaxSteps
                )
            ) {
                LabeledContent("ReAct 步骤上限", value: "\(clampedMaxSteps)")
            }
            timeoutStepper("文字超时上限", value: $textTimeout)
            timeoutStepper("图片超时上限", value: $imageTimeout)
            timeoutStepper("视频超时上限", value: $videoTimeout)
            Button("恢复默认 ReAct 设置", action: restoreDefaults)
                .disabled(isUsingDefaults)
        } header: {
            Text("ReAct 循环")
        } footer: {
            Text(footerText)
        }
        .onAppear(perform: normalizeValues)
    }

    private func timeoutStepper(
        _ title: String,
        value: Binding<Int>
    ) -> some View {
        Stepper(
            value: clampedBinding(value, range: timeoutRange)
        ) {
            LabeledContent(
                title,
                value: "\(clamped(value.wrappedValue, in: timeoutRange)) 分钟"
            )
        }
        .accessibilityLabel(title)
        .accessibilityValue("\(clamped(value.wrappedValue, in: timeoutRange)) 分钟")
    }

    private var timeoutRange: ClosedRange<Int> {
        ReActAgentPreference.minimumRuntimeTimeoutMinutes
            ... ReActAgentPreference.maximumRuntimeTimeoutMinutes
    }

    private var clampedMaxSteps: Int {
        clamped(
            maxSteps,
            in: ReActAgentPreference.minimumMaxSteps
                ... ReActAgentPreference.maximumMaxSteps
        )
    }

    private func clampedBinding(
        _ value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { clamped(value.wrappedValue, in: range) },
            set: { value.wrappedValue = clamped($0, in: range) }
        )
    }

    private func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private var isUsingDefaults: Bool {
        clampedMaxSteps == ReActAgentPreference.defaultMaxSteps
            && textTimeout == ReActAgentPreference.defaultTextRuntimeTimeoutMinutes
            && imageTimeout == ReActAgentPreference.defaultImageRuntimeTimeoutMinutes
            && videoTimeout == ReActAgentPreference.defaultVideoRuntimeTimeoutMinutes
    }

    private func normalizeValues() {
        ReActAgentPreference.migrateLegacyRuntimeTimeoutIfNeeded()
        maxSteps = clampedMaxSteps
        textTimeout = ReActAgentPreference.textRuntimeTimeoutMinutes()
        imageTimeout = ReActAgentPreference.imageRuntimeTimeoutMinutes()
        videoTimeout = ReActAgentPreference.videoRuntimeTimeoutMinutes()
    }

    private func restoreDefaults() {
        maxSteps = ReActAgentPreference.defaultMaxSteps
        textTimeout = ReActAgentPreference.defaultTextRuntimeTimeoutMinutes
        imageTimeout = ReActAgentPreference.defaultImageRuntimeTimeoutMinutes
        videoTimeout = ReActAgentPreference.defaultVideoRuntimeTimeoutMinutes
    }

    private var footerText: String {
        "单次发送内模型与本地工具最多往返 \(ReActAgentPreference.defaultMaxSteps) 步。"
            + "文字、图片、视频分别计算实际执行时间，默认 3、5、10 分钟，均可独立设为 3–60 分钟。"
            + "等待用户、网络或前台不计时；更高上限会增加耗时与费用。"
    }
}

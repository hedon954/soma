import SwiftUI

/// 高级设置中的 ReAct 步数与活动执行时间上限。
struct ReActLoopSettingsSection: View {
    @AppStorage(ReActAgentPreference.maxStepsKey)
    private var maxSteps = ReActAgentPreference.defaultMaxSteps
    @AppStorage(ReActAgentPreference.runtimeTimeoutMinutesKey)
    private var runtimeTimeoutMinutes = ReActAgentPreference.automaticRuntimeTimeoutMinutes

    var body: some View {
        Section {
            Stepper(
                value: maxStepsBinding,
                in: ReActAgentPreference.minimumMaxSteps ... ReActAgentPreference.maximumMaxSteps,
                step: 1
            ) {
                LabeledContent("ReAct 步骤上限", value: "\(clampedMaxSteps)")
            }
            .accessibilityLabel("ReAct 步骤上限")
            .accessibilityValue("\(clampedMaxSteps)")
            Stepper(
                value: runtimeTimeoutOptionBinding,
                in: 0 ... runtimeTimeoutOptionCount,
                step: 1
            ) {
                LabeledContent("运行超时上限", value: runtimeTimeoutValueText)
            }
            .accessibilityLabel("运行超时上限")
            .accessibilityValue(runtimeTimeoutValueText)
            Button("恢复默认 ReAct 设置") {
                maxSteps = ReActAgentPreference.defaultMaxSteps
                runtimeTimeoutMinutes = ReActAgentPreference.automaticRuntimeTimeoutMinutes
            }
            .disabled(isUsingDefaults)
        } header: {
            Text("ReAct 循环")
        } footer: {
            Text(footerText)
        }
        .onAppear {
            maxSteps = clampedMaxSteps
            runtimeTimeoutMinutes = clampedRuntimeTimeoutMinutes
        }
    }

    private var clampedMaxSteps: Int {
        min(
            ReActAgentPreference.maximumMaxSteps,
            max(ReActAgentPreference.minimumMaxSteps, maxSteps)
        )
    }

    private var maxStepsBinding: Binding<Int> {
        Binding(
            get: { clampedMaxSteps },
            set: { maxSteps = $0 }
        )
    }

    private var clampedRuntimeTimeoutMinutes: Int {
        guard runtimeTimeoutMinutes != ReActAgentPreference.automaticRuntimeTimeoutMinutes else {
            return ReActAgentPreference.automaticRuntimeTimeoutMinutes
        }
        return min(
            ReActAgentPreference.maximumRuntimeTimeoutMinutes,
            max(ReActAgentPreference.minimumRuntimeTimeoutMinutes, runtimeTimeoutMinutes)
        )
    }

    private var runtimeTimeoutOptionCount: Int {
        ReActAgentPreference.maximumRuntimeTimeoutMinutes
            - ReActAgentPreference.minimumRuntimeTimeoutMinutes + 1
    }

    private var runtimeTimeoutOption: Int {
        guard clampedRuntimeTimeoutMinutes != ReActAgentPreference.automaticRuntimeTimeoutMinutes
        else {
            return 0
        }
        return clampedRuntimeTimeoutMinutes
            - ReActAgentPreference.minimumRuntimeTimeoutMinutes + 1
    }

    private var runtimeTimeoutOptionBinding: Binding<Int> {
        Binding(
            get: { runtimeTimeoutOption },
            set: { option in
                runtimeTimeoutMinutes = option == 0
                    ? ReActAgentPreference.automaticRuntimeTimeoutMinutes
                    : ReActAgentPreference.minimumRuntimeTimeoutMinutes + option - 1
            }
        )
    }

    private var runtimeTimeoutValueText: String {
        guard clampedRuntimeTimeoutMinutes != ReActAgentPreference.automaticRuntimeTimeoutMinutes
        else {
            return "自动（3/5/10 分钟）"
        }
        return "\(clampedRuntimeTimeoutMinutes) 分钟"
    }

    private var isUsingDefaults: Bool {
        clampedMaxSteps == ReActAgentPreference.defaultMaxSteps
            && clampedRuntimeTimeoutMinutes
            == ReActAgentPreference.automaticRuntimeTimeoutMinutes
    }

    private var footerText: String {
        let lower = ReActAgentPreference.minimumMaxSteps
        let upper = ReActAgentPreference.maximumMaxSteps
        let defaultSteps = ReActAgentPreference.defaultMaxSteps
        return "单次发送内模型与本地工具最多往返的步数。默认 \(defaultSteps)；"
            + "可设为 \(lower)–\(upper)。运行超时只累计实际执行时间；自动模式按文字、图片、"
            + "视频使用 3/5/10 分钟，自定义可设为 3–60 分钟。等待用户、网络或前台不计时。"
            + "更高上限会增加耗时与费用。"
    }
}

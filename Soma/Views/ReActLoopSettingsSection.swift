import SwiftUI

/// 高级设置中的 ReAct 步数上限控件。
struct ReActLoopSettingsSection: View {
    @AppStorage(ReActAgentPreference.maxStepsKey)
    private var maxSteps = ReActAgentPreference.defaultMaxSteps

    var body: some View {
        Section {
            Stepper(
                value: maxStepsBinding,
                in: ReActAgentPreference.minimumMaxSteps ... ReActAgentPreference.maximumMaxSteps,
                step: 1
            ) {
                LabeledContent("ReAct 步骤上限", value: "\(clampedMaxSteps)")
            }
            Button("恢复默认上限（\(ReActAgentPreference.defaultMaxSteps)）") {
                maxSteps = ReActAgentPreference.defaultMaxSteps
            }
            .disabled(clampedMaxSteps == ReActAgentPreference.defaultMaxSteps)
        } header: {
            Text("ReAct 循环")
        } footer: {
            Text(footerText)
        }
        .onAppear {
            maxSteps = clampedMaxSteps
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

    private var footerText: String {
        let lower = ReActAgentPreference.minimumMaxSteps
        let upper = ReActAgentPreference.maximumMaxSteps
        let defaultSteps = ReActAgentPreference.defaultMaxSteps
        return "单次发送内模型与本地工具最多往返的步数。默认 \(defaultSteps)；"
            + "可设为 \(lower)–\(upper)。更高上限会增加耗时与费用。"
    }
}

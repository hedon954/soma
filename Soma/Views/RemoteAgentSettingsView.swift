import SwiftData
import SwiftUI

struct RemoteAgentSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(RemoteAgentPreference.enabledKey)
    private var enabled = false
    @AppStorage(RemoteAgentPreference.baseURLKey)
    private var baseURL = ""
    @Query private var jobs: [AgentJob]

    @State private var status = RemoteAgentStatus()
    @State private var showsEnableConfirmation = false
    @State private var showsDisableConfirmation = false
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("后台持续处理", isOn: Binding(
                    get: { enabled },
                    set: { requested in
                        if requested {
                            guard RemoteAgentPreference.baseURL() != nil else {
                                validationMessage = "请先填写有效的 HTTPS 服务地址。"
                                return
                            }
                            showsEnableConfirmation = true
                        } else {
                            showsDisableConfirmation = true
                        }
                    }
                ))
                .disabled(status.isWorking)

                TextField(
                    "https://api.example.com",
                    text: $baseURL,
                    prompt: Text("Soma 后台服务地址")
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .disabled(enabled)
                .accessibilityHint("仅接受 HTTPS；Debug 可使用本机回环地址")
            } header: {
                Text("执行方式")
            } footer: {
                Text("默认关闭。开启后，新消息会创建服务器持久任务；退出 App 或短时断网后，服务器仍可继续执行。每条消息仍可在输入框选择“本次仅本机”。")
            }

            Section("数据边界") {
                LabeledContent("模型凭据", value: "Soma 管理")
                LabeledContent("用户 BYOK", value: "永不上传")
                LabeledContent("任务内容", value: "确认消费后 24 小时清理")
                LabeledContent("硬性内容上限", value: "7 天")
                LabeledContent("非内容运行元数据", value: "30 天")
                Label(
                    "仅发送当前消息、所选图片或视频关键帧，以及提交时的最小上下文快照",
                    systemImage: "checkmark.shield"
                )
                Label(
                    "训练、饮食、身体与健身房业务数据仍由本机固定 Tool 写入",
                    systemImage: "iphone.and.arrow.forward"
                )
            }

            Section {
                Button("关闭并清除远端临时数据", role: .destructive) {
                    showsDisableConfirmation = true
                }
                .disabled(status.isWorking)
                if let message = status.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("关闭时会先取消未结束任务，再撤销匿名设备 token。无法联网时本机立即关闭，之后可重新连接并再次清除。")
            }
        }
        .navigationTitle("后台持续处理")
        .navigationBarTitleDisplayMode(.inline)
        .alert("开启后台持续处理？", isPresented: $showsEnableConfirmation) {
            Button("取消", role: .cancel) {}
            Button("同意并开启") {
                RemoteAgentPreference.setBaseURL(baseURL)
                enabled = true
            }
        } message: {
            Text("Soma 会把当前任务的文字、所选图片或视频关键帧和最小上下文发送到你配置的服务，由 Soma 管理的模型凭据执行。原始视频和你的个人 API Key 不会上传。")
        }
        .alert("关闭并清除？", isPresented: $showsDisableConfirmation) {
            Button("取消", role: .cancel) {}
            Button("关闭并清除", role: .destructive) {
                Task { await disableRemoteExecution() }
            }
        } message: {
            Text("未完成的远端任务会取消，远端临时内容与设备 token 会撤销；本机聊天和已写入记录不会删除。")
        }
        .alert(
            "服务地址无效",
            isPresented: Binding(
                get: { validationMessage != nil },
                set: {
                    if !$0 {
                        validationMessage = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private func disableRemoteExecution() async {
        if let endpoint = RemoteAgentPreference.baseURL() {
            let client = RemoteAgentClient(baseURL: endpoint)
            for job in jobs where job.backend == .remote && !job.state.isTerminal {
                if let remoteJobID = job.remoteJobID {
                    try? await client.cancel(remoteJobID: remoteJobID)
                }
                if job.state.canTransition(to: .cancelled) {
                    try? job.transition(to: .cancelled)
                    _ = try? AgentJobStore.append(
                        kind: .cancelled,
                        payload: .init(
                            message: "用户关闭了后台持续处理。",
                            cancelled: true
                        ),
                        to: job,
                        in: modelContext
                    )
                }
            }
            try? modelContext.save()
        }
        await status.revokeAndDisable()
        enabled = false
    }
}

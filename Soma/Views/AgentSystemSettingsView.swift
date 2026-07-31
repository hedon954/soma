import SwiftUI

struct AgentSystemSettingsView: View {
    @Environment(AgentSystemProjectionCoordinator.self)
    private var coordinator
    @AppStorage(AgentSystemPreference.liveActivitiesKey)
    private var liveActivitiesEnabled = false
    @AppStorage(AgentSystemPreference.completionNotificationsKey)
    private var completionNotificationsEnabled = false
    @State private var authorizationMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle(
                    "锁屏与灵动岛显示长任务",
                    isOn: $liveActivitiesEnabled
                )
                Toggle(
                    "任务完成通知",
                    isOn: notificationBinding
                )
            } header: {
                Text("系统进度")
            } footer: {
                Text("只显示排队、处理、等待、完成或失败等通用状态和操作数量；不会显示你的原文、动作、重量、饮食、身体数据或媒体。")
            }

            Section("说明") {
                Label(
                    "Live Activity 只展示任务状态，不会延长 App 的后台运行时间。",
                    systemImage: "info.circle"
                )
                Label(
                    "普通短文字默认不启动；带媒体或远程长任务才会显示。",
                    systemImage: "timer"
                )
                Label(
                    "点击锁屏、灵动岛或通知会回到对应对话。",
                    systemImage: "arrow.turn.down.right"
                )
            }
        }
        .navigationTitle("任务进度与通知")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "通知不可用",
            isPresented: Binding(
                get: { authorizationMessage != nil },
                set: {
                    if !$0 {
                        authorizationMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(authorizationMessage ?? "")
        }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { completionNotificationsEnabled },
            set: { enabled in
                guard enabled else {
                    completionNotificationsEnabled = false
                    return
                }
                Task {
                    let granted = await coordinator
                        .requestNotificationAuthorization()
                    completionNotificationsEnabled = granted
                    if !granted {
                        authorizationMessage = "请在系统设置中允许 Soma 发送通知。"
                    }
                }
            }
        )
    }
}

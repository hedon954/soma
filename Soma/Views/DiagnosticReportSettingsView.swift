import SwiftUI

/// ADR 0095：只有 MetricKit 系统确认的崩溃进入这里。开关关闭后仍会本地留盘，只是不发送。
struct DiagnosticReportSettingsView: View {
    private let coordinator = CrashDiagnosticsCoordinator.shared
    @State private var isAutoSendEnabled = CrashDiagnosticsCoordinator.shared
        .isAutoSendEnabled
    @State private var reportText: String?
    @State private var logText = ""

    var body: some View {
        Form {
            Section {
                Toggle("自动发送崩溃诊断", isOn: $isAutoSendEnabled)
                    .appToggleStyle()
                    .onChange(of: isAutoSendEnabled) { _, newValue in
                        coordinator.isAutoSendEnabled = newValue
                    }
            } footer: {
                Text("开启后，只有系统 MetricKit 明确记录到崩溃时才会发送诊断邮件；强杀、模拟器停止、安装替换或哨兵未清位都不会生成报告。关闭后只在本机留存。")
            }

            Section {
                if let reportText, !reportText.isEmpty {
                    NavigationLink {
                        DiagnosticTextDetailView(
                            title: "上次诊断报告",
                            text: reportText
                        )
                    } label: {
                        LabeledContent(
                            "上次诊断报告",
                            value: coordinator.lastReportSummary ?? "可查看"
                        )
                    }
                } else {
                    LabeledContent("上次诊断报告", value: "暂无")
                }
                LabeledContent(
                    "待发送报告",
                    value: "\(coordinator.pendingReportCount)"
                )
                Button("立即尝试发送") {
                    Task {
                        await coordinator.deliverPendingReports()
                        await reload()
                    }
                }
                .disabled(coordinator.pendingReportCount == 0)
                Button("丢弃待发送报告", role: .destructive) {
                    Task {
                        await coordinator.discardPendingReportsAsync()
                        await reload()
                    }
                }
                .disabled(coordinator.pendingReportCount == 0)
            } header: {
                Text("报告")
            } footer: {
                Text("发送失败的系统确认报告会在下次启动重试；缺少 MetricKit 证据的旧报告会自动清除。")
            }

            Section {
                NavigationLink {
                    DiagnosticTextDetailView(
                        title: "本机诊断日志",
                        text: logText
                    )
                } label: {
                    Label("查看本机诊断日志", systemImage: "doc.text.magnifyingglass")
                }
                Button("清空本机诊断日志", role: .destructive) {
                    Task {
                        await DiagnosticsLogStore.shared.clearAsync()
                        await reload()
                    }
                }
            } footer: {
                Text("日志只保留最近的运行面包屑，API Key、授权头与媒体内容恒定脱敏。")
            }
        }
        .navigationTitle("崩溃诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await Task.yield()
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        isAutoSendEnabled = coordinator.isAutoSendEnabled
        async let latestReport = coordinator.latestReportTextAsync()
        async let recentLog = DiagnosticsLogStore.shared.recentTextAsync()
        reportText = await latestReport
        logText = await recentLog
    }
}

struct DiagnosticTextDetailView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "暂无内容" : text)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityLabel(title)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(text.isEmpty)
            }
        }
    }
}

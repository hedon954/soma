import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai
    @AppStorage(ConversationLocationPreference.defaultsKey)
    private var locationPreferenceRaw = ConversationLocationPreference.unasked.rawValue
    @AppStorage("workout.voiceCuesEnabled")
    private var voiceCuesEnabled = true
    @AppStorage(AppAppearancePreference.defaultsKey)
    private var appearanceRaw = AppAppearancePreference.system.rawValue
    @State private var path: [SettingsRoute]
    private let showsAIConfigurationReminder: Bool
    private let isEmbeddedInTab: Bool

    init(
        initialRoute: SettingsRoute? = nil,
        showsAIConfigurationReminder: Bool = false,
        isEmbeddedInTab: Bool = false
    ) {
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
        self.showsAIConfigurationReminder = showsAIConfigurationReminder
        self.isEmbeddedInTab = isEmbeddedInTab
    }

    private var locationEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                locationPreferenceRaw == ConversationLocationPreference.enabled.rawValue
            },
            set: { enabled in
                locationPreferenceRaw = (
                    enabled
                        ? ConversationLocationPreference.enabled
                        : ConversationLocationPreference.disabled
                ).rawValue
            }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                ForEach(SettingsHomeSection.allCases) { section in
                    settingsSection(section)
                }
            }
            .scrollContentBackground(.hidden)
            .listSectionSpacing(18)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
            .appPageBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbeddedInTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .llm:
                    LLMConfigurationView(
                        showsAIConfigurationReminder: showsAIConfigurationReminder
                    )
                }
            }
        }
    }

    private func settingsSection(_ section: SettingsHomeSection) -> some View {
        Group {
            switch section {
            case .profileAndTraining: profileAndTrainingSection
            case .service: serviceSection
            case .more: privacyAndAdvancedSection
            case .about: aboutSection
            case .display: displaySection
            case .feedback: feedbackSection
            }
        }
        .listRowBackground(AppTheme.cardBackground)
    }

    private var profileAndTrainingSection: some View {
        Section {
            NavigationLink {
                PersonalBodyInfoView()
            } label: {
                SettingsHomeRowLabel(item: .bodyInfo, title: "身体信息")
            }

            NavigationLink {
                GymLibraryView()
            } label: {
                SettingsHomeRowLabel(item: .gym, title: "健身房")
            }

            // PRD 020：带练语音提示从每次开练的准备页移到设置。
            Toggle(isOn: $voiceCuesEnabled) {
                SettingsHomeRowLabel(item: .voiceCues, title: "带练语音提示")
            }
            .appToggleStyle()
        } header: {
            settingsHomeSectionHeader("个人与训练")
        }
    }

    private var serviceSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.llm) {
                SettingsSummaryRow(
                    item: .llm,
                    title: "LLM 配置",
                    detail: "\(ai.provider.displayName) · \(ai.model(for: ai.provider))"
                )
            }

            NavigationLink {
                HealthDataIntegrationsView()
            } label: {
                SettingsSummaryRow(
                    item: .healthDevices,
                    title: "健康数据与设备",
                    detail: "Apple 健康、Keep、COROS"
                )
            }
        } header: {
            settingsHomeSectionHeader("服务")
        }
    }

    /// PRD 020：任务进度与后台处理是低频配置，下沉到「更多」。
    private var privacyAndAdvancedSection: some View {
        Section {
            NavigationLink {
                DataManagementView()
            } label: {
                SettingsHomeRowLabel(item: .dataBackup, title: "数据与备份")
            }

            NavigationLink {
                AgentSystemSettingsView()
            } label: {
                SettingsHomeRowLabel(item: .taskProgress, title: "任务进度与通知")
            }

            NavigationLink {
                RemoteAgentSettingsView()
            } label: {
                SettingsHomeRowLabel(item: .backgroundProcessing, title: "后台持续处理")
            }

            NavigationLink {
                Form {
                    privacySection
                    safetySection
                }
                .navigationTitle("隐私与安全")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsHomeRowLabel(item: .privacy, title: "隐私与安全")
            }

            NavigationLink {
                DeveloperSettingsView()
            } label: {
                SettingsHomeRowLabel(item: .advanced, title: "高级设置")
            }
        } header: {
            settingsHomeSectionHeader("更多")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Soma", value: "1.0.0 (1)")
            Text("Your body, understood.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let attributionURL = URL(string: "https://open-meteo.com/") {
                LabeledContent("天气数据") {
                    Link("Open-Meteo", destination: attributionURL)
                }
            }
        } header: {
            settingsHomeSectionHeader("关于")
        }
    }

    private var displaySection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                SettingsSummaryRow(
                    item: .appearance,
                    title: "外观",
                    detail: AppAppearancePreference.stored(appearanceRaw).title
                )
            }
        } header: {
            settingsHomeSectionHeader("显示")
        }
    }

    private var feedbackSection: some View {
        Section {
            DeferredSettingsFeedbackView()
                .listRowInsets(
                    EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
                )
                .listRowBackground(Color.clear)
        } header: {
            settingsHomeSectionHeader("反馈")
        }
    }

    private func settingsHomeSectionHeader(_ title: String) -> some View {
        Text(title)
            .textCase(nil)
            .padding(.leading, -AppTheme.pagePadding)
    }

    /// PRD 020：隐私页只保留可操作的位置开关，静态说明压缩为一句 footer。
    private var privacySection: some View {
        Section {
            Toggle(isOn: locationEnabledBinding) {
                Label("随消息记录位置", systemImage: "location")
            }
            .appToggleStyle()
        } header: {
            Text("隐私")
        } footer: {
            Text("开启后仅在发送时获取一次位置并保存在本机；天气或户外消息会向 Open-Meteo 发送约 1 公里精度的位置。Soma 无账户，数据与 API Key 只保存在本机。")
        }
    }

    private var safetySection: some View {
        Section("动作安全") {
            Label("AI 反馈用于训练记录和一般性建议，不能替代医生、物理治疗师或现场教练。", systemImage: "cross.case")
                .foregroundStyle(.secondary)
            Label("出现锐痛、眩晕或关节异常时应立即停止训练。", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

/// Form 会为屏外 Section 提前求值 View body。反馈编辑器包含媒体选择、评分和
/// 投递状态，只需在设置页已经提交选中外观后再挂载；一次加载后由 Tab 栈保留。
private struct DeferredSettingsFeedbackView: View {
    @State private var didLoad = false

    var body: some View {
        Group {
            if didLoad {
                FeedbackView(isEmbedded: true)
            } else {
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard !didLoad else { return }
            await Task.yield()
            didLoad = true
        }
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage(AppAppearancePreference.defaultsKey)
    private var appearanceRaw = AppAppearancePreference.system.rawValue

    private var selection: Binding<AppAppearancePreference> {
        Binding(
            get: { AppAppearancePreference.stored(appearanceRaw) },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppCard {
                    VStack(spacing: 0) {
                        ForEach(Array(AppAppearancePreference.allCases.enumerated()), id: \.element) { index, option in
                            Button {
                                selection.wrappedValue = option
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: option.icon)
                                        .frame(width: 24)
                                        .foregroundStyle(AppTheme.tint)
                                    Text(option.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selection.wrappedValue == option {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.tint)
                                    }
                                }
                                .frame(minHeight: AppTheme.minimumTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                selection.wrappedValue == option ? .isSelected : []
                            )

                            if index < AppAppearancePreference.allCases.count - 1 {
                                Divider()
                                    .overlay(AppTheme.separator)
                            }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("预览")
                            .font(.headline)
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AppTheme.trainingEmphasis)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "dumbbell.fill")
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("训练记录")
                                    .font(.headline)
                                Text("10 次 · 16 kg · 间歇 60 秒")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            AppTheme.insetBackground,
                            in: RoundedRectangle(
                                cornerRadius: AppTheme.controlRadius,
                                style: .continuous
                            )
                        )
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .appPageBackground()
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HealthDataIntegrationsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("healthkit.lastImportAt") private var lastImportAt = 0.0
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var otherDevicesExpanded = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(healthStatus)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Apple 健康", systemImage: "heart.fill")
                        .foregroundStyle(.primary)
                }

                Button {
                    importHealthData()
                } label: {
                    if isImporting {
                        HStack {
                            ProgressView()
                            Text("正在同步…")
                        }
                    } else {
                        Label("授权并同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isImporting || !HealthKitImporter.isAvailable)

                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.tint)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.warning)
                }
            } header: {
                Text("Apple 健康")
            } footer: {
                Text("只读取你明确授权的最近一年体重、训练和训练活动能量，并转换为 Soma 记录写入当前数据空间。每类数据分别保存增量游标，同时按 HealthKit 样本 ID 去重并同步来源删除；权限可随时在“健康”App 中撤销。")
            }

            // PRD 020：Keep/COROS 没有直连路径，说明折叠为「其他设备」。
            Section {
                DisclosureGroup("Keep 与 COROS", isExpanded: $otherDevicesExpanded) {
                    LabeledContent("Keep 直接接入", value: "暂不可用")
                    Text("Keep 暂无面向个人开发者的官方运动数据 API。若 Keep 已把数据写入 Apple 健康，可通过上方路径读取。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent("COROS 推荐方式", value: "经 Apple 健康")
                    Text("COROS 支持把部分数据同步到 Apple 健康；更完整的云端直连需要开发者申请 OAuth API 凭据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Link(
                        "查看 COROS 与 Apple 健康同步说明",
                        destination: URL(string: "https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App")!
                    )
                    Link(
                        "申请 COROS API 接入",
                        destination: URL(string: "https://support.coros.com/hc/en-us/articles/17085887816340-Submitting-an-API-Application")!
                    )
                }
            } header: {
                Text("其他设备")
            } footer: {
                Text("Keep 与 COROS 数据统一经 Apple 健康路径读取。")
            }
        }
        .navigationTitle("健康数据与设备")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var healthStatus: String {
        guard HealthKitImporter.isAvailable else { return "当前设备不可用" }
        guard lastImportAt > 0 else { return "尚未同步" }
        return Date(timeIntervalSince1970: lastImportAt)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func importHealthData() {
        isImporting = true
        resultMessage = nil
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                let result = try await HealthKitImporter.requestAuthorizationAndImport(
                    into: modelContext
                )
                lastImportAt = Date.now.timeIntervalSince1970
                resultMessage = result.summary
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PersonalBodyInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(
        filter: #Predicate<BodyEntry> { $0.imagePath != nil },
        sort: \BodyEntry.date,
        order: .reverse
    ) private var bodyEntries: [BodyEntry]

    @State private var displayName = ""
    @State private var biologicalSex: BiologicalSex = .unspecified
    @State private var birthDate = Calendar.current.date(
        byAdding: .year,
        value: -25,
        to: .now
    ) ?? .now
    @State private var hasBirthDate = false
    @State private var height = ""
    @State private var fitnessGoal: FitnessGoal?
    @State private var healthNotes = ""
    @State private var loadedProfileID: UUID?
    @State private var moreBasicsExpanded = false
    @State private var contextExpanded = false
    @State private var latestWeightValue: Double?
    @State private var latestWeightDate: Date?

    init() {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        _profiles = Query(descriptor)
        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.imagePath != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = 500
        _bodyEntries = Query(bodyDescriptor)
    }

    private var profile: UserProfile? {
        loadedProfileID.flatMap { id in profiles.first(where: { $0.id == id }) }
            ?? profiles.first
    }

    private var postureEntries: [BodyEntry] {
        bodyEntries.filter { $0.imagePath != nil }
    }

    var body: some View {
        Form {
            Section {
                Picker("生理性别", selection: $biologicalSex) {
                    ForEach(BiologicalSex.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                ProfileFieldRow(
                    title: "身高",
                    placeholder: "未填写",
                    unit: "cm",
                    text: $height,
                    keyboard: .decimalPad
                )
                LabeledContent("当前体重") {
                    if let weight = latestWeightValue,
                       let date = latestWeightDate,
                       weight > 0
                    {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(formatted(weight)) kg")
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("暂无体重记录")
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("更多（可选）", isExpanded: $moreBasicsExpanded) {
                    ProfileFieldRow(title: "称呼", placeholder: "可选", text: $displayName)
                    Toggle("填写出生日期", isOn: $hasBirthDate)
                        .appToggleStyle()
                    if hasBirthDate {
                        DatePicker(
                            "出生日期",
                            selection: $birthDate,
                            in: earliestBirthDate ... Date.now,
                            displayedComponents: .date
                        )
                    }
                }
            } header: {
                Text("基本信息")
            } footer: {
                Text("当前体重始终读取最新一条体重记录；请在教练中记录或修正体重。")
            }

            Section {
                Picker("健身目标", selection: $fitnessGoal) {
                    Text("未选择").tag(nil as FitnessGoal?)
                    ForEach(FitnessGoal.allCases) { goal in
                        Text(goal.rawValue).tag(Optional(goal))
                    }
                }
                DisclosureGroup("训练上下文", isExpanded: $contextExpanded) {
                    ProfileFieldRow(
                        title: "身体限制与注意事项",
                        placeholder: "例如：膝盖不适、医生给出的运动限制",
                        text: $healthNotes,
                        isMultiline: true
                    )
                }
            } footer: {
                Text("AI 只会把这里的信息当作上下文，不会据此进行医学诊断。")
            }

            Section {
                if postureEntries.isEmpty {
                    Label {
                        Text("在教练对话中发送体态图后，会自动保存在这里。")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "person.crop.rectangle.badge.plus")
                            .foregroundStyle(AppTheme.tint)
                    }
                } else {
                    ForEach(postureEntries) { entry in
                        NavigationLink {
                            BodyRecordDetailView(entry: entry)
                        } label: {
                            HStack(spacing: 12) {
                                MediaThumbnail(
                                    kind: .image,
                                    path: entry.imagePath,
                                    fallbackIcon: "figure.stand"
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.weight(.medium))
                                    Text(postureSummary(entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(entry)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除体态记录")
                            .tint(.red)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("体态图")
                    Spacer()
                    if !postureEntries.isEmpty {
                        Text("\(postureEntries.count) 张")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("体态图按时间保留，方便在相近拍摄条件下回溯变化。左滑可删除，点入后可编辑解析数据。")
            }
        }
        .navigationTitle("身体信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(!isValid)
                }
            }
        }
        .onAppear {
            load()
            loadLatestWeight()
        }
    }

    private var isValid: Bool {
        (!hasBirthDate || birthDate <= .now)
            && validDouble(height, range: 80 ... 250)
    }

    private var isDirty: Bool {
        guard let profile else {
            return [displayName, height, healthNotes]
                .contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                || biologicalSex != .unspecified
                || hasBirthDate
                || fitnessGoal != nil
        }
        return normalized(displayName) != profile.displayName
            || biologicalSex != profile.biologicalSex
            || birthDateChanged(from: profile.birthDate)
            || parsedDouble(height) != profile.height
            || fitnessGoal?.rawValue
            != (profile.fitnessGoal.isEmpty ? nil : profile.fitnessGoal)
            || normalized(healthNotes) != profile.healthNotes
    }

    private func load() {
        guard loadedProfileID == nil, let profile = profiles.first else { return }
        loadedProfileID = profile.id
        displayName = profile.displayName
        biologicalSex = profile.biologicalSex
        if let storedBirthDate = profile.birthDate {
            birthDate = storedBirthDate
            hasBirthDate = true
        } else {
            hasBirthDate = false
        }
        height = profile.height.map(formatted) ?? ""
        fitnessGoal = FitnessGoal(rawValue: profile.fitnessGoal)
        healthNotes = profile.healthNotes
        moreBasicsExpanded = !profile.displayName.isEmpty || hasBirthDate
        contextExpanded = !profile.fitnessGoal.isEmpty || !profile.healthNotes.isEmpty
    }

    private func loadLatestWeight() {
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.weight != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let entry = try? modelContext.fetch(descriptor).first
        latestWeightValue = entry?.weight
        latestWeightDate = entry?.date
    }

    private func save() {
        let target: UserProfile
        if let profile {
            target = profile
        } else {
            target = UserProfile()
            modelContext.insert(target)
            loadedProfileID = target.id
        }
        target.updatedAt = .now
        target.displayName = normalized(displayName)
        target.biologicalSex = biologicalSex
        target.birthDate = optionalBirthDate
        target.age = nil
        target.height = parsedDouble(height)
        target.fitnessGoal = fitnessGoal?.rawValue ?? ""
        target.healthNotes = normalized(healthNotes)
        try? modelContext.save()
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsedDouble(_ value: String) -> Double? {
        Double(normalized(value).replacingOccurrences(of: ",", with: "."))
    }

    private func validDouble(_ value: String, range: ClosedRange<Double>) -> Bool {
        normalized(value).isEmpty || parsedDouble(value).map(range.contains) == true
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private var optionalBirthDate: Date? {
        guard hasBirthDate else { return nil }
        return Calendar.current.startOfDay(for: birthDate)
    }

    private var earliestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: .now) ?? .distantPast
    }

    private func birthDateChanged(from storedDate: Date?) -> Bool {
        switch (optionalBirthDate, storedDate) {
        case (nil, nil):
            false
        case let (newDate?, storedDate?):
            !Calendar.current.isDate(newDate, inSameDayAs: storedDate)
        default:
            true
        }
    }

    private func postureSummary(_ entry: BodyEntry) -> String {
        if !entry.analysis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.analysis
        }
        if let weight = entry.weight {
            return "体重 \(formatted(weight)) kg"
        }
        return "体态图记录"
    }
}

private struct ProfileFieldRow: View {
    let title: String
    let placeholder: String
    var unit: String?
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isMultiline = false

    var body: some View {
        if isMultiline {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .keyboardType(keyboard)
            }
            .padding(.vertical, 2)
        } else {
            LabeledContent(title) {
                HStack(spacing: 5) {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.trailing)
                    if let unit {
                        Text(unit)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DeveloperSettingsView: View {
    @Environment(DataSpaceController.self) private var dataSpace
    @State private var customizedSections = Set<ReActPromptSection>()
    @State private var customizedSkillCount = 0
    @State private var visibleShortcutCount = 0
    @State private var confirmsResetAllPrompts = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AgentExecutionLogView()
                } label: {
                    Label("执行日志", systemImage: "point.3.connected.trianglepath.dotted")
                }
                NavigationLink {
                    DiagnosticReportSettingsView()
                } label: {
                    Label("崩溃诊断", systemImage: "ladybug")
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("审查当前数据空间内每次 ReAct Loop 的完整本地 Trace。")
            }

            ReActLoopSettingsSection()

            Section {
                ForEach(ReActPromptSection.userEditableCases) { section in
                    NavigationLink {
                        ReActPromptEditor(section: section)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(section.title)
                                    .font(.headline)
                                Spacer()
                                Text(customizedSections.contains(section) ? "已自定义" : "默认")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(customizedSections.contains(section) ? AppTheme.tint : .secondary)
                            }
                            Text(section.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
                NavigationLink {
                    FixedAgentContractView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(ReActPromptSection.policy.title)
                                .font(.headline)
                            Spacer()
                            Text("只读")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(ReActPromptSection.policy.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("系统提示词")
            } footer: {
                Text("只允许编辑教练人格；安全、真实性和授权契约始终由 App 固定。")
            }

            Section {
                Button("全部恢复默认提示词", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmsResetAllPrompts = true
                }
            }

            // PRD 020：Skill 列表收进二级页，这里只保留入口与自定义摘要。
            Section {
                NavigationLink {
                    AgentSkillsListView()
                } label: {
                    HStack {
                        Label("Skills", systemImage: "text.book.closed")
                        Spacer()
                        Text(customizedSkillCount > 0 ? "\(customizedSkillCount) 项自定义" : "默认")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("可编辑内置 Skill、创建本地 Skill；Skill 只描述方法，不再自带工具权限。")
            }

            // PRD 033：快捷按钮持有 Skill 绑定与工具白名单，是聊天输入区的唯一入口配置。
            Section {
                NavigationLink {
                    AgentInputShortcutListView()
                } label: {
                    HStack {
                        Label("输入框快捷按钮", systemImage: "square.grid.2x2")
                        Spacer()
                        Text("\(visibleShortcutCount) 个显示")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("新增、编辑、排序或隐藏快捷按钮，并为每个按钮勾选允许使用的工具。")
            }

            Section {
                Picker(
                    "当前数据",
                    selection: Binding(
                        get: { dataSpace.activeSpace },
                        set: { dataSpace.select($0) }
                    )
                ) {
                    ForEach(DataSpace.allCases) { space in
                        Label(space.title, systemImage: space.icon)
                            .tag(space)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("演示与调试")
            } footer: {
                Text("演示空间用于展示完整功能；个人空间只保存真实数据。两个空间完全隔离，切换不会删除内容。")
            }
        }
        .navigationTitle("高级设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshSummaryAfterTransition()
        }
        .alert("恢复全部默认提示词？", isPresented: $confirmsResetAllPrompts) {
            Button("恢复默认", role: .destructive) {
                ReActPromptSection.allCases.forEach { $0.reset() }
                customizedSections = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你保存的教练人格自定义内容会被移除；固定契约不会改变。")
        }
    }

    @MainActor
    private func refreshSummaryAfterTransition() async {
        await Task.yield()
        let summary = await Task.detached(priority: .userInitiated) {
            let sectionIDs = ReActPromptSection.userEditableCases
                .filter { $0.isCustomized() }
                .map(\.rawValue)
            let skillCount = AgentSkill.allCases.count { $0.isCustomized() }
            let shortcutCount = AgentInputShortcutStore.visibleShortcuts().count
            return (sectionIDs, skillCount, shortcutCount)
        }.value
        guard !Task.isCancelled else { return }
        customizedSections = Set(
            ReActPromptSection.userEditableCases.filter {
                summary.0.contains($0.rawValue)
            }
        )
        customizedSkillCount = summary.1
        visibleShortcutCount = summary.2
    }
}

struct AgentSkillEditor: View {
    let skill: AgentSkill
    @State private var text: String
    @State private var savedText: String
    @State private var mode: MarkdownEditorMode = .edit
    @State private var confirmsReset = false

    init(skill: AgentSkill) {
        self.skill = skill
        let initial = skill.text()
        _text = State(initialValue: initial)
        _savedText = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                Picker("显示方式", selection: $mode) {
                    ForEach(MarkdownEditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                if mode == .edit {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 420)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    MarkdownText(text)
                        .frame(minHeight: 420, alignment: .topLeading)
                        .padding(.vertical, 6)
                }
            } header: {
                Text(skill.title)
            } footer: {
                Text(skill.summary)
            }

            Section {
                LabeledContent("Skill ID", value: skill.rawValue)
                Button("恢复这个 Skill 的默认值", systemImage: "arrow.counterclockwise") {
                    confirmsReset = true
                }
                .disabled(!skill.isCustomized() && text == skill.defaultText)
            } footer: {
                Text("保存后从下一次 load_skill 调用开始生效。")
            }
        }
        .navigationTitle(skill.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(normalizedText.isEmpty)
                }
            }
        }
        .alert("恢复默认 Skill？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) {
                skill.reset()
                text = skill.defaultText
                savedText = skill.defaultText
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(skill.title)”的自定义内容会被移除。")
        }
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        normalizedText != savedText
    }

    private func save() {
        skill.save(text)
        let persisted = skill.text()
        text = persisted
        savedText = persisted
    }
}

struct AgentCustomSkillEditor: View {
    @Environment(\.dismiss) private var dismiss
    let originalID: String
    @State private var name: String
    @State private var description: String
    @State private var whenToUse: String
    @State private var content: String
    @State private var mode: MarkdownEditorMode = .edit

    init(skill: AgentCustomSkill) {
        originalID = skill.id
        _name = State(initialValue: skill.name)
        _description = State(initialValue: skill.description)
        _whenToUse = State(initialValue: skill.whenToUse)
        _content = State(initialValue: skill.content)
    }

    var body: some View {
        Form {
            Section("目录元数据") {
                TextField("名称", text: $name)
                TextField("描述", text: $description, axis: .vertical)
                TextField("什么时候使用", text: $whenToUse, axis: .vertical)
                LabeledContent("Skill ID", value: originalID)
            }

            Section {
                Picker("显示方式", selection: $mode) {
                    ForEach(MarkdownEditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if mode == .edit {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 260)
                } else {
                    MarkdownText(content)
                        .frame(minHeight: 260, alignment: .topLeading)
                }
            } header: {
                Text("Markdown 内容")
            }

            Section {
                Text("在「输入框快捷按钮」里新建按钮并绑定这个 Skill，就能决定它可以使用哪些工具、以及是否显示在聊天输入区。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("工具权限")
            }
        }
        .navigationTitle("自定义 Skill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        [name, description, whenToUse, content].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        AgentSkillRegistry.save(AgentCustomSkill(
            id: originalID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            whenToUse: whenToUse.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        dismiss()
    }
}

private enum AgentTraceFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case succeeded = "成功"
    case failed = "失败"

    var id: String {
        rawValue
    }
}

private struct AgentExecutionLogView: View {
    @State private var limit = 30
    @State private var filter: AgentTraceFilter = .all

    var body: some View {
        AgentExecutionLogPage(
            filter: $filter,
            limit: limit,
            onLoadMore: { limit += 30 }
        )
        .onChange(of: filter) { _, _ in limit = 30 }
    }
}

private struct AgentExecutionLogPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var loadedTraces: [AgentTrace]
    @Binding var filter: AgentTraceFilter
    let limit: Int
    let onLoadMore: () -> Void

    init(
        filter: Binding<AgentTraceFilter>,
        limit: Int,
        onLoadMore: @escaping () -> Void
    ) {
        let baseDescriptor: FetchDescriptor<AgentTrace> = switch filter.wrappedValue {
        case .all:
            FetchDescriptor(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        case .succeeded:
            FetchDescriptor(
                predicate: #Predicate { $0.statusRaw == "succeeded" },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        case .failed:
            FetchDescriptor(
                predicate: #Predicate {
                    $0.statusRaw == "failed" || $0.statusRaw == "cancelled"
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        }
        var descriptor = baseDescriptor
        descriptor.fetchLimit = limit + 1
        _loadedTraces = Query(descriptor)
        _filter = filter
        self.limit = limit
        self.onLoadMore = onLoadMore
    }

    private var traces: [AgentTrace] {
        Array(loadedTraces.prefix(limit))
    }

    private var hasMore: Bool {
        loadedTraces.count > limit
    }

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $filter) {
                    ForEach(AgentTraceFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if traces.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "暂无执行日志" : "没有\(filter.rawValue)日志",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("发送消息并完成一次 Agent Loop 后，这里会生成对应 Trace。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(traces) { trace in
                        NavigationLink {
                            AgentTraceDetailView(trace: trace)
                        } label: {
                            AgentTraceRow(trace: trace)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(trace)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除执行日志")
                            .tint(.red)
                        }
                    }
                    if hasMore {
                        Button("加载更多", action: onLoadMore)
                            .frame(maxWidth: .infinity)
                            .accessibilityHint("每次再加载 30 条执行日志")
                    }
                } footer: {
                    Text("Trace 只保存在当前数据空间。日志不包含 API Key、Authorization 头或图片 Base64。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("执行日志")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AgentTraceRow: View {
    let trace: AgentTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(TraceStyle.color(for: trace.status))
                    .frame(width: 7, height: 7)
                Text("\(trace.status.title) · Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TraceStyle.color(for: trace.status))
                Spacer(minLength: 8)
                if let duration = trace.durationMilliseconds {
                    Text(TraceStyle.duration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(trace.userInput)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 4)
            }

            Text("\(trace.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(trace.provider)/\(trace.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct AgentTraceDetailView: View {
    let trace: AgentTrace

    private var timelineEntries: [AgentTraceTimelineEntry] {
        var kindCounts: [AgentTraceSpanKind: Int] = [:]
        return trace.spans.map { span in
            let nextOrdinal = kindCounts[span.kind, default: 0] + 1
            kindCounts[span.kind] = nextOrdinal
            return AgentTraceTimelineEntry(
                span: span,
                ordinal: nextOrdinal,
                traceStartedAt: trace.startedAt
            )
        }
    }

    private var diagnosticSpan: AgentTraceSpan? {
        trace.spans.first {
            [.failed, .cancelled].contains($0.status) && $0.kind != .output
        } ?? trace.spans.first {
            [.failed, .cancelled].contains($0.status)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AppCard {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(TraceStyle.color(for: trace.status).opacity(0.13))
                            Image(systemName: TraceStyle.icon(for: trace.status))
                                .font(.title2)
                                .foregroundStyle(TraceStyle.color(for: trace.status))
                        }
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(TraceStyle.detailTitle(for: trace.status))
                                .font(.title3.bold())
                            HStack(spacing: 5) {
                                if let duration = trace.durationMilliseconds {
                                    Text("耗时 \(TraceStyle.duration(duration))")
                                } else {
                                    Text("正在执行")
                                }
                                Text("·")
                                Text("\(trace.spans.count) 个 Span")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            Text("\(trace.provider)/\(trace.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                tracePreviewCard(
                    title: "输入预览",
                    icon: "text.bubble",
                    text: trace.userInput,
                    detail: mediaDescription
                )

                if trace.status == .succeeded, let finalAnswer = trace.finalAnswer {
                    tracePreviewCard(
                        title: "结果预览",
                        icon: "checkmark.bubble.fill",
                        text: finalAnswer,
                        color: AppTheme.tint
                    )
                }

                if [.failed, .cancelled].contains(trace.status),
                   let errorMessage = trace.errorMessage
                {
                    traceErrorCard(errorMessage)
                }

                Text("执行时间线 (\(trace.spans.count))")
                    .font(.title3.bold())
                    .padding(.horizontal, 2)

                AppCard {
                    if timelineEntries.isEmpty {
                        Text("本次执行没有生成 Span。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(timelineEntries) { entry in
                                AgentTraceSpanRow(
                                    entry: entry,
                                    provider: trace.provider,
                                    model: trace.model
                                )
                                if entry.id != timelineEntries.last?.id {
                                    Divider()
                                        .padding(.leading, 42)
                                }
                            }
                        }
                    }
                }

                AppCard {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            traceMetadata("开始", trace.startedAt.formatted(date: .long, time: .standard))
                            traceMetadata("平台", trace.provider)
                            traceMetadata("模型", trace.model)
                            traceMetadata("Endpoint", trace.endpoint)
                            traceMetadata("Trace ID", trace.id.uuidString)
                            if !trace.contextSnapshot.isEmpty {
                                Divider()
                                Text("本地上下文快照")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(trace.contextSnapshot)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        Label("运行信息", systemImage: "info.circle")
                            .font(.headline)
                    }
                    .tint(.secondary)
                }

                Label(
                    "日志仅保存在当前数据空间，不包含 API Key、Authorization 头或图片 Base64。",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .appPageBackground()
        .navigationTitle("执行详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func traceMetadata(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var mediaDescription: String? {
        guard trace.mediaKind != .none else { return nil }
        var parts: [String] = []
        if trace.imageAttachmentCount > 0 {
            parts.append("\(trace.imageAttachmentCount) 张图片")
        }
        if trace.videoAttachmentCount > 0 {
            parts.append("\(trace.videoAttachmentCount) 个视频")
        }
        if parts.isEmpty {
            parts.append(trace.mediaKind == .video ? "视频" : "图片")
        }
        parts.append("\(trace.imageCount) 个分析帧")
        return parts.joined(separator: " · ")
    }

    private func tracePreviewCard(
        title: String,
        icon: String,
        text: String,
        detail: String? = nil,
        color: Color = .primary
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func traceErrorCard(_ errorMessage: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("错误详情", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.subheadline)
                    .textSelection(.enabled)
                if let diagnosticSpan {
                    Text("失败于：\(TraceStyle.displayTitle(for: diagnosticSpan, ordinal: timelineOrdinal(for: diagnosticSpan)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timelineOrdinal(for span: AgentTraceSpan) -> Int {
        timelineEntries.first(where: { $0.id == span.id })?.ordinal ?? 1
    }
}

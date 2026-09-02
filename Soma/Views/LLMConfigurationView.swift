import SwiftUI

/// LLM 配置拥有自己的状态生命周期。设置根页不再为一个尚未打开的二级页面
/// 注册十余个 State/FocusState，也不会在第一次选择设置 Tab 时构造完整配置表单。
struct LLMConfigurationView: View {
    @Environment(AIService.self) private var ai
    @State private var modelTier: AIModelTier = .standard
    @State private var smallModelEnabled = false
    @State private var provider: AIProvider = .openAI
    @State private var baseURL = ""
    @State private var model = ""
    @State private var imageModel = ""
    @State private var apiKey = ""
    @State private var extraConfig = ""
    @State private var extraConfigError: String?
    @State private var extraConfigSaved = false
    @State private var models: [AIModelInfo] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var keySaved = false
    @State private var showKey = false
    @State private var didLoadConfiguration = false
    @FocusState private var modelFieldFocused: Bool

    let showsAIConfigurationReminder: Bool

    private var selectedCapabilityAssessment: MultimodalCapabilityAssessment {
        models.first(where: { $0.id == model })?.multimodalAssessment
            ?? ai.modelMultimodalAssessment(
                provider: provider,
                baseURL: baseURL,
                model: model
            )
    }

    private var selectedCapability: MultimodalSupport {
        selectedCapabilityAssessment.support
    }

    var body: some View {
        Form {
            if showsAIConfigurationReminder {
                AIConfigurationReminder()
            }
            llmSections
        }
        .navigationTitle("LLM 配置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await Task.yield()
            loadInitialConfiguration()
        }
        .task(id: "\(didLoadConfiguration).\(modelTier.rawValue).\(provider.rawValue)") {
            guard didLoadConfiguration, !apiKey.isEmpty else { return }
            await refreshModels()
        }
        .onChange(of: smallModelEnabled) {
            ai.setTierEnabled(smallModelEnabled, tier: .small)
        }
        .onDisappear {
            ai.notifyConfigurationChanged()
        }
    }

    /// ADR 0046：配置页不折叠配置本身。两档在顶部分段切换，
    /// 平台、Base URL、API Key 与模型同屏可见可改，改动即时落盘。
    @ViewBuilder
    private var llmSections: some View {
        Section {
            Picker("模型档位", selection: modelTierBinding) {
                ForEach(AIModelTier.allCases) { tier in
                    Text(tier.title).tag(tier)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            Text(
                modelTier == .standard
                    ? "标准模型负责所有含媒体、含业务写入和复杂纠错的任务，是聊天的能力下限。"
                    : "小模型可不配置。配置并启用后，Agent 只把短文本、无媒体且无业务写入意图的简单任务交给它。"
            )
        }

        Section {
            Picker("平台", selection: providerBinding) {
                ForEach(AIProvider.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            TextField("Base URL", text: $baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onChange(of: baseURL) { oldValue, newValue in
                    refreshDefaultExtraIfUnmodified(
                        previousBaseURL: oldValue,
                        previousModel: model,
                        newBaseURL: newValue,
                        newModel: model
                    )
                    persistConfiguration()
                }

            HStack {
                Group {
                    if showKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showKey ? "隐藏 API Key" : "显示 API Key")
            }

            Button {
                saveKeyAndRefresh()
            } label: {
                if isLoadingModels {
                    HStack {
                        ProgressView()
                        Text("正在获取模型…")
                    }
                } else {
                    Text(keySaved ? "保存并重新获取模型" : "保存并获取模型")
                }
            }
            .disabled(
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isLoadingModels
            )
        } header: {
            Text("平台与凭据")
        } footer: {
            Text("Base URL 会按所选平台预填，可以改成自建或代理地址。API Key 只保存在本机 Keychain。")
        }

        modelSection

        extraConfigSection

        if modelTier == .standard {
            Section {
                TextField("例如 gpt-image-2", text: $imageModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: imageModel) { persistConfiguration() }
            } header: {
                Text("图片生成模型")
            } footer: {
                Text("留空表示不启用。动作图片只在动作详情主动点击生成时请求。")
            }
        } else {
            Section {
                Toggle("启用小模型", isOn: $smallModelEnabled)
                    .appToggleStyle()
            } footer: {
                Text("关闭时所有任务都走标准模型，这里的配置会被保留。")
            }
        }
    }

    /// ADR 0046：模型是纯输入框，`/models` 结果只作为输入历史式建议。
    private var modelSection: some View {
        Section {
            TextField("输入模型 ID", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($modelFieldFocused)
                .onChange(of: model) { oldValue, newValue in
                    refreshDefaultExtraIfUnmodified(
                        previousBaseURL: baseURL,
                        previousModel: oldValue,
                        newBaseURL: baseURL,
                        newModel: newValue
                    )
                    persistConfiguration()
                }

            if showsModelSuggestions {
                InputSuggestionList(
                    items: modelSuggestions,
                    selectionHint: "填入模型输入框",
                    scrollAfter: 5
                ) { item in
                    model = item.id
                    modelFieldFocused = false
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if isLoadingModels {
                LabeledContent("可用模型") {
                    ProgressView().controlSize(.small)
                }
            }

            if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                capabilityRow
            }

            if let modelError {
                Label(modelError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
            }
        } header: {
            Text("模型")
        } footer: {
            Text(modelFooterText)
        }
    }

    private var extraConfigSection: some View {
        Section {
            JSONEditorView(text: $extraConfig, minHeight: 180)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if let extraConfigError {
                Label(extraConfigError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
            }

            Button(extraConfigSaved ? "已保存 Extra Config" : "保存 Extra Config") {
                saveExtraConfig()
            }
        } header: {
            Text("Extra Config")
        } footer: {
            Text("默认显示当前厂商关闭思考推理的字段；你可以直接修改。清空并保存会恢复默认，保存 {} 表示不附加任何扩展字段。不能覆盖 messages、stream 或 stream_options。")
        }
    }

    private var modelFooterText: String {
        if models.isEmpty {
            return "可以直接输入平台的模型 ID。保存 API Key 后 Soma 会尝试拉取 /models，成功时在输入框下方给出候选。"
        }
        return "点选候选或直接输入都可以，输入的值会立即保存，重新拉取候选不会覆盖它。"
    }

    private var showsModelSuggestions: Bool {
        modelFieldFocused && !modelSuggestions.isEmpty
    }

    /// 候选行只给模型 ID：能力标注在选定之后由下方那一行说明，不在每行重复。
    private var modelSuggestions: [InputSuggestionItem] {
        let query = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty
            ? models
            : models.filter { $0.id.localizedCaseInsensitiveContains(query) }
        if matched.count == 1, matched[0].id == query {
            return []
        }
        return matched.map { option in
            InputSuggestionItem(id: option.id, title: option.id, icon: "cpu")
        }
    }

    /// 模型名不是能力证据；能力结论和实际来源一起显示。
    private var capabilityRow: some View {
        HStack(spacing: 8) {
            Image(systemName: capabilityIcon)
                .foregroundStyle(capabilityColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCapability.label)
                    .font(.footnote)
                    .foregroundStyle(
                        selectedCapability == .unsupported
                            ? AppTheme.warning
                            : .secondary
                    )
                Text(selectedCapabilityAssessment.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var capabilityIcon: String {
        switch selectedCapability {
        case .supported: "photo.badge.checkmark"
        case .unsupported: "photo.badge.exclamationmark"
        case .unknown: "questionmark.circle"
        }
    }

    private var capabilityColor: Color {
        switch selectedCapability {
        case .supported: AppTheme.success
        case .unsupported: AppTheme.warning
        case .unknown: .secondary
        }
    }

    /// 只在首次出现时载入，避免子页自身的状态刷新覆盖刚完成的编辑。
    private func loadInitialConfiguration() {
        guard !didLoadConfiguration else { return }
        didLoadConfiguration = true
        smallModelEnabled = ai.isTierEnabled(.small)
        loadTierConfiguration(.standard)
    }

    private var modelTierBinding: Binding<AIModelTier> {
        Binding(
            get: { modelTier },
            set: { newTier in
                guard newTier != modelTier else { return }
                modelFieldFocused = false
                modelTier = newTier
                loadTierConfiguration(newTier)
            }
        )
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { provider },
            set: { newProvider in
                guard newProvider != provider else { return }
                modelFieldFocused = false
                provider = newProvider
                loadProviderConfiguration()
            }
        )
    }

    private func loadTierConfiguration(_ tier: AIModelTier) {
        applyConfigurationDraft(
            SettingsLLMConfigurationDraft.load(from: ai, tier: tier)
        )
    }

    private func loadProviderConfiguration() {
        applyConfigurationDraft(
            SettingsLLMConfigurationDraft.load(
                from: ai,
                tier: modelTier,
                provider: provider
            )
        )
    }

    private func applyConfigurationDraft(_ draft: SettingsLLMConfigurationDraft) {
        provider = draft.provider
        baseURL = draft.baseURL
        model = draft.model
        imageModel = draft.imageModel
        apiKey = draft.apiKey
        extraConfig = draft.extraConfig
        extraConfigError = nil
        extraConfigSaved = false
        models = []
        modelError = nil
        keySaved = !apiKey.isEmpty
    }

    private func saveExtraConfig() {
        do {
            let normalized = try AIExtraConfig.validatedJSON(extraConfig)
            try ai.saveExtraConfig(normalized, for: baseURL)
            extraConfig = normalized.isEmpty
                ? ai.effectiveExtraConfig(baseURL: baseURL, model: model)
                : normalized
            extraConfigError = nil
            extraConfigSaved = true
        } catch {
            extraConfigError = error.localizedDescription
            extraConfigSaved = false
        }
    }

    private func refreshDefaultExtraIfUnmodified(
        previousBaseURL: String,
        previousModel: String,
        newBaseURL: String,
        newModel: String
    ) {
        let previousDefault = AIThinkingExtraConfig.defaultJSON(
            baseURL: previousBaseURL,
            model: previousModel
        )
        guard extraConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || AIExtraConfig.jsonEquals(extraConfig, previousDefault)
        else { return }
        extraConfig = ai.effectiveExtraConfig(
            baseURL: newBaseURL,
            model: newModel
        )
        extraConfigSaved = false
    }

    private func persistConfiguration(
        tier: AIModelTier? = nil,
        provider configuredProvider: AIProvider? = nil
    ) {
        ai.configure(
            tier: tier ?? modelTier,
            provider: configuredProvider ?? provider,
            baseURL: baseURL,
            model: model
        )
        if (tier ?? modelTier) == .standard {
            ai.configureImageModel(
                imageModel,
                for: configuredProvider ?? provider
            )
        }
    }

    private func saveKeyAndRefresh() {
        persistConfiguration()
        ai.saveAPIKey(apiKey, for: provider, tier: modelTier)
        keySaved = true
        Task { await refreshModels() }
    }

    @MainActor
    private func refreshModels() async {
        let requestedProvider = provider
        let requestedBaseURL = baseURL
        let requestedAPIKey = apiKey
        isLoadingModels = true
        modelError = nil
        defer {
            if provider == requestedProvider {
                isLoadingModels = false
            }
        }

        do {
            let fetched = try await ai.fetchAvailableModels(
                provider: requestedProvider,
                baseURL: requestedBaseURL,
                apiKey: requestedAPIKey
            )
            try Task.checkCancellation()
            guard provider == requestedProvider else { return }
            models = fetched
            // ADR 0046：刷新候选不覆盖已填写的模型，只在为空时补一个默认值。
            guard model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let suggested = fetched.first(where: {
                      $0.multimodalSupport == .supported
                  }) ?? fetched.first
            else {
                return
            }
            model = suggested.id
            persistConfiguration()
        } catch {
            guard !Task.isCancelled, provider == requestedProvider else { return }
            models = []
            modelError = error.localizedDescription
        }
    }
}

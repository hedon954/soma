import Foundation

extension Notification.Name {
    /// ADR 0045：LLM 配置变化是暂存补偿消费的唤醒信号之一。
    static let llmConfigurationDidChange = Notification.Name(
        "Soma.llmConfigurationDidChange"
    )
}

extension AIService {
    var provider: AIProvider {
        get {
            guard let value = defaults.string(forKey: providerDefaultsKey(for: .standard)),
                  let provider = AIProvider(rawValue: value)
            else {
                return .openAI
            }
            return provider
        }
        set { setProvider(newValue, for: .standard) }
    }

    func baseURL(for provider: AIProvider) -> String {
        baseURL(for: provider, tier: .standard)
    }

    func model(for provider: AIProvider) -> String {
        model(for: provider, tier: .standard)
    }

    func configure(provider: AIProvider, baseURL: String, model: String) {
        configure(
            tier: .standard,
            provider: provider,
            baseURL: baseURL,
            model: model
        )
    }

    func provider(for tier: AIModelTier) -> AIProvider {
        guard let value = defaults.string(forKey: providerDefaultsKey(for: tier)),
              let provider = AIProvider(rawValue: value)
        else {
            return .openAI
        }
        return provider
    }

    func setProvider(_ provider: AIProvider, for tier: AIModelTier) {
        defaults.set(provider.rawValue, forKey: providerDefaultsKey(for: tier))
    }

    func baseURL(for provider: AIProvider, tier: AIModelTier) -> String {
        defaults.string(forKey: baseURLDefaultsKey(for: provider, tier: tier))
            ?? provider.defaultBaseURL
    }

    func model(for provider: AIProvider, tier: AIModelTier) -> String {
        defaults.string(forKey: modelDefaultsKey(for: provider, tier: tier))
            ?? provider.fallbackModel
    }

    func configure(
        tier: AIModelTier,
        provider: AIProvider,
        baseURL: String,
        model: String
    ) {
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = normalizedBaseURL.isEmpty
            ? provider.defaultBaseURL
            : normalizedBaseURL
        let resolvedModel = normalizedModel.isEmpty
            ? provider.fallbackModel
            : normalizedModel
        setProvider(provider, for: tier)
        defaults.set(
            resolvedBaseURL,
            forKey: baseURLDefaultsKey(for: provider, tier: tier)
        )
        defaults.set(
            resolvedModel,
            forKey: modelDefaultsKey(for: provider, tier: tier)
        )
    }

    func imageModel(for provider: AIProvider) -> String {
        defaults.string(forKey: "ai.image.model.\(provider.rawValue)")
            ?? (provider == .openAI ? "gpt-image-2" : "")
    }

    func configureImageModel(_ model: String, for provider: AIProvider) {
        defaults.set(
            model.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: "ai.image.model.\(provider.rawValue)"
        )
    }

    func saveAPIKey(_ key: String, for provider: AIProvider) {
        saveAPIKey(key, for: provider, tier: .standard)
    }

    func apiKey(for provider: AIProvider) -> String {
        apiKey(for: provider, tier: .standard)
    }

    func saveAPIKey(
        _ key: String,
        for provider: AIProvider,
        tier: AIModelTier
    ) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = apiKey(for: provider, tier: tier) != normalized
        KeychainStore.save(
            normalized,
            for: keychainAccount(for: provider, tier: tier)
        )
        if changed {
            notifyConfigurationChanged()
        }
    }

    func apiKey(for provider: AIProvider, tier: AIModelTier) -> String {
        apiKeyOverride
            ?? KeychainStore.read(keychainAccount(for: provider, tier: tier))
            ?? ""
    }

    func isTierEnabled(_ tier: AIModelTier) -> Bool {
        tier == .standard || defaults.bool(forKey: "ai.profile.small.enabled")
    }

    func setTierEnabled(_ enabled: Bool, tier: AIModelTier) {
        guard tier == .small else { return }
        let changed = defaults.bool(forKey: "ai.profile.small.enabled") != enabled
        defaults.set(enabled, forKey: "ai.profile.small.enabled")
        if changed {
            notifyConfigurationChanged()
        }
    }

    /// ADR 0045：唤醒暂存补偿。逐字符编辑地址或模型时不广播——半截配置发起请求
    /// 只会把 Job 推进无谓的退避，改由保存 Key、切换档位或离开配置页时统一通知。
    func notifyConfigurationChanged() {
        NotificationCenter.default.post(
            name: .llmConfigurationDidChange,
            object: nil
        )
    }

    func route(
        text: String,
        hasMedia: Bool,
        hasVideo: Bool
    ) -> AIModelRoute {
        let standard = modelRoute(for: .standard, reason: "标准模型兜底")
        let small = modelRoute(
            for: .small,
            reason: "短文本、无媒体且无业务写入意图"
        )
        guard isTierEnabled(.small),
              !apiKey(for: small.provider, tier: .small).isEmpty,
              !small.baseURL.isEmpty,
              !small.model.isEmpty,
              !requiresStandardModel(
                  text: text,
                  hasMedia: hasMedia,
                  hasVideo: hasVideo
              )
        else {
            return standard
        }
        return small
    }

    var selectedModelMultimodalSupport: MultimodalSupport {
        ModelCapability.multimodalSupport(
            provider: provider,
            model: model(for: provider)
        )
    }

    var hasRequiredAPIKey: Bool {
        !apiKey(for: provider(for: .standard), tier: .standard)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func resolvedRoute(
        requested: AIModelRoute?,
        text: String,
        hasMedia: Bool,
        hasVideo: Bool
    ) throws -> (route: AIModelRoute, apiKey: String) {
        let selected = requested ?? route(
            text: text,
            hasMedia: hasMedia,
            hasVideo: hasVideo
        )
        let key = apiKey(for: selected.provider, tier: selected.tier)
        guard !key.isEmpty else {
            throw AIServiceError.missingAPIKey(selected.provider.displayName)
        }
        return (selected, key)
    }

    private func modelRoute(
        for tier: AIModelTier,
        reason: String
    ) -> AIModelRoute {
        let provider = provider(for: tier)
        return AIModelRoute(
            tier: tier,
            provider: provider,
            baseURL: baseURL(for: provider, tier: tier),
            model: model(for: provider, tier: tier),
            reason: reason
        )
    }

    private func requiresStandardModel(
        text: String,
        hasMedia: Bool,
        hasVideo: Bool
    ) -> Bool {
        let normalized = text.lowercased()
        return hasMedia
            || hasVideo
            || text.count > 280
            || [
                "分析", "比较", "计划", "纠正", "更正", "为什么", "风险",
                "疼", "痛", "受伤", "删除", "更新", "记录", "训练", "饮食",
                "analyze", "compare", "plan", "update", "delete"
            ].contains(where: normalized.contains)
    }

    private func providerDefaultsKey(for tier: AIModelTier) -> String {
        tier == .standard ? "ai.provider" : "ai.profile.small.provider"
    }

    private func baseURLDefaultsKey(
        for provider: AIProvider,
        tier: AIModelTier
    ) -> String {
        tier == .standard
            ? provider.baseURLDefaultsKey
            : "ai.profile.small.baseURL.\(provider.rawValue)"
    }

    private func modelDefaultsKey(
        for provider: AIProvider,
        tier: AIModelTier
    ) -> String {
        tier == .standard
            ? provider.modelDefaultsKey
            : "ai.profile.small.model.\(provider.rawValue)"
    }

    private func keychainAccount(
        for provider: AIProvider,
        tier: AIModelTier
    ) -> String {
        tier == .standard
            ? provider.keychainAccount
            : "ai.apiKey.small.\(provider.rawValue)"
    }
}

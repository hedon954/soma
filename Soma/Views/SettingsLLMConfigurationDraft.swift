import Foundation

/// 所有设置入口都从同一个 `AIService` 事实源创建草稿，避免独立页面以默认值开场。
struct SettingsLLMConfigurationDraft: Equatable {
    let provider: AIProvider
    let baseURL: String
    let model: String
    let imageModel: String
    let apiKey: String
    let extraConfig: String

    @MainActor
    static func load(
        from ai: AIService,
        tier: AIModelTier,
        provider requestedProvider: AIProvider? = nil
    ) -> Self {
        let provider = requestedProvider ?? ai.provider(for: tier)
        return Self(
            provider: provider,
            baseURL: ai.baseURL(for: provider, tier: tier),
            model: ai.model(for: provider, tier: tier),
            imageModel: ai.imageModel(for: provider),
            apiKey: ai.apiKey(for: provider, tier: tier),
            extraConfig: ai.effectiveExtraConfig(
                baseURL: ai.baseURL(for: provider, tier: tier),
                model: ai.model(for: provider, tier: tier)
            )
        )
    }
}

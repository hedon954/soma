import Foundation

extension AppErrorMessage {
    static func modelMessage(status: Int?, response: String) -> String? {
        let text = response.lowercased()
        if let status, (500 ..< 600).contains(status) {
            return "模型服务暂时出现故障。请稍后重试；已经保存的记录仍保留。"
        }
        if status == 401 || status == 403 {
            return "模型服务拒绝了当前授权。请在设置的「LLM 配置」中检查 API Key 和该模型的使用权限后重试。"
        }
        let quota = ["insufficient_quota", "quota_exhausted", "credit balance", "billing", "余额不足", "额度已用尽", "欠费"]
        if status == 402 || quota.contains(where: text.contains) {
            return "模型服务的可用额度或余额已用尽。请到服务提供方补充额度，或在设置中更换模型服务后重试。"
        }
        if status == 429 || text.contains("rate_limit") || text.contains("rate limit") {
            return "模型服务当前请求过多。请稍后重试，或在设置中更换模型服务。"
        }
        if text.contains("invalid_api_key") || text.contains("invalid api key") || text.contains("incorrect api key") {
            return "模型密钥无效或已过期。请在设置的「LLM 配置」中更新 API Key 后重试。"
        }
        let context = ["context_length", "context length", "maximum context", "too many tokens", "token limit"]
        if status == 413 || context.contains(where: text.contains) {
            return "这次内容超过模型可处理的长度或大小。请减少附件、缩短描述，或新建一个会话后分开发送。"
        }
        let unsupported = ["unknown variant", "unsupported", "not support", "doesn't support", "not allowed", "不支持"]
            .contains(where: text.contains)
        if unsupported, text.contains("video_url") || text.contains("video input") || text.contains("不支持视频") {
            return "当前模型不支持这次视频输入，未能完成分析。请更换支持视频或图片的模型后重试；原视频仍保留。"
        }
        if unsupported, text.contains("image_url") || text.contains("image input") || text.contains("vision") {
            return "当前模型不支持图片分析。请在设置中更换支持图片的模型后重试；原附件仍保留。"
        }
        if status == 404 || text.contains("model_not_found") || text.contains("model not found") {
            return "找不到所选模型或服务地址。请在设置的「LLM 配置」中刷新模型列表，并检查服务地址后重试。"
        }
        if text.contains("content_filter") || text.contains("safety check") || text.contains("moderation") {
            return "模型服务未接受这次内容。请检查文字或附件是否适合该服务，再调整内容后重试。"
        }
        if status == 400 || status == 415 || status == 422 {
            return "模型服务不接受这次请求的格式或参数。请检查模型配置，或更换模型后重试。"
        }
        if status == 408 {
            return "模型服务等待超时。请检查网络后重试，或稍后再试。"
        }
        return nil
    }
}

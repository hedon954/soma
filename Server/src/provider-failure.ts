import { ProtocolError } from "./domain.js";

/** Classify bounded in-memory provider responses; never persist the raw response. */
export function providerFailure(status: number, raw: string): ProtocolError {
  const text = raw.toLowerCase();
  if (status >= 500) return new ProtocolError("provider_unavailable", "模型服务暂时出现故障，请稍后重试。", status);
  if (status === 401 || status === 403) return new ProtocolError("provider_authentication_failed", "模型服务授权失败，请检查模型凭据与权限。", status);
  if (status === 402 || ["insufficient_quota", "quota_exhausted", "credit balance", "billing", "余额不足", "欠费"]
    .some((value) => text.includes(value))) {
    return new ProtocolError("provider_quota_exhausted", "模型服务额度已用尽，请补充额度或更换服务。", status);
  }
  if (status === 429) return new ProtocolError("provider_rate_limited", "模型请求过多，请稍后重试。", status);
  if (status === 413 || ["context_length", "context length", "maximum context", "too many tokens", "token limit"]
    .some((value) => text.includes(value))) {
    return new ProtocolError("provider_context_exceeded", "请求内容过长或过大，请减少附件并分开发送。", status);
  }
  if ([400, 415, 422].includes(status) &&
      ["unsupported", "not support", "unknown variant", "不支持"].some((value) => text.includes(value)) &&
      ["image_url", "image input", "vision"].some((value) => text.includes(value))) {
    return new ProtocolError("provider_vision_unsupported", "模型不支持图片，请更换支持视觉的模型。", status);
  }
  if ([400, 404, 415, 422].includes(status)) {
    return new ProtocolError("provider_configuration_invalid", "模型地址、名称或请求参数不可用，请检查配置。", status);
  }
  if (status === 408) return new ProtocolError("provider_timeout", "模型等待超时，请重试。", status);
  return new ProtocolError("provider_unavailable", "模型服务暂时不可用，请稍后重试。", status);
}

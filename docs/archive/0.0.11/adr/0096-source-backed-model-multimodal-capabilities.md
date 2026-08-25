# ADR 0096：模型多模态能力必须由明确来源证明

- 状态：已采纳
- 日期：2026-08-23
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 中按平台和模型名称保守标注能力的决定
- 上游依据：[BUG 0033](../../../bugs/0033-model-name-multimodal-misclassification.md)

## 背景

模型 ID 是供应商可自由命名的字符串。`vision`、`vl`、版本号或平台名称既不能证明支持图片/视频，
也不能证明不支持。旧实现把 DeepSeek 一律判为不支持，并维护 Qwen 直传视频名前缀白名单，导致新模型
和实验模型在没有事实来源时被错误拦截，配置页还把推断结果显示成确定事实。

## 决策

1. provider、Base URL 和模型名都不是多模态能力证据；代码不得按名称包含关系、前缀、后缀或固定
   模型清单返回支持或不支持。
2. 客户端只读取所配置平台 `/models` 响应中明确的能力元数据，包括输入模态数组或明确视觉布尔值，
   并保存实际字段路径作为来源。支持与不支持都必须能展示来源。
3. 平台没有返回明确字段、字段为空或模型只由用户手输时，能力为 `unknown`。未知不会在发送前拦截
   图片或关键帧；由真实平台请求验证，失败保留原始原因与 Trace。
4. 只有输入模态明确包含 `video` 时，本地才允许直传视频；图片能力不能推导出视频能力。固定 7 MB
   与 MP4 是 Soma 自身传输限制，不是模型能力证据。
5. 远程 Worker 无法读取用户配置页的模型目录，直传视频默认关闭。只有部署者根据明确供应商资料设置
   `SOMA_PROVIDER_SUPPORTS_DIRECT_VIDEO=true` 时，API 与 Worker 才共同宣布并使用该能力；不得从
   `SOMA_PROVIDER_MODEL` 推断。
6. 能力缓存按 provider、规范化 Base URL 与精确模型 ID 隔离；刷新模型目录可更新来源，切换地址或
   模型不能复用旧证据。

## 结果

- `deepseek-v4-flash-vision-exp` 在平台未返回能力字段时显示“未知”，而不是被硬编码为不支持。
- 新模型不会因为命名方式被误拦；明确不支持的模型仍可在发送前给出可操作提示。
- 代价是部分平台永远显示未知，并把最终兼容性验证推迟到真实请求；这比伪造确定性更符合数据真值。

## 验证

- `LLMConfigurationTests` 覆盖 DeepSeek、OpenAI、百炼和 opencode 的名称均不能推断能力。
- `/models` fixture 覆盖明确图片/视频、明确纯文本、缺少字段三种结果，并验证来源字段与缓存隔离。
- Server 测试证明直传视频只由显式部署能力开关启用，模型名不再参与判断。

## 信息来源

- [DeepSeek API：Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing)
- [DeepSeek API：Anthropic API 兼容说明](https://api-docs.deepseek.com/guides/anthropic_api/)

# ADR 0025：使用双档模型配置与本地保守路由

- 状态：已接受
- 日期：2026-07-30
- 维护者：Soma maintainers

## 背景

当前远程 Agent 只有一套平台、Base URL 和模型。所有任务无论难度都使用同一模型，设置页又
在已有动态模型列表时同时展示手写框，增加选择噪音。用户还需要连接预设列表之外的
OpenAI-compatible 服务。

模型不能在开始请求后才“自主决定”自己应该是谁；路由必须发生在网络调用前，并在多模态、
Tool Calling、安全边界和失败升级上保持可测试。

## 决策

- 定义“小模型”和“标准”两个独立 `ModelProfile`。每档保存平台、Base URL、模型 ID 和能力
  快照；凭据以档位和端点身份存入 ThisDeviceOnly Keychain。
- 标准档是聊天发送的必配档，小模型可不配置。未配置标准档 API Key 时的发送前门禁见
  [ADR 0027](0027-required-ai-configuration-and-send-gate.md)；旧单模型配置确定性迁移到标准档。
- 平台增加“其他（OpenAI-compatible）”。它要求用户输入有效 HTTPS Base URL，并继续使用
  Chat Completions、流式 SSE 和原生 Tool Calling 子集。
- `/models` 返回非空可用列表时只使用 Picker；只有列表为空或获取失败时显示手动模型 ID。
- 每个 Profile 独立保存平台、URL、模型和 Keychain 凭据。媒体固定使用标准档，并由已知
  平台能力矩阵选择图片、内联视频或关键帧；其他平台保持未知并由真实请求验证。
- App 根层的本地 `ModelRouter` 在每个 Attempt 开始前选择档位：
  - 无小模型时选择标准；
  - 当前含媒体、多个意图、复杂纠错、安全敏感建议或需要更高能力时选择标准；
  - 明确、低风险、单意图的文字任务可选择小模型。
- 小模型缺失或任务包含媒体、写入、复杂纠错和安全敏感语义时直接使用标准档。标准档的
  视频能力再决定内联视频或关键帧。
- Trace 记录档位、端点显示名、模型和路由原因，不记录 API Key 或 Authorization 头。
- 路由由本地规则和可测试能力矩阵控制，用户提示词不能强制绕过标准档、安全边界或工具协议。

## 未选择的方案

- 让当前模型在提示词中选择另一个模型：调用前无法生效，也不可可靠审计。
- 所有任务固定标准模型：实现简单但无法满足成本与延迟分档。
- 小模型必配：增加首次设置阻力，且没有小模型时标准档已经能完整工作。
- 有动态列表时仍常驻手写框：重复控件并容易保存不在列表中的错误 ID。
- 在第一版自动跨平台竞价或测速：扩大网络、隐私和可预测性边界。

## 结果

### 正向影响

- 简单任务可降低延迟与成本，复杂和多模态任务保持能力下限。
- 自定义 OpenAI-compatible 端点成为正式配置，而不是冒充已知平台。
- 每次模型选择和升级都可在 Trace 中解释。

### 成本与限制

- 设置、Keychain、模型列表缓存、迁移和 Trace 都需要支持两个 Profile。
- 任务复杂度判断可能保守地多用标准模型，但不能冒险把高风险任务降档。
- “其他”平台的兼容性仍需由真实请求验证，Soma 不保证供应商完整实现协议。

## 验证

- 覆盖旧配置继续作为标准档、小模型为空、已知平台和其他 URL 校验。
- `/models` 成功时只见 Picker，空列表和失败时只见手写入口。
- 表驱动测试覆盖文字、图片、内联视频、关键帧降级、复杂纠错、安全敏感任务和能力不支持。

## 参考

- [PRD 008](../prd/008-coach-continuity-and-adaptive-models.md)
- [ADR 0003](0003-native-streaming-react-tool-calling.md)
- [ADR 0005](0005-trace-span-event-observability.md)
- [ADR 0024](0024-session-context-projection-and-compaction.md)
- [ADR 0027](0027-required-ai-configuration-and-send-gate.md)

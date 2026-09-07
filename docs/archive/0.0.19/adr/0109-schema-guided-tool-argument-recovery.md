# ADR 0109：Schema 驱动的 Tool 参数恢复

- 状态：已采纳
- 日期：2026-08-28
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的 Tool 参数失败处理与进展明细布局
- 后续替代：[ADR 0114](0114-progress-periods-and-adaptive-energy.md) 的四周期能量依据替代进展浮层；Tool 参数恢复仍有效
- 上游依据：
  - [PRD 051](../prd/051-self-healing-tool-arguments-and-wide-progress-disclosure.md)
  - [BUG 0044](../../../bugs/0044-tool-argument-type-mismatch-aborts-react.md)
- 下游落地：
  - [验收矩阵](../../../acceptance.md)

## 背景

Provider 的 strict Tool Calling 只能降低、不能消除参数类型漂移。原执行链先严格解码，再建立原生
assistant/tool 帧；因此类型错误会绕过协议已经要求的 Tool 错误回路。另一方面，直接放宽全部
`Codable` 字段会让单位和含混文本悄悄进入业务数据。

## 决策

1. 本地和远程共用相同语义：只按当轮已注册 JSON Schema 递归访问 object/array，在声明为
   `integer` 或 `number` 的位置尝试转换无单位的非负十进制字符串与简单分数。
2. integer 转换后必须仍为整数；零、上限与领域关系继续由既有 Schema validator 和业务 Store
   决定。无法转换的原值保持不变，让严格校验给出确定错误。
3. 已知 Tool 的预执行参数错误生成 `invalid_tool_arguments` envelope，包含 `field`、`expected`、
   `retryable=true`，连同原生 `tool_call_id` 追加为 `role: tool`。该失败也进入 step 检查点，恢复时
   不会重新执行或丢失 assistant/tool 配对。
4. 远程 Worker 对参数错误写入 completed Tool Event 并重新排队，使下一模型步骤读到同一错误；未知
   Tool、Schema 版本不匹配、路径/URL/密钥等安全拒绝仍终止任务，不降级成可重试参数错误。
5. 进展浮层宽度取 `min(400, screenWidth - 24)`，小屏下限有界；组成行与公式默认单行，名称尾部
   截断、公式有限缩放，VoiceOver 保留完整字符串。

## 未选择的方案

- 不让每个 DTO 分别实现宽松 `init(from:)`；那会复制规则并让未声明字段绕过 Schema。
- 不把任何字符串都交给 Locale/单位解析器；工具执行不能从含混文本猜身体事实。
- 不原样重复同一无效调用；纠正必须由模型读取结构化错误后生成新参数。
- 不把浮层扩到 iPad 全宽，也不允许名称挤掉右侧数值。

## 结果

### 正向影响

- 常见兼容 Provider 类型漂移可以本地自愈；真正错误仍可被模型看见并在同一 Loop 内修正。
- 进展组成更接近账单式单行浏览，减少不必要的换行和卡片高度。

### 成本与限制

- 分数使用 Double 表达，显示与业务范围仍由下游规则负责；不支持带单位分数或中文分数。
- post-release App 代码与远程 Worker 需要共同部署，旧 Worker 仍可能把参数错误终止为远程失败。

## 验证

`AgentToolSchemaAssemblyTests`、`AgentReActLoopTests`、Server Worker 测试、
`SomaUILayoutContractTests`、`make server-test`、`make verify` 与双主题模拟器/真机检查。

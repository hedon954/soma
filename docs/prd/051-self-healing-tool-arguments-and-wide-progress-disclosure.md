# PRD 051：可自愈工具参数与宽幅进展明细

- 状态：已采纳，已实施；待真机交互验收
- 日期：2026-08-28
- 修订自：
  - [PRD 000](000-origin-through-0.0.11.md) 的严格 Tool 参数与 ReAct 错误回路
  - [PRD 050](050-lightweight-progress-disclosure-and-coach-controls.md) 的跟随式进展明细
- 后续修订：暂无
- 上游依据：
  - 维护者提供的真机参数失败与进展浮层截图
  - [BUG 0044](../bugs/0044-tool-argument-type-mismatch-aborts-react.md)
- 下游落地：[ADR 0109](../adr/0109-schema-guided-tool-argument-recovery.md)

## 背景

兼容 Provider 即使收到 strict Tool Schema，仍可能把 `record_id`、克数或分数写成 JSON 字符串。
本地解码此前在写入 `assistant.tool_calls` 之前直接抛错，模型收不到错误结果，用户只看到泛化的
“格式不正确”。进展明细浮层固定 300 pt，也让公式项和较长餐食名称过早换行。

## 用户结果

1. Tool 说明明确区分 JSON integer/number 与自然语言份量；分数必须先换算为小数。
2. 无单位的非负数字字符串和简单分数字符串可按已注册 Schema 安全转换后继续执行；无法确定的值
   不猜测、不写入。
3. 仍不合法的参数以带字段、预期类型和 `retryable` 的 `role: tool` 结果返回，模型在既有 ReAct
   步数预算内自行修正；只有后续仍无法完成时才进入用户可见失败。
4. 进展明细浮层在手机上尽量使用可用宽度，组成名称与数值保持单行；超长名称尾部截断，完整内容
   仍可由 VoiceOver 读取。

## 产品规则

- 归一化只由 App 注册的 Schema 驱动，只接受十进制数字和 `分子/分母`；不解析单位、中文数词、
  负数、非有限值或含混文本。
- integer 字段只接受换算后仍为整数的值。转换后继续经过现有范围、关系、授权和业务真值校验。
- 参数纠错不是网络自动重试，不突破人工失败屏障；它只是同一 ReAct Loop 内模型读取 Tool 错误后的
  下一步。
- 浮层最大宽度保持有界；小屏保留页面边距，iPad 不扩成横跨内容区的大卡。

## 数据与隐私

- 不新增 SwiftData 字段、PostgreSQL migration 或远程身体数据。
- 原始 Tool 参数仍只进入开发者 Trace；普通聊天不展示原始 JSON。

## 验收

- 本地与远程测试覆盖数字字符串、简单分数、嵌套数组、带单位拒绝，以及错误结果驱动下一轮模型调用。
- 375 pt、440 pt 手机宽度与 iPad 检查浮层边距、单行组成、公式缩放、滚动和 VoiceOver。
- `make server-test`、`make check`、`make verify` 通过；真机复现份量纠正时不再直接出现格式失败。

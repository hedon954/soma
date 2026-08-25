# ADR 0064：精确结构化快捷输入直写本地，最新回复提供原位审查

- 状态：部分已替代
- 日期：2026-08-13
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0027](../../0.0.1/adr/0027-required-ai-configuration-and-send-gate.md) 中所有教练发送都必须先具备可用 LLM 的边界
  - [ADR 0059](../../0.0.4/adr/0059-precise-tools-and-reviewable-meal-items.md) 中记录结果只投影为只读结果卡、修改进入详情页的边界
- 后续修订：[ADR 0077](../../0.0.7/adr/0077-same-turn-identity-merge-and-additive-inline-review.md) 原位卡与 Event Cards 共存，保存必须有可见确认
- 后续替代：
  - [ADR 0084](../../0.0.7/adr/0084-inline-meal-breakdown-and-derived-totals.md) 把饮食原位审查从整餐字段改为可编辑
    菜品拆解卡加派生汇总卡；确定性快捷直写与最新回复原位审查继续有效
- 下游落地：[BUG 0023](../../../bugs/0023-same-turn-multi-exercise-merged-into-one.md)
- 上游依据：[PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)

## 背景

最近训练建议的显示文本背后已经有稳定动作 ID 与逐组事实；将未修改文本再次交给 LLM 既浪费
成本，也可能把确定事实解释错。另一方面，Agent 写入后的识别结果最需要立即纠错，跳到记录页
打断聊天闭环。

## 决策

1. 建议携带 typed draft。trim 后文本完全一致且无附件时，创建 `deterministicWorkout` Job，直接
   执行固定写 Tool；任意编辑或媒体都回到 ReAct。
2. 确定性路径仍写 User Message、Trace、Tool Span、Assistant Event 和 record reference，使用
   发送执行时的实时 `.now`，不伪造模型调用。
3. 训练、饮食、身体、健身房 record reference 在来源 AI 回复下投影原位卡片。只有当前 Session
   最新 AI 回复可编辑；旧卡片只读。
4. 保存／删除直接操作稳定 record ID，并向来源 AI Message 追加有界 correction summary；下一轮
   上下文紧邻原回复投影该块，不重写历史 Tool 协议帧。
5. 删除需要显式确认；若记录已不存在，卡片诚实显示不可用，不重建。

## 未选择的方案

- 不从任意自由文本反解析结构化记录；不让所有历史 AI 卡片持续可编辑；不回写历史 Tool 帧。

## 结果

### 正向影响

- 无 API Key 也能完成精确快捷训练记录，但自由文本仍必须经过 Agent。
- 最新回复限制牺牲了聊天内长期编辑，换取可重放上下文和明确的一致性边界。

### 成本与限制

- 记录页继续承担完整历史 CRUD；聊天卡片不是第二套数据库。

## 验证

- 快捷建议、空 Key 直存、record reference 解析和下一轮 correction projection 使用确定性测试验证。

## 参考

- [PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)

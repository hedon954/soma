# BUG 0039：餐次和时长动作被模型参数改写

- 状态：已修复
- 发现日期：2026-08-26
- 影响范围：饮食餐次与聊天动作卡/训练记录单位
- 上游依据：维护者复现反馈
- 下游落地：
  - [PRD 046](../prd/046-coach-records-and-goal-directed-progress.md)
  - [ADR 0101](../adr/0101-record-truth-and-agent-profile-context.md)

## 症状

18 点发生的饮食可能被保存为午餐；按时长的动作在聊天卡显示“次数”。前者由模型提供的
`meal_type` 直接覆盖设备可确定的发生时间。

## 根因

餐次写入信任了模型参数；训练 `set_entries` 只有 `reps`，丢失动作定义已经存在的 `targetKind`。

## 修复

餐次先读取用户原文中的明确称呼，否则按 `occurred_at` 本地时钟确定；14–17 增加下午点心，
17–22 为晚餐。训练 Tool 每组支持互斥的 `reps` / `duration_seconds`，设备按动作定义归一化后保存，
卡片复用同一 formatter 显示次数或秒数。

## 回归门禁

- 自动化测试：`MealOccurrenceTimeTests` 固定 15:30、18:00 与明确补记午餐；
  `ConversationRecorderToolTests` 固定时长动作只保存秒数，不生成次数。
- 手工验收：聊天创建虚构晚餐和按时长动作，核对卡片餐次与秒数。
- 仍无法自动化的风险：不同 Dynamic Type 下动作卡的视觉密度需模拟器验收。

## 验证

`make test`、`make check`；Tool Schema 与数据库文档静态门禁通过。

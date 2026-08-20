# BUG 0026：饮食创建的整餐汇总覆盖菜品确定性求和

- 状态：已修复，待真机 Agent 复验
- 发现日期：2026-08-20
- 影响范围：`create_meal`、饮食菜品明细、营养汇总与聊天结果卡
- 上游依据：
  - [PRD 033](../prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)
  - [ADR 0084](../adr/0084-inline-meal-breakdown-and-derived-totals.md)
- 后续修订：暂无

## 症状

饮食卡已经能展示和编辑菜品清单，但当模型同时提交菜品和整餐数值时，写入路径会优先保留整餐
数值；当两者不一致时，聊天汇总卡与菜品求和出现两个事实源。

记录的 `date` 已正确使用 Job 冻结的发送时刻，这部分没有丢失钟点。

## 根因

`recordMeal` 仅在四个整餐营养字段全部省略时调用 `replaceItemsAndDeriveTotals`；只要模型多给出
一个整餐数值，就绕过
[ADR 0084](../adr/0084-inline-meal-breakdown-and-derived-totals.md) 的统一派生规则。

## 修复

- 只要记录包含菜品，`recordMeal` 一律调用 `replaceItemsAndDeriveTotals`；模型附带的整餐热量与宏量
  不再覆盖菜品事实。
- 历史记录、旧 Job 与无法可靠拆出菜品的请求仍可保留只有整餐汇总的兼容路径，不要求数据迁移；
  当前饮食 Skill 继续要求证据足够时提交有序菜品，无法识别时先询问用户。
- `sourceDate` 继续直接写入记录，保留原始 Turn 的时分秒。

## 回归门禁

- iOS 端到端 Tool 测试使用两道虚构菜品与故意冲突的整餐数值，要求保存两道菜、按菜品求和并保留
  指定发生时刻。
- 现有无菜品 Tool 回归继续通过，证明旧 Job 恢复路径未被收紧。
- `MealNutritionTotalsTests` 继续覆盖缺项保持 `nil`，不能用 0 补齐未知营养。

## 验证

- `AgentV2Tests`
- `MealNutritionTotalsTests`
- `make verify`
- 真机待验收：发送只含虚构内容的两道菜描述，确认第一张卡逐项展示，第二张卡等于逐项求和且时间
  为消息发送时刻。

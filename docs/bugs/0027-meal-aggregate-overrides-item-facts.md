# BUG 0027：Agent 创建饮食时整餐聚合值可覆盖菜品事实

- 状态：已修复，待真机 Agent 交互确认
- 发现日期：2026-08-21
- 影响范围：`create_meal`、`update_meal`、菜品编辑、饮食派生汇总
- 下游落地：
  - [PRD 036](../archive/0.0.9/prd/036-meal-sugar-and-glycemic-speed-estimate.md)
  - [ADR 0087](../archive/0.0.9/adr/0087-reviewable-total-sugar-and-glycemic-speed.md)

## 症状

同一次创建或更新同时提供有序菜品和整餐热量／宏量时，记录先从菜品派生汇总，随后又把模型给的
整餐聚合值写回。结果可能与菜品之和不一致，聊天评价卡和以后编辑得到的值也会跳变。

## 根因

创建路径把「菜品是事实来源」当成一次临时计算，而不是最终写入优先级。`replaceItemsAndDeriveTotals`
执行后仍无条件应用顶层聚合字段，形成两个可写事实源。

## 修复

- 先增加回归测试：两个虚构菜品之和必须成为记录与 Tool 返回值，不能被冲突的顶层值覆盖。
- 有菜品时，创建与更新路径始终以 `replaceItemsAndDeriveTotals` 的结果为准；只有没有菜品的旧式调用才使用
  顶层可选营养值。
- 升糖速度和依据不参与确定性求和，但替换菜品会使旧评估失效；同次合法成对输入可显式重建。

## 回归门禁

- `AgentV2Tests` 覆盖创建路径的菜品优先和结构化 Tool 结果。
- `MealNutritionTotalsTests` 覆盖完整字段求和与任一缺失保持为空。
- `make verify`；测试只使用虚构餐食。

# ADR 0084：饮食原位审查拆为可编辑菜品卡与派生汇总卡

- 状态：已采纳
- 日期：2026-08-20
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0064](0064-deterministic-quick-write-and-latest-inline-review.md) 中饮食原位审查只提供整餐字段、菜品编辑必须进入详情页的边界；确定性快捷直写与最新回复原位审查继续有效
  - [ADR 0077](0077-same-turn-identity-merge-and-additive-inline-review.md) 中一条记录只投影一张原位卡的呈现边界；原位卡与 Event Cards 共存、保存必须可见确认继续有效
- 后续修订：暂无
- 修订自：
  - [ADR 0059](0059-precise-tools-and-reviewable-meal-items.md) 中食物项只用于只读审查的边界；精确 Tool 查询与 `MealItem` 结构继续有效
- 后续替代：
  - [ADR 0087](0087-reviewable-total-sugar-and-glycemic-speed.md) 把菜品与派生汇总字段扩展到总糖，并增加独立、成对、非诊断的餐食组成升糖速度评估
- 上游依据：[PRD 033](../prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)

## 背景

饮食结果此前是一张卡，只能改整餐热量与宏量。模型给出的菜品拆解在卡上是只读文本，用户要纠正
一道菜的份量必须跳进详情页，回到聊天后又看不到改动结果。

同时整餐汇总与菜品拆解各自可写，两者可以不一致：改了整餐热量，菜品之和仍是旧值，审查时无法判断
哪个是事实。

## 决策

1. 饮食原位审查在同一条回复下渲染两张卡，位置按
   [ADR 0085](0085-record-cards-follow-the-producing-step.md) 跟随写入那一步：
   - 卡一「记饮食」可编辑 `[MealItem]`（名称、份量、kcal、蛋白、碳水、脂肪），支持增删行与改餐次，
     保存走 `replaceItemsAndDeriveTotals` 并写入 correction block。
   - 卡二「饮食评价」只读，随卡一草稿实时重算，并提供进入详情页的入口。
   - 卡一按清单读：每行是图标块、菜名与热量，第二行是份量与宏量。数值是行内无边框输入，聚焦时
     才出现底色；卡片默认看起来是记录，不是表单。宏量单位只在汇总卡写全，行内保留标签与数字。
2. 菜品拆解是事实来源，汇总是纯派生。派生规则抽成 `MealNutritionTotals.derive(from:)`，模型写入路径
   与卡片共用同一实现。
3. 只有当所有菜品都提供某个字段时才汇总该字段；任一缺失保持为空并显示「未估算」，不补零。
4. 编辑草稿保持字符串，空字符串代表用户没有提供，保存时写回 `nil`。名称为空的行不写入记录。
5. 旧记录只有整餐汇总时，卡一把它展示为一行菜品，用户可以继续拆解，不需要迁移数据。
6. 饮食时间使用钟点：用户没有明确说时间时省略 `occurred_at`，由 App 使用发送时刻；餐次按记录发生
   时刻推断，而不是按当前墙钟。
7. 饮食 Skill 在调用 `create_meal` / `update_meal` 之前先用一句话说明识别结果，且不复述菜名与数字，
   让卡片承担数据、文字承担解释。

## 未选择的方案

- 不让汇总独立可编辑。两个可写来源会重新产生「哪个是事实」的问题。
- 不把菜品编辑继续留在详情页。审查闭环要求在教练回复现场就能纠正。
- 不为缺项补零。补零会让「没提供」和「确实是 0」不可区分，违反 missing-is-nil。
- 不把卡片做成默认只读、点「编辑」才可改。多一次点击换来的只是视觉安静，纠正一个份量的成本反而变高。

## 结果

### 正向影响

- 用户在聊天里就能改完一餐的每道菜，汇总立刻反映改动结果。
- 汇总只有一条求和规则，写入与呈现不会分叉。
- 旧记录不需要迁移即可继续编辑。

### 成本与限制

- 一条饮食记录在聊天里占两张卡，回复更长；卡二保持紧凑只读以控制高度。
- 用户删掉所有菜品时保存被拒绝：记录必须至少有一道菜，否则应使用删除。
- 汇总缺项显示「未估算」，习惯看到数字的用户需要先补齐菜品字段。

## 验证

- `MealNutritionTotalsTests` 覆盖完整求和、缺项保持为空、空列表、写入路径共用规则与草稿转换。
- `MealOccurrenceTimeTests` 覆盖默认记录时间保留钟点与餐次按记录时刻推断。
- `make check`、`make verify`。

## 参考

- `Soma/Models/MealNutritionTotals.swift`
- `Soma/Views/MealInlineEditorCards.swift`
- `Soma/Services/ConversationRecorder.swift`

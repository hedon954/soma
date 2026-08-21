# ADR 0087：总糖作为可空营养事实，升糖速度作为成对的非诊断餐食评估

- 状态：已采纳
- 日期：2026-08-21
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0084](0084-inline-meal-breakdown-and-derived-totals.md) 中菜品与派生汇总只覆盖热量和三大宏量的字段范围；菜品作为事实来源、缺项保持为空与双卡片边界继续有效
- 后续替代：暂无
- 上游依据：
  - [PRD 036](../prd/036-meal-sugar-and-glycemic-speed-estimate.md)
  - [BUG 0027](../bugs/0027-meal-aggregate-overrides-item-facts.md)

## 背景

糖分是营养事实，升糖速度却不是一个能从糖克数直接推出的确定性标量。若把二者混成一个分数，
模型会把照片估算包装成个体血糖预测；若只把结论留在回复文字里，用户又无法审查、修正或导出。

## 决策

1. `MealItem.totalSugar: Double?` 与 `MealEntry.totalSugar: Double?` 记录总糖克数。整餐有菜品时，
   `MealNutritionTotals` 按完整性规则派生总糖；任一菜品未知则整餐未知。
2. `MealEntry` 另存 `glycemicSpeedRaw: String?` 与 `glycemicAssessment: String`。速度只有
   `slow`、`moderate`、`fast`；运行时要求速度和非空依据成对出现。
3. 升糖速度表示「基于本餐组成的定性估算」，不是个人血糖读数。UI、导出和 Agent Skill 持续注明
   实际反应因人而异，禁止血糖峰值、曲线和诊断表达。
4. 替换菜品时，模型层自动清空旧速度与依据。创建或更新 Tool 只有在同一次调用提供合法成对字段时
   才重新写入，避免改了食物却保留过期结论。
5. `create_meal`、`update_meal`、查询、结果和 Server registry 在既有协议版本内增加可选字段。
   这是向后兼容扩展，不改变 Tool 名称、必填字段或远程 Job 事实来源。
6. 新增 SwiftData 属性均为可选或有默认空值，按 ADR 0075 依赖当前 schema 的轻量推断打开；同步
   数据库结构文档。若真实旧库不能打开，必须停在可恢复启动门禁并另立 ADR，不清空个人数据。
7. 备份 DTO 与开放导出显式保存新字段；旧 JSON 缺少可选字段仍可解码。

## 未选择的方案

- 不保存「添加糖」标量：照片和普通描述通常无法区分天然糖与添加糖。
- 不输出 GI／GL 数值或血糖曲线：餐食混合、份量与个体差异使这种精度不可证实。
- 不让整餐总糖覆盖菜品之和：双重可写事实源会重现聚合与分项冲突。
- 不只生成临时回复文字：无法进入审查、纠错、备份和导出闭环。

## 结果

用户能在同一饮食审查闭环中看到可核对的糖分与克制的速度判断；代价是 Tool、DTO、导出和 UI 都要
维护新字段，并且旧库打开与真实多模态判断仍需真机验收。

## 验证

- `MealNutritionTotalsTests`：完整总糖求和、缺项为空、草稿往返与改菜清除旧评估。
- `AgentV2Tests` 与 Server registry 测试：成对字段、枚举、结果 payload 与分项优先。
- `DataBackupServiceTests`、`DataExportServiceTests`：虚构餐食往返。
- `make check`、`make verify`、`npm --prefix Server run check`。

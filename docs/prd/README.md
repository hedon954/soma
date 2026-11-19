# Soma 产品需求

先读压缩起点，再按顺序阅读最近三个营销版本。版本以 `project.yml` 和 [CHANGELOG](../../CHANGELOG.md) 为准。

| 版本 | 文档 | 范围 |
| --- | --- | --- |
| ≤0.0.34 | [压缩起点](000-origin-through-0.0.11.md) | 仍然有效的产品要求 |
| 0.0.35 | [PRD 080](080-healthkit-body-mass.md) | Apple 健康体重与体脂按日保存，列表随所选区间展示 |
| 0.0.36 | [PRD 081](081-training-energy-in-total.md) | 总消耗直接加入训练列表估算，兼容历史能量依据 |
| 0.0.37 | [PRD 082](082-coach-progress-reliability.md) | 教练连续性、进展可信度与记录体验 |

每次发布，把滑出窗口的原文移入[文档归档](../archive/README.md)，将仍有效的边界合并进压缩起点。
窗口内最早文档的前驱指向起点。同一修订的正向与反向关系写入两份文档的头部，并由 `make check` 验证。
默认只阅读活文档。产品不变量见[工程契约](../../CLAUDE.md)，验证证据见[验收清单](../acceptance.md)。
新增文档使用[模板](template.md)。

0.0.37 的回归见 [BUG 0072 · 营养表列归属](../bugs/0072-nutrition-label-obscured-column.md)、[BUG 0073 · 建议可用性](../bugs/0073-stale-coach-next-actions.md)、[BUG 0074 · 重量校正的实际来源](../bugs/0074-stale-workout-weight-correction.md)和 [BUG 0075 · 仅补记缺失餐次](../bugs/0075-already-recorded-meals-in-backfill.md)。

PRD 082 的补餐输入回归见 [BUG 0076 · 键盘焦点循环](../bugs/0076-meal-backfill-keyboard-watchdog.md)，提醒重进回归见 [BUG 0077 · 关闭提醒的生效范围](../bugs/0077-meal-backfill-dismissal-lifetime.md)。

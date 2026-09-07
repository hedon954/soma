# PRD 050：轻量进展披露与教练内联控制

- 状态：已采纳，已实施；已通过模拟器验收，待 Release 真机验收
- 日期：2026-08-27
- 修订自：
  - [PRD 048](../../0.0.17/prd/048-reviewable-record-derivation-and-user-controlled-interruption.md) 的主动中断入口、消息元信息和饮食评价
  - [PRD 049](049-foreground-responsiveness-and-readable-monthly-progress.md) 的指标来源入口与目标概览
- 后续修订：
  - [PRD 051](../../0.0.19/prd/051-self-healing-tool-arguments-and-wide-progress-disclosure.md) 的宽幅单行明细浮层
  - [PRD 053](../../0.0.19/prd/053-adaptive-energy-estimation-and-progress.md) 修订能量预估、累计缺失与公式披露，实施中
  - [PRD 054](../../0.0.19/prd/054-progress-history-and-periods.md) 修订为固定首页层级与四周期历史，实施中
- 上游依据：
  - 维护者提供的进展页标注稿与教练交互反馈
  - [BUG 0031](../../../bugs/0031-feedback-sheet-transition-jank.md)
- 下游落地：[ADR 0108](../adr/0108-contextual-progress-disclosure-and-reviewable-meal-order.md)

## 用户结果

1. 进展首卡的目标直接在卡片顶部选择，不再要求先去身体信息页；四个能量指标标题始终居中。
2. 指标本身就是明细入口，不显示感叹号。点按后在该区域旁展开随内容收缩的浮层，直接从第一条组成项
   开始，不显示标题、关闭按钮、色条或外层已有合计；分项标记和数值用稳定语义色区分。
3. Agent 处理中，输入框发送键原位切换为暂停键。点击后保留已完成步骤并进入既有人工重试边界，
   回复下方不再出现第二个停止入口。
4. AI 回复的执行日志与反馈仍各自保留至少 44 pt 触达区，但图形在相邻槽内相向对齐，视觉上更紧凑。
5. 饮食分析在证据足够时显示一行“建议食用顺序”，只排列这餐实际识别到的食物；详情页可编辑，
   备份、导出和 Agent 查询均保留该值。

## 真值、兼容与隐私

- 全天总消耗浮层继续先显示原始公式，再显示带入用户当前事实的算式；缺事实保持为空。
- 建议顺序不是诊断或治疗结论。组成不足时不生成，菜品或份量改变时清空旧顺序，不能凭空补菜。
- `MealEntry.recommendedEatingOrder` 使用空字符串兼容旧记录；只保存在本地业务库，不新增远程数据流或
  PostgreSQL migration。便携导出格式升为 4，旧备份缺少该可选字段时按空值恢复。

## 验收

- 浅色、深色和大字号下点击四项能量、能量差、训练指标与趋势标题，确认浮层跟随入口、无标题且可滚动。
- 目标选择后当前卡片立即刷新，身体信息页读取同一 `UserProfile` 值。
- 处理中发送键显示暂停图标；暂停后已完成 Tool 记录仍可审查，按钮恢复正常发送态并可手动重试。
- 饮食 Tool 写入、菜品编辑清空、详情编辑、备份恢复和便携导出均覆盖建议食用顺序。

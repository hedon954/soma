# PRD 016：训练成为一级执行入口

- 状态：已实现，待真机验收
- 日期：2026-08-04
- 修订自：
  - [PRD 002](002-chat-first-review-loop.md) 的仅“教练 / 进展”顶层结构
  - [PRD 004](004-soma-current-product.md) 的进展内计划入口
  - [PRD 006](006-footprints-location-and-retry.md) 的“第三个 Tab”限制
  - [PRD 010](010-exercise-library-plans-guided-training.md)、[PRD 012](012-gui-training-program-authoring.md)、[PRD 013](013-guided-workout-experience-and-capture.md) 的进展内计划入口
- 后续修订：暂无
- 上游依据：[ADR 0041](../adr/0041-training-primary-tab.md)

## 用户结果

训练计划和带练从“进展”深层入口迁移为底部一级“训练”Tab。用户打开 App 后可直接继续未结束训练、
查看/新建计划、进入计划详情开始带练，并回看执行历史；“进展”专注记录审查与长期趋势。

## 产品规则

- 顶层固定为“教练、训练、进展”三个目的明确的 Tab；训练位于教练与进展之间。
- “训练”页复用既有 `TrainingProgramLibraryView` 与 `TrainingPlanStore`，不创建第二套计划或 Session 数据。
- 进行中的 Session 永远位于训练页最上方，主操作为继续训练；无进行中 Session 时不显示占位入口。
- 当前计划、新建计划、归档计划和计划执行历史都在训练页；计划详情继续负责就绪检查、录像策略和启动。
- “进展”不再包含训练计划索引行，但保留训练记录、动作库、饮食、身体、足迹和趋势。
- 聊天中的 Agent 计划 CRUD 和 `start_guided_workout` 入口保持可用；多个入口共享本地 Session 快照和幂等边界。

## 验收

- 底部栏按“教练、训练、进展”顺序显示，训练 Tab 可直接打开计划库。
- 进行中 Session 可从训练 Tab 一次点击恢复，并打开原有带练全屏体验。
- 新建、计划详情、归档和训练历史删除功能迁移后保持原有行为。
- 进展页不再出现重复的“训练计划”记录索引；训练、动作和趋势统计不受影响。
- VoiceOver 可读出三个 Tab，深浅色、Dynamic Type 和安全区在 iPhone 模拟器可用。

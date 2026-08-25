# Soma 0.0.10 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；
只有维护者明确要求历史时才打开原始文件。

## 产品要求摘要

- PRD 041：计划组间歇与左右换侧间歇归动作配置；进展总览使用单张分段卡，最近活动有界显示

## 架构决策摘要

- ADR 0091：计划间歇归 `TemplateExercise`，开始 Session 时编译到逻辑组，实际休息证据仍逐组保存

## 原始文件

- [PRD 041：动作级间歇与紧凑进展总览](prd/041-action-level-rest-and-compact-progress.md)
- [ADR 0091：计划间歇归动作，执行事实仍归逻辑组](adr/0091-action-level-planned-rest.md)

# Soma 0.0.9 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；
只有维护者明确要求历史时才打开原始文件。

## 产品要求摘要

- PRD 035：带练先取景再录像，完成后立即分享并回训练主页
- PRD 036：饮食总糖分析与餐食组成升糖速度估算
- PRD 037：会话标题自动生成、可编辑与输入上下文单行收敛
- PRD 038：历史会话标题长按编辑
- PRD 039：频率优先的双主题全产品界面
- PRD 040：业务数据只保留当前状态与执行事实

## 架构决策摘要

- ADR 0087：总糖作为可空营养事实，升糖速度作为成对的非诊断餐食评估
- ADR 0088：会话标题异步生成且手动编辑具有最高优先级
- ADR 0089：黑白双主题、受控 AI 排版与无损训练编辑投影
- ADR 0090：业务模型只保留当前状态，历史由事件事实承担

## 原始文件

- [PRD 035：带练先取景再录像，完成后立即分享并回训练主页](prd/035-guided-preview-then-record-and-immediate-share.md)
- [PRD 036：饮食总糖分析与餐食组成升糖速度估算](prd/036-meal-sugar-and-glycemic-speed-estimate.md)
- [PRD 037：会话标题自动生成、可编辑与输入上下文单行收敛](prd/037-generated-editable-session-titles-and-single-row-composer-context.md)
- [PRD 038：历史会话标题长按编辑](prd/038-long-press-session-title-editing.md)
- [PRD 039：频率优先的双主题全产品界面](prd/039-frequency-first-dual-theme-ui.md)
- [PRD 040：业务数据只保留当前状态与执行事实](prd/040-current-state-business-data-with-session-facts.md)
- [ADR 0087：总糖作为可空营养事实，升糖速度作为成对的非诊断餐食评估](adr/0087-reviewable-total-sugar-and-glycemic-speed.md)
- [ADR 0088：会话标题异步生成且手动编辑具有最高优先级](adr/0088-async-generated-session-title-with-manual-precedence.md)
- [ADR 0089：黑白双主题、受控 AI 排版与无损训练编辑投影](adr/0089-semantic-dual-theme-and-lossless-workout-editor.md)
- [ADR 0090：业务模型只保留当前状态，历史由事件事实承担](adr/0090-current-state-business-models-and-session-facts.md)

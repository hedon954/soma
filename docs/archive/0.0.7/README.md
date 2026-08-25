# Soma 0.0.7 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；
只有维护者明确要求历史时才打开原始文件。

## 产品要求摘要

- PRD 031：独立逐组处方、低摩擦带练与自动完成分享
- PRD 032：未选 Skill 全量注册工具，选中 Skill 只注册绑定集合
- PRD 033：消息元信息、快捷按钮 CRUD、可观测性与可编辑饮食双卡片

## 架构决策摘要

- ADR 0073：独立逐组处方、原子执行与确定性带练收口
- ADR 0074：带练相机采用完整有界 activation 与部分录像证据
- ADR 0075：SwiftData 只打开当前模型，不维护历史 VersionedSchema
- ADR 0076：侧别与完成方式归动作定义，组只保存必要参数
- ADR 0077：同一 Turn 合并必须身份匹配，原位审查不得替换 Event Cards
- ADR 0078：批量创建动作与训练记录，模型不指定记录 ID
- ADR 0079：创建始终新增，纠正只走更新工具
- ADR 0080：对话历史抽屉支持左滑删除聊天图
- ADR 0081：未选 Skill 全量注册当前协议 Tool，选中 Skill 只注册绑定子集
- ADR 0082：输入框快捷按钮持有工具绑定，Skill 只保留专业方法
- ADR 0083：本机滚动诊断日志与默认静默的崩溃上报
- ADR 0084：饮食原位审查拆为可编辑菜品卡与派生汇总卡
- ADR 0085：原位卡跟随产生它的那一步渲染

## 原始文件

- [PRD 031：独立逐组处方、低摩擦带练与自动完成分享](prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
- [PRD 032：未选 Skill 全量注册工具，选中 Skill 只注册绑定集合](prd/032-default-full-tools-and-selected-skill-subset.md)
- [PRD 033：消息元信息、快捷按钮 CRUD、可观测性与可编辑饮食双卡片](prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)
- [ADR 0073：独立逐组处方、原子执行与确定性带练收口](adr/0073-independent-set-prescriptions-efforts-and-guided-finalization.md)
- [ADR 0074：带练相机采用完整有界 activation 与部分录像证据](adr/0074-bounded-guided-camera-activation-and-partial-evidence.md)
- [ADR 0075：SwiftData 只打开当前模型，不维护历史 VersionedSchema](adr/0075-current-swiftdata-schema-without-historical-versions.md)
- [ADR 0076：侧别与完成方式归动作定义，组只保存必要参数](adr/0076-exercise-owned-laterality-and-target-kind.md)
- [ADR 0077：同一 Turn 合并必须身份匹配，原位审查不得替换 Event Cards](adr/0077-same-turn-identity-merge-and-additive-inline-review.md)
- [ADR 0078：批量创建动作与训练记录，模型不指定记录 ID](adr/0078-batch-create-exercise-and-workout.md)
- [ADR 0079：创建始终新增，纠正只走更新工具](adr/0079-create-inserts-update-by-id.md)
- [ADR 0080：对话历史抽屉支持左滑删除聊天图](adr/0080-conversation-session-swipe-delete.md)
- [ADR 0081：未选 Skill 全量注册当前协议 Tool，选中 Skill 只注册绑定子集](adr/0081-default-full-tool-registration-and-selected-skill-subset.md)
- [ADR 0082：输入框快捷按钮持有工具绑定，Skill 只保留专业方法](adr/0082-shortcut-owned-tool-bindings-and-method-only-skills.md)
- [ADR 0083：本机滚动诊断日志与默认静默的崩溃上报](adr/0083-local-diagnostics-log-and-silent-crash-reporting.md)
- [ADR 0084：饮食原位审查拆为可编辑菜品卡与派生汇总卡](adr/0084-inline-meal-breakdown-and-derived-totals.md)
- [ADR 0085：原位卡跟随产生它的那一步渲染](adr/0085-record-cards-follow-the-producing-step.md)

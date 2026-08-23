# PRD 040：业务数据只保留当前状态与执行事实

- 状态：已实现
- 日期：2026-08-23
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的版本化训练计划与动作内容边界
  - [PRD 010](010-exercise-library-plans-guided-training.md) 的计划版本历史
  - [PRD 012](012-gui-training-program-authoring.md) 的版本化计划保存路径
  - [PRD 013](013-guided-workout-experience-and-capture.md) 的保存新版本交互
  - [PRD 019](019-training-review-plan-management-and-muscle-map-share.md) 的版本历史、版本差异和来源版本展示
  - [PRD 020](020-gui-simplification-and-progressive-disclosure.md) 的折叠版本历史区块
  - [PRD 030](030-agent-prompt-skill-context-and-tool-v3.md) 的计划版本 Tool
- 下游落地：[ADR 0090](../adr/0090-current-state-business-models-and-session-facts.md)

## 用户问题

版本号、版本历史和恢复入口没有帮助用户更快完成训练，反而隐藏了当前可修改参数，让计划编辑路径
变长。动作说明和热量记录也没有用户可操作的版本需求，不应为内部实现暴露版本概念。

## 当前要求

1. 训练计划只展示和保存当前名称、概览、安排、动作与逐组参数；进入详情即可看见并修改参数。
2. GUI 与 Agent 都直接更新同一份当前计划，不创建版本对象、不展示版本号、不提供版本历史或恢复。
3. 开始训练时把当前处方冻结到 `WorkoutSession`。计划后续修改不得改变已开始或已完成的训练事实。
4. 动作说明、主要/辅助肌群和动作模式只保存当前内容，不维护内容修订数组。
5. 训练热量保存可审查的输入与结果，不保存算法版本号。
6. 删除计划只删除当前计划及其处方；已产生的 Session、动作执行、训练记录和媒体继续保留。
7. 备份、导出、Agent Tool、设计稿、工程文档和测试只描述当前状态与执行事实。
8. 数据库迁移、备份格式、远程协议、Tool Schema 与并发控制的技术版本继续存在，但不得显示成用户
   业务版本，也不得形成业务历史入口。

## 验收

- 计划详情可直接修改动作顺序、每组次数/时长、重量、左右方式和间歇，并在一次保存后生效。
- 修改计划前启动的 Session 处方快照保持不变；修改后新开的 Session 使用当前处方。
- App、Server 与文档不再出现计划版本 Tool、版本模型、版本号字段、内容修订数组或热量算法版本字段。
- 旧库启动后保留原当前计划；非当前计划版本数据不继续成为业务对象。
- 加密备份往返、数据清除、模拟器测试和数据库结构门禁通过。

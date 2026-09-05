# ADR 0108：跟随式进展披露与可审查饮食顺序

- 后续替代：[ADR 0114](../../../adr/0114-progress-periods-and-adaptive-energy.md) 部分替代进展浮层为四周期能量依据；饮食记录顺序仍有效

- 状态：已采纳
- 日期：2026-08-27
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0106](../../0.0.17/adr/0106-reviewable-derived-records-and-manual-interruption.md) 的中断入口与消息元信息排列
  - [ADR 0107](0107-foreground-recovery-and-progress-evidence-projection.md) 的来源 Sheet 交互
- 后续替代：[ADR 0109](../../../adr/0109-schema-guided-tool-argument-recovery.md) 的宽幅单行浮层
- 上游依据：
  - [PRD 050](../prd/050-lightweight-progress-disclosure-and-coach-controls.md)
  - [BUG 0031](../../../bugs/0031-feedback-sheet-transition-jank.md)
- 下游落地：[验收矩阵](../../../acceptance.md)

## 背景

上一轮为每项指标增加了独立来源 Sheet，也给处理中的回复增加了停止按钮，但真实界面暴露了新的
层级问题：小明细占满半屏、指标与感叹号形成两个目标、输入区和消息行同时出现停止语义。饮食评价
已有组成分析，却没有把食用顺序作为可回看、可修改的业务结果保存。

## 决策

1. `ProgressSourceDisclosure` 让指标内容本身成为 Button，并以强制 compact adaptation 的系统 popover
   锚定到入口。浮层只渲染组成行和必要公式，不渲染标题、关闭按钮、说明色条或外层合计。
2. `UserProfile.fitnessGoal` 仍是目标唯一事实源；进展卡的 Menu 直接写同一个最新 Profile，不增加页面
   私有目标状态。快照只做保存成功后的乐观投影，失败时回滚并重新加载。
3. 当前 Session 在处理时，Composer 的发送控件优先投影为暂停控件并调用既有人工中断动作。消息气泡
   只保留实时状态和时间，避免同一动作存在两个入口。
4. Trace 与反馈各占不重叠的 44 pt 槽；图标分别靠相邻边对齐。触达面积与可见图形间距分开建模。
5. `MealEntry.recommendedEatingOrder` 保存简短顺序文本。Tool schema、幂等签名、查询、编辑、备份与导出
   使用同一字段；菜品改变时与旧升糖评估一起失效。

## 未选择的方案

- 不用大尺寸 Sheet 或每项感叹号；它们增加视觉重量和额外目标。
- 不把浮层标题换成更短文案；入口上下文已经说明指标，任何标题都是重复。
- 不用固定饮食模板覆盖所有餐食；缺少蔬菜、蛋白质或主食时必须按实际组成给出或省略建议。
- 不缩小或重叠消息操作的触达区来换取紧凑外观。

## 结果

进展明细更接近被点击的数据，外层总计和内层组成职责清晰；Agent 停止权回到高频输入控件，消息
元信息不再承担进行中操作。新增的饮食顺序随记录生命周期审查，也增加一个需要兼容旧数据的本地字段。

## 数据兼容与验证

新增 SwiftData 字符串字段带空默认值，旧本地记录可直接读取；没有 PostgreSQL schema 变化。备份 DTO
使用可选字段兼容旧文件，便携导出格式升为 4。验证覆盖 Tool 写入、项目变化失效、备份/导出、静态
门禁、`make verify` 和双主题模拟器交互。

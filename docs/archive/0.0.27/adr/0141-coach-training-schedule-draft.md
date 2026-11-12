# ADR 0141：训练计划草稿确认后才写入

- 状态：已采纳，已实现
- 版本：0.0.27
- 日期：2026-10-10
- 维护者：Soma maintainers
- 上游依据：[PRD 072](../prd/072-coach-training-schedule-draft.md)
- 部分替代：
  - [ADR 0140](../../0.0.26/adr/0140-training-schedule.md)（仅创建入口；周期、缺席、休息、停住和单份进行中计划不变）
  - [ADR 0000](../../../adr/0000-origin-through-0.0.11.md)（仅带 `selection` 的提问：点按改为选中，每题都有自填，一次发送；点按即发送的旧题不变）
  - [ADR 0000](../../../adr/0000-origin-through-0.0.11.md)（仅 Tool 目录增加一个不落库的草稿工具；业务写入仍走固定 Tool）
- 后续替代：暂无
- 下游落地：
  - [验收](../../../acceptance.md)
  - [ReAct Agent](../../../react-agent.md)
  - [Tool 目录](../../../engineering/agent-tool-catalog.md)

## 背景

计划编辑器已经是 `TrainingSchedule` 的唯一写入界面。教练能创建课程，但不能提交一份尚未确认的周期。若让模型直接 `保存`，用户还没改天数和课程就会归档掉别的计划，或把猜出来的安排写成事实。

## 决策

增加设备执行的 `propose_training_schedule`。它校验并返回草稿，不插入、不更新 `TrainingSchedule`。服务器只按其他业务工具转发这次调用，不保存计划。

参数与设备和服务器 Schema 同步：

- `name` 非空；`anchor_date` 可省略，未说就使用今天。
- `slots` 为 `rest` 或 `training`。后者的 `contents` 是有序内容，`kind` 为 exercise/course/plan。
- course 带 `program_id`，plan 带 `schedule_id`，都是正 Int64；exercise 带一个 `exercises` 元素，复用课程的逐组参数 Schema。无需先创建课程。
- 所有对象 additionalProperties 为 false。展开后最多 14 天，至少一个有效动作。

工具通过 TrainingContentCompiler 校验，但不插入或更新训练计划或课程。工具结果保存可编辑槽位和展开后的天序标题。卡片是固定本地组件，「查看并修改」预填同一个计划编辑器；引用失效时显示错误并保留草稿，不能悄悄替换成休息。用户关闭编辑器不写库。

起草前置提问使用 `ask_user_questions`，每题 `selection` 为 single/multiple，`allows_custom_input` 必须 true，不绑定 action。单选和多选只切换状态，每题显示输入框，整张卡一次发送；至少一题有选中或自填。普通旧题仍点按即发送。提问成功结束本轮，不同批起草。

本地将问题、选中句子和「我补充：」自填合成一条普通用户 Turn，不启动确定性工具 Job。固定开场白或提问卡刚发出的回答且尚无成功草稿时，要求单选/多选协议；用户另发内容后恢复旧规则。

「教练来排」发送一条普通用户 Turn，暴露当轮全部工具，不走只预填输入框的 `prefillCoachDraft`。系统提示增加一条：排训练计划时，先用已注入的课程和最近训练；只问会改变周期且仍缺失的事实；每题必须带 `selection` 和自填输入；草稿只用 `propose_training_schedule`，不要把计划写成已经保存。内置 `training_plan` 的默认说明同步写上「频率进入计划草稿，课程处方仍走 `create_program`」。用户已经改过的 Skill 正文不覆盖。

打开卡片时若已有另一份进行中计划，沿用保存即归档。卡片文案说明这件事。

## 未选择的方案

- 由模型调用新的 `create_schedule` 直接落库。用户还不能在保存前改每一天。
- 从助手正文解析周期。计划结构不能靠拆句子恢复。
- 为草稿新增 SwiftData 模型或服务器表。工具结果已经能在重启后重新打开卡片。
- 点按钮只把提示放进输入框。产品要求这一下就是明确发送。
- 起草提问继续点按即发送。多选和自填无法在同一次点击里一起交出去。
- 为计划问卷另做工具或模型自定义界面。回答仍是固定提问组件产生的用户消息。

## 结果

### 正向影响

- 手建和教练起草共用编辑器、槽位上限和「一份进行中」规则。
- 未确认的周期不会变成计划，也不会改写课程重量。

### 成本与限制

- Tool 数量从 33 增至 34。远程注册表要同步这个只在设备执行的工具。
- 用户确认后创建的课程在计划尚未保存时已经存在，删除仍走课程自己的删除。
- 自定义过的课程 Skill 可能仍只写课程；系统提示和工具本身保持草稿不落库。

## 验证

直接动作草稿无需课程且不落库；全休息、无效引用、参数越界、循环与展开超过14天被拒绝。单选、多选、自填、全空拒绝发送和旧题点按行为由确定性测试覆盖。编辑器与手建共享编译和保存路径。`make check`、`make verify`。

## 参考

- [PRD 072](../prd/072-coach-training-schedule-draft.md)
- [ADR 0140](../../0.0.26/adr/0140-training-schedule.md)
- [ADR 0000](../../../adr/0000-origin-through-0.0.11.md)

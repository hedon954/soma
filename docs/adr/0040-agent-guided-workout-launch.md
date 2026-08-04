# ADR 0040：Agent 通过受控计划工具启动本地带练

- 状态：已采纳
- 日期：2026-08-04
- 维护者：Soma maintainers
- 部分替代：[ADR 0030](0030-deterministic-guided-workout-and-session-recording.md) 的仅 GUI 计划启动入口
- 后续替代：暂无
- 上游依据：[PRD 015](../prd/015-agent-guided-workout-launch.md)

## 背景

训练计划已经支持聊天创建、版本化调整和 GUI 启动，但用户在教练对话中无法可靠地查看可执行计划并直接进入
带练。通用 `query_user_data` 的计划输出不包含可执行性约束和当前模板细节，无法为一次有副作用的启动提供
明确、可审查的 Tool 协议。

## 决策

新增固定 Tool `list_training_programs`、`get_training_program`、`start_guided_workout` 和
`delete_training_program`。前两者只读返回当前数据空间可执行计划或其当前模板；启动工具只接受列表返回的
计划 ID，调用 `TrainingPlanStore.startSession` 创建不可变本地快照，再经 `SomaCaptureRouter` 打开既有
`GuidedWorkoutView`。永久删除清除计划及模板，但保留已开始的 Session 快照。

启动工具是有副作用的 mutation：只在用户当前消息明确要求执行计划时可调用，纳入既有
`AgentMutationReceipt` 幂等回执。自动录像默认关闭，只有明确参数才映射为现有“每动作一组”或“每组”。

## 未选择的方案

- 让模型直接操作组、相机、倒计时或录像：会绕过可恢复的确定性带练状态机。
- 只复用 `query_user_data(programs)`：该通用输出并不保证计划可执行，且无法形成启动工具的明确契约。
- 将永久删除实现为删除历史 Session：会破坏用户已确认的训练事实和录像证据。
- 在服务端创建 Session：服务器没有本地 SwiftData 与相机权限，也不能成为训练事实来源。

## 结果

计划可以从聊天低摩擦进入带练，同时 GUI 入口继续保留。Swift 单测验证可执行计划列表、Session 快照、
录像策略映射和路由请求；真机验证对话完成后带练全屏打开、默认不申请相机、显式录像策略生效。

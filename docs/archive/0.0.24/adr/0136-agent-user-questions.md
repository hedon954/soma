# ADR 0136：受控提问工具与确定性按钮 Job

- 状态：已采纳
- 日期：2026-09-12
- 版本：0.0.24
- 上游依据：[PRD 066](../prd/066-agent-user-questions.md)
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的纯 Markdown 交互与快捷聚焦工具曝光：新增固定提问组件及始终可用的提问工具
- 部分替代：[ReAct Agent](../../../react-agent.md)、[Tool 目录](../../../engineering/agent-tool-catalog.md) 的工具目录与循环停止规则
- 后续替代：[ADR 0141](../../0.0.27/adr/0141-coach-training-schedule-draft.md)（仅带 selection 的提问不再点按即发送）
- 下游落地：[验收](../../../acceptance.md)

## 背景

纯文字追问要求用户重新输入；已经确定的选择仍走模型，增加等待和不必要的推断。

## 决策

1. `ask_user_questions` schema 1 返回受控 questions 数据；成功即结束当前 Agent Loop，提问不阻塞 FIFO。
   每题有稳定 ID、问题、最多六个选项及自定义输入开关。选项 text 同时用于按钮和用户消息。
   每个选项按钮独占一行并铺满提问区域；长文字完整换行，自定义输入框位于选项下方。
2. 可选 action 只绑定现有本地工具与完整 `arguments_json`。请求和执行均校验目标工具 Schema；
   不允许绑定提问本身、Skill、产品反馈远程发送或依赖当前媒体的视频复盘。绑定不能越过当前曝光集合。
   不确定或需要模型分析的操作使用普通文本选项。
3. 问题存于既有工具结果与 Event；助手历史文字保留问题和选项语义，界面由本地固定组件呈现。
   当前 Session 的后续用户 Turn 使旧问题失效，包括旧 Job 迟到的提问。点击时重新读取验证来源。
4. 点击确定性选项保存新的用户 Turn 与 `deterministicQuestion` Job，复用 `deterministicPayloadData`、
   现有业务工具、MutationReceipt 和事件投影。成功、失败、取消和重试都可审查，不启动模型。
5. 提问组件只是固定 Tool 输出的原生呈现，正文仍为受控 Markdown，不接受模型任意 UI 或代码。
   本地和 Server 都在提问成功后停止推理；用户下一次输入启动正常新 Turn。

## 结果

减少输入和模型调用，保留数据审查、权限和幂等边界。无需新增持久字段或迁移；既有 Job payload 增加
一个按 executionKind 区分的格式。远程使用需同步部署工具注册与停止规则。不做多题批量提交：每次点击立即发送。

## 验证

固定工具 Schema、普通与确定性路由、无 Key 执行、重复点击、失效、持久恢复、受限工具、Server 停止与 UI 测试。

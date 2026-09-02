# ADR 0111：Agent 响应身份与人工恢复

- 状态：已采纳，已实施；待真机交互验收
- 日期：2026-09-02
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：暂无
- 上游依据：
  - [PRD 052](../prd/052-coach-training-and-lifecycle-reliability.md)
  - [BUG 0047](../bugs/0047-terminal-failure-retry-leaves-stale-error.md)

## 背景

响应要等到模型首 token 才出现，终态失败又可能在重试时留下旧错误并新建第二个气泡。消息身份与
Job 身份没有在入队事务中绑定，使 UI 无法保证原位恢复。

## 决策

- 入队事务原子保存用户消息、Job、预绑定响应消息和 `jobQueued` Event。
- `CoachMessage.text` 只保存真正的 AI 正文；队列、模型执行、网络、配置和设备等待由稳定 Activity
  Item 更新。首段正文、Skill 或 Tool 卡出现时隐藏重复 Activity，进入下一轮模型请求时重新显示
  “正在处理请求…”。临时状态不得经过普通 `CoachResponseView`。
- Runner、远程 Event 投影、失败和人工重试都按 `responseMessageID` 复用同一响应。
- Agent Item/Span 使用可选 `operationID` 和阶段
  `queued/modelRunning/preparing/running/waitingForDevice/completed/failed/cancelled`；旧数据缺少字段时
  继续按既有 status 解码。
- 本地 Tool/Skill、Server Event、远程重连和设备领取都用原生 `toolCallID` 作为 operation 身份。
  参数通过或失败时先有 preparing；执行开始为 running；设备交接为 waitingForDevice；终态只更新
  同一张卡。快速操作不人为 sleep，全部阶段仍进入 Event Log。
- 人工重试开始时删除旧失败投影，保留已经成功的 Tool 步骤，只运行未完成检查点；可见失败后不再
  自动重试，ReAct 内部仍保留三次指数退避。

## 未选择的方案

- 不为“正在处理”创建临时非持久视图，也不在首 token 到达后再建正式消息。
- 不在 Loop 外轮询自动重试用户已经看到的失败。

## 结果

用户立即得到反馈，并能连续看到模型、Skill、Tool 与设备交接阶段；失败恢复不污染会话。成本是
本地/远程 reducer、旧事件兼容和 Job 恢复路径都必须共享稳定消息与 operation 身份。

## 验证

- 临时 `ModelContainer` 验证原子入队、重启恢复、同气泡重试和成功步骤保留。
- reducer/Server 测试验证重复 Event、并行 Tool、Skill、设备等待、重连和失败自纠始终每个
  `operationID` 一张卡。
- 真机逐态验证已接收、模型处理中、准备、执行中、设备等待、成功、失败与手动重试。

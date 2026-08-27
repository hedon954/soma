# ADR 0098：用户可配置 ReAct 活动执行超时

- 状态：部分已替代；活动计时边界继续有效，统一自定义值已被三类独立值替代
- 日期：2026-08-25
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 中活动执行预算固定为文字/图片/视频 3/5/10 分钟的边界
- 后续替代：[ADR 0104](../../0.0.15/adr/0104-independent-react-timeouts-by-media.md) 替代统一自定义上限
- 上游依据：[PRD 043](../prd/043-configurable-react-runtime-timeout.md)

## 背景

活动执行时间与业务时间已经由 ADR 0067 解耦，但预算数值仍写死在
`AgentStreamDeadlinePolicy`。步骤上限可以配置、时间上限却不能配置，使两个共同控制单次 ReAct
资源消耗的边界分散且不对称。

## 决策

1. `ReActAgentPreference` 同时拥有步骤上限与可选的自定义运行超时分钟数。
2. 未设置自定义值时继续使用文字/图片/视频 3/5/10 分钟；自定义值限定为 3–60 分钟，并统一
   覆盖三种媒体的 Loop total，不改变 20/40/60 秒首增量门禁。
3. 设置使用 `UserDefaults`；`0` 只作为界面中的自动模式哨兵，不作为有效 deadline。业务读取返回
   `nil` 表示使用媒体自适应默认值。
4. 本地执行在建立 `AgentLoopDeadline` 前读取生效策略；远程提交在设备生成的版本化
   `AgentModelInputEnvelope.runtime.deadlines` 中冻结同一策略。Server 不自行读取本机偏好。
5. 当前活动窗口建立后不热更新；新 Job、自动恢复或用户显式重试在进入下一个执行窗口时读取最新
   设置。ADR 0067 的活动计时、人工重试清零、自动恢复保留已耗时和检查点语义全部保持。
6. 运行超时不能禁用。超时继续形成可解释 `loop_total` 失败并进入人工恢复，不丢弃已成功步骤。

## 未选择的方案

- 不把默认统一改为 10 分钟；这会静默改变纯文本与图片任务的既有资源边界。
- 不提供无限运行；步骤上限不能约束单次 Provider 卡住或极慢流式连接。
- 不为文字、图片、视频增加三组高级字段；此项已由 ADR 0104 根据实际任务差异替代。
- 不新增 SwiftData 字段；这是设备级运行偏好，不是业务事实或 Job 历史。

## 结果

### 正向影响

- 复杂任务可以由维护者明确放宽预算，且步骤与时间两个资源上限集中在同一区块。
- 默认升级行为不变；远程模型输入继续携带完整、可审查的实际 deadline。
- 用户调整后手动重试即可应用新预算，不需要删除回复或重跑成功 Tool。

### 成本与限制

- 自定义值统一覆盖三类媒体；需要媒体差异时使用自动模式。
- 已经开始的活动窗口不会中途延长，避免并发 timer 与持久活动时长失去一致性。

## 验证

- `AgentReliabilityTests` 覆盖自动默认、3/60 分钟夹取、17 分钟三类统一和恢复自动。
- `AgentV2Tests` 继续覆盖默认 3/5/10 分钟与 `loop_total` 结构化取消。
- `RemoteAgentExecutionTests` 覆盖版本化输入的 deadline 传输与 Server 校验。
- `make check`、`make verify`；真机高级设置与虚构超时恢复验收。

## 参考

- [PRD 043](../prd/043-configurable-react-runtime-timeout.md)
- [ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的活动计时与固定预算收口
- [Agent 运行时设置](../../../../Soma/Views/ReActLoopSettingsSection.swift)

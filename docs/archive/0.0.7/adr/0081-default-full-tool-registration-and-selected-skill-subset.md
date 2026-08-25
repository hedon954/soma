# ADR 0081：未选 Skill 全量注册当前协议 Tool，选中 Skill 只注册绑定子集

- 状态：已采纳
- 日期：2026-08-19
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0050](../../0.0.3/adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md) 中每轮按关键词、active 计划和带练状态预选工具组的边界；整轮固定、并行 `tool_calls` 与历史帧 clearing 继续有效
  - [ADR 0065](../../0.0.5/adr/0065-intent-scoped-tools-and-prefix-stable-prompts.md) 中按副作用意图预选 Tool、建议不暴露 mutation 的边界；原生 Tool Calling 与稳定 Prompt 前缀继续有效
  - [ADR 0069](../../0.0.6/adr/0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) 中 Tool Exposure Middleware 按当前 Turn 信号剪枝、普通建议无业务 Tool 的边界；选中 Skill 直载全文与白名单 Tool、强类型 Schema 继续有效
- 后续替代：
  - [ADR 0082](0082-shortcut-owned-tool-bindings-and-method-only-skills.md) 把曝光集合的来源从
    Skill 的 `toolGroups` 改为快捷按钮的工具白名单；Loop 开始判断一次与未选时全量曝光继续有效
- 上游依据：[PRD 032](../prd/032-default-full-tools-and-selected-skill-subset.md)

## 背景

意图剪枝把「未选 Skill」当成需要分类的特殊路径：建议变成零 Tool，记录才打开对应领域。维护者明确纠正：未选 Skill 的直接发送是默认完整能力；只有用户主动指定场景 Skill 时才收缩工具集。

关键词分类既不能覆盖自然表达，也会在本机存在 active 计划时把无关建议绑上计划工具。这与「一次判断、两种模式」冲突。

## 决策

1. ReAct Loop 开始时决定本轮 `tools`，整轮固定。恢复 Checkpoint 时沿用已持久化的 `exposedGroups`。
2. 存在 `selectedSkillID` 且能解析到当前 Registry 描述时，只注册该 Skill 的 `toolGroups`。不附加 `core`/`load_skill`。
3. 未选 Skill 时注册 `AgentToolExposurePolicy.currentProtocolGroups`：`core`、`exercises`、`workouts`、`meals`、`body`、`plans`、`gym`、`review`、`feedback`。对应当前协议 32 个 Tool，含 `load_skill`。
4. 删除基于原文、视频、active 计划和带练 session 的预选信号。本地与远程组装 Envelope 使用同一判断。
5. 运行时只解码当前协议 Tool 名称；未知名称解码失败。
6. System Prompt 的 Skill 目录始终完整；未选 Skill 时模型通过 `load_skill` 读取全文，选中 Skill 时由 User Prompt 直载。

## 未选择的方案

- 不保留关键词/问句启发式作为未选 Skill 的兜底。它会把默认路径重新变成剪枝。
- 不把建议路径重新变成空 `tools`。直接回答由 Prompt 纪律约束，不靠隐藏工具。

## 结果

### 正向影响

- 默认聊天不再因为用词漏掉饮食、训练或反馈工具。
- 快捷 Skill 仍然是明确的能力收缩，避免把无关领域 Schema 塞进已选场景。

### 成本与限制

- 未选 Skill 的每次模型调用都携带完整 32 个 Tool Schema，prefill 大于旧的最小子集。
- 模型可能在建议句上尝试调用工具；设备仍执行授权、幂等和 Schema 校验，Prompt 继续要求能直接回答时不要查询。

## 验证

- `AgentReliabilityTests` 与 `AgentPromptMigrationRefactorTests` 覆盖未选全量、选中子集、本地/远程同一 Builder。
- `make check`、`make verify`。

## 参考

- [Agent Tool 目录](../../../engineering/agent-tool-catalog.md)
- `Soma/Services/AgentToolExposurePolicy.swift`

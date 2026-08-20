# ADR 0082：输入框快捷按钮持有工具绑定，Skill 只保留专业方法

- 状态：已采纳
- 日期：2026-08-20
- 维护者：Soma maintainers
- 替代：
  - [ADR 0081](0081-default-full-tool-registration-and-selected-skill-subset.md) 由 Skill 的 `toolGroups` 决定选中场景曝光集合的机制；「Loop 开始时判断一次、未选时全量曝光」继续有效
- 部分替代：
  - [ADR 0069](0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) 中 Skill 声明并绑定工具白名单的边界；分层 Prompt、Skill 直载与强类型 Tool 继续有效
- 后续替代：暂无
- 上游依据：[PRD 033](../prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)

## 背景

工具权限此前挂在 Skill 上：内置 Skill 硬编码 `toolGroups`，自定义 Skill 保存 `toolGroupIDs`。
输入框快捷按钮只是 Skill 的一个排序视图，用户无法新增、改名或换绑，也无法让同一个 Skill 在不同
场景下使用不同工具。

同时「分组」既被当成设置页的选择单位，又被当成运行时的曝光单位。用户想去掉某个分组里的一个工具
时无处可改，Skill 与快捷按钮的职责也说不清。

## 决策

1. 新增独立实体 `AgentInputShortcut`：`id`、`title`、`iconSystemName`、`skillID?`、`toolNames`、
   `isVisible`、`order`，以 JSON 存 UserDefaults 键 `ai.react.input-shortcuts.v1`，不进入
   SwiftData schema。
2. 工具曝光边界归快捷按钮。`AgentToolExposurePolicy` 只认工具名：未选按钮时返回当前协议全量，
   选中按钮时返回该按钮 `toolNames` 与当前协议的交集，顺序由固定目录决定。
3. Skill 只描述专业方法。`AgentSkillDescriptor`、`AgentCustomSkill` 与内置 `AgentSkill` 都不再
   携带工具分组；删除 Skill 时同步解绑引用它的快捷按钮。
4. `AgentToolGroup` 降级为设置页的分类维度，只用于「按组勾选/取消」，不再是运行时单位。
5. `AgentJob` 新增可选 `selectedShortcutID`；本地准备与远程 Envelope 使用同一判断。
   `AgentLoopCheckpoint` 保存 `exposedToolNames`，并继续解码旧 `exposedGroups` 以还原在盘检查点。
6. 默认可见按钮为饮食分析、训练记录、近期分析；其余内置 Skill 保留但默认不占用聊天输入区。
7. 新增一次性 AI 推荐：把按钮名称、绑定 Skill 正文与工具目录送一次非流式 completion，优先小模型档，
   返回 `{tools, reason}`；本地丢弃未知名称后由用户一键采纳。推荐只在用户点按时触发。

## 未选择的方案

- 不在 Skill 上继续保留工具绑定并让快捷按钮覆盖。两个来源会产生「谁赢」的隐式规则。
- 不把快捷按钮写进 SwiftData。它是本机偏好而不是业务事实，放进 schema 会引入无意义迁移。
- 不让模型在运行时自行扩展工具集。曝光边界必须是设备侧的确定性决定。

## 结果

### 正向影响

- 用户可以按场景精确控制能力：同一个 Skill 可以有「只读分析」和「可写记录」两个按钮。
- Skill 回归可编辑的专业方法，改正文不再意外改变权限。
- 恢复中途 Checkpoint 与远程执行沿用同一份工具名清单，不再依赖分组语义。

### 成本与限制

- 用户可以把某个按钮的工具删到不足以完成任务；工具错误仍以 `role: tool` 返回，模型需要解释。
- 旧在盘 checkpoint 只有分组信息，恢复时按分组展开为工具名，可能与用户随后修改的白名单不同；
  这是有意的，恢复优先保持该轮的一致性。
- AI 推荐依赖用户已配置的模型；未配置或返回不可解析时保持原选择并提示失败原因。

## 验证

- `AgentInputShortcutTests` 覆盖默认三按钮、增删改排序、可见性与未知工具名清理。
- `AgentToolExposureLoggingTests` 覆盖未选全量、选中子集与 checkpoint 还原。
- `make check`、`make verify`。

## 参考

- [Agent Tool 目录](../engineering/agent-tool-catalog.md)
- `Soma/Services/AgentInputShortcut.swift`
- `Soma/Services/AgentToolExposurePolicy.swift`
- `Soma/Services/AgentToolRecommendationService.swift`

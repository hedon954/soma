# PRD 032：未选 Skill 全量注册工具，选中 Skill 只注册绑定集合

- 状态：已实施，待真机 Agent 交互验收
- 日期：2026-08-19
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的聊天驱动教练与固定 Tool 写入闭环
  - [PRD 022](022-react-reliability-and-context-awareness.md) 中每轮按关键词和本机状态预选工具组的边界
  - [PRD 027](027-reliable-efficient-react-and-in-context-review.md) 中建议类问题不暴露写入 Tool 的边界
  - [PRD 030](030-agent-prompt-skill-context-and-tool-v3.md) 中通用建议发送空 Tool 集、未选 Skill 按输入剪枝的边界
- 后续修订：
  - [PRD 033](033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md) 把「选中 Skill 决定
    子集」改为「选中快捷按钮决定子集」；未选时全量曝光继续有效
- 上游依据：维护者对当前 ReAct Loop 工具注册规则的纠正：未选 Skill 必须是完整默认集，不得按句子剪枝
- 下游落地：
  - [ADR 0081](../adr/0081-default-full-tool-registration-and-selected-skill-subset.md)

## 背景

PRD 022/027/030 曾要求按当前句子和本机状态预选最小 Tool 集，普通建议甚至零 Tool。实现因此用关键词、问句和进行中计划做剪枝。这不是当前产品规则。

用户在输入框上方主动选中某个场景 Skill 时，本轮只需要该 Skill 绑定的工具。用户不选任何 Skill、直接发送时，本轮是默认完整能力：当前协议的全部工具，以及 System Prompt 中的完整 Skill 目录，并保留 `load_skill`。ReAct Loop 开始时判断一次，整轮不再按文本重算。

## 用户结果

1. 用户点选饮食分析、动作分析等快捷 Skill 后发送：首轮注入该 Skill 全文，API `tools` 只包含该 Skill 经 App 白名单绑定的工具；不再注册 `load_skill`。
2. 用户不选 Skill 直接发送：本轮注册当前协议全部 32 个工具，Skill 目录完整可见，模型可按需 `load_skill`。建议、问句、记录、计划或反馈都不再因用词被剪成空集或某个领域子集。
3. 恢复中途 Checkpoint 时继续使用已持久化的暴露集合，不在中途改写。

## 产品规则

- 每个 ReAct Loop 开始时只判断一次工具注册；后续 step 只追加 assistant/tool 消息，不按新关键词重选。
- 选中快捷 Skill：只注册该 Skill 声明且通过 App 白名单的 Tool 组。自定义 Skill 不能扩权到白名单之外。
- 未选 Skill：注册当前协议全部业务与 runtime 工具，包括 `load_skill`、健身房、复盘和产品反馈。不做关键词、问句或本机计划/带练状态剪枝。
- 运行时只解码当前协议 Tool 名称；未知名称解码失败。
- System Prompt 继续只披露 Skill 的 `name` / `description` / `when_to_use`；Tool 名称和 Schema 只进入 API `tools`。
- 写入授权、missing-is-nil、固定 Schema 和设备二次校验不变。模型仍应在事实已注入时直接回答，但这由 Prompt 约束，不靠把 `tools` 留空来实现。

## 数据与隐私

- 不新增离开设备的数据。远程 Job 仍只携带本轮 Envelope 中已经决定的 `activeTools`。
- 选中 Skill 的快照继续随 Job 保存，供恢复和远程执行使用。

## 明确不在范围

- 不恢复按句子选择工具组，不把普通建议重新变成零 Tool。
- 不让 Skill Markdown 声明任意 Tool。

## 验收

- 未选 Skill 时 `AgentToolExposurePolicy` 暴露当前协议 32 个工具。
- 选中饮食分析时只暴露饮食五个 Tool，不含 `load_skill`。
- 建议句、问句和记录句在未选 Skill 时得到同一完整集合。
- 本地准备路径与远程 Envelope 使用同一判断。
- `make check`、`make verify` 通过。

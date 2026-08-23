# PRD 030：Agent Prompt、Skill、上下文与强类型 Tool v3

- 状态：已实施，部分修订；远端部署、旧版本覆盖迁移与真机 Agent 交互仍待维护者验收
- 日期：2026-08-15
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的教练身份、Prompt、Skill、记录身份与会话时间基线
  - [PRD 008](008-coach-continuity-and-adaptive-models.md) 的长 Session 上下文与双档模型路由
  - [PRD 010](010-exercise-library-plans-guided-training.md) 的动作身份和训练计划引用
  - [PRD 025](025-trusted-context-direct-video-and-reviewable-meals.md) 的十轮上下文、通用 CRUD Tool 与可信时间
  - [PRD 027](027-reliable-efficient-react-and-in-context-review.md) 的稳定 Prompt、意图 Tool 和固定业务时间
  - [PRD 029](029-unified-local-remote-agent-model-input.md) 的统一模型输入协议
- 后续修订：
  - [PRD 040](040-current-state-business-data-with-session-facts.md) 删除计划版本 Tool，改为直接更新当前计划
  - [PRD 032](032-default-full-tools-and-selected-skill-subset.md) 将未选 Skill 改为全量当前协议 Tool，并取消通用建议空 Tool 集
  - [PRD 033](033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md) 把工具权限从 Skill 移到
    可完整 CRUD 的输入框快捷按钮；Skill 只保留专业方法
- 上游依据：用户对真实模型 Prompt、无意义 Tool 调用和跨天记录时间的审查
- 下游落地：
  - [ADR 0069](../adr/0069-layered-agent-prompt-skill-middleware-and-typed-tools.md)
  - [ADR 0070](../adr/0070-reviewable-rolling-session-compaction.md)
  - [ADR 0071](../adr/0071-integer-business-identities-and-explicit-relations.md)
  - [ADR 0072](../adr/0072-session-business-date-and-record-occurrence-time.md)
  - [ADR 0078](../adr/0078-batch-create-exercise-and-workout.md)
  - [ADR 0079](../adr/0079-create-inserts-update-by-id.md)

## 背景

当前 System Prompt 把角色、可编辑安全策略和 Skill 目录混在同一层；业务上下文会输出无意义
空态，并按真实今天而非 Session 业务日组织。`query_user_data` 与 `mutate_user_data` 把多个领域
和条件参数塞进同一 Schema，模型容易混用字段。普通任务仍可能先加载 Skill、查询已注入事实、
再展开 Tool 组，造成额外模型步骤。

动作和业务记录使用 UUID 软引用。新 Agent 记录虽会确定性解析动作，但旧训练仍允许缺失动作
身份，Tool 也会要求模型复制长 UUID。记录写入时间取 Loop 首次领取时刻，不能显式表达历史
Session 日期、原始消息时间或用户修正的发生时间。

## 用户结果

1. Soma 以专业训练、饮食和体态教练身份工作；用户可调整表达人格，但不能移除安全、真实性、
   写入授权和 Prompt Injection 边界。
2. 普通建议仍应直接回答。选中快捷 Skill 后，首轮已经拥有完整 Skill、必要本机事实和绑定
   Tool，不再先调用 `load_skill` 或重复查询。未选 Skill 时的 Tool 注册见
   [PRD 032](032-default-full-tools-and-selected-skill-subset.md)：发送完整当前协议 Tool，
   不再把建议变成空集。
3. Session 最近十个完整来回保持原生角色；更早对话形成可展开、可追溯、可降级的滚动摘要。
4. 模型调用单一职责 Tool；训练记录和计划动作只引用短整型动作 ID。一堂课的多个新动作、多条训练记录应一次批量写入，新建记录 ID 由本机分配。
5. 用户继续旧 Session、跨午夜排队或重试时，记录仍落在真实业务日期与原始 Turn 时间；需要时
   可明确修正 `occurred_at`。
6. 安装过旧版本的用户打开 App 后会先看到可恢复的数据迁移进度；个人与演示空间全部完成迁移
   和校验前，不进入业务页面、不领取 Agent Job，也不接受新的业务写入。

## 产品规则

### Prompt 与上下文

- System Prompt 固定顺序为：固定身份、用户人格、固定契约、能力目录、Skill 目录。
- Skill 目录只披露 `name`、`description`、`when_to_use`；Tool 名称和 Schema 只进入 API
  `tools` 参数。
- User Prompt 固定注入可信时间和当前输入；身体、健身房、业务日记录、身体趋势、选中 Skill、
  摘要和媒体块只在真实非空时出现。禁止“未填写”“无记录”和虚假的零值占位。
- 最近十个完整 user-assistant 对作为原生历史消息发送。当前 Turn 不混入历史；Loop 内只追加
  assistant/tool 协议消息。

### Skills 与快捷入口

- 内置 Skill 是带三字段 frontmatter 的 Markdown；用户编辑形成 override，重置恢复内置正文。
- 用户可新增、复制、编辑、启用和删除自定义 Skill。Skill 不可声明代码、动态 Tool 或任意数据源；
  Tool 与上下文只能从 App 白名单绑定。
- 输入框上方最多显示六个可排序快捷 Skill，每个 Turn 单选。提交后清除界面选择，但 Job 保存
  选中 Skill 快照用于恢复和远程执行。

### 长会话压缩

- 第十一个完整来回出现时，在 ReAct Loop 前把已有摘要和新移出窗口的完整对交给小模型，生成
  一份完全替代的结构化摘要；不是字符串追加。
- 小模型缺失或校验失败时使用标准模型，再失败使用确定性 digest。任何压缩失败不阻止当前发送。
- Chat 显示可展开压缩事件卡；原消息、媒体、Trace 和 Tool 事实永不删除。
- 最近十对本身超预算时，从最旧完整对开始继续压缩，不拆对、不截字，并标记预算降级。

### 身份、关系与时间

- Tool 可寻址的身体业务实体使用本机单调递增 `Int64`。聊天、Agent、媒体和外部 Provider 身份
  继续使用 UUID 或字符串。
- 所有训练记录、模板动作和带练动作必须引用存在的 `ExerciseDefinition`；无动作身份不能创建。
- Session 保存业务日和时区。无显式时间时，新记录使用原始 Turn 在生效业务日上的本地时分秒；
  同一 Job 的排队、恢复和重试复用该值。
- “今天/昨天/具体日期”只覆盖当前 Turn；只有日期芯片更新 Session 默认业务日。
- 训练、饮食、身体的 create/update Tool 支持可选 ISO-8601 `occurred_at`；Tool 结果返回最终
  时间与来源。
- 旧 schema 在 App 根生命周期中触发阻塞式迁移。迁移按数据空间独立执行和校验，成功后持久化
  schema marker；失败保留原库，不以半迁移状态启动业务服务，并提供重试和不含身体事实的诊断导出。

### Tool 与远程协议

- 训练、饮食、身体分别使用 list/get/create/update/delete Tool；动作使用 search/create/update/
  archive/merge；计划使用 list/get/create/update/archive/delete/start。`create_exercise`
  接收 `exercise_names`，`create_workout` 接收 `workouts`；每条训练必须带有效 `exercise_id`，
  不得指定新建 `record_id`。create 每次都新增；纠正、补图和改已有记录必须使用对应 update
  工具和查询得到的 `record_id`。同一 ReAct Loop 可多次创建。
- Schema 禁止额外字段；Provider 支持时启用 strict，设备始终二次校验并返回结构化错误。
- 选中 Skill 时只发送绑定集合。未选 Skill 时发送当前协议全部 Tool，见
  [PRD 032](032-default-full-tools-and-selected-skill-subset.md)。
- iOS 继续是模型输入唯一组装方。Server 只验证、消费并执行同一 Envelope；版本不匹配时拒绝，
  不回退到旧 Prompt 或 Tool。

## 数据与隐私

- Skill override、自定义 Skill、快捷配置和压缩摘要只保存在本机；远程模式只随用户明确发送的
  具体 Job 临时提交必要快照，沿用既有 24 小时清理和 7 天硬上限。
- 压缩输入只包含当前 Session 已有文字、人工修订和短业务引用，不包含未选媒体、密钥、完整
  SwiftData、thinking 或原始 Tool 日志。
- Int64 只替代本机业务身份，不把身体数据库迁移到服务器，不增加账户或跨设备同步。

## 明确不在范围

- 不允许用户创建可执行代码 Tool、修改 Tool Schema 或绕过固定写入授权。
- 不增加后台主动教练通知；主动建议只发生在用户发起的当前 Turn。
- 不让 LLM 删除原始聊天或把压缩摘要作为业务事实来源。
- 不依赖 SwiftData 底层 SQLite 未公开自增行为。

## 验收

- 已有动作 ID 的多条训练记录一次模型调用和一次 `create_workout`。未选 Skill 的 Tool 集合验收见
  [PRD 032](032-default-full-tools-and-selected-skill-subset.md)。
- Prompt 快照证明空块完全省略、Tool 不进入 System、最近历史角色顺序正确。
- 压缩替换、双模型回退、确定性兜底、超预算和 Chat 事件卡均有确定性测试。
- 旧 UUID 数据迁移后统计、媒体、导出、计划快照和两个数据空间不丢失；训练关系完整。
- 启动迁移门禁证明迁移完成前业务 Root、Agent runner 和写入入口均不可用；迁移失败可重试，
  再次启动不会重复已经提交的数据空间。
- 新旧 Session、自然语言日期、日期芯片、跨午夜排队和重试时间均有固定 Clock 测试。
- 本地与远程 Envelope、Skill 快照、Tool Schema 和 assistant/tool 恢复链等价。
- `make check`、`make verify` 通过；快捷 UI 完成 iPhone 浅色/深色、Dynamic Type、键盘和
  VoiceOver 验收。

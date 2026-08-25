# ADR 0088：会话标题异步生成且手动编辑具有最高优先级

- 状态：已采纳
- 日期：2026-08-22
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：暂无
- 上游依据：[PRD 037](../prd/037-generated-editable-session-titles-and-single-row-composer-context.md)

## 背景

Session 标题既是本地可审查导航元数据，又需要模型理解首轮主题。若把标题塞进主 Agent 的最终
回复协议，会污染原生流式文字与 Tool Calling；若增加 `set_conversation_title` Tool，会把 UI
元数据错误扩张成模型可调用的业务协议。独立异步请求又存在迟到结果覆盖用户改名、重复请求和额外
数据流的问题，必须固定长期优先级和失败边界。

## 决策

1. `ConversationSession.title` 继续保存当前展示值，新增可选 `titleSourceRaw`：`fallback`、
   `generated`、`manual`。未知或旧库空值按 `fallback` 解释。
2. 优先级固定为 `manual > generated > fallback`。任何异步写回都重新按 Session ID 获取对象并
   检查来源；`manual` 与已经成功的 `generated` 均拒绝覆盖。
3. 首条用户消息同步产生确定性兜底。首个成功 ReAct 来回落盘后，App scoped
   `ConversationProcessingService` 启动独立标题 Task，同一 Session 同时最多一个；请求不阻塞
   Job 终态、聊天回复或 FIFO 队列。
4. 标题请求优先已启用且配置完整的小模型，失败后调用标准模型。两次都失败则不修改 Session；
   下一次成功 ReAct Turn 可以重试。确定性快捷训练不为标题额外调用模型。
5. 生成输入只含一个有界 user-assistant 可见文字对，不含媒体、Tool、Trace 或其他 Session。
   模型无工具、无业务写权限；输出经过本机确定性规范化并限制到 28 字。
6. 手动重命名规范化后最多 40 字，并保存为 `manual`。「恢复自动标题」先重建本地兜底、改回
   `fallback`，再在已有成功来回时走同一生成协调器。
7. 标题变更不调用 `touch`，因此不改变 `updatedAt` 和历史排序。可选来源字段进入备份 DTO；
   旧备份缺字段仍可解码。
8. 这次调用写入隐私安全诊断元数据（Provider、模型、档位、零工具），不保存输入全文，也不建立
   Agent Trace/Event Card；标题失败不是聊天 Turn 失败。

## 未选择的方案

- 不让主 Agent 返回 JSON 包裹的「标题 + 回复」：会破坏 Markdown 流和原生回复协议。
- 不新增标题 Tool：UI 导航元数据不属于身体业务工具，也不能被用户提示词间接覆盖。
- 不只比较标题字符串判断是否手动修改：用户可能把标题改成与兜底相同的文字，必须保存来源。
- 不在每一轮持续重新生成：标题跳动会破坏用户对历史列表的稳定认知，并增加无意义请求。
- 不让模型请求阻塞下一个 Agent Job：标题不是业务闭环的完成条件。

## 结果

### 正向影响

- 标题具备语义质量，同时保持发送即时反馈、失败可退化和用户最终控制权。
- 模型生成不进入 Tool 协议，不影响 Agent Job、Trace 和业务写入幂等边界。

### 成本与限制

- 每个成功生成的 Session 最多增加一次模型请求；小模型不可用时会使用标准模型。
- 远程持续模式若设备没有可用 BYOK 配置，只保留本地兜底，不能越权使用未定义的 Server 标题接口。
- 当前 schema 依赖可选字段的轻量推断打开；真实旧库仍需启动门禁与真机验收。

## 验证

- `ConversationSessionTitleTests` 覆盖来源优先级、规范化、生成档位回落和异步竞态。
- `DataBackupServiceTests` 的完整快照相等性覆盖来源字段往返与旧 JSON 缺字段兼容。
- 模拟器检查历史抽屉重命名、恢复自动标题、处理中改名和列表排序。
- `make check`、`make verify`。

## 参考

- [ADR 0015：按自然日解析当前对话 Session](../../0.0.1/adr/0015-daily-conversation-session-lifecycle.md)
- [ADR 0080：对话历史抽屉左滑删除聊天图](../../0.0.7/adr/0080-conversation-session-swipe-delete.md)
- `Soma/Models/ConversationSession.swift`
- `Soma/Services/ConversationSessionTitleService.swift`

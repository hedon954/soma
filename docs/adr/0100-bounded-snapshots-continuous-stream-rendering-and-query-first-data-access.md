# ADR 0100：有界快照、连续流式文本与查询优先的数据访问

- 状态：已采纳，Release 真机量化验收中
- 日期：2026-08-25
- 维护者：Soma maintainers
- 修订自：[ADR 0097](0097-current-baseline-performance-budget-and-cache-invalidation.md) 的长流分块展示、快照失效与数据库访问细则
- 上游依据：
  - [PRD 045](../prd/045-performance-reliability-and-bounded-data-access.md)
  - [BUG 0036](../bugs/0036-long-stream-continuous-text-and-completion-cliff.md)
  - [BUG 0037](../bugs/0037-insights-snapshot-stale-and-overfetch.md)
- 下游落地：
  - [数据库结构与 ER 图](../engineering/database-schema.md)
  - [验收矩阵](../acceptance.md)

## 背景

0.0.12 的稳定块和懒布局显著降低了有换行长流的持续成本，但“存储块等于展示块”仍让无换行正文
退化，完成态 Markdown 切换又制造一次全量主线程工作。进展页虽已异步聚合，却没有可靠的请求代际、
错误恢复和跨 context 失效语义。数据库侧还存在先全量 fetch 再过滤/计数的路径。

Soma 最低仍为 iOS 17。SwiftData `#Index` 是 iOS 18 引入的 schema 能力；不能为了性能修复静默
提高最低系统，也不能绕过 SwiftData 私自修改其 SQLite。现阶段先保证查询形状与返回规模有界，
物理 SwiftData 索引作为单独的最低系统与迁移决策处理。

## 决策

1. 一次 AI 回复始终是一条 `CoachMessage`。流式 `AgentTurnItem` 和最多 256 字符的内部块是状态
   投影，不是多条聊天消息，也不得在块之间插入展示字符。
2. 流式正文使用单一 TextKit 文本面；正常更新只追加已确认后缀。SwiftUI 不再为每个存储块创建
   一个文本 View。SSE 消费通过单飞 projection pump 与主线程解耦：主线程繁忙时合并积压正文，
   不能等待一次投影后把节流退化为逐 token 提交。自动滚动仍按既有节流与用户阅读状态执行。
3. 完成态 Markdown 的 block 解析和 inline attributed text 准备在后台完成，主线程只提交不可变
   属性文本。准备期间继续显示同一连续文本，避免空白或位置跳变。完成事务先清理 live 投影再
   发布持久化消息；完成态继续使用单一 TextKit 文本面，不为 Markdown block 创建数百个 SwiftUI
   子 View，也不在外层懒消息列表中嵌套内容高度持续变化的懒容器。
4. 当前会话流式期间始终跟随当前 `CoachMessage.id` 的底边。revision 观察者独立于可能被回收的
   Lazy row；内容增长、用户上滑或 geometry 瞬态都不得关闭跟随，流式结束后再执行一次底部归位。
5. 性能夹具必须覆盖无换行、混合 Markdown、SwiftData 持久化、live projection 清理和完成后交互；
   只持续发送、不进入完成态的夹具不能作为完整结论。
6. 异步页面快照使用显式 load phase 与单调 revision。失败必须可见且可重试；已有内容刷新失败时
   保留可读旧值。只有当前 request key 可以提交结果。
7. 快照失效以 `ModelContainer` 和相关实体为边界。同一数据空间的后台 context 保存必须生效；
   另一个数据空间不得导致无关刷新。
8. 只需要数量时使用 `ModelContext.fetchCount`，不得物化模型数组再 `.count`。需要明细时把时间、
   业务键、来源与状态谓词下推，并设置与 UI/协议一致的排序和 `fetchLimit`。
9. 本地 Job 领取由数据库选择当前数据空间最早的一条非终态记录，继续保留严格 FIFO 屏障；业务
   去重和 HealthKit 去重只查询可能命中的日期/业务键或外部身份，不整表拉入内存。
10. iOS 17 基线不添加 `#Index`。未来提高最低系统或建立版本化 schema 时，必须单独 ADR 评估
   `#Index`、现有用户 store 迁移与回滚；`businessID`/UUID 也只在领域唯一性已被证明时加唯一约束。
11. PostgreSQL 通过只向前 migration 为过期清理、撤销设备、按设备 token 删除和 outbox 聚合清理
    补索引；`agent_events(job_id, sequence)` 复用 unique constraint 自动索引，删除重复普通索引。

## 未采用方案

- 把每个流式 chunk 变成一条消息：会破坏回复、时间、反馈、复制和审计的一致身份。
- 完成前不展示正文或只定时重画全量 Markdown：前者牺牲流式体验，后者仍让成本随正文长度增长。
- 用 `try?` 把快照失败继续当空数据：用户无法区分真实空态、加载中和失败。
- 为了 `#Index` 直接把最低系统改成 iOS 18：这是产品兼容与数据迁移决策，不是局部性能修复。
- 直接操作 SwiftData 管理的 SQLite 索引：绕过 schema 所有权，升级与迁移行为不可审查。
- 给每列都加 PostgreSQL 索引：索引有写放大和空间成本，只覆盖已存在的谓词、排序与清理路径。

## 结果

- 长流每次增量的文本处理成本与历史长度解耦，完成态昂贵准备离开主线程。
- 进展页不再以永久空白表达失败；保存、请求代际和重试有确定语义。
- 纯计数不再分配模型数组，去重与领取查询的返回规模由业务边界限定。

## 验证

- `make check`、单元压力测试、Server migration 测试、真实 PostgreSQL `EXPLAIN`（环境可用时）和
  Release 真机 Time Profiler/SwiftUI/Animation Hitches 共同验收；缺少后两项时不得宣称性能已量化达标。

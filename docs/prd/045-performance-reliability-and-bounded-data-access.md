# PRD 045：长流与进展可靠性及有界数据访问

- 状态：已采纳，已实施于 0.0.14；Release 真机量化验收中
- 日期：2026-08-25
- 修订自：[PRD 044](044-behavior-preserving-modernization.md) 的 0.0.13 行为保持基线
- 后续修订：[PRD 046](046-coach-records-and-goal-directed-progress.md) 在既有有界查询上修订会话初始定位、记录编辑和目标导向进展
- 上游依据：
  - 用户对长流后段/完成后卡顿、进展永久空白和数据库索引的明确反馈
  - [BUG 0036](../bugs/0036-long-stream-continuous-text-and-completion-cliff.md)
  - [BUG 0037](../bugs/0037-insights-snapshot-stale-and-overfetch.md)
- 下游落地：[ADR 0100](../adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)

## 背景

0.0.12 已明显降低长流 CPU，但无换行正文仍会让尾块无限增长，结束时同步 Markdown 解析和布局又
让整个 App 继续卡顿。进展页的异步快照在失败、后台 context 保存和请求乱序时可能永久显示空白，
而重新切 Tab 才恢复。设备端还存在整表读取后计数、去重或选一行的查询反模式；Server 的部分清理
和按设备删除路径缺少物理索引。

## 用户结果

1. 一轮 AI 回复始终是一条消息；流式增量只更新这条消息的连续正文，不出现多条碎片消息。
2. 长段落即使没有换行，后段也不应因历史正文增长而持续恶化；流式完成后 App 不应承担同步全量
   Markdown 解析造成的卡顿。
3. 流式期间始终跟随当前 AI 回复的真实尾部；用户不需要手动向下追赶不断增长的内容。
4. AI 回复时间从流式开始到结束始终固定在消息左下角；完成不会改变消息身份或元信息位置。
5. 进展页首次读取有明确加载态；失败可重试；已有内容刷新失败时继续可读，不永久伪装成空数据。
6. 在后台或另一个同数据空间 context 写入训练、饮食、身体、健身房或成功回复后，进展页原位刷新；
   另一个数据空间不会触发无关刷新。
7. 只展示数量的指标直接向数据库请求 count；图表和最近活动只读取业务需要的时间窗口与条数。
8. 本地 Job 领取、业务去重和 HealthKit 去重不再把完整表拉进内存；Server 清理和按设备删除使用
   与真实查询匹配的索引。

## 产品与兼容边界

- 最低系统继续为 iOS 17，个人与演示空间及现有 SwiftData store 不重建。
- SwiftData `#Index` 需要 iOS 18；0.0.14 不静默提高最低系统，也不直接修改框架管理的 SQLite。
  设备端先用谓词、排序、`fetchLimit` 和 `fetchCount` 把读取规模约束为业务常数。
- 未来增加设备端物理索引必须单独决定最低系统、VersionedSchema/迁移和回滚，不以局部宏改动混入。
- PostgreSQL 只通过新 migration 向前增加索引和删除重复索引，不修改已执行 migration。
- 不新增账户、身体数据出网、云端业务事实或日志中的敏感内容。

## 验收

- 单元测试覆盖无换行硬分块的文本等价与有界尾部、TextKit 每字符只追加一次、后台 Markdown 准备、
  进展 revision 乱序、同/异 container 失效和超过旧上限的 `fetchCount`。
- 压力测试覆盖 1,200 条终态 Job 后的严格 FIFO 领取；静态门禁禁止业务/HealthKit 去重恢复整表读取。
- UI 夹具覆盖无换行与混合 Markdown 的真实保存、live 清理、完成后四 Tab 往返，以及流式中上滑后
  自动回到真实尾部。
- Server migration 测试固定过期 nonce/challenge、撤销设备、按设备 token 与 outbox 聚合索引，并
  删除与 unique constraint 重复的 Event cursor 索引。
- `make check`、`make verify` 和 `make perf-check` 通过；Release 真机分别录制 Time Profiler、SwiftUI
  与 Animation Hitches。没有真机 Trace 时只能确认实现与门禁，不能宣称性能预算已经量化达标。

# BUG 0037：进展快照失效遗漏与全量读取造成空白和延迟

- 状态：已修复，待 Release 真机交互复验
- 日期：2026-08-25
- 影响：进入进展页偶发永久空白，切走再回来才出现；纯数量指标还会物化不需要的完整模型
- 上游依据：用户真机反馈
- 下游落地：
  - [PRD 045](../archive/0.0.14/prd/045-performance-reliability-and-bounded-data-access.md)
  - [ADR 0100](../archive/0.0.14/adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)
  - [PRD 059](../archive/0.0.23/prd/059-coach-ids-progress-and-required-zeros.md)

## 症状

进展页异步构建快照，但错误被静默吞掉，也没有可见加载或重试状态。后台 `ModelContext` 保存时，
旧过滤只认可当前 context 或特定通知对象，可能漏掉同一 container 的变更；同时较旧请求完成后可以
覆盖较新 revision。结果是页面看起来像“懒加载一直没有完成”，重新切 Tab 才触发下一次加载。

## 根因

- 快照请求没有显式 `idle/loading/loaded/failed` 生命周期，`try?` 把失败变成永久空态。
- 失效判断绑定 context 实例而非共享 `ModelContainer`，遗漏后台写入。
- 缺少 revision token，异步完成顺序与用户看到的快照顺序不一致。
- “足迹数量”等只需要数量的指标仍读取最多上千条消息再在内存计数。
- 健身房、饮食等辅助数据读取上限明显超过页面实际展示需要。

## 修复

- 引入单调 revision 状态机，只接收当前 request key；旧请求完成后立即为最新 revision 补请求。
- 同一 `ModelContainer` 的相关保存都使快照失效；另一个数据空间的 container 不触发刷新。
- 首次加载显示进度；失败显示可操作重试；已有内容刷新失败时保留旧快照并显示非阻断错误。
- 训练、身体和 Session 仅保留图表需要的 95 天有界明细；饮食只取最近 30 条。
- 记录卡数量、成功 AI 足迹、器材和动作数量统一使用数据库 `fetchCount`；当前健身房用谓词和
  `fetchLimit = 1`，不再读取完整候选集合。

## 回归门禁

- 压力测试插入超过旧上限的成功消息，`fetchCount` 必须返回完整数量且排除用户消息。
- 测试覆盖同 container 后台保存会失效、另一 container 不失效，以及旧 revision 完成不能覆盖新值。
- `make perf-check` 禁止进展页恢复全量消息、器材、动作和训练子表扫描。
- Release 真机验收首次进入、刷新失败后重试、后台记录写入后原位刷新和快速切 Tab 往返。

# BUG 0050：教练页前台恢复再次冻结

- 状态：已实施第二阶段修复，待 Release 真机量化
- 发现日期：2026-09-02
- 影响范围：教练长会话从后台或锁屏回到前台后的首个滚动、输入和触摸
- 修订自：[BUG 0043](0043-coach-foreground-recovery-main-thread-stall.md) 的首次修复
- 上游依据：维护者真机反馈
- 下游落地：
  - [PRD 052](../archive/0.0.19/prd/052-coach-training-and-lifecycle-reliability.md)
  - [ADR 0113](../archive/0.0.19/adr/0113-capture-and-foreground-lifecycle.md)

## 症状

回到已经可见的教练页后仍短时无法滑动，等待一会才恢复。症状与 BUG 0043 相同，说明首次只限制
查询条数和让出 MainActor 仍不足。

## 根因

当前把“内存警告清空缓存、首帧长会话重排、Job 恢复、远程撤销、自动备份”列为待量化竞争机制，
不提前指定唯一根因。静态路径确认这些工作都可能紧邻 scene active；各自占比必须由同口径 Release
真机 signpost、Hangs 和最大主线程栈决定。

## 修复

- scene active 先取消未完成自动备份，保留上一份成功备份；一次真实显示帧之后才启动可取消的
  generation 恢复。
- Job 候选在独立读取上下文只返回稳定 ID，MainActor 重新 fetch/写入；远程网络不占首交互区间。
- 内存警告保留当前 Session 最多 10 条、2 MB 的不可变渲染 DTO，后台按消息 ID/revision 对账。
- 增加 scene、首帧、可交互、缓存、备份、远程撤销、Job 与滚动布局 signpost。

## 回归门禁

- 自动化：generation 取消/去重、下一帧门禁、FIFO 稳定 ID、缓存条数与成本上限。
- 手工：长虚构会话 Home→App 5 次、锁屏→App 5 次及一次内存警告后复测；warm p95 `<100ms`，
  无 `>100ms` 主线程停顿和 Hangs，立即可滑动/输入。
- 风险：没有上述同口径真机证据前不得标记完成；超预算继续按最大栈消除。

## 验证

代码、单元测试和 signpost 已落地；Release 真机量化待执行。

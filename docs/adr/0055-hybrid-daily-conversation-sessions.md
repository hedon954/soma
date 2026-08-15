# ADR 0055：自动按日解析并允许显式继续旧 Session

- 状态：已采纳
- 日期：2026-08-11
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0015](0015-daily-conversation-session-lifecycle.md) 中只读历史与无手动继续旧会话的边界
  - [ADR 0022](0022-user-controlled-conversation-sessions.md) 中跨日、冷启动和 foreground 永不自动切换的边界
- 后续替代：[ADR 0072](0072-session-business-date-and-record-occurrence-time.md) 增加可编辑 Session 业务日与当前 Turn 日期覆盖
- 上游依据：[PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)

## 背景

完全用户控制会让重新进入 App 的新一天仍停在旧聊天；完全每日强制切换又会抢走用户刚主动
选择的旧会话。Session 需要同时表达默认日常边界和明确的继续意图。

## 决策

1. 冷启动和 `scenePhase == active` 时按设备自然日解析：最新用户消息在今天则复用其 Session；
   否则复用今天唯一空 Session或新建。
2. 重复解析幂等并按数据空间隔离。Turn 提交后冻结 Session，不因界面切换或午夜迁移。
3. 手动选择旧 Session 形成仅当前前台生命周期有效的显式覆盖；发送前解析尊重该覆盖。
4. App 跨午夜保持前台时，发送前重新解析；若无显式覆盖则进入今天 Session。
5. ADR 0015 的旧消息迁移、Session 持久化和稳定滚动继续有效；ADR 0022 的抽屉、新建、选择、
   可继续和在途 Turn 归属继续有效。

## 未选择的方案

- 永远恢复 preferred session：不能形成用户期待的新一天边界。
- 午夜定时强制切换：会中断正在进行的 Turn，也无法表达主动继续旧会话。

## 结果

### 正向影响

- 默认每天获得清晰会话边界，同时保留继续旧对话的控制权。

### 成本与限制

- Controller 需要记录前台生命周期内的手动覆盖，并在发送前参与解析。

## 验证

- 固定 Calendar/Clock 覆盖当天复用、跨日新建、重复 active、空 Session、手动覆盖和跨午夜发送。

## 参考

- [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)

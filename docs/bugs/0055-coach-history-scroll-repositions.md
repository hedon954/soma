# BUG 0055：上滑聊天历史时视口持续重定位

- 状态：已修复，待真机长会话复验
- 发现日期：2026-09-08
- 影响范围：教练消息列表上滑阅读、分页加载、含原位记录卡的历史气泡
- 上游依据：维护者复现：上滑过程中列表不断跳，滑不到目标位置
- 下游落地：
  - [PRD 052](../archive/0.0.19/prd/052-coach-training-and-lifecycle-reliability.md)
  - [ADR 0125](../adr/0125-eager-loaded-coach-messages.md)
  - [ADR 0112](../archive/0.0.19/adr/0112-coach-scroll-and-session-behavior.md)

## 症状

在已有历史的会话里往上滑，视口反复被拽走，无法停在要读的那一段。不是只有到顶分页才跳，
滑动中间也会跳。

## 根因

满 10 条后外层改用 `LazyVStack`。离屏气泡被卸载，卡片 `@State` 丢掉；滚回来时先以 1pt
占位再异步回填，高度突然撑开。内容尺寸一变，`defaultScrollAnchor(.top, for: .alignment)`
和高度 Preference 跟着改，父层 `messageListPosition` 反复失效。懒栈里「加载更早」的
`onAppear` 还会在估算单元出现时触发分页，和手势抢 `scrollTo`。

## 修复

- 已加载窗口固定用即时 `VStack`；仍按 30 条分页。
- 记录卡和完成态正文写入常驻缓存；切 Tab／Session 命中即终态，不再 1pt 占位或
  Incremental→Markdown 切换。
- 去掉滑动过程中的 alignment 锚点；「加载更早」只在真正进入视口或点按钮时触发。

## 回归门禁

- 自动化：`make perf-check` 禁止消息列表 `LazyVStack`、哨兵 `onAppear` 和 `.alignment` 顶锚。
- 手工：真机打开 30 条以上会话，上滑阅读应跟手、不跳；到顶才再多 30 条且当前位置不丢。
  切 Session、切 Tab、连续输入不得出现秒级卡顿。
- 仍无法自动化的风险：真机 120 Hz 与大会话卡片回填的最终手感。

## 验证

单元与 `make check` 热路径门禁已更新。真机覆盖安装后由维护者上滑复验。

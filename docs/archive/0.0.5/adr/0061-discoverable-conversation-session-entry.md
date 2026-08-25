# ADR 0061：会话抽屉同时保留可见时间按钮与边缘手势

- 状态：已采纳
- 日期：2026-08-12
- 维护者：Soma maintainers
- 部分替代：[ADR 0022](../../0.0.1/adr/0022-user-controlled-conversation-sessions.md) 中移除历史时钟图标、只保留
  隐藏手势与 VoiceOver 的入口选择
- 后续替代：暂无
- 上游依据：[PRD 026](../prd/026-guided-workout-record-projection-camera-failures-and-session-entry.md)

## 背景

左缘右滑适合熟悉手势的用户，但没有视觉线索；VoiceOver 自定义操作也不能帮助普通用户发现
历史会话。会话列表承担继续旧对话和新建 Session 的核心导航，完全隐藏会增加不可发现性。

## 决策

1. 教练页左上角恢复 `clock.arrow.circlepath` 系统图标按钮，点击打开既有 Session 抽屉。
2. 左缘右滑和 VoiceOver“打开历史对话”继续保留，三种入口调用同一状态与业务操作。
3. 按钮使用“历史对话”无障碍标签；不新增页面、复制列表或改变 Session 生命周期。

## 未选择的方案

- 继续只保留边缘手势：没有可发现线索，已被真实使用反馈证明不足。
- 新增独立历史 Tab：会扩大顶层信息架构，并重复现有抽屉。
- 用文字常驻按钮：占用导航标题空间，系统时钟图标已能表达时间历史。

## 结果

### 正向影响

- 新用户可以直接发现会话历史，熟悉手势与 VoiceOver 的用户无需改变习惯。

### 成本与限制

- 导航栏恢复一个常驻次级控件，但它直接服务跨会话导航而非调试能力。

## 验证

- iPhone 17 Pro 模拟器已检查浅色、深色与无障碍大字；按钮不遮挡标题和安全区，点击打开既有抽屉。
- UI 语义快照确认按钮 label 为“历史对话”，图标为 `clock.arrow.circlepath`；既有边缘手势与
  VoiceOver 自定义操作仍调用同一抽屉状态。
- `make verify` 与会话生命周期测试继续通过。

## 参考

- [ADR 0055：自动按日解析并允许显式继续旧 Session](../../0.0.4/adr/0055-hybrid-daily-conversation-sessions.md)

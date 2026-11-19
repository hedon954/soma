# BUG 0076 · 补餐或发送时键盘焦点循环

- 状态：已修复输入区缺陷，真机待复测
- 上游依据：[PRD 082](../prd/082-coach-progress-reliability.md)

## 症状

保留教练页的当天补餐提醒，等待一轮 Agent 回复完成，再点击「记录」。真机上输入框未能开始编辑，界面无响应。已打开键盘时，点击发送带三张图片的文字草稿也能触发界面无响应，有无补餐提醒均出现过。MetricKit 的补餐报告为 `scene-update` 超时，发送报告为 `process-exit` 超时，两种均由系统看门狗以 `0x8BADF00D` 终止。

## 根因

点击「记录」同一轮更新中会写入带日期的草稿，并要求编辑器开始聚焦。旧编辑器在 `updateUIView` 内同步切换第一响应者，键盘会改变安全区。同时，候选宽度的测量会修改实际编辑器的滚动属性。回归测试在旧代码上确认，测量一个更窄的候选宽度即可错误开启滚动。

实际发送启动提交时，`isSending` 变化会请求收起键盘。用相同 iOS 版本的系统符号还原真机日志，一份发送报告显示在 SwiftUI 更新 `UIViewRepresentable` 期间调用了 `UITextView.resignFirstResponder()`，随后转入 SwiftUI 焦点树计算和 AttributeGraph 循环。另一份发送报告与补餐报告有 42 个连续栈帧一致，包括 UIKit 第一响应者更新、SwiftUI `FocusBridge` 和 AttributeGraph。发送和补餐共用同一个编辑器，分别触发焦点关闭与打开。

## 修复

在当前视图更新返回后执行焦点切换，编辑器卸载时取消待处理请求。候选宽度只用于返回高度。滚动开关由 UIKit 按实际宽度布局时更新，只在需要切换时设置。日期和餐次预填、可继续输入、五行上限与长文本滚动沿用现有交互。

## 回归门禁

- `CoachDraftEditorTests` 检查候选宽度不会改变滚动状态，实际布局仍能在五行溢出时开启内部滚动。
- `LibraryAndMealsUITests.testTodaysMealBackfillFocusesAfterAgentReply` 用虚构 Agent 流经过实际持久化投影，浅色、深色检查点击后的带日期草稿、键盘与输入，退后台再回前台核对草稿。修改前的 iOS 26.5 模拟器可以走通点击流程，未复现真机超时。
- `LibraryAndMealsUITests.testSendingThreePhotosFromTheFocusedComposerAfterAgentReply` 覆盖有无提醒两种情况下从已聚焦的输入框发送文字和 3 张虚构附件。校验键盘退出、消息与附件落盘、输入区附件清空。测试以无 Key 的暂存状态确认提交成功。
- 真机复测两个入口。补餐核对预填、键盘弹出与继续编辑。发送核对键盘收起、消息带齐三张图片，以及已配置模型时开始回合。

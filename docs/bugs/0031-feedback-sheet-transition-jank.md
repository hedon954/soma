# BUG 0031：逐回复反馈页弹出与收起卡顿

- 状态：已修复，待真机手感复验
- 发现日期：2026-08-23
- 影响范围：教练页逐回复反馈入口、反馈编辑器展开与收起
- 上游依据：[PRD 042](../archive/0.0.11/prd/042-user-controlled-recovery-message-feedback-and-action-art.md)
- 下游落地：
  - [ADR 0093](../archive/0.0.11/adr/0093-bounded-per-reply-multimodal-feedback-context.md)
  - [PRD 048](../prd/048-reviewable-record-derivation-and-user-controlled-interruption.md)
  - [ADR 0106](../adr/0106-reviewable-derived-records-and-manual-interruption.md)

## 症状

点按 AI 回复时间旁的反馈按钮时，反馈页弹出不连贯；下拉或点返回收起时也有明显停顿。按钮本身
被整行 `Spacer` 推到消息区右边，和时间形成不必要的大段空白。改成原位展开后，如果编辑器下半部
落在可视区域外，用户仍需手动滑到底部才能开始输入，展开动作没有完成视口衔接。

## 根因

第一版实现为逐回复反馈新增了全量 `AgentTrace` 查询，并在点按按钮的同一主线程事件中扫描消息、
Job、Trace、解码 Span 并构造完整反馈上下文，然后才改变 Sheet 状态。即使随后改成延迟组装，
Sheet 仍然需要创建新页面、建立导航容器并执行系统转场；根聊天树和复杂消息布局也参与状态更新。
对于本质上只是一段短表单的交互，这些成本没有用户价值。

## 修复

- 元信息行移除弹性占位，反馈图标与时间保留 8 pt 可见间距，并以 44 pt 触达区域承载
  `text.bubble` 线框图标。
- 每条回复的叶子 `AssistantFeedbackButton` 自己持有原位展开状态，只携带稳定的 AI 消息 ID；
  点按后在当前消息下方直接展开紧凑 `FeedbackView`，不创建 Sheet、导航栈或页面转场。
- `CoachView` 不再订阅全部 `AgentTrace`；上下文只在用户点按发送时按消息 ID 定向读取。
- 临时视频清理转入 utility 后台任务，收起交互的主线程路径不执行文件删除。
- 编辑器由当前回复右侧的关闭图标直接收起，并移除用户不需要的上下文说明区块。
- 每条回复增加独立的编辑器底部锚点；只有用户点按展开时才发出滚动意图，等待 SwiftUI 完成本轮
  布局后由聊天 `ScrollViewReader` 平滑滚到该锚点。收起不滚动，也不触发上下文查询。
- 邮件服务明确返回成功后，由 `FeedbackView` 回调当前回复的叶子组件自动收起；失败路径不调用
  回调，继续保留展开状态、文字、评分和附件。设置页通用反馈仍显示原有成功确认。

## 回归门禁

- 自动化测试或静态检查：上下文按消息 ID 读取测试；`make check` 禁止 `CoachView` 全量查询
  `AgentTrace`、禁止逐回复反馈恢复 `.sheet`、禁止入口预组装上下文，并禁止恢复已删除的上下文提示；
  同时要求消息专属底部锚点、展开滚动意图和 `anchor: .bottom` 的聊天滚动落点同时存在。
- `FeedbackSubmissionTests` 覆盖逐回复成功后收起、设置页成功后确认的分流；静态门禁要求成功回调
  由叶子组件消费并把 `isExpanded` 置为 `false`。
- 手工验收：在浅色、深色 iPhone 模拟器和真机连续展开、收起反馈编辑器，确认没有页面切换；
  时间与图标同排并保留 8 pt 可见间距，关闭按钮可见且可访问；从编辑器底部在屏幕外的状态点按
  反馈，确认自动平滑滚入完整输入区，收起后不跳动。
- 使用虚构反馈验证发送成功后编辑器自动收起；断网发送失败时编辑器继续展开，文字、评分和附件不丢失。
- 仍无法自动化的风险：复杂长会话中的原位布局手感仍需真机确认。

## 验证

- `make check` 与 `make verify` 通过；iOS 558 个 XCTest 与 7 个 Swift Testing 测试均为 0 失败，
  Server 30 个测试通过，1 个需 PostgreSQL 环境的测试按预期跳过。
- iPhone 17 Pro（iOS 26.5）模拟器浅色、深色实测：反馈编辑器在同一消息下方直接展开和收起，
  没有页面或 Sheet；布局完成后一次平滑滚动让评分、输入框、附件入口和发送按钮完整可见，收起
  不发出额外滚动意图；时间与图标同排、8 pt 可见间距，VoiceOver 可读展开状态。
- 本次自动滚动修订已签名安装并启动到 iPhone 17 Pro Max：`Soma 0.0.10 (14)`；`devicectl`
  只读核对显示主 App 与 Widget Extension 进程均在运行。安装与启动证明部署闭环，最终触感仍由
  维护者在设备上确认。

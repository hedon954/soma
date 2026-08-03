# BUG 0005：远程 Agent 丢失流式体验并引入固定轮询延迟

- 状态：已修复，待真机网络与后台体验确认
- 发现日期：2026-08-03
- 影响范围：开启“后台持续处理”后的首段文本、Tool 往返和最终回复投影
- 修订自：[BUG 0004](0004-agent-background-stream-interruption.md) 的远程持续执行闭环
- 下游落地：
  - [ADR 0037](../adr/0037-backend-transparent-streaming-and-notification-wake.md)
  - [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)

## 症状

相同短消息在“本次可后台继续”模式下长时间没有文字，最终答案一次性出现；“本次仅本机”则
能很快显示首段文本。需要设备 Tool 的记录任务还会在每轮模型与 Tool 之间出现额外停顿。

## 根因

1. Server Provider 使用 `stream: false`，只在模型完成后写最终 output。
2. Worker 无任务时固定等待一秒再领取新 Job。
3. Server SSE 自身每秒查询 Event，未由 Event append 主动唤醒。
4. iOS Remote Backend 未消费 SSE，而是每次补拉一页后固定两秒再重试。
5. Job、调度与用户体验 Event 没有明确分层，Remote Backend 使用了独立 UI 投影代码。

持久队列本身不是根因；问题是健康路径仍然依赖轮询且远端没有产生文本增量。

## 修复

按 [ADR 0037](../adr/0037-backend-transparent-streaming-and-notification-wake.md)：

- Local/Remote 输出同一种体验 Event；
- Provider 使用流式 Tool Calling并合并文本 chunk；
- PostgreSQL `LISTEN/NOTIFY` 唤醒 Worker 与 SSE；
- iOS 前台持续消费 SSE，cursor 分页只负责恢复；
- 设备 Tool Result 立即重新唤醒 Worker；
- Job 内部状态不再生成用户可见事件卡片。

## 回归门禁

- 自动化测试或静态检查：
  - Provider 请求启用 stream，并在完整答案前产生 text Event；
  - Job/Event/Tool Result 通知可立即唤醒等待者；
  - SSE 断线按 cursor 恢复且不重复；
  - Remote 文本 chunk 逐段投影，最终 output 不重复附加；
  - Local/Remote 规范化体验 Event 序列相同；
  - 不允许健康路径用固定一秒或两秒轮询驱动进展。
- 手工验收：
  - 使用虚构文本对比“本次仅本机”和“本次可后台继续”的首段文字与卡片顺序；
  - 在模型流、Tool Request、Tool Result 后和最终回复四个阶段切换网络；
  - 按 Home 后让纯远程任务完成；设备 Tool 任务应等待，回前台后立即继续。
- 仍无法自动化的风险：
  - 真机网络、服务器部署区域和管理模型本身的生成速度；
  - iOS 挂起时设备 Tool 无法执行。

## 验证

- 2026-08-03：`make verify` 通过，包括文档生命周期、格式、lint、Server TypeScript、14 项
  可运行 Server 测试、iOS Simulator build 和全量测试；真实 PostgreSQL 集成项因未配置
  `SOMA_TEST_DATABASE_URL` 按约定跳过。
- 2026-08-03：另行启动隔离的临时 PostgreSQL，`npm run test:postgres` 无跳过通过，并实际
  覆盖 Job/Event commit 经 `LISTEN/NOTIFY` 唤醒等待者；测试结束后数据库进程已停止。
- 2026-08-03：通过 XcodeBuildMCP 在 iPhone 17 Pro Simulator 完成 build、install、launch，
  并确认教练主界面可访问；本次没有修改 View 布局。
- 2026-08-03：使用本机 Apple Development Team 完成连线 iPhone 的签名构建和安装；设备当时
  处于锁定状态，因此系统拒绝自动启动，需解锁后手工打开 Soma。
- Local/Remote 首段时间、Tool 往返、Home/锁屏和网络切换仍由维护者使用虚构输入确认，不能
  由构建、安装或模拟器结果替代。

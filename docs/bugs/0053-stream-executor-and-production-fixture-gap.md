# BUG 0053：原始流式处理抢占主线程，性能夹具未覆盖生产链路

- 状态：已修复并通过双机虚构生产链路采样；真实网络会话持续卡顿待复验
- 日期：2026-09-05
- 部分替代：[BUG 0024](0024-streaming-cross-actor-swiftdata-crash.md) 的原始 chunk 主线程要求
- 修订自：[BUG 0036](0036-long-stream-continuous-text-and-completion-cliff.md) 的长流与完成态验证

## 症状

用户再次报告长流式期间和结束后全 App 卡顿，模型输出有时像自我讨论草稿；既有本地门禁通过却没有覆盖生产处理边界。

## 根因

1. `AIService` 的 SSE 生产 Task 继承 MainActor，在 UI 执行器逐行解析 JSON。
2. Worker 虽是非隔离类型，Deadline 的 `onChunk: @MainActor` 仍把正文、思考与工具参数累积送回主线程。合批只限制了 UI 投影，没有隔离原始消费。
3. `pendingLiveTextSnapshot` 在判断事件类型前先合并完整正文；增量和 Span 都重复复制后丢弃。
4. 旧夹具直接调用 live projection，跳过生产边界；混合 Markdown 只有 3 轮历史，没有覆盖懒消息列表。

这些遗漏不等于用户“完成后长期卡顿”的唯一根因。邮件慢模型 Span 是网络/模型耗时；附近 MetricKit 是 process-exit watchdog，不能直接当作渲染根因。报告缺少原始 SSE，不能从文字口吻判断实际字段。

## 修复

- SSE 生产任务显式脱离 MainActor，由流终止回调取消；原始 chunk 回调不再隔离到 UI。
- 保留 Worker 合批 `project: @MainActor` 和 SwiftData/Observable 入口断言，不能恢复跨线程业务写入。
- 只在正文完成、Turn 完成或失败时物化完整文本快照，其他事件提前返回。
- `long-stream-production-completion` 使用 39 轮虚构历史，经过 Deadline、Worker、Pump、真实持久化和完成事件；结束后验证四 Tab 与输入。
- 静态门禁不再把旧的主线程 chunk 处理当作安全要求。
- 同批补齐 `reasoning_content` 为 null/空串但厂商别名有内容的情况；只归一到思考字段，不改写正文。已有思考卡完成后收起的行为保持不变。

## 回归门禁

执行器与别名确定性测试、静态隔离约束、生产链路长流 UI 测试、完整 `make verify`；Release 真机分别记录完成前后表现，不把模型耗时或简化夹具结果当成整个 App 已修复。

## 验证

- `AgentStreamExecutionBoundaryTests` 先复现 6 次主线程断言失败、4 次思考别名断言失败；修复后通过。
- 17 Pro Max Release 基线：75 秒无换行长流，完成后 40 次 Tab 切换；p95 76.803ms、max 86.446ms，没有录到大于 250ms 的 Hangs。
- 基线仍是旧简化夹具，不能据此宣布生产卡顿已解决。Xcode 首次导出崩溃，保留原 trace 后再次导出成功；本地证据在 `build/performance/baseline-20260905/`。
- 新生产夹具：39 轮虚构历史、240 段 Markdown、75 秒 Release 采样，完成后各 40 次 Tab 切换。17 Pro Max p95 76.942ms、max 83.124ms；14 Pro Max p95 86.040ms、max 106.247ms。两机均无大于 250ms 的 Hangs。14 Pro Max 的 Hang 表首次导出崩溃，同一 trace 再次导出成功。
- 该夹具覆盖真实 Deadline、Worker、Pump、持久化与完成态，但不连接模型，也不读取个人会话；这不是修复前后的同口径加速比，不替代真实网络、历史数据与锁屏恢复验收。
- 最终 `make verify`：727 项 XCTest、7 项 Swift Testing 通过；Server 39 项通过，1 项数据库测试因未配置测试库跳过。生产链路 UI 回归验证完成后 Tab 切换和输入。
- 长流 UI 批次 8 项中 7 项首轮通过；历史分页用例误用增长到 73 屏的尾消息，12 次上滑未触达顶部。改用仍有 39 轮历史的短尾夹具后，保留 10→20 条断言，独立复跑通过；没有修改 App 分页规则或降低断言。
- Release 0.0.18 (22) 已安装并正常启动到两机，匹配二进制/dSYM UUID 为 `78BD3F7D-90B9-3721-B010-25BE21EFA42B`。本地证据在 `build/performance/production-20260905/`、`build/performance/production-14pm-20260905/`，不提交个人设备 Trace。

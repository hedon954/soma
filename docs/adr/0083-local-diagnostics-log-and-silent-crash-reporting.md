# ADR 0083：本机滚动诊断日志与默认静默的崩溃上报

- 状态：已采纳，个人使用阶段；对外分发前必须补明确授权
- 日期：2026-08-20
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0053](0053-personal-only-direct-qq-mail-feedback.md) 中邮件只承载用户明确填写内容的边界；个人阶段 QQ→Gmail 投递路径与凭据位置继续有效
  - [ADR 0054](0054-device-executed-chat-feedback-tool.md) 中只有用户明确意图才触发投递的边界；`submit_feedback` 的模型可控内容与设备执行语义继续有效
- 后续替代：暂无
- 上游依据：
  - [PRD 033](../prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)
  - [BUG 0024](../bugs/0024-streaming-cross-actor-swiftdata-crash.md)
  - [BUG 0025](../bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md)
- 下游落地：[BUG 0028](../bugs/0028-remote-model-tool-list-missing-from-logs.md)

## 背景

流式回复期间的闪退和带练录像的提前结束都发生在真机，事后只剩一句用户描述。`os.Logger`
在进程被杀后不可检索，Xcode 也不一定连着设备。BUG 0024 与 BUG 0025 的定位都依赖反复复现，
成本很高。

同时「模型说自己没有饮食写入工具」这种问题，如果不记录当轮真正注册的工具名，就只能靠猜。

## 决策

1. 新增 `DiagnosticsLogStore`：Application Support 下的双文件滚动日志（各约 512KB），串行写入，
   记录启动与前后台切换、每次模型调用（provider/model/tier/skill/工具名与数量/消息数）、
   Tool 执行结果、Turn 终态和录像阶段。写入前恒定脱敏 API Key 与 Authorization，不写媒体 Base64。
2. 新增 `AppRunSentinel`：UserDefaults 记录本次前台运行标记与最后一次 session/turn 活动。
   上次运行没有干净结束即视为异常终止，用于覆盖 MetricKit 未投递的情况。
   哨兵只在真实运行里生效：单测宿主是 App 本身、每轮测试结束都被杀进程，所以测试进程里
   既不置位也不上报；附着调试器的运行结束同样不作为崩溃证据，只写一条日志。
3. 崩溃证据同时来自 MetricKit `MXCrashDiagnostic`（异常类型、终止原因、callStackTree）与哨兵。
4. 新增 `CrashReportComposer` 组装纯文本报告：设备与版本、崩溃类型与堆栈、诊断日志尾部、
   崩溃时所在 Session 的消息与最后一次 Job/Trace 摘要（含该轮工具清单）。各段独立截断。
5. 新增 `DiagnosticReportStore` 与 `DiagnosticReportMailer`：报告先落盘，再以独立主题和 `.txt`
   附件复用现有 SMTP 链路发送，不走用户反馈的 5,000 字校验；失败留盘，下次启动重试，最多保留 5 份，
   成功后删除。
6. 默认静默发送，高级设置提供「自动发送崩溃诊断」总开关、「查看上次报告」与「丢弃待发送报告」。
   当前阶段只有维护者本人使用，报告优先完整；对外分发前必须改为一次性明确授权，并由新 ADR 记录。

## 未选择的方案

- 不接入第三方崩溃 SDK。它会把身体数据所在进程的符号、日志与设备标识交给外部服务。
- 不在崩溃后弹窗询问。崩溃当次进程已结束，下一次启动弹窗会打断使用，且当前只有维护者一个用户。
- 不把诊断日志写进 SwiftData。日志是滚动证据，不是业务事实，不应参与迁移与备份。

## 结果

### 正向影响

- 崩溃与录像失败都留下可检索证据，不再依赖复现。
- 每轮工具清单可在执行日志与诊断日志中直接核对，模型自述与实际注册不一致时能立即判定。
- 报告投递复用已验证链路，不新增服务端组件。

### 成本与限制

- 这是新增的自动出网数据流：上次运行异常结束且开关打开时，会在启动后发送包含 Session 消息与
  Trace 摘要的报告。个人阶段可接受，推广前必须补授权界面与内容裁剪。
- 诊断日志按体积滚动，长时间使用后早期证据会被覆盖。
- 报告体积上限内截断，极长堆栈或超长会话只保留尾部。

## 验证

- `CrashDiagnosticsTests` 覆盖哨兵判定、测试进程内哨兵完全停用、调试器结束不上报、报告分段与脱敏、
  截断保留尾部、留盘上限与投递体积。
- `DiagnosticsLogStoreTests` 覆盖滚动、脱敏与并发写入。
- 手工验收：人工触发一次诊断邮件，确认主题、附件与内容边界。
- `make check`、`make verify`。

## 参考

- `Soma/Services/DiagnosticsLogStore.swift`
- `Soma/Services/AppRunSentinel.swift`
- `Soma/Services/CrashDiagnosticsCoordinator.swift`
- `Soma/Services/CrashReportComposer.swift`
- `Soma/Services/DiagnosticReportMailer.swift`

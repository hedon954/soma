# Soma 关键 Bug 索引

本目录记录已经造成核心功能不可用、数据失真、隐私风险或高概率重复回归的关键 Bug。普通
样式问题和一次性开发环境故障不在这里堆积。

每个 Bug 使用独立文件，至少记录症状、根因、修复和回归门禁。能自动化的约束必须进入
测试或 `make check`；依赖系统权限、签名或扩展宿主的行为同时保留真机验收步骤。文档不得
包含真实健康数据、媒体、密钥或完整私有日志。

## 索引

| Bug | 状态 | 摘要 | 回归门禁 |
| --- | --- | --- | --- |
| [0001](0001-widget-configuration-metadata-crash.md) | 已修复，待真机界面确认 | 动态 Widget 配置文本导致扩展崩溃并从组件库消失 | `make check` 禁止 Widget 配置元数据使用 `Text` 重载 |
| [0002](0002-video-frame-extraction-silent-fallback.md) | 已修复，待真机媒体验收 | 视频抽帧失败后仍以无画面的纯文本请求调用模型 | 稳定副本抽帧、零帧阻断、直接视频降级与首次/重试媒体一致性 |
| [0003](0003-gym-photo-lost-after-name-followup.md) | 已修复，待真机媒体验收 | 下一轮补充健身房名称时，上一轮图片只留在聊天 | 紧邻同 Session 归档、禁止跨 Turn 回捞与单张解绑测试 |
| [0004](0004-agent-background-stream-interruption.md) | 已修复，待部署后持续验收 | App 进入后台后 Agent SSE 与本地 ReAct 执行被系统挂起 | 持久 Job、后台租约、远程执行、事件游标与真机验收 |
| [0005](0005-remote-agent-streaming-latency-regression.md) | 已修复，待真机体验确认 | 远程模式丢失流式输出，并由 Worker/iOS 固定轮询叠加延迟 | 统一体验事件、流式 Provider、PostgreSQL 通知与 SSE 恢复 |
| [0006](0006-workout-camera-preview-recording-mismatch.md) | 基础合同已修复，后续见 0007 | 带练预览裁切且没有横竖屏共同录像几何 | 完整适配、共同旋转镜像、录制方向锁定与真机对照 |
| [0007](0007-guided-workout-countdown-capture-orientation-regression.md) | 首次修复不足，后续见 0008 | 倒计时停在 1、完整取景不切换、方向协调器误判 | 倒计时截止时间、显式投影状态、预览层窗口时机与方向策略测试 |
| [0008](0008-guided-workout-realtime-camera-projection.md) | 首次修复不足，后续见 0009 | 倒计时归零后仍等待相机、取景切换重建预览层、横竖屏布局漂移 | 非阻塞相机队列、共享预览层、界面比例与精确方向映射测试 |
| [0009](0009-guided-workout-preview-host-ownership-and-visible-state.md) | 已修复并部分修订 | 旧 Host 抢回共享层导致放大/返回黑屏，且错误和动作信息缺失 | Host 所有权、真实 previewing 状态、错误投影与竖屏布局测试 |
| [0010](0010-guided-recording-state-and-cue-gaps.md) | 已修复，待真机复验 | 录像策略和真实活动混用，导致首组失败、相机常驻、语音与完成反馈缺失 | 多策略/手动录像、启动回调、Cue 序列、总结与级联删除测试 |
| [0011](0011-meal-correction-misattributed-media.md) | 修复中 | 饮食纠错把当前图片写入错误记录，且结果难以审查 | 选择性媒体、精确 record ID、歧义不写入与 typed 结果卡 |
| [0012](0012-direct-video-and-first-delta-timeout.md) | 修复中 | 直传视频仍重复抽帧，请求缺少首增量门禁 | 请求体、延迟抽帧、8/10/20 秒 TTFT、Abort 与单次重试 |
| [0013](0013-guided-recording-startup-silent-stall.md) | 首次修复不足，后续见 0019/0020 | 带练录像启动可永久等待，失败无诊断日志且提示不可见 | 完整 activation 截止、独立失败事件、阶段日志、系统警告框与真机复验 |
| [0014](0014-guided-performance-missing-workout-entry.md) | 已修复，待真机观察 | 带练动作完成后只保留 Session/Set，没有形成统一训练记录 | 终态投影、来源 ID、幂等回填、趋势去重、备份与级联删除测试 |
| [0015](0015-billing-retry-loop-and-queue-order.md) | 已修复，待真机确认 | 明确欠费在进入 App 后反复重试，后发消息可能错序 | 欠费分类、人工释放、严格 FIFO、单删与全清测试 |
| [0016](0016-batched-tool-retry-repeats-completed-work.md) | 已修复，待真机观察 | 批量 Tool 中途失败会重复已成功的模型和工具步骤 | 原生 assistant/tool 检查点与失败 Tool 精确续跑测试 |
| [0017](0017-manual-retry-immediately-cancelled.md) | 已修复，待真机确认 | 等待超过整轮墙钟后，手动重试每次都在 0.01 秒内取消 | 活动执行预算、人工重置、错误覆盖与成功清理测试 |
| [0018](0018-remote-agent-model-input-divergence.md) | 已修复，待部署与真机确认 | 远程使用独立 Prompt，丢失 Skills、历史媒体和并行 Tool Call | 统一 Builder 静态门禁、请求逐项对照、runtime Skill 与并行 Tool 测试 |
| [0019](0019-guided-recording-attempt-terminal-and-duplicate-alerts.md) | 首次修复不足，后续见 0020 | 系统提前结束后活动状态未清理，成功 key 被误判且同一 attempt 可弹两次失败 | attempt 单终态、stop reason、部分证据、幂等 stop、单 Alert 与真机系统中断 |
| [0020](0020-guided-camera-activation-deadline-and-partial-evidence.md) | 修复中并部分修订，后续见 0025 | 权限后配置与 Session 启动无截止，准备状态不可见，异常极短文件误报完整成功 | 完整 request deadline、可见 preflight、generation 隔离、部分证据、恢复与真机门禁 |
| [0021](0021-unique-optional-projection-key-blocks-launch-migration.md) | 已修复，待真机复验 | 可空唯一 projectionKey 让多条旧训练记录在启动迁移时失败或丢行 | 当前 schema 上预修复与 nil-key 回填；失败诊断含堆栈、SQLite 结构和训练样例 |
| [0022](0022-installed-v5-schema-checksum-blocks-container-open.md) | 已修复，待真机复验 | 已安装 store 上改当前 schema 后容器无法打开 | 只打开当前 SomaDataSchema、不带 migrationPlan；真机只点重试迁移 |
| [0023](0023-same-turn-multi-exercise-merged-into-one.md) | 已修复，待真机复验 | 同一条消息的多个动作被合并成一条训练记录，Event Cards 被结果卡替换 | create 每次新增独立记录；原位卡不隐藏 Tool Event；保存有确认 |
| [0024](0024-streaming-cross-actor-swiftdata-crash.md) | 已修复，待真机连续对话复验 | 流式回复期间在非主线程投影 Event，写 SwiftData 与 AttributeGraph 导致频繁闪退 | chunk 回调保持 `@MainActor`、投影主 actor 断言、文字增量合批与 segment 身份唯一 |
| [0025](0025-guided-recording-terminated-by-connection-reconfiguration.md) | 已修复，待真机复验 | 录像开始后预览交接重放几何改写视频连接，录像提前结束且只提示固定文案 | 录像中禁止改写 movieOutput 连接的静态门禁；错误码与中断原因映射为具体原因加技术标识 |

新增记录时从 [模板](template.md) 开始，并同步更新本索引。

Bug 形成正式 PRD/ADR 修复时，Bug 用“下游落地”链接新文，新文用“上游依据”反向链接 Bug；
关系必须通过 `make check` 的双向文档门禁。

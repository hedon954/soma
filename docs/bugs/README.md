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
| [0013](0013-guided-recording-startup-silent-stall.md) | 已修复，待真机复验 | 带练录像启动可永久等待，失败无诊断日志且提示不可见 | 启动截止时间、独立失败事件、阶段日志、系统警告框与真机复验 |
| [0014](0014-guided-performance-missing-workout-entry.md) | 已修复，待真机观察 | 带练动作完成后只保留 Session/Set，没有形成统一训练记录 | 终态投影、来源 ID、幂等回填、趋势去重、备份与级联删除测试 |

新增记录时从 [模板](template.md) 开始，并同步更新本索引。

Bug 形成正式 PRD/ADR 修复时，Bug 用“下游落地”链接新文，新文用“上游依据”反向链接 Bug；
关系必须通过 `make check` 的双向文档门禁。

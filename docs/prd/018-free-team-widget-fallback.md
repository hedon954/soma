# PRD 018：免费签名下的 Widget 能力降级

- 状态：已实现，待真机验收
- 日期：2026-08-04
- 修订自：[PRD 017](017-contextual-private-coach-widgets.md) 的情境化主屏状态范围
- 后续修订：暂无
- 上游依据：[ADR 0043](../adr/0043-free-team-widget-fallback.md)

## 目标

在未加入支持 App Groups 的 Apple Developer Team 前，让 Soma 可以重新安装到真机，同时保留最低摩擦的
主屏和锁屏录入入口。

## 当前行为

- 主屏仅提供中尺寸「Soma 快速记录」：文字、拍照、照片/视频三个入口。
- 锁屏仍提供同样的三个独立入口和系统允许的行内、圆形、矩形样式。
- 入口只通过既有 `soma://capture/*` 打开 App；不创建训练、运行 Agent 或访问训练历史。
- 不申请 App Groups，不显示进行中的带练、计划、训练节奏、动作、重量、次数、媒体或 AI 内容。

## 验收

- 免费 Team 构建不包含 `com.apple.security.application-groups`，可成功安装到真机。
- 主屏三项入口和锁屏三项入口均能进入各自既有录入路径。
- 用户加入支持 App Groups 的 Team 前，设置中不出现无效的主屏状态、固定计划或隐私详情配置。

# BUG 0064：失败提示暴露原始错误且缺少可执行恢复

- 状态：完整本地门禁通过，界面待验收
- 日期：2026-09-10
- 上游依据：[PRD 063](../archive/0.0.23/prd/063-video-compatibility-and-actionable-errors.md)、[ADR 0132](../archive/0.0.23/adr/0132-actionable-error-presentation.md)
- 下游落地：[错误呈现清单](../engineering/user-facing-errors.md)、[验收](../acceptance.md)

## 症状

聊天失败出现原始 JSON、英文和内部标识；授权失效、余额不足和断网无法区分。
本地文件、录像、保存和设置错误也缺少对应处理办法，旧错误卡重开后仍回显原文。

## 根因

呈现层直接拼接 `localizedDescription`，远程 Provider 又将不同原因归为同一临时故障。
少数页面丢弃 Error 只写“失败”，另一些把诊断标识直接放入用户提示。

## 修复

采用共享类型分类与页面操作上下文，保留具体原因并提供当前界面可执行的下一步。
远程稳定错误码贯穿 Worker 和 App，旧失败卡只在显示时净化；未知错误不猜测。
诊断与工具协议保留独立边界，成功记录、原媒体和部分录像仍按原事实保留。

## 回归门禁

`AppErrorMessageTests` 最初两条在旧实现实际失败，修复后六项覆盖模型 JSON/内部 ID、
授权/额度/网络、本地空间/权限/缺文件、旧失败、未知原因、录像诊断、启动导出与反馈配置。
Server 测试检查稳定原因、不持久化响应原文、额度不足不进入瞬态重试。
`scripts/check-user-facing-errors.rb` 随 `make check` 禁止呈现层重新直出底层错误。

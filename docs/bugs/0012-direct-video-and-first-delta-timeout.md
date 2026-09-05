# BUG 0012：直传视频重复送帧且请求缺少首增量门禁

- 后续修订：[BUG 0054](0054-full-video-playback-and-dictation-regressions.md)（完整视频与当前草稿追加规则）

- 状态：已修复；真机供应商验收待维护者确认
- 发现日期：2026-08-11
- 影响范围：百炼直接视频、本地/远程流式首响应、关键帧降级与延迟诊断
- 修订自：
  - [BUG 0002](0002-video-frame-extraction-silent-fallback.md) 的视频准备与诚实降级边界
  - [BUG 0005](0005-remote-agent-streaming-latency-regression.md) 的远程流式延迟边界
- 下游落地：
  - [ADR 0057](../archive/0.0.4/adr/0057-direct-video-capability-and-observable-fallback.md)
  - [ADR 0058](../archive/0.0.4/adr/0058-first-delta-deadline-and-bounded-retry.md)
  - [PRD 025](../archive/0.0.4/prd/025-trusted-context-direct-video-and-reviewable-meals.md)

## 症状

支持直接视频的请求仍在发送前抽取关键帧，并把视频与帧同时放入首请求；不支持直传时只发帧，
但用户和 Trace 无法清晰区分。Provider 长时间无首增量时只能等待连接级 timeout。

## 根因

媒体准备不感知最终路由，统一抽帧并读取完整视频；直接视频流在首 chunk 前失败才由 SDK 请求
回退，但没有 TTFT watchdog。Server fetch 同样没有 AbortSignal。

## 修复

- 路由能力先决策，直传首请求不抽帧；失败后才延迟抽帧并占用唯一重试。
- 增加 8/10/20 秒 TTFT、30 秒 idle、180 秒 total 与底层取消。
- Trace 分段记录媒体模式、字节、帧数、TTFT、request attempt 和降级原因。

## 回归门禁

- 自动化测试：请求体不重复、按需抽帧、三档 TTFT、Abort、单次重试、Tool 无重复写入。
- 手工验收：虚构短视频比较直接视频与关键帧路由，确认 Trace 和用户提示一致。
- 仍无法自动化的风险：真实供应商排队、编码兼容和真机网络波动。

## 验证

`make verify` 已通过；确定性测试覆盖直传首请求无重复帧、直传失败后唯一关键帧重试、三档 TTFT、
流空闲/总时限、取消传播和远程 `mediaMode/requestAttempt`。真实供应商排队与真机网络仍由维护者
手工确认。

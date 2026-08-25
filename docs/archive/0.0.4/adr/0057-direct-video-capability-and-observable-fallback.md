# ADR 0057：按能力直传视频并可观察降级

- 状态：已采纳
- 日期：2026-08-11
- 维护者：Soma maintainers
- 部分替代：[ADR 0024](../../0.0.1/adr/0024-session-context-projection-and-compaction.md) 中视频统一提前抽帧并占用视觉额度的边界
- 后续替代：暂无
- 上游依据：
  - [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
  - [BUG 0002](../../../bugs/0002-video-frame-extraction-silent-fallback.md)
  - [BUG 0012](../../../bugs/0012-direct-video-and-first-delta-timeout.md)

## 背景

现有百炼直传路径在发送完整视频前仍抽取关键帧，并把帧和视频一起交给模型。这样延长准备、
重复 token，也让 Trace 无法说明模型究竟使用了完整视频还是帧。

## 决策

1. 由明确 provider/model capability 决定 `directVideo` 或 `keyframes`，未知能力一律关键帧。
2. 首批只为百炼已验证的 Qwen 视觉模型开启直传。副本规范化为兼容 MP4，Base64 原始数据以
   约 7 MB 为安全上限；超过后先压缩，仍超限则进入关键帧。
3. 直传首请求只携带视频，不抽帧。仅首增量前失败或超时才延迟抽帧并消耗唯一重试。
4. 本地与远程使用相同 media mode；Server 可接收规范化视频 upload 并生成 provider content。
5. Trace 与用户可见失败/降级记录 mode、字节数、帧数和原因，不记录内容、路径或 Base64。

## 未选择的方案

- 用模型名称子串为所有网关乐观开启：代理端兼容性无法验证。
- 同时发送完整视频与帧：重复成本且削弱媒体归因。

## 结果

### 正向影响

- 支持时序输入的模型获得完整视频，不支持时保持诚实的关键帧分析。

### 成本与限制

- 视频规范化和远程 upload 有额外本地 CPU、临时空间与网络成本。

## 验证

- 请求体、延迟抽帧、超限、远程 upload、Trace mode 与零视觉失败测试。

## 参考

- [阿里云 Qwen 视觉文档](https://www.alibabacloud.com/help/en/model-studio/vision)

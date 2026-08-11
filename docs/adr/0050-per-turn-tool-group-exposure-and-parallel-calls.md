# ADR 0050：每轮工具组渐进披露与并行 tool_calls

- 状态：部分已替代
- 日期：2026-08-05
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0003](0003-native-streaming-react-tool-calling.md) 中「每步暴露全部工具且 parallelToolCalls=false」的默认运行参数
  - [ADR 0004](0004-progressive-skills-fixed-tool-contract.md) 中「工具目录始终全量暴露给模型」的运行时暴露策略（工具契约本身仍固定）
- 上游依据：[PRD 022](../prd/022-react-reliability-and-context-awareness.md)
- 后续替代：[ADR 0054](0054-device-executed-chat-feedback-tool.md) 增加 `feedback` 工具组，其余预选、展开和并行规则保持不变

## 背景

每次 LLM 请求附带全部 21 个工具 Schema（约 21KB），且 `parallelToolCalls=false`。
工具过载降低选择准确率并拉长 prefill；串行 tool_calls 让「一次记三个动作」变成多步往返。
历史视觉帧在后续 step 重复 base64 传输也破坏前缀缓存稳定性。

## 决策

1. 工具分成 `core` / `plans` / `gym` / `review`。core 与固定 `expand_tool_group` 常驻。
2. 每轮开始按确定性信号预选组（关键词、active 计划、进行中带练、视频）；**整轮固定**。
3. 仅模型调用 `expand_tool_group` 时可中途扩展；该轮剩余步骤接受前缀缓存失效。
4. 打开 `parallelToolCalls`；本地仍顺序执行 mutation，以配合幂等账本。
5. step ≥ 2 清除历史视觉帧，保留文字占位；当前轮媒体不变。
6. 流式 UI 滚动节流到约 10Hz 非动画跟随；历史视频抽帧结果缓存于 `Library/Caches`。

## 未选择的方案

- 每步动态重选工具：破坏 turn 内前缀缓存。
- RAG 检索式工具选择：对当前 22 个工具过重。
- 保持串行 tool_calls：在幂等改造后收益小于成本。

## 结果

### 正向影响

- 常见记录路径 Schema 约减半；多动作写入可一步完成。
- 前缀更稳定，有利于供应商隐式缓存命中观测。

### 成本与限制

- 预选猜错时多一次 expand 往返。
- 并行调用依赖规范化幂等已落地。

## 验证

- 工具组预选与前缀稳定性单元测试。
- Trace 记录 `exposed_tool_groups` / `exposed_tool_count`。

## 参考

- [PRD 022](../prd/022-react-reliability-and-context-awareness.md)
- [ADR 0003](0003-native-streaming-react-tool-calling.md)
- [ADR 0004](0004-progressive-skills-fixed-tool-contract.md)

# ADR 0126：训练分享固定为 iPhone 17 Pro Max 纸面

- 状态：部分已替代
- 日期：2026-09-08
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0000](0000-origin-through-0.0.11.md) 仅训练分享导出画布尺寸
  - [ADR 0117](0117-workout-share-editorial-poster.md) 仅导出画布由随内容增高改为固定 440×956 pt；白底、橙黄主视觉与同值压缩仍有效
- 上游依据：[PRD 059](../prd/059-coach-ids-progress-and-required-zeros.md)
- 后续替代：[ADR 0130](0130-workout-share-fill-or-grow.md)（仅短会话铺满、超出才加高；440×956 基准纸面仍有效）
- 下游落地：[验收](../acceptance.md)

## 背景

维护者要求分享图贴合 iPhone 17 Pro Max 屏幕，而不是随动作卡堆成一条长卷。

## 决策

导出画布固定为 440×956 pt（1320×2868 px @3x）。明细改为一行摘要，压缩字号与间距，完整保留
动作名与合并组次，不再加高纸面。

## 未选择的方案

继续按内容增高；只对预览 `scaledToFill` 裁切长 PNG。

## 结果

同一训练从深浅色 App 导出尺寸一致，可铺满 Pro Max 竖屏。

## 验证

渲染测试断言画布宽高；`make verify`。

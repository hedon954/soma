# 进展设计稿文案清理：图像编辑提示词

- 工具：内置 Image Gen；编辑已有四周期稿，不生成新设计方向。
- 输出：[设计稿索引](../../docs/assets/ui/2026-09-05/progress-refinement/README.md)

## Year

Use case: precise-object-edit. Asset type: existing Soma iPhone UI mockup, YEAR state.
Edit image 1 only. Image 2 is the user's crop identifying the redundant sentence.
Primary request: Remove the exact sentence "月内可继续选择任意一天" below the selected-August information strip. Remove its reserved text row; bring the Training and Body cards upward by that row's height, keeping a normal 16px visual gap between sections. Do not replace the sentence with any other hint, tooltip, slogan, instruction, or placeholder. The bottom tab bar stays pinned to its original position; unused space stays plain black.
Invariants: preserve ALL other text, values, dates, charts, icons, colors, typography, geometry, selected year segment and screen width. Preserve the functional "查看该月" button. Do not redesign or fix unrelated chart labels.
Target: preserve exact input dimensions/aspect ratio, app content only. Current date 2026-09-05; preserve the source's historical 2026/August dates. No bezel or device chrome.

## Week

Use case: precise-object-edit. Asset type: existing Soma iPhone UI mockup, WEEK state.
Primary request: delete the standalone gray sentence "估算仅供参考，漏记不等于零摄入" between the selected-day information strip and Training card. Delete the reserved row, lift Training and Body cards by the removed row height. Retain ordinary 16px visual section gaps. Do not replace with other explanatory prose. Bottom tabs remain at same vertical position, excess space stays black.
Invariants: all remaining text, chart legends, numbers, dates, approximate marker "约", coverage "7个有记录日", functional "查看当天" button, chart shapes, icons, typography, colors and layout stay unchanged. Do not redesign or correct other details. Only this copy removal.
Target: same exact input dimensions and aspect, app content only, no device chrome. Current date 2026-09-05; preserve source's historical August24–30 dates.

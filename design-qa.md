# Soma 多媒体折叠卡片 Design QA

- Source visual truth: 2026-07-29 产品验收对话中提供的微信折叠/展开参考图。
- Implementation evidence: 2026-07-29 在 iPhone 17 Pro Simulator 上分别截取折叠态与展开态，
  并按相同视口高度进行并排比较；运行时截图属于本地验收产物，不进入 Git。
- Runtime viewport: iPhone 17 Pro simulator, 368 × 800 optimized capture
- State: three mixed-aspect-ratio images, collapsed and expanded
- Density normalization: the reference and simulator captures were proportionally resized to a common 1000 px comparison height; device chrome was excluded from fidelity findings.

## Full-view comparison

The collapsed state follows the reference composition: the first image stays upright on a stable portrait, square, or landscape canvas; the second and third images use that same canvas at 0.9 and 0.8 scale, rotate clockwise, and expose progressively on the right. The full stack reserves its overflow width and remains right-aligned rather than clipping against the screen.

The expanded state removes rotation and renders a right-aligned vertical list. The control changes from “展开 3” to “收起”; there is no horizontal paging gesture.

## Focused component comparison

- Layout and spacing: passed. The rear layers expose 10% and 16.5% of the front-card width, and the expand/collapse control is centered against the first card.
- Typography: passed for the scoped component. The compact secondary capsule treatment matches the reference hierarchy.
- Colors and tokens: passed. The capsule uses a low-emphasis neutral fill and the media cards do not add a background surface.
- Image quality and asset fidelity: passed. Soma uses the real user media; different subjects from the reference are expected. The folded state crops into a stable canvas, while the expanded state keeps each item’s own aspect ratio.
- Copy and content: passed. “展开 3” and “收起” match the reference behavior.
- Interaction and accessibility: passed. The stack and capsule expose a button label, expand vertically, collapse again, and do not introduce horizontal scrolling.

## Comparison history

1. Earlier implementation: blocked by P1 clipping. Rear images were clipped before receiving their final frame, so their pixels overflowed and appeared as a black column.
2. Fix: each rear image now receives its real scaled frame first and is independently rounded/clipped; the outer stack no longer clips away the fan.
3. Earlier implementation: blocked by P1 geometry drift. Rotation direction and layer exposure did not match the reference.
4. Fix: clockwise rotations are 1.8° and 3.6°, with cumulative right exposure of 10% and 16.5%.
5. Mixed-orientation verification: rear images share the first card’s stable canvas before layer scaling and rotation, so a portrait first image no longer makes the whole message excessively tall.

## Residual notes

The source and implementation contain different user images, so subject colors and crops are intentionally not compared. No actionable P0, P1, or P2 mismatch remains in the folded-media component.

final result: passed

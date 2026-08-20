# ADR 0086：带练预览与历史录像缩略使用 aspect fill

- 状态：已采纳
- 日期：2026-08-20
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0038](0038-focused-guided-workout-and-capture-geometry.md) 中预览使用 `.resizeAspect` 完整展示输出、不以裁切填满的显示合同
  - [ADR 0039](0039-event-driven-guided-recording-cues-and-review.md) 中放大取景 Host 使用 `.resizeAspect`、禁止全部预览统一 fill 的显示合同
- 后续替代：暂无
- 上游依据：[PRD 034](../prd/034-history-media-tabs-and-guided-capture-polish.md)
- 下游落地：[训练领域模型与运行时协议](../engineering/training-domain-model.md)

## 背景

ADR 0038/0039 把「预览即所得」写成 letterbox：放大取景展示完整保存画幅，紧凑小窗才允许 fill。
真机上放大取景和 58×58 历史缩略都会留下上下黑边，用户把它当成取景失败；同时自动录像还要在
PIP 与放大宿主之间切换 `videoGravity`，放大这次交接会触发几何重放。

保存文件的旋转、镜像和锁定几何仍然正确。需要改的是**显示容器**如何铺满，而不是改 Movie Output。

## 决策

1. 紧凑 PIP 与放大取景都使用 `.resizeAspectFill`。容器按当前取景比例（竖 9:16 / 横 16:9）裁切，
   不再 letterbox。
2. 训练历史、详情封面和聊天中的录像缩略使用同一取景比例 + `scaledToFill` 裁切。
3. `WorkoutCaptureGeometry`、开始录像时锁定方向/角度/镜像、预览与文件共用镜像策略保持不变。
4. 用户接受预览边缘可能被裁掉；完整原片仍在本机文件和媒体查看器的 `scaledToFit` 中。

## 未选择的方案

- 继续放大 letterbox、只改历史缩略：带练主路径仍然有黑边，且 PIP→放大仍切换 gravity。
- 改变 Movie Output 画幅去迁就缩略容器：会改写已锁定的捕获几何，并与 BUG 0025 冲突。

## 结果

### 正向影响

- 预览、缩略和查看器的任务分离清楚：容器铺满，查看器看全图，文件保留锁定几何。
- 自动录像不必为了换 gravity 拆掉 PIP 宿主。

### 成本与限制

- 放大取景不再承诺「屏幕上能看到将被保存的每一像素」。
- Simulator 仍不能代替真机构图验收。

## 验证

- `GuidedWorkoutLayoutTests` 共享预览层默认 fill。
- 真机确认展开取景与历史缩略无上下黑边，媒体查看器仍 letterbox 原片。

## 参考

- [PRD 034](../prd/034-history-media-tabs-and-guided-capture-polish.md)
- [BUG 0025](../bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md)

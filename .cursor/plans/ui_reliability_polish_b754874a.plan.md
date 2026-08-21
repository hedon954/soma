---
name: UI reliability polish
overview: v0.0.8 把 8 项真机反馈收成一轮：图片放大用从缩略图 zoom 过渡去掉黑闪、饮食详情复用聊天清单并压紧聊天卡、训练/饮食历史统一「标题下月份芯片 + 按天可折叠」、执行日志大 payload 推到新页、再点当前 Tab 回主页，以及自动录像在预览宿主交接完成后再启动并用取景比例铺满缩略图。
todos:
  - id: media-zoom
    content: MediaViewer zoom 过渡 + VideoPosterView 去黑底占位
    status: completed
  - id: meal-cards
    content: 详情复用聊天菜品行，压紧聊天卡密度
    status: completed
  - id: history-unify
    content: 训练/饮食历史：标题下月份芯片、按天分组、可折叠
    status: completed
  - id: trace-page
    content: 执行时间线 LLM/span 改 NavigationLink 到独立详情页
    status: completed
  - id: tab-reselect
    content: 再点当前 Tab pop to root，换 Tab 保留子页面
    status: completed
  - id: auto-record
    content: 自动录像稳定宿主后再 start；预览与缩略 fill 取景比例
    status: completed
  - id: docs-verify
    content: PRD 034、BUG 0025 修订、acceptance、CHANGELOG；make verify
    status: completed
isProject: false
---

# v0.0.8 交互与可靠性打磨

业内对照后的原则：图片放大学 Photos/Instagram 的「从缩略图 zoom」，不要先铺黑底再弹出；列表学 Keep/Health 的「大标题下芯片 + 按天可折叠」；Tab 学苹果/Instagram 的「换 Tab 保留栈，再点当前 Tab 回根」；日志学 Xcode/GitHub 的「时间线只摘要，全文进独立页」；录像学 AVFoundation 惯例「先锁几何与预览宿主，再 `startRecording`，画面用 fill 而不是 letterbox」。

产品范围写入新 [PRD 034](docs/prd/034-history-media-tabs-and-guided-capture-polish.md)；自动录像剩余竞态作为 [BUG 0025](docs/bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md) 后续修订。体重记录不改。

## 1. 图片放大不再先变黑

根因在 `[Soma/Components/MediaViewer.swift](Soma/Components/MediaViewer.swift)`：`fullScreenCover` 先动画一块纯黑全屏，缩略图是 `scaledToFill`、查看器是 `scaledToFit` + 72pt 边距，视频封面在 `[VideoPosterView](Soma/Components/VideoPosterView.swift)` 里用 `Color.black.opacity(0.82)` 占位。

做法：

- iOS 18+（真机已是 26）：缩略图 `.matchedTransitionSource`，查看器 `.navigationTransition(.zoom(sourceID:in:))`，背景随图片一起从缩略图位置长出来，不再先铺黑底。
- iOS 17 回退：cover 关闭系统弹出动画，先把已解码的 `UIImage` 交给查看器，再淡入操作条；仍避免「空黑页」。
- `VideoPosterView` 未就绪时改用 `AppTheme.softTint`，与其它空图一致。
- 查看器仍 `scaledToFit`（Photos 也是 letterbox 原图），zoom 过渡负责 crop → fit 的形态变化。

改动集中在 `MediaViewer`、`StoredMediaStrip`、`RecordMediaGallery`、`FootprintMediaGrid`、`GymViews` 的 cover 调用点。

## 2. 饮食详情清单对齐聊天卡，聊天卡再压一档

详情现在是 Form 里堆 `TextField` +「分项营养」Disclosure（`[MealItemEditorRow](Soma/Views/RecordDetailViews.swift)`），和聊天里已经定型的 Keep 风格行完全两套。

- 详情「食物项」复用 `[MealItemDraftRow](Soma/Views/MealInlineEditorCards.swift)` / `MealItemReadOnlyRow`（抽成 Views 层共享，不把聊天壳硬塞进 Form）。
- 聊天卡只减密度、不减字段：外壳 padding 12/10 → 10/7，行间距 8 → 4，图标 28 → 22，菜名 `.footnote`，宏量 `.caption2` 单行，汇总热量 `.title2`。`ViewThatFits` 与辅助字号折行规则保留。

## 3 / 7 / 8. 训练与饮食历史：按天分组、标题下筛选、可折叠

现状：训练已按天 `Section`，筛选藏在右上 `Menu`；饮食是一条平铺列表（`[HistoryViews.swift](Soma/Views/HistoryViews.swift)`）。

统一成：

```text
大标题
全部  8月  7月  6月   ← 横向芯片，当前项用 tint 胶囊
8月20日 星期四    ∨   ← 点标题折叠/展开当天
  行…
```

- 抽出共用 `HistoryMonthFilterBar` + `HistoryDaySection`（折叠状态为 `Set<Date>`，默认全部展开）。
- 饮食复用训练同一套 `groupedByDay` / `filterChoices` / 分页思路（`MealEntry.date`），芯片文案仍是「全部 + 按月」。
- 行样式保持现有信息量，只把录像缩略从图 6 改成取景比例。

## 4. LLM 调用进独立页

`[AgentTraceSpanRow](Soma/Views/SettingsView.swift)` 已用右 chevron，却在时间线里 `withAnimation` 展开整份 system+history。改成 `NavigationLink` 推 `[AgentTraceSpanDetailView](Soma/Views/SettingsView.swift)`：分段展示绑定工具 / 入参 / 返回 / 元数据，可选中复制，时间线行只留标题、状态、耗时、token。失败行仍可在时间线露出一行错误摘要。

## 5. 再点当前 Tab 回到该 Tab 主页

按你选的苹果惯例：**换 Tab 保留子页面；再点已选中的 Tab 才 pop to root**。

`[RootView](Soma/Views/RootView.swift)` 现在每个 Tab 一个无 path 的 `NavigationStack`。给四个 Tab 各一个稳定 `stackID`，`TabView` selection Binding 在「新值 == 旧值」时刷新该 ID，从而重建栈（兼容现有 `NavigationLink { Dest }`，不必先全改 typed route）。`[SettingsView](Soma/Views/SettingsView.swift)` 额外 `path.removeAll()`。教练 Tab 回到 Session 根，不清会话。

## 6. 自动录像生效，缩略图跟取景比例、无上下黑边

自动路径在 `beginCurrentSet` 里先 `setPhase(.setInProgress)`（PIP 拆掉、换 set-hero 宿主）再 `startRecording`；`isRecording` 在 `didStartRecordingTo` 之前仍为 false，几何守卫拦不住，这是 [BUG 0025](docs/bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md) 手工路径修完后自动路径剩下的洞。手动开始时宿主已经稳定，所以看起来「手动可以、自动不行」。

- 倒计时结束：先 `startRecording`，**等 `didStartRecordingTo` 成功后再切 `.setInProgress`**；或录像中保持同一 preview host，禁止拆 PIP。
- `startingRecording` 与 `isRecording` 一样禁止改 movieOutput 几何。
- 展开预览从 `resizeAspect`（黑边）改为 `resizeAspectFill`（`[GuidedWorkoutExecutionViews.swift](Soma/Views/GuidedWorkoutExecutionViews.swift)` ~970）。
- 有录像的训练行 / 详情封面用 9:16（竖）或 16:9（横）`scaledToFill` 裁切，不再用 58×58 方块把 16:9 帧上下填黑。`VideoPosterView` 继续 fill+clip。

```mermaid
sequenceDiagram
    participant UI as GuidedWorkoutView
    participant Coord as GuidedWorkoutCoordinator
    participant Cam as WorkoutCameraService
    UI->>Coord: countdown ends
    Coord->>Cam: startRecording on existing PIP host
    Cam-->>Coord: didStartRecordingTo
    Coord->>UI: setPhase setInProgress
    Note over UI,Cam: geometry locked; no movieOutput rewrite
```



## 文档与验证

- 新增 PRD 034，修订 BUG 0025、acceptance、CHANGELOG Unreleased。
- 单测：饮食按天分组与筛选、Tab reselect 重置、span 行不再内嵌超长 Text、录像 `startingRecording` 几何守卫。
- 真机：点开饮食/足迹图无黑闪；聊天饮食卡更矮且字段仍在；详情菜品行与聊天一致；训练/饮食芯片+折叠；再点「进展」回到进展首页；自动录像连续 3 组；执行日志 LLM 进新页不卡。


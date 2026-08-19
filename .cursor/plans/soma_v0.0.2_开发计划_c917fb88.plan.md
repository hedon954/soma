---
name: Soma v0.0.2 开发计划
overview: v0.0.2 覆盖 9 项需求：训练记录分组/筛选/分页、流式换行 bug 修复、计划管理补全（删除/恢复/关联历史/有含义的版本变更）、录制失败提示、程序化肌肉受力图与训练分享海报。
todos:
  - id: docs-prd-adr
    content: 写 PRD 019 与 ADR 0044，补双向链接并更新索引
    status: completed
  - id: fix-markdown-newlines
    content: 修复 MarkdownText 段落/列表换行丢失并补单元测试
    status: completed
  - id: history-group-filter-paging
    content: 训练记录按天分组、年月日筛选、分页加载
    status: completed
  - id: history-thumbnail
    content: 记录行视频缩略图改为动作静态插画
    status: completed
  - id: session-program-link
    content: WorkoutSession 关联计划并在训练历史显示计划名
    status: completed
  - id: plan-delete-restore
    content: 计划详情增加删除与归档恢复入口
    status: completed
  - id: template-changelog
    content: 模板版本确定性 diff 生成变更摘要与明细，UI 长按查看
    status: completed
  - id: recording-error-toast
    content: 排查录制失败路径并新增 toast 错误提示
    status: completed
  - id: plan-detail-stats
    content: 计划详情新增该计划训练历史统计图
    status: completed
  - id: muscle-map-engine
    content: 规范肌群枚举、中文映射与 MuscleMapView 程序化受力图
    status: completed
  - id: muscle-map-adoption
    content: 动作详情改用程序化受力图，统一 AI 插画风格模板
    status: completed
  - id: share-poster
    content: 训练分享海报视图与 ShareLink 分享
    status: completed
  - id: verify-release-prep
    content: make verify 全绿并准备 v0.0.2 版本收尾
    status: completed
isProject: false
---

# Soma v0.0.2 开发计划

## 0. 文档先行（已完成）

- 已新增 [docs/prd/019-training-review-plan-management-and-muscle-map-share.md](docs/prd/019-training-review-plan-management-and-muscle-map-share.md) 定义本版 9 项需求与验收边界。
- 已新增 [docs/adr/0044-programmatic-muscle-map-and-training-share-poster.md](docs/adr/0044-programmatic-muscle-map-and-training-share-poster.md)：程序化肌群受力图与分享海报（规范肌群枚举、MIT 矢量路径素材、强度叠加规则、部分替代 ADR 0035 的肌群图范围）。
- 已在 PRD 004/010/014、ADR 0035 与两个 README 索引补齐双向生命周期链接，`make check` 通过。
- `docs/acceptance.md` 在各项实现完成后再补当前证据。

## 1. 训练记录：按天分组 + 年月日筛选 + 分页（需求1）

改造 [Soma/Views/HistoryViews.swift](Soma/Views/HistoryViews.swift) 的 `WorkoutHistoryView`：

- 放弃全量 `@Query`，改为 `FetchDescriptor<WorkoutEntry>` + `fetchLimit`/`fetchOffset` 分页（每页约 50 条），滚动到底自动加载下一页。
- 结果在内存中按自然日分组，`Section` 头显示"8月4日 周二"样式。
- 顶部筛选：系统 Menu/DatePicker 选择年、月、日（可只选年或年月），生成日期区间 `#Predicate` 下推到 fetch。
- 左滑删除、详情跳转保持不变。

## 2. 记录行缩略图：视频改为动作静态图（需求2）

改 [Soma/Views/RecordDetailViews.swift](Soma/Views/RecordDetailViews.swift) 的 `MediaThumbnail` 使用方（`WorkoutHistoryRow`）：

- 优先用 `WorkoutEntry.exerciseID` / `exercise` 名称查 `ExerciseDefinition`，用现有 `ExerciseArtworkView` 展示动作插画；查不到再退回现有图标。视频入口保留在详情页，列表不再显示黑底播放按钮。

## 3. 修复流式文本换行丢失（需求3）

根因：[Soma/Components/DesignSystem.swift](Soma/Components/DesignSystem.swift) L182-188 `AttributedString(markdown:, .full)` 会剥离换行、把块结构存入 `PresentationIntent`，现有代码未重建段落，导致段落/列表全部黏连。

- 修复 `MarkdownText.attributedMarkdown`：遍历 `presentationIntent` runs，为段落间插入 `\n\n`、列表项重建 `1. ` / `• ` 前缀、代码块保留原样；样式映射逻辑保留。
- 补充确定性单元测试：多段落、编号列表、无序列表输入 → 渲染字符串包含正确换行。
- 顺带核对 `AgentVisibleTextSanitizer.sanitize`（[Soma/Services/AgentChatPresentation.swift](Soma/Services/AgentChatPresentation.swift)）不吞中间换行（目前只 trim 首尾，预计不用改）。

## 4. 训练历史关联计划 + 计划删除/归档恢复（需求4）

模型与 Store（[Soma/Models/TrainingPlan.swift](Soma/Models/TrainingPlan.swift)、[Soma/Services/TrainingPlanStore.swift](Soma/Services/TrainingPlanStore.swift)）：

- `WorkoutSession` 新增可选 `programID: UUID?` 与 `programNameSnapshot: String?`，`startSession` 时写入；旧数据用 `sourceTemplateFamilyID` 反查兜底显示。
- 训练历史列表行（[Soma/Views/TrainingProgramViews.swift](Soma/Views/TrainingProgramViews.swift) L83-118）显示"周训练力量一 · v2"来源。
- 归档恢复：`TrainingPlanStore` 增加 `unarchive`，归档计划详情页显示"恢复计划"。
- 删除：详情页新增系统 destructive"删除计划"（confirmationDialog 二次确认），复用已有 `deleteProgram`；说明会保留训练历史（session 不删）。

## 5. 带练录制失败提示 + 排查（需求5）

[Soma/Services/GuidedWorkoutCoordinator.swift](Soma/Services/GuidedWorkoutCoordinator.swift) / [Soma/Services/WorkoutCameraService.swift](Soma/Services/WorkoutCameraService.swift)：

- 排查 `prepare`/权限/`startRecording` 各失败路径，确保全部写入 `recordingErrorMessage` 并映射为可理解文案（权限被拒 → 引导去设置；会话中断 → 重试建议）。
- 新增轻量 toast 组件（`Soma/Components`，自动消失的顶部横幅），带练页录制失败时弹出，替代现在容易被忽略的橙色 Label；按钮禁用时说明原因（如"正在开启相机"）。

## 6+9a. 程序化肌肉受力图（需求6、9①）

调研结论：业界（react-body-highlighter / body-muscles / MuscleMap）通用做法是"正/背面身体底图 + 每块肌肉独立矢量路径（语义 ID），按强度上色"。采用 MIT 协议开源肌肉 SVG 路径数据移植为 Swift 静态数据（保留 attribution），不再依赖 AI 生成 muscle map。

```mermaid
flowchart LR
    exercises[动作的肌群标注] --> mapping[中文名到规范肌群枚举映射]
    mapping --> intensity[按主次肌群与组数累加强度]
    intensity --> renderer[MuscleMapView 矢量渲染]
    baseArt[正背面底图与逐块肌肉路径] --> renderer
    renderer --> exerciseDetail[动作详情受力图]
    renderer --> sharePoster[训练分享海报]
```

- 新增 `Soma/Models/MuscleGroup.swift`：规范肌群枚举（约 20-30 块，含正/背面归属），以及中文自由文本（现有 `primaryMuscles: [String]`）→ 枚举的确定性映射表；映射不到的保持不高亮（missing-is-nil）。
- 新增 `Soma/Components/MuscleMapView.swift`：SwiftUI Canvas/Path 渲染底图轮廓 + 高亮肌肉；主肌群深色、次肌群浅色；多动作叠加时强度累加 → 透明度分档（与图7的深浅一致思路）。
- 动作详情/列表的 muscle map 改用 `MuscleMapView`，替换 `soma_muscle_*.png` 静态图与 AI 生成路径；动作插画（action illustration）继续用 bundled 素材，AI 生成入口保留但在 prompt 中固定统一风格模板（回应需求6 的风格不统一）。
- 单元测试：中文映射、强度叠加、主/次区分。

## 9b. 训练分享海报（需求9②）

- 新增 `Soma/Views/WorkoutShareViews.swift`：session 复盘页（`WorkoutSessionReviewView`）加"分享"入口，用 `ImageRenderer` 把海报视图渲染成图片，经系统 `ShareLink` 分享。
- 海报内容：日期、计划名、正/背面肌肉受力图、消耗/总容量/时长统计、动作-组次重量列表、Soma 标识；样式遵循 App 现有绿色系设计，不复刻训记。
- 隐私：纯本地渲染，不含照片/视频帧。

## 7. 计划详情展示该计划的训练统计（需求7）

[Soma/Views/TrainingProgramViews.swift](Soma/Views/TrainingProgramViews.swift) `TrainingProgramDetailView` 新增"训练统计"区块：

- 按 `programID`（兜底 `sourceTemplateFamilyID`）查该计划的已完成 session。
- 用 Swift Charts 展示：近 N 次的有效容量趋势柱状图 + 完成次数/最近一次摘要；点击柱子可跳到对应 session 复盘页。空态显示"还没有用该计划训练过"。

## 8. 版本历史改为有含义的变更说明（需求8）

- `WorkoutTemplateVersion` 新增 `changeSummary: String?`（短标题）与 `changeDetails: String?`（明细）。
- 在 `TrainingPlanStore.createNextVersion` 中确定性 diff 前后 `TemplateExercise`：新增/移除动作、组次重量间歇变化，生成如"移除 引体向上；深蹲 4→5 组"的摘要与逐条明细；GUI 编辑与 Agent 工具（`ConversationRecorderTrainingPlans.swift`）两条路径共用同一 diff 逻辑。
- 详情页版本历史行显示摘要标题，长按（contextMenu 或 sheet）查看完整变更明细；v1 显示"初始版本"。旧数据 `changeSummary` 为 nil 时按需从相邻版本现算。
- diff 生成的确定性单元测试。

## 验证与收尾

- 每个工作流独立 Conventional Commit；迭代中 `make check`，完成后 `make verify`。
- 录制失败与真机相机行为补手工验收步骤（模拟器无相机）。
- 全部完成后按 `.claude/skills/soma-release/SKILL.md` 走 v0.0.2 版本号、CHANGELOG 与 tag（需你确认后再发布）。

## 建议实施顺序

小而独立的先做：3（换行 bug）→ 1、2（记录列表）→ 4、8（计划模型小改）→ 5（录制提示）→ 7（统计图）→ 6+9（肌肉图与分享，工作量最大）。
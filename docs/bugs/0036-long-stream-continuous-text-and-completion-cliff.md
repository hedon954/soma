# BUG 0036：无换行长流与完成态切换仍造成性能悬崖

- 状态：已修复，待 Release 真机量化复验
- 日期：2026-08-25
- 影响：长段落越流越卡；流式结束后整段 Markdown 同步解析、重建和布局，拖慢整个 App
- 修订自：[BUG 0035](0035-long-stream-text-relayout-thermal-jank.md)
- 下游落地：
  - [PRD 045](../archive/0.0.14/prd/045-performance-reliability-and-bounded-data-access.md)
  - [ADR 0100](../archive/0.0.14/adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)

## 症状

第一轮修复只在换行处冻结文本块。模型输出长段落而迟迟没有换行时，可变尾块仍会无限增长；结束时
UI 又从流式块一次性切换为完整 Markdown 树，并在主线程同步解析所有 inline attributed text。
因此开始阶段快、后段卡，并且完成后 Tab、滚动和 Session 切换继续受完成态工作拖累。

## 根因

- 流式缓存把“换行”误当作增量边界，无法约束无换行内容的尾部成本。
- 多个 SwiftUI `Text` 块仍需要重复参与测量，存储分块泄漏成了展示结构。
- 旧节流器在消费 SSE 的任务中直接等待 `MainActor` 投影；当一次布局超过节流窗口时，后续 token
  已经全部过期，节流因此退化成近似逐 token 的主线程更新，正文越长反压越严重。
- 完成态 Markdown 的 block 解析、inline `AttributedString` 转换和整棵视图树切换都落在主线程。
- 完成提交先发布持久化消息、后清理 live projection，导致同一帧同时布局两份完整正文；完成态又在
  外层懒消息列表中嵌套 `LazyVStack`，高度失效时可能短暂空白并放大切换成本。
- 自动滚动观察者挂在可能被 `LazyVStack` 回收的最后一条消息内；内容增长造成的瞬时“离底部”又会
  关闭跟随，因此长流后段可能永久停在旧段落，要求用户手动追赶。
- 旧性能夹具不会走真实完成、持久化和 live projection 清理路径，漏掉最重的一帧。

## 修复

- AI 回复在产品层仍是一条 `CoachMessage`；内部流式正文是一段连续文本，最多 256 字符的存储块
  只服务投影稳定性，不插入可见换行，也不产生多条消息。
- 流式 UI 改为单一不可滚动 `UITextView`/TextKit 文本面，正常增量只向 `textStorage` 追加后缀；
  只有不连续替换或 Dynamic Type 改变时才全量重建。
- SSE 消费只把增量交给单飞 projection pump；pump 每 200 ms 最多排队一次主线程提交，主线程繁忙时
  继续合并积压文本，不让消费任务等待 UI，也不产生过期 token 的提交风暴。
- 完成态受控 Markdown 与 inline attributed text 在后台准备并缓存；准备期间继续显示同一连续文本，
  完成后提交一份带标题、列表、分隔线与内联样式的属性文本，继续使用单一 TextKit 文本面，而不是
  为每个 block 创建 SwiftUI 子 View。
- 完成事务先移除 live TextKit 投影，再一次性发布持久化消息；完成态不再创建内层 block stack，
  也不在外层懒消息列表中继续嵌套按内容高度变化的懒容器。
- 高频 revision 由消息列表外的独立叶子观察；流式期间始终保持跟随，并在布局提交后滚到当前
  `CoachMessage.id` 的底边。Lazy row 是否挂载、用户上滑或 geometry 瞬态都不能关闭跟随。
- 新增无换行和混合 Markdown 完成夹具，必须实际更新 `CoachMessage`、保存 SwiftData、清理 live
  projection，再验证完成后的四 Tab 交互。

## 回归门禁

- 单元测试验证无换行长流按字符硬分块、拼接后字节等价、尾块有界，TextKit 每个字符只追加一次。
- 压力测试让主线程投影故意变慢，验证 projection pump 仍保持文本字节等价且提交次数有界。
- `make perf-check` 固定单一 TextKit 文本面、单飞投影、256 字符边界、非嵌套懒布局、后台
  Markdown 准备和完成阶段 signpost。
- UI 性能测试覆盖 `long-stream-no-newline` 与 `long-stream-markdown-completion` 两条真实完成路径。
- UI 回归在持续流式中主动上滑，必须让当前回复真实尾部重新进入可见区，不能只检查布尔状态。
- 发布前用 Release 真机分别录制 Time Profiler、SwiftUI 与 Animation Hitches；完成后继续执行 Tab
  往返，不能只测仍在流式中的短窗口。

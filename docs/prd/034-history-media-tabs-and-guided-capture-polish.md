# PRD 034：历史、媒体、Tab 与带练取景打磨

- 状态：已实施
- 日期：2026-08-20
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的媒体放大、训练/饮食历史、底部 Tab 与饮食审查基线
  - [PRD 009](009-record-media-association-and-detachment.md) 的统一全屏查看浮层呈现
  - [PRD 013](013-guided-workout-experience-and-capture.md) 的放大取景完整画幅、倒计时归零即切组的边界
  - [PRD 014](014-guided-workout-recording-cues-and-review.md) 的自动录像启动时机与历史录像缩略
  - [PRD 016](016-training-primary-tab.md) 的底部 Tab 导航栈行为
  - [PRD 019](019-training-review-plan-management-and-muscle-map-share.md) 的训练按天分组与筛选入口
  - [PRD 020](020-gui-simplification-and-progressive-disclosure.md) 的训练筛选菜单与设置/日志密度
  - [PRD 031](031-guided-workout-v5-independent-sets-and-automatic-completion.md) 的倒计时结束先切 `.setInProgress` 再启动录像
  - [PRD 033](033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md) 的聊天饮食双卡片密度与执行日志内联展开 LLM 入参
- 后续修订：暂无
- 上游依据：
  - [BUG 0025](../bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md)
- 下游落地：[ADR 0086](../adr/0086-preview-and-history-thumbs-use-aspect-fill.md)

## 背景

v0.0.7 真机走查留下八项交互与可靠性问题，可收成一轮：

1. 点开饮食/足迹图片会先闪一块黑全屏，再弹出查看器。
2. 饮食详情是 Form 输入框，和聊天里已经定型的菜品行完全两套。
3. 聊天饮食卡仍然偏高。
4. 训练历史筛选藏在右上菜单；饮食历史是一条平铺列表。
5. 执行日志点开 LLM 调用会在时间线里展开整份 system+history，造成卡顿。
6. 再点当前底部 Tab 不会回到该 Tab 主页。
7. 自动录像在倒计时结束后经常立刻失败；手动开始却可用。
8. 展开取景和历史录像缩略上下留黑边。

体重记录列表不在本轮范围。

## 用户结果

1. 从缩略图进入媒体查看时，画面从原位置放大，不再先铺黑底。未就绪的视频封面使用与其它空图一致的
   浅底，不出现纯黑方块。
2. 饮食详情的食物项与聊天「记饮食」卡共用同一行样式；聊天卡更矮，名称、热量、份量和三大宏量仍在。
3. 训练与饮食历史用常驻导航标题（带图标），下方是没有实心底条的横向月份芯片；每一天是一张带摘要的卡片，点日期可折叠，折叠后仍能从容量或热量上区分各天；默认全部展开。
4. 执行时间线只显示标题、状态、耗时和 token；完整入参、返回、绑定工具与元数据进入独立页，可选择复制。
   失败行仍在时间线露出最多两行错误摘要。
5. 换到底部另一个 Tab 时保留各自子页面；再点已经选中的 Tab 才回到该 Tab 根页面。教练 Tab 回到当前
   Session，不清空对话。
6. 自动录像在倒计时 PIP 宿主上真正开始写入之后，才切换到本组放大取景。展开预览与历史缩略按取景比例
   铺满裁切，不再 letterbox。

## 产品规则

### 媒体放大

- iOS 18+ 使用从缩略图到查看器的 zoom 过渡；查看器仍 `scaledToFit` 展示原图。
- iOS 17 关闭系统 cover 弹出动画，先把已解码图片交给查看器，再淡入操作条。
- 不在 zoom 过渡上额外铺一层 presentation 黑底。
- 删除、左右切换和聊天只读边界保持 PRD 009。

### 饮食卡

- 详情「食物项」复用聊天菜品行，不把聊天外壳塞进 Form。
- 聊天卡只减密度：更小的内边距、行距和图标，菜名与宏量更小一档；`ViewThatFits` 与辅助字号折行保留。
- 缺项仍为空，不补零。

### 历史列表

- 训练与饮食共用常驻导航标题、透明月份芯片和按天折叠；不用大标题，也不给芯片铺实心底条。
- 每一天是一张卡片：左侧日期与条数与下方动作/食物缩略图左缘对齐，右侧只展示已有容量或热量；缺项保持为空，不补零。折叠后卡片仍分开，不会收成一排灰字。
- 芯片当前项使用 tint 胶囊；同一年内省略年份。
- 折叠状态只作用于当前列表会话，默认展开。
- 行信息量保持现有主指标；有录像的训练行按竖 9:16 或横 16:9 裁切封面。
- 身体/体重历史不改。

### 执行日志

- 时间线 Span 行是 `NavigationLink`，不再 `withAnimation` 展开超长文本。
- 详情页分段展示绑定工具、入参、返回、元数据和错误，文本可选择。

### Tab

- 四个 Tab 各自保留导航栈。
- 只有「新 selection 等于旧 selection」时重建该 Tab 根栈。
- 程序化切到教练（Widget、通知、捕获路由）不视为再点当前 Tab。

### 自动录像与取景

- 倒计时结束：先在现有 PIP 宿主 `startRecording`，等到 `didStartRecordingTo` 成功后再进入
  `.setInProgress`。
- `startingRecording` 与 `isRecording` 均不得改写 `movieOutput` 连接几何。
- 紧凑与放大预览都使用 `.resizeAspectFill`；保存文件仍使用已锁定的捕获几何。

## 数据与隐私

- 不新增 SwiftData 字段、远程数据流、权限或 Agent Tool。
- 执行日志全文仍只留在本机；独立详情页不改变脱敏与不出网边界。
- 测试与文档继续只用虚构记录和 DemoMedia。

## 明确不在范围

- 体重/身体历史改版。
- 换 Tab 时自动 pop 到根。
- 改变录像策略、attempt 终态、热量或容量规则。
- 把媒体查看改成 Photos 式裁切编辑。

## 验收

- 点开饮食、足迹、训练和健身房媒体无先黑后图。
- 聊天饮食卡字段仍在且更矮；详情菜品行与聊天一致。
- 训练/饮食历史常驻标题下可横滑月份芯片，芯片无实心底条，按天折叠可复现。
- 再点「进展」回到进展首页；从进展进入饮食详情后再切到训练再回来，仍停在详情。
- 执行日志 LLM 行推进独立页，时间线不内嵌超长入参。
- 自动录像连续 3 组不因切组宿主交接提前终止；展开预览与历史缩略无上下黑边。
- 饮食按天分组、月份芯片、Tab 再选重置和 Span payload 分段由单测覆盖；录像几何守卫由
  `make check` 静态门禁覆盖。

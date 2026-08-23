# Soma UI 设计 QA

- 日期：2026-08-23
- 范围：黑白双主题、四个根页面、教练消息排版、输入区、训练记录逻辑组、计划总览与动作详情
- 设备：iPhone 17 Pro Simulator，iOS 26.5
- 数据：仅使用演示空间虚构内容

## 对照方法

教练页设计稿为 853×1844，Simulator 原图为 1206×2622。实施截图按比例归一为 853×1844，
与设计稿左右并排检查；输入区另截取底部 620 px 聚焦比较。比较范围包括信息层级、字体大小与
字重、边距、留白、表面层级、图标、边框、圆角、Tab、Composer 和浅深主题；设计稿的长回复与
实施截图的空态引导仅用于覆盖两种内容状态。

| 场景 | 设计稿 | 实施截图 | 同屏对照 |
| --- | --- | --- | --- |
| 教练浅色 | [设计稿](docs/assets/ui/2026-08-22/reference-coach-light.png) | [实施](docs/assets/ui/2026-08-22/implementation-coach-light.png) | [全页](docs/assets/ui/2026-08-22/qa-coach-light.png) / [底部](docs/assets/ui/2026-08-22/qa-coach-light-bottom.png) |
| 教练深色 | [设计稿](docs/assets/ui/2026-08-22/reference-coach-dark.png) | [实施](docs/assets/ui/2026-08-22/implementation-coach-dark.png) | [全页](docs/assets/ui/2026-08-22/qa-coach-dark.png) / [底部](docs/assets/ui/2026-08-22/qa-coach-dark-bottom.png) |
| 训练记录逻辑组 | [设计稿](docs/assets/ui/2026-08-22/reference-workout-editor.png) | `WorkoutLogicalGroupsEditor` | 双主题共用无损逻辑组投影 |

四个根页面实施证据：

- [训练浅色](docs/assets/ui/2026-08-22/implementation-training-light.png) / [训练深色](docs/assets/ui/2026-08-22/implementation-training-dark.png)
- [进展浅色](docs/assets/ui/2026-08-22/implementation-progress-light.png) / [进展深色](docs/assets/ui/2026-08-22/implementation-progress-dark.png)
- [进展趋势浅色](docs/assets/ui/2026-08-22/implementation-progress-trends-light.png) / [进展趋势深色](docs/assets/ui/2026-08-22/implementation-progress-trends-dark.png)
- [设置浅色](docs/assets/ui/2026-08-22/implementation-settings-light.png) / [设置深色](docs/assets/ui/2026-08-22/implementation-settings-dark.png)

## 视觉结论

- 浅色页面为纯白、分组卡为浅灰；深色页面为纯黑、卡片与内嵌块为两级深灰。页面、卡片、输入、
  用户消息和分隔线在两种主题中均可区分，没有灰雾或反相感。
- 黑白承担导航、标题与主操作；类别、指标、状态各自使用确定语义色，不形成品牌色铺面，也不把
  训练页面无差别染橙。训练计划和最近训练仍使用训练类别橙，不使用无差别黑色。
- 浅色语义图标与数据标记适度提高明度与饱和度，在纯白背景上保持清晰且对比度至少为 4.5:1；
  不使用阴影、柔光或模糊。暗色八组语义色保持既定色值。
- 进展页的最近训练柱和连续性热力格使用频率青，训练容量线/点/面积使用负荷橙，体重线/点使用
  身体蓝；指标标题使用对应 SF Symbol。坐标轴、网格、分隔线和根 Tab 保持中性。同一曲线只有在
  确定阈值存在时才按状态分段，不使用装饰性彩虹色。
- AI 正文为 Dynamic Type Subheadline Light，标题和显式强调只升到 Medium。没有厚重 Bold/
  Semibold 文字块。
- AI 消息直接从消息区左边界开始，没有重复头像或装饰图标列。用户消息为右对齐主题灰色小气泡，
  暗色不出现突兀白块。
- 每条消息显示日期与时间。AI 结构只由本地受控 Markdown 映射标题、段落、分隔线和列表。
- Composer 只保留加号、文本、麦克风和发送；三个 Skill 小胶囊保持紧凑，按钮触达范围仍为 44 pt。
- 四个 Tab 未选中使用线框符号，选中项使用对应填充符号和中性底；没有彩色品牌导航。
- 设置的浅灰分组卡、组间距和分隔线在纯白背景上清晰；分区标题对齐卡片外沿，反馈输入使用 inset
  表面和 1 pt 边界；外观倒数第二，反馈保持末端直接发送。设置首页保留原文字、SF Symbol 和行布局，
  仅给现有图标增加身体蓝、训练橙、智能紫、健康红、数据青、通知黄和后台绿等功能色，不给文字或
  图标背景着色。
- 训练记录编辑器不显示组号，覆盖次数/时长、双侧同时、左右各做、仅左、仅右；处方字段相同的
  连续逻辑组忽略间歇压缩为 `×N`，最后一组无组间歇但保留必要的换侧间歇，缺失值不补齐。
- 计划总览分别显示主要与辅助肌群，累计强度不改变动作库角色；动作详情把主要/辅助肌群、提示、
  双面训练橙受力图和图例合并为“标准动作”的单一列表行，浅深主题均无幽灵分隔行或重复章节。

## 交互与辅助功能

- Simulator 语义树确认历史、业务日期、三个 Skill、加号、语音、四个 Tab 和设置外观均为独立可触达控件。
- 浅色、深色切换即时生效；四个 Tab 可切换且保持各自导航栈。
- 长文本区域可滚动；消息选择与复制、Tool/Skill 过程展开、用户消息右对齐和输入安全区均保留。
- 训练记录逻辑组继续复用同一草稿和保存投影，视觉压缩不改变数据真值。

## 工程门禁

- `make format`：通过。
- `make check`：通过；格式、Lint、Markdown 链接、文档生命周期、仓库契约与 Server 类型检查均通过。
- `make verify`：通过；Server 30 项中 29 项通过、1 项因未配置测试数据库而跳过；iOS XCTest
  544 项与 Swift Testing 6 项通过，0 项失败。

# 私人健身教练的情境化主屏组件调研

- 日期：2026-08-04
- 状态：已转化并实现
- 修订自：无
- 下游落地：[PRD 017](../archive/0.0.1/prd/017-contextual-private-coach-widgets.md)、[ADR 0042](../archive/0.0.1/adr/0042-contextual-widget-snapshot-and-privacy.md)

## 结论

Soma 的主屏组件不应继续只是三个“打开 App”的按钮，也不应成为缩小版训练页。它应在用户抬手看
主屏时只回答一个问题：**我现在最应该做什么，点一下会去到哪里？**

最小摩擦来自情境优先级，而不是信息密度：进行中的带练永远优先“继续”；没有进行中带练时优先
显示用户已明确指定的计划；没有计划时才显示本周节奏或开始记录。活动中的逐组细节属于现有
Live Activity，锁屏只保留不暴露训练事实的入口。

```text
进行中的 Session ──→ 继续带练
        ↓ 无
固定/待执行计划 ────→ 打开该计划并确认开始
        ↓ 无
已有训练历史 ───────→ 本周节奏 + 打开训练
        ↓ 无
首次使用 ──────────→ 开始记录 / 建立第一份计划
```

## 行业做法与可迁移结论

### Fitbod：把“本周”和“下一次”放在同一眼可读层

Fitbod 的 iOS 主屏组件在小/中尺寸展示当周已记录训练、周目标和下一次训练；训练进行时则交由
Live Activity 展示当前动作、组次、休息计时与时长。其帮助文档还明确说明，未曾打开 App 或 App
尚未生成组件数据时可能先看到占位态。

- 可迁移：主屏组件应同时给出“当前训练节奏”和一个明确下一步；无数据时必须是诚实、可理解的
  首次/待同步态，不能假定组件已拿到个人数据。
- 不直接照搬：Fitbod 的训练细节、休息计时不应放入 Soma 静态主屏组件；Soma 已有带练 Live
  Activity，且私人身体数据应默认收敛展示。

来源：[Fitbod iOS Widget](https://help.fitbod.me/hc/en-us/articles/360058341233-iOS-Widget)。

### Hevy：一个组件只完成一个任务，并允许用户配置

Hevy 将组件拆分为日常训练、周统计、日历、连续性、常用 Routine 等独立用途；“Routine of the
Day”由用户按星期指定，快速入口能打开空训练或指定 Routine。其统计组件一次只展示一个指标和一段
时间范围，而不是把所有图表压缩进一个卡片。

- 可迁移：Soma 应提供“自动 / 今日训练 / 训练节奏 / 快速记录”的明确显示模式，并允许选择一个
  固定计划；没有结构化排期时，不能凭自然语言 `scheduleHint` 猜测“今天该练什么”。
- 不直接照搬：Soma 不应让 Widget 直接创建训练事实或绕过带练确认；启动仍进入 App 的确定性
  Session 创建流程。

来源：[Hevy Home Screen Widgets](https://www.hevyapp.com/features/home-screen-widgets/)、
[Hevy widgets setup and features](https://help.hevyapp.com/hc/en-us/articles/36956630666647-Hevy-App-Widgets-Explained-Setup-Features-and-How-to-Use-Them)。

### Strong：下一次训练是最短的开始路径

Strong 的组件以“下一次训练”为中心，提供动作、组次、次数、重量与一致性信息，并强调从快捷入口
开始或恢复训练。

- 可迁移：Soma 的主要点击目标必须是与可见信息同一对象的深链接；例如看到“继续训练”就直接
  回到该 Session，看到固定计划就打开该计划的就绪确认。
- 不直接照搬：重量、次数、动作名属于可识别的个人训练事实，只在用户选择“训练详情”显示级别时
  才可出现在主屏；锁屏永不显示。

来源：[Strong Widget](https://support.stronglifts.com/article/186-widget)。

### Apple WidgetKit：可瞥读、按情境刷新、不要伪实时

Apple 的组件设计准则要求按尺寸提供有价值而非单纯放大的内容，保留单一目的、清晰层级和可直接到达
对应页面的深链接。WidgetKit 在独立进程、时间线机制中渲染；组件不持续运行。应用应在数据真正变化
时请求刷新，并为可预测的时间点安排时间线。系统还会限制刷新预算，因此不能把主屏组件当作秒级
计时器或实时取景器。

- 可迁移：小组件只呈现一个指标/一个动作；中组件呈现“情境 + 下一步”；大组件才可加入一周回顾。
- 可迁移：带练计时、休息倒计时和逐组状态继续使用 Live Activity；主屏组件只提供恢复入口和最后
  一次已知状态。
- 可迁移：组件配置应用 `WidgetConfigurationIntent`，并用短、同一语义的深链接把人带到 App 内
  对应页面；不做“点击只是打开首页”的假快捷方式。

来源：[Apple Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)、
[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)、
[Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)、
[Making a configurable widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)。

## Soma 现状审计

当前 `SomaQuickCaptureWidget` 只有中尺寸，Timeline 为 `.never`，Entry 只有日期；它只提供文字、
拍照、照片/视频三个 `soma://capture/*` 深链接。Widget Extension 未读 SwiftData，且 ADR 0013
明确禁止 App Group。因此它稳定、隐私边界清楚，却无法知道是否有进行中的带练、固定计划或近期训练。

Soma 已经具备两个应保留的系统面：

- 训练 Tab 是计划与带练的一级入口；
- `SomaWorkoutLiveActivity` 是训练进行中的状态投影，深链接可直接恢复 Session。

所以新组件不是第三套训练状态机，而是 App 内确定性状态的只读、最小快照投影。

## 推荐内容模型与显示规则

### 组件家族

| 家族 | 默认任务 | 内容上限 | 主点击目标 |
| --- | --- | --- | --- |
| 小尺寸「训练节奏」 | 一眼了解连续性 | 本周训练次数或距上次训练天数，外加一个简短下一步 | 训练 Tab |
| 中尺寸「Soma 今日训练」 | 降低开始/恢复成本 | 当前情境、一条补充信息、一个主操作，至多两个辅助入口 | 对应 Session、计划或训练 Tab |
| 大尺寸「本周训练」 | 回顾与安排，而非实时操控 | 本周概览、固定计划卡和最近训练；不展示全量趋势 | 训练 Tab 或计划详情 |
| 锁屏组件 | 不暴露身体事实的快速进入 | “开始训练”或现有三种记录入口 | 解锁后训练/教练对应位置 |

### 自动模式优先级

1. **有未结束的 `GuidedWorkoutSession`**：中/大组件显示“继续带练”和已知进度摘要；点击恢复原
   Session。详情隐私级别才允许显示计划/动作名，默认不显示倒计时或相机画面。
2. **没有 Session，但用户配置了固定计划**：显示固定计划及“准备开始”；点击进入计划详情的就绪
   确认，不能在 Widget 内创建 Session。
3. **没有固定计划，但最近有训练事实**：显示本周训练次数与距上次训练；主操作为“打开训练”，
   辅助入口可为“记录训练”。不把“最近一次”错误命名为“今天计划”。
4. **无训练计划且无训练事实**：显示首次使用解释和“开始记录”；不虚构周目标、动作建议或训练
   容量。

用户选择非自动模式时，优先级不替换安全边界：进行中的 Session 仍可以以“继续带练”覆盖，避免
用户在最需要恢复时看不到恢复入口。

### 隐私显示级别

| 级别 | 默认值 | 可显示 | 禁止显示 |
| --- | --- | --- | --- |
| 私密 | 默认 | 通用状态、进入训练/记录入口 | 计划名、动作名、重量次数、训练日期、体重、饮食、照片/视频 |
| 概览 | 用户明确开启 | 本周次数、完成组数、距上次训练的相对天数 | 动作名、重量次数、身体/饮食信息、媒体 |
| 训练详情 | 用户明确开启，仅主屏 | Session 或固定计划名称、下一个动作的名称、处方摘要 | 体重、饮食、健康备注、原始媒体、相机预览、AI 评价 |

锁屏、StandBy、CarPlay 与 Live Activity 默认遵循“私密”显示；其中训练 Live Activity 的既有通用
状态保持不扩展。用户在 Widget 编辑页可以选择显示模式、隐私级别和固定计划；设置页提供总开关与
“组件可显示训练详情”总授权。

## 技术可行性与边界

### 必要的最小共享快照

要显示内容，Widget Extension 必须读取应用预先准备的数据，而不是直接打开 App 的 SwiftData。
Apple 也明确建议 App 与扩展通过 App Group 共享容器存放数据；WidgetKit 独立进程渲染，不能依赖
屏幕上的 App 绑定实时更新。

建议在实现前以新 ADR 固化以下设计：

- App 的 `WidgetSnapshotProjector` 仅在主进程读取 SwiftData，产出按当前数据空间隔离的
  `WidgetSnapshot`；Widget Extension 只读该快照，绝不写训练、计划或聊天业务数据。
- 共享容器只保留展示所需的最小派生字段、版本、生成时间、隐私级别和用于深链接的内部 UUID；
  不存照片/视频、完整训练历史、原始聊天、API Key、位置或健康原始样本。
- Snapshot 使用原子写入；App 切换演示/个人空间、删除数据或关闭组件详情时立即写空/降级快照并
  请求刷新，避免跨空间残留。
- 每次计划/Session/训练事实/隐私设置发生相关变化时合并调用 `reloadTimelines(ofKind:)`；周界与
  日期相对文案使用预测时间线。刷新未及时到达时应显示“打开 Soma 更新”，不得声称实时。

来源：[WidgetKit foundations (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/277/)、
[TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider)、
[reloadTimelines(ofKind:)](https://developer.apple.com/documentation/widgetkit/widgetcenter/reloadtimelines%28ofkind%3A%29/)。

### 交互边界

WidgetKit 支持 `AppIntent` 按钮和开关，但 Apple 同时要求交互应完成有意义的动作，而不是只打开
App。对 Soma 而言，“完成本组”“开始一条训练”“确认录像”等会改变健康/训练业务事实，仍需要 App
内的计划就绪、权限、确定性状态机与用户确认。因此本期组件只使用 `Link` / `widgetURL` 深链接。

未来如增加 Widget 内交互，必须先由 ADR 明确它是否可安全、幂等地写入最小本地事实，并处理设备锁定、
失败回显与时间线刷新；不能借 App Intent 绕过记录审查。

来源：[Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)。

### 隐私与不可用态

Apple 将 Widget 视为始终可见的敏感信息表面，支持自定义遮罩和数据保护。Soma 应以私密模式为默认、
在设备尚未解锁或共享快照不可读时显示通用占位态，并让用户可从组件设置撤回详情展示。

来源：[Widget security](https://support.apple.com/en-gb/guide/security/secbb0a1f9b4/web)。

## 不建议的方向

- 在主屏组件显示摄像头预览、动作示范视频、实时动作计数或黑色预览窗：它们不适合时间线渲染，
  且会泄露或误导用户。
- 让组件直接记录“完成训练”、创建计划、调用 Agent 或发送媒体：这会绕过当前聊天/计划确认与本地
  事实边界。
- 用 AI 每天生成“今天练什么”再推到组件：这既不具备用户显式计划依据，也会消耗 Token；组件只
  投影已存在的计划和确定性训练历史。
- 在锁屏显示动作、重量、体重、饮食、训练照片或 AI 分析。

## 需要验证的产品假设

- 自动模式中“继续带练 / 准备固定计划 / 打开训练”是否能覆盖大多数主屏点击；需要匿名、本机可选
  的组件点击漏斗，而不是上传训练内容。
- 用户是否愿意为组件详情明确开启隐私级别；若开启率低，私密模式必须仍有足够的启动价值。
- 固定计划是否比未来引入的结构化周排期更适合作为第一版；在还没有可靠排期模型前，不新增“今日
  计划”承诺。

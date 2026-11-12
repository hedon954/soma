# HealthKit 能力调研与每日运动记录方案

- 日期：2026-10-21
- 状态：已转化为 PRD 075 / ADR 0144，按每日一条运动记录实施
- 修订自：[日消耗本地公式调研](2026-09-08-daily-energy-expenditure-methods.md)（三项活动日汇总的只读来源与覆盖边界）
- 后续修订：[多来源优先级调研](2026-11-05-daily-activity-source-priority.md)
- 下游落地：[PRD 075](../archive/0.0.30/prd/075-healthkit-daily-activity.md)、[ADR 0144](../archive/0.0.30/adr/0144-healthkit-daily-activity.md)

## 一、HealthKit 能提供什么

HealthKit 是设备上的健康数据存储与授权接口；可读取的数据取决于用户允许的类型及实际写入的数据源。
不是所有 iPhone 都会自动拥有所有指标，也不保证一个来源全天佩戴或数据完整。

| 类别 | 典型数据 | 本次 |
| --- | --- | --- |
| 日常活动 | 步数、步跑距离、骑行距离、活动能量、爬楼等 | 只选三项 |
| 能量 | 活动能量、静息能量 | 只读活动能量 |
| 训练 | 类型、起止时间、时长、相关统计、路线等 | 不读 |
| 身体测量 | 体重、身高、体脂等 | 不读 |
| 心血管和生命体征 | 心率、静息心率、HRV、血氧等 | 不读 |
| 睡眠 | 睡眠区间和阶段 | 不读 |
| 饮食和摄入 | 营养素、水、能量摄入等 | 不读 |
| 其他健康数据 | 症状、正念、生殖健康等授权类型 | 不读 |

目录参考：[HealthKit 数据类型](https://developer.apple.com/documentation/healthkit/data-types)。

### 授权与可用性

- 仅在用户点连接时申请读取。检查 isHealthDataAvailable()；写入类型为空。
- 读取授权状态受隐私限制，不能把授权流程完成等同于三项已获准，也不能根据空数据断言用户拒绝。
- 锁屏或其他读取错误不写成 0；明确 0 与无可读数据不同。
- 项目最低 iOS 17，使用本机 SDK 可用的统计 descriptor；不依赖 iOS 27 新增的最早授权日期 API。

参考：[授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)、
[隐私](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)。

## 二、这次我们用什么

| 指标 | HealthKit 类型 | 内部单位 |
| --- | --- | --- |
| 每日步数 | stepCount | count |
| 步行与跑步距离 | distanceWalkingRunning | m；显示时转 km |
| 活动消耗 | activeEnergyBurned | kcal |

热量只读活动能量，不读 basalEnergyBurned。不依赖 Apple Watch；COROS App 已写入健康库的对应数据可被 Soma 读取。
COROS 的连接清单包含步数和步跑距离；活动能量支持另由官方更新说明确认，实际设备同步需要真机对照。

参考：[COROS 连接 Apple 健康](https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App)、
[COROS 活动能量更新](https://coros.com/stories/latest-news/c/august-2023)、
[活动能量类型](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned)。

### 用户路径

设置连接后，每天形成一条「日常活动」运动记录，包含步数、距离、活动消耗。
复用运动记录列表、详情与进展统计，不添加独立仪表卡、来源列表或最近读取时间。
source 保留在数据中，实际写入者由 HealthKit 返回；COROS 直接写入时保留其名称/标识，转写时不猜测原始厂商。

### 统计口径

活动能量读数（包含 0）保留为健康观察，不证明全天生活活动完整覆盖。
总消耗按动态消耗方案计算参考生活、非训练步行差额、去重训练增量和长期修正；日合计不再额外相加。
缺少静息公式所需资料时，不推测静息或全天总消耗；活动来源未知保持未知。

日/周/月/年图表、热量缺口及推荐目标共享既有运动记录投影。当天值仍是截至最近成功读取的活动数据，不能把它当作完整全天覆盖的保证。
这部分是产品统计规则，静息仍为估算，不能称为设备测得的全天总消耗。

## 三、实现方案

### 查询与来源

- 固定三个 quantity 类型，各用 cumulativeSum 统计 descriptor，默认采用系统合并总量。
- 同窗口独立 separateBySource 查询只提取每天 HKStatistics.sources 的名称和 bundleIdentifier。
- 不相加来源分项数值，也不把窗口来源并集复制给每一天。来源查询失败不阻塞数值。
- 按 Calendar 的自然日切片，明确时区与起止点；加一天不能用固定 86400 秒替代，覆盖 DST。
- 前台持续窗口的 predicate 截止该窗口末日的次日零点，避免在首次 now 截断后续更新。

参考：[统计 descriptor](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquerydescriptor)、
[统计来源](https://developer.apple.com/documentation/healthkit/hkstatistics/sources)、
[HKSource](https://developer.apple.com/documentation/healthkit/hksource)。

### 每日覆盖为一条记录

WorkoutEntry 增加可空 dailyActivityData，保存三个指标和逐指标 source；旧记录为 nil。
externalSource 固定 appleHealth，externalID 为 daily:yyyy-MM-dd；projectionKey 是唯一身份，不使用来源名称作为去重键。
同一天反复同步更新同一 id / businessID，来源变化、值变小、0 和空结果均覆盖；未完成/失败的指标不覆盖。
三项均无值时删除同步记录；不制造组数、次数、重量、时长或动作关系。

默认每次冷启动或回前台在已连接个人空间读取近 30 日，更早日期按需刷新。
根生命周期负责 owner，不依赖进展是否可见；后台、切演示或断开取消，以 generation 阻止迟到结果落盘。
写入通过 MainActor 的共享 Store，保存后由既有 SwiftData 通知刷新进展。

### 隐私与兼容

- 新增可空字段兼容旧 SwiftData 记录，不新增模型，不需要 SQL migration。
- 健康记录与普通记录共享个人库，因此个人库及其目录采用 complete 文件保护并排除系统备份。
- 应用备份和导出过滤 appleHealth 记录；内部恢复回滚快照仍保留字段，避免恢复失败丢失现有数据。
- 模型上下文、读取工具、Server 和反馈自动上下文不包含这些健康记录。
- 断开停止读取并删除连接设置，已同步运动记录保留。清空个人数据会删除记录并断开；备份恢复后重新连接再同步。
- 只给主 App 增加 HealthKit entitlement 与 NSHealthShareUsageDescription，不给 Widget/Server 增加健康能力。
- 不启用健康写回、后台交付、厂商 API、Watch App 或样本镜像游标。

## 四、验收

确定性测试覆盖：同日稳定身份、较小值/0/nil 替换、部分失败保留、全空删除、source 持久化、空间隔离、重启/前台和迟到结果。
统计测试覆盖：活动能量替换原活动估算，日/周/月/年、缺口、推荐目标一致，缺资料保持未知，无读数回退。
数据库结构、备份/模型过滤、旧数据兼容与 make verify 为门禁。界面用虚构数据检查浅深主题、Dynamic Type、小屏和 iPad。
真实权限、COROS 对照、系统多来源合并、删除回调、跨午夜/时区和锁屏保护另行真机验收，不保存真实数值或截图。

本轮实现与安装证据见 [验收清单](../acceptance.md#apple-健康每日活动prd-075)。

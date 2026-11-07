# ADR 0148：个人资料保存每日目标热量缺口

- 状态：已采纳并实现；模拟器验证通过；真实旧库升级待验收
- 日期：2026-11-07
- 版本：未发布
- 上游依据：[PRD 079](../prd/079-daily-target-deficit.md)、[ADR 0147](0147-residual-energy-coefficient.md)（保持总消耗公式）
- 下游落地：[验收](../acceptance.md)

## 背景

减脂摄入目标此前固定减去 400 kcal，无法表达用户选择的每日目标缺口。需要在个人资料中保存偏好，保持既有总消耗模型与健康事实边界。

## 决策

`UserProfile.dailyTargetDeficitKilocalories: Double?` 保存用户偏好。新增可选字段采用 SwiftData
加字段轻量迁移，不注册新模型，不引入历史 VersionedSchema 或破坏性重建。旧值为 nil，不回填。
实际旧库升级仍须在 Apple 平台验证；增加字段不等于已经完成迁移验收。

`DailyTargetDeficit` 统一有限非负数校验、输入解析与默认值 400；损坏或非法存储值只在读取时回退，
不静默覆盖原记录。显式 0 不回退。设置沿用资料页保存动作，失败提示可重试，不假装成功。

`NutritionTargetCalculator` 只在 `.fatLoss` 应用此偏好。`ProgressHistoryLoader` 将数值投影为
Sendable facts，日营养环和仍可摄入共用结果；`ModelContextSaveImpact` 已包含 UserProfile，
保存会失效现有进展快照。零推荐摄入不计算百分比，不制造除零结果。

备份 `UserProfileDTO` 增加同名可选字段；合成 Codable 支持旧 JSON 缺键，恢复保留 0 和自定义值。
这是资料偏好，和已有健身目标一样可进入教练上下文，不包含 HealthKit 读数或派生消耗证据。

这是当前偏好，不是有效日期历史；保存后查看旧日期时，推荐摄入也按当前偏好重算。
已保存的健康证据、真实摄入与实际消耗不被改写。切换非减脂目标保留但不应用该数值。

## 未选择的方案

- UserDefaults：会脱离个人 / 演示数据空间以及现有加密备份。
- 改残差系数或总消耗来满足目标：混淆用户意图与消耗估算。
- 强制历史回填 400：没有必要写入用户没有明确设置的数据。
- 预设医学安全上限或自动校准：当前需求未定义，不擅自增加。

## 结果

用户偏好随个人数据空间和备份保留，摄入推荐与进展共用确定性规则。代价是新增可选持久字段，旧库迁移及 iOS 界面必须在 Apple 平台验收。

## 验证

`DailyTargetDeficitTests`、`DailyTargetDeficitPersistenceTests`、`ProgressEnergyDeficitTests`、
`ConversationContextProjectionTests` 和 `DailyTargetDeficitUITests` 覆盖规则与接入。
磁盘重开与备份测试不替代真实旧库升级测试；完整构建、SwiftData 与 UI 验收依赖 Xcode。

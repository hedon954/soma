# ADR 0009：全量迁移为 Soma

- 状态：已采纳
- 决策日期：2026-07-29

## 背景

早期工作名 FormCoach 强调动作教练，但产品已扩展为理解训练环境、饮食、身体、趋势和健康数据的个人身体智能。用户要求不保留旧名称兼容，也不迁移旧数据。

## 决策

- 产品名称统一为 **Soma**。
- 产品主张统一为 **Your body, understood.**
- Xcode project、scheme、target、module、测试 target、源码目录和 UI 文案全部改名。
- Bundle ID 改为 `top.hedon.soma`。
- Keychain service、归档名称和文档入口使用 Soma。
- 不兼容旧 Bundle ID 的本地数据库和 Keychain 数据。

## 未选择的方案

- 只改显示名称：代码、签名、日志和文档会继续出现旧品牌。
- 保留旧 Bundle ID 迁移数据：用户明确表示当前无需关心数据。

## 结果

Soma 在设备上被视为新的 App 身份。旧 FormCoach 的签名配置、容器和本地数据不属于当前兼容范围。

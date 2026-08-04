# ADR 0043：免费签名阶段使用静态 Widget 入口

- 状态：已采纳
- 日期：2026-08-04
- 维护者：Soma maintainers
- 部分替代：[ADR 0042](0042-contextual-widget-snapshot-and-privacy.md) 的 App Group 最小快照实现，直至获得支持该 capability 的开发者 Team
- 后续替代：暂无
- 上游依据：[PRD 018](../prd/018-free-team-widget-fallback.md)、[ADR 0013](0013-widget-and-app-intent-capture-routing.md)

## 背景

当前 Apple ID 只能使用免费 Personal Team。该签名能力不能为主 App 和 Widget Extension 同时签发
`com.apple.security.application-groups`，因此包含 App Group entitlement 的构建无法安装到真机。

## 决策

1. 移除主 App 与 Widget Extension 的 App Group entitlement、共享快照投影、动态组件设置和关联路由。
2. 主屏恢复为中尺寸静态“文字、拍照、照片/视频”快速记录入口；锁屏 Widget 与 App Shortcut 保持不变。
3. 不以服务器、iCloud、剪贴板、Keychain 或跨进程写 SwiftData 伪造共享状态；这些方案要么增加未授权的数据流，
   要么仍依赖 entitlement，或不满足本地优先与隐私边界。
4. 当用户加入支持 App Groups 的 Apple Developer Team 后，以 ADR 0042 的最小快照边界重新实现并验收情境化组件。

## 结果

免费签名真机可以重新安装并使用所有现有快速记录和锁屏入口，但不会显示训练进度、固定计划或训练节奏。
这是一项诚实的能力降级，不会影响训练计划、带练、聊天或本地数据。

## 验证

- `make verify` 通过，且在免费 Team 下 `make install-device` 成功安装。
- 真机从主屏及锁屏三个入口分别能打开对应的录入路径。

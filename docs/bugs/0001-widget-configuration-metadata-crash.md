# BUG 0001：动态配置文本导致 Widget 从组件库消失

- 状态：已修复，待真机界面确认
- 发现日期：2026-07-30
- 影响范围：主屏幕和锁屏组件库无法发现 Soma

## 症状

主 App 能正常安装和启动，安装包也包含签名有效的 `SomaWidgetExtension.appex`，但桌面与
锁屏的“添加小组件”都搜索不到 Soma。反复安装不会恢复。

真机系统崩溃目录中持续出现 `SomaWidgetExtension` 报告；崩溃栈落在
`lockScreenConfiguration(for:)` 的 `configurationDisplayName`，WidgetKit 在读取组件
描述阶段触发 Swift 断言。系统发现扩展但无法取得有效描述，因此不把它展示到组件库。

## 根因

锁屏组件使用 `Text("Soma \(action.title)")` 和 `Text(action.detail)` 生成配置名称与描述。
这些内容属于 Widget 的静态注册元数据，却通过包含运行时字符串的 SwiftUI `Text` 传入。
iOS 26.3.1 的 WidgetKit 无法把这种动态 `Text` 作为扩展元数据透传，触发
`Unsupported string type` 断言并终止扩展。

这不是签名、嵌入、Bundle ID 或组件缓存问题。只检查 `.appex` 是否存在和 codesign 是否
通过不足以发现它，必须检查扩展崩溃报告或实际打开组件库。

## 修复

- 为三种锁屏动作分别提供固定的 `LocalizedStringKey` 名称与描述；
- Widget 配置直接使用本地化字符串重载，不再把运行时拼接内容包装为 `Text`；
- 构建号从 1 提升到 2，确保真机重新注册修复后的扩展。

修复不改变 [ADR 0013](../archive/0.0.1/adr/0013-widget-and-app-intent-capture-routing.md) 的路由、数据或
隐私边界。

## 回归门禁

- `make check` 扫描 `SomaWidget`，禁止
  `configurationDisplayName(Text(...))` 和 `description(Text(...))`；
- `make verify` 必须编译包含全部四种 Widget 的扩展；
- 真机安装后同时在桌面与锁屏组件库搜索 Soma，并确认没有生成新的
  `SomaWidgetExtension` 崩溃报告；
- 只要涉及 Widget 注册元数据、签名或嵌入配置，就不能以主 App 能启动作为验收完成。

## 验证

- `make check`：通过；
- `make verify`：通过；
- 构建号 2 已安装并启动于 iOS 26.3.1 真机；
- 安装后的监控窗口内没有新增 `SomaWidgetExtension` 崩溃报告；
- 桌面和锁屏组件库的最终可发现性等待本次真机界面确认。

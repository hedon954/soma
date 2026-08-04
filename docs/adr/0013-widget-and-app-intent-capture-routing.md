# ADR 0013：Widget 与 App Intent 只负责进入聊天录入

- 状态：部分已替代
- 决策阶段：2026-07-29
- 后续替代：[ADR 0042](0042-contextual-widget-snapshot-and-privacy.md) 部分替代主屏 Widget 的只读数据投影范围

## 背景

Soma 的价值来自低摩擦记录。用户希望从主屏幕和锁屏直接开始文字、拍照或媒体输入，但
Widget 不能承载任意文本编辑，也不能在扩展进程中直接呈现系统相机和照片选择器。让扩展
直接写 SwiftData 还会引入 App Group、并发写入和新的隐私边界。

## 决策

- 提供中尺寸 `SomaWidget`，包含“文字”“拍照”“照片/视频”三个入口。
- 提供文字、拍照、照片/视频三个独立锁屏 Widget；每个入口同时支持
  `accessoryInline`、`accessoryCircular` 和 `accessoryRectangular`，用户可按锁屏位置
  选择系统允许的样式。
- Widget 使用 `soma://capture/{mode}` 深链接打开主 App；系统快捷指令通过
  `StartSomaCaptureIntent` 暴露相同三种意图。
- `SomaCaptureRouter` 由 App 根生命周期持有，只传递短生命周期的录入意图。
- 文字入口切到教练并聚焦输入框；拍照和媒体入口直接呈现对应的系统选择器，选择结果再交给
  教练输入区。
- Widget 和 App Intent 不直接写业务记录、不运行 Agent、不读取本地健康数据。主屏 Widget 的最小
  只读 App Group 快照由 ADR 0042 单独授权；所有事实仍从聊天或确定性带练闭环进入。
- 锁屏入口在设备锁定时由系统先完成身份验证；Widget 不尝试绕过解锁直接访问相机、媒体或
  私人身体数据。
- App 未运行时允许系统启动 App；App 被终止后不承诺扩展内后台解析。

## 未选择的方案

- Widget 内直接编辑和发送：系统能力不足，也会复制聊天输入逻辑。
- Share Extension：适合从其他 App 分享已有媒体，不覆盖主屏幕快速拍照与文字入口。
- Widget 直接写 SwiftData：需要共享容器和额外一致性设计，破坏当前本地数据边界。
- 静默后台运行 Agent：超出 iOS Widget 生命周期，也与当前 PRD 的进程存活边界冲突。

## 结果

主屏幕 Widget、锁屏 Widget 和系统快捷指令只是聊天的低摩擦入口，不形成第二条写入路径。
后续若增加 Share Extension、Widget 内写入或后台处理，必须新增 ADR 说明数据一致性、隐私和失败恢复；
App Group 的主屏只读快照已由 ADR 0042 限定。

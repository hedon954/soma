# 2026-08-04：情境化主屏组件

## 用户结果

Soma 主屏组件从纯快捷按钮升级为“当前下一步”入口：可继续的带练优先恢复，随后是用户固定计划、
本周训练节奏或首次训练。用户可在“设置 → 主屏组件”选择自动、固定计划、训练节奏或快速记录，并以
私密、概览、训练详情三个等级控制主屏可见内容。

## 实现边界

- App 把当前数据空间的最小派生快照写入本机 App Group，Widget Extension 只读并在相关事实或日期
  边界请求刷新；不上传服务器或模型 Provider。
- Widget 不写 SwiftData、不创建/完成训练、不调用 Agent、不录制媒体。继续带练、固定计划和记录入口
  分别深链到既有 Session、计划开始前确认和教练录入流程。
- 锁屏、StandBy、CarPlay、灵动岛与 Live Activity 保持私密，不显示计划、动作、重量、体重、饮食或媒体。

## 关联

- [PRD 017](../archive/0.0.1/prd/017-contextual-private-coach-widgets.md)
- [ADR 0042](../archive/0.0.1/adr/0042-contextual-widget-snapshot-and-privacy.md)
- [组件调研](../research/2026-08-04-contextual-private-coach-widgets.md)

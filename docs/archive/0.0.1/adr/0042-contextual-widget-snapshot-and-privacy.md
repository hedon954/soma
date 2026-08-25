# ADR 0042：情境化组件使用最小本地快照与私密默认值

- 状态：暂缓（需支持 App Groups 的开发者 Team）
- 日期：2026-08-04
- 维护者：Soma maintainers
- 部分替代：[ADR 0013](0013-widget-and-app-intent-capture-routing.md) 的“Widget 不读取本地数据、不引入 App Group”范围
- 后续替代：[ADR 0043](0043-free-team-widget-fallback.md) 在免费签名阶段恢复静态快速记录组件
- 上游依据：[PRD 017](../prd/017-contextual-private-coach-widgets.md)、[组件调研](../../../research/2026-08-04-contextual-private-coach-widgets.md)

## 背景

纯快速录入 Widget 无法降低“继续当前带练”和“开始固定计划”的摩擦。Widget Extension 与 App 是独立
进程，不能直接读取 App 的 SwiftData；若为此让扩展写业务记录，则会破坏聊天/计划确认、数据空间隔离
与训练状态机边界。

## 决策

1. 主 App 在当前数据空间内读取 SwiftData，并将最小 `SomaWidgetSnapshot` 原子写入 App Group
   `group.top.hedon.soma`；Widget Extension 只读取该 Codable 快照。
2. 快照仅有 Schema 版本、数据空间标识、生成时间、可恢复 Session 的内部 ID/组进度、有效固定计划
   的内部 ID，以及周训练次数/距上次训练等派生摘要。它不含聊天、媒体、健康样本、位置、API Key、
   AI Trace 或完整训练历史。
3. “私密”是默认组件显示级别。只有用户在 App 设置明确选择“概览”或“训练详情”后，快照才包含相应
   允许的派生信息；计划名仅在“训练详情”进入主屏快照。锁屏、StandBy、CarPlay、灵动岛和 Live Activity
   不读取详情内容。
4. App 在计划、Session、训练事实、隐私设置、数据空间或日期周界改变后调用
   `WidgetCenter.reloadTimelines(ofKind:)`；刷新是合并请求、非实时承诺。Widget 时间线还会在下一日
   刷新相对日期文案。
5. Widget 使用深链接进入已有 Session、计划就绪确认、训练 Tab 或既有记录入口；它不创建/完成训练、
   修改计划、调用 Agent、录制媒体或写 SwiftData。
6. Widget 读取不到快照时显示通用“打开 Soma 更新”状态。切换数据空间、清除数据、关闭详情或删除固定
   计划时，App 先写入降级/新空间快照再请求刷新，避免残留旧空间或已删除计划信息。

## 未选择的方案

- Widget 直接访问 SwiftData：扩展进程和 App 容器边界不允许，且会把数据访问并发扩散到系统组件。
- Widget App Intent 直接完成组次或启动训练：会绕过开始前确认、权限、幂等状态机和事实审查。
- 将完整计划、动作处方或训练历史复制到 App Group：隐私暴露面过大，也不符合组件只回答当前下一步。
- 服务器推送组件快照：Soma 的组件状态完全可由本机事实派生，引入远程投影会违背本地优先且不改善
  当前离线场景。

## 结果

Soma 可在主屏按“继续带练 → 固定计划 → 训练节奏 → 首次记录”提供低摩擦入口，同时所有健康事实
仍由 App 内确定性流程保存。ADR 0013 关于锁屏快捷录入、App Intent 不写业务记录和不绕过系统解锁的
约束继续有效；仅主屏内容读取与 App Group 最小快照由本 ADR 扩展。

在当前免费 Personal Team 无法为 App Groups 签名时，ADR 0043 暂时恢复 ADR 0013 的静态入口；本决策
及实现会保留在 Git 历史中，待可用 Team 开通后重新采纳。

## 验证

- 单元测试覆盖进行中 Session 的优先级、私密固定计划不泄露名称、训练节奏与首次使用回退。
- 模拟器检查小/中/大组件、深色、着色、Dynamic Type、无快照和切换隐私级别后的刷新。
- 真机确认 App Group 快照可被组件读取；从继续带练、固定计划、训练节奏和三种记录入口分别深链到
  正确 App 场景；锁屏不显示训练详情。

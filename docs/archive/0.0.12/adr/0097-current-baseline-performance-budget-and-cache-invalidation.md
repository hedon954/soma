# ADR 0097：当前安装基线、性能预算与缓存失效

- 状态：已采纳，Release 真机量化验收中
- 日期：2026-08-24
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 中每次启动继续执行业务整表回填的边界；当前 marker 命中后必须立即返回
- 上游依据：当前唯一用户已安装 Soma `0.0.11 (15)` 的无损要求
- 下游落地：
  - [全 App 性能审计报告](../../../engineering/performance-audit-2026-08-24.md)
  - [数据库结构与 ER 图](../../../engineering/database-schema.md)
  - [验收矩阵](../../../acceptance.md)
- 后续修订：[ADR 0100](../../../adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)

## 背景

稳定 Tab 栈并不等于切换成本低。SwiftUI 首次构建、动态属性取值、无界 SwiftData 订阅、同步媒体
解码和重复派生都可以在没有“重新打开数据库”的情况下阻塞一帧。当前只有一名用户，且最新版已经
安装；继续让已经完成的历史迁移、旧 repair 和兼容读取进入每次启动或每次渲染没有产品收益。

## 决策

1. `DataMigrationMarker.schemaVersion = 6` 是 `0.0.11 (15)` 当前安装基线。marker 谓词与
   `fetchLimit = 1` 必须先于任何 SwiftData 整表业务迁移；命中后立即返回。
2. Root 可交互前只执行容器打开、当前 marker 和中断一致性所必需的门禁。演示内容检查、媒体
   去重和孤儿回收在 Root 可见后运行，必须幂等、可取消并且不阻塞首帧。
3. 根页面不得用无界查询订阅与首屏无关的历史。列表使用稳定排序、谓词、上限和手动分页；详情按
   稳定业务 ID/UUID 定向读取。`fetchCount` 只用于计数。
4. 120 Hz 严格档的目标是：warm 常用交互 p95 `<100 ms`、冷页面首个有效内容 p95
   `<200 ms`、滚动 hitch `<1%`、无 `>100 ms` 主线程停顿、可重复 `body` 热点 `<1 ms`。
   这些是 Release 真机验收目标，不用 Debug Simulator 冒充通过。
5. 派生快照只包含不可变 Sendable DTO。大量查询和聚合在独立 actor 执行；SwiftUI 主线程只接收
   完成值。不得用拼接全量字段的 String 作为 revision。
6. 图片缓存 key 包含文件身份和目标像素，成本上限 48 MB；内存警告、数据空间切换或文件指纹变化
   必须失效。全屏只加载当前项和相邻需求，不把原始大图长期留在缓存。
7. 相同媒体内容以 SHA-256 发现，数据库引用仍获得独立逻辑路径；相同内容路径之间使用硬链接，
   从而既复用物理空间，又保持单条记录删除安全。孤儿回收使用个人/演示空间引用并集。
8. Agent 投影以 Job ID 和 sequence/cursor 高水位增量工作。终态历史 Event 只在执行日志按需分页，
   不参与根页面 revision。
9. 导出、备份、恢复准备、媒体读取/加密和诊断文件工作在后台执行并传播取消。最终 SwiftData 替换
   是明确的事务性维护阶段，UI 必须显示工作态和可恢复错误。
10. 删除不可达的旧整表 repair、重复判断和无调用 backfill；当前 marker 6、当前归档、当前在途
    Job 或当前字段 getter 仍需要的技术兼容代码继续保留。物理旧列不进入新业务 API。
11. Tab selection 只允许写一次选中状态；禁止调用 `UIView.setAnimationsEnabled` 全局抑制动画，
    也不得替换系统 Tab bar 或用包装器改变四个原生 Tab 的结构和样式。性能优化必须减少实际
    invalidation、布局、文本处理和查询工作，而不是隐藏系统反馈。
12. Coach 每个 Session 首次只查询最近 10 条消息和一条“是否还有更早”的哨兵；用户向上滚到
    顶部后每次增加 10 条，并恢复分页前首条消息的视觉位置。短内容顶部对齐，超过一屏时初始定位
    最后一条消息到底部。用户主动向上阅读后，流式更新不得持续抢回底部。
13. Session 缓存必须以实际访问为边界：只有已经由懒栈创建的可见消息气泡才能写入有界纯渲染
    缓存；未打开的 Session、未滚到的历史消息和未出现的记录卡不得预取或预热。消息原始字段变化
    自然换条目，内存警告清空；不得把 SwiftData 模型对象放入跨 Session 缓存。
14. 长流式正文使用稳定块与最多 256 字符的可变尾块。正文块必须懒布局，冻结块不得因尾部 5 Hz
    更新而反复断行；完整正文只在完成时合并持久化。不能以截断历史正文或提高缓存常驻量代替
    真实布局减法。

## 未采用方案

- 切 Tab 时销毁再重建页面：会丢导航栈、草稿和缓存，且不能解决首次构建查询成本。
- 缓存 SwiftData 模型对象：对象不能跨 `ModelContext` 安全复用，也会把缓存变成隐性事实来源。
- 多引用直接共用同一路径：任意调用 `removeStoredFile` 都可能破坏其他记录。
- 只靠更快设备掩盖：数据增长后无界算法仍会退化，并且 120 Hz 帧预算更严格。
- 删除所有含 legacy/fallback 的代码：会破坏当前已安装 store、当前归档或在途 Job；只按可达性删除。

## 结果

- warm Tab 继续保留状态，同时首屏读取与历史规模解耦。
- 系统底栏反馈和四个独立导航栈继续保留；页面切换成本通过减少实际工作量收敛。
- 当前安装 marker 命中后的启动成本近似常数；一次性维护不占首帧。
- 图片和媒体占用有明确成本、失效与删除安全语义。
- 长流式的每次刷新成本由完整正文长度解耦，只处理有界尾块和当前可见布局。
- 性能退化由 `make perf-check`、压力夹具、signpost 和真机 trace 四层发现。
- 最终真机量化数据仍是发布验收项；没有 trace 时不得宣称 120 Hz 已完全达标。

## 验证

- `make perf-check`：Root 查询、热服务整表 fetch、同步图片 I/O、字符串 revision 与启动 repair。
- 10,000 消息、5,000 训练记录、1,000 媒体引用压力夹具。
- 图片下采样、请求缓存清理、共享硬链接、双空间引用和孤儿选择测试。
- `make verify`，iPhone 17 Pro Max Simulator 四 Tab、详情、输入焦点、主题、Dynamic Type、滚动与安全区回归；逐帧视频验证页面内容无长交叉淡化，软件键盘面板保留到真机手感验收。
- `SOMA_PROFILE_DEVICE=<UDID> SOMA_PROFILE_RUNS=1 SOMA_PROFILE_INTERACTION=tabs SOMA_PROFILE_INTERACTION_ROUNDS=30 SOMA_PROFILE_TEMPLATES='Time Profiler' SOMA_PROFILE_DURATION=120s make perf-profile-device` 在一个真机 trace 内采集 30 轮四 Tab；脚本验证 trace 完整性、每个 Tab 的样本数和 p95 `<100 ms`。Animation Hitches、SwiftUI 与 Allocations 复用同一路径分别录制。

# Soma 0.0.12 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；只有维护者明确要求
历史时才打开原始文件。仍有效的最终状态已经折叠进活的 PRD 000 与 ADR 0000 压缩起点。

## 产品要求摘要

- PRD 043：ReAct 活动执行上限进入高级设置，默认保留文字、图片、视频 3/5/10 分钟，并限制为
  3–60 分钟；后续 0.0.15 将统一自定义值细分为三类独立配置。

## 架构决策摘要

- ADR 0097：marker 命中后立即返回；根页面与详情使用有界查询、后台不可变快照、受控媒体缓存，
  Session 最近 10 条倒序分页，并保留 Release 真机性能预算作为后续量化边界。
- ADR 0098：ReAct deadline 与活动时间语义保持独立，设备设置冻结到本地与远程执行输入；统一值
  后续由 ADR 0104 修订为文字、图片、视频分别配置。

## 原始文件

- [PRD 043：可配置 ReAct 运行超时](prd/043-configurable-react-runtime-timeout.md)
- [ADR 0097：当前安装基线、性能预算与缓存失效](adr/0097-current-baseline-performance-budget-and-cache-invalidation.md)
- [ADR 0098：用户可配置 ReAct 活动执行超时](adr/0098-user-configurable-react-active-runtime-timeout.md)

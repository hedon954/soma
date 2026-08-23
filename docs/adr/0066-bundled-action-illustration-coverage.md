# ADR 0066：静默动作目录维持至少一百个专属动作图

- 状态：已采纳
- 日期：2026-08-13
- 维护者：Soma maintainers
- 部分替代：[ADR 0035](0035-silent-bundled-exercise-content-and-on-demand-images.md) 中常见动作专属图只覆盖精选小集合的边界
- 后续替代：[ADR 0094](0094-user-first-versioned-bundled-action-art.md) 把覆盖门槛提升到至少 239，并固定用户图、新版内置图与生成图的优先级
- 上游依据：[PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)

## 背景

目录已有两百余个动作，但只有约四十个专属动作图，常见动作大量落到中性占位。用户已有动作和
计划详情因此无法稳定获得动作示意，而运行时按需生成又会引入费用、延迟与不可控远程数据流。

## 决策

1. 继续遵守 ADR 0035 的静默 fill-only：只在用户动作被创建或匹配时关联内置内容，不把目录写入
   SwiftData，也不暴露为用户练过的事实。
2. 常见蹲、铰链、推、拉、手臂、核心与体能动作中，至少 100 个 canonicalName 显式映射专属图。
3. 沿用仓库已登记的 Free Exercise DB 公共领域资源；每个文件本地打包，运行时不联网取图。
4. 测试同时约束专属图条目数、canonicalName 唯一性和 Bundle 资源存在性。
5. 本次只从真机临时读取动作名称，核对的 24 个名称全部建立显式目录映射；其中侧桥、爆发式
   俯卧撑、单腿硬拉、单臂卧推、平板划船和负重蹲跳补入对应 Free Exercise DB 离线资源。
   长尾动作继续使用明确占位，不在运行时按模糊相似度套图或自动生成。

## 未选择的方案

- 不在运行时联网取图，不批量激活用户未练过的动作，也不使用模糊相似图替代专属映射。

## 结果

### 正向影响

- App 包体积增加，但动作图离线、确定且无运行时费用。
- 新增目录动作时不强制立刻配图；覆盖总数不能退回一百以下。

### 成本与限制

- 第三方来源与许可继续记录在 `ExerciseCatalog/THIRD_PARTY_NOTICES.md`。

## 验证

- `ExerciseLibraryTests` 验证专属图数量、canonicalName 唯一性、所有声明资源的 Bundle 可用性，
  以及本次真机动作名称集合均能解析到非空离线动作图。

## 参考

- [Free Exercise DB](https://github.com/yuhonas/free-exercise-db)
- [资源声明](../../Soma/Resources/ExerciseCatalog/THIRD_PARTY_NOTICES.md)

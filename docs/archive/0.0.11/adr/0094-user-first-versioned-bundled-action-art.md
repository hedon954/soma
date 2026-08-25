# ADR 0094：用户图优先与可升级的 239 张内置动作图

- 状态：已采纳
- 日期：2026-08-23
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的至少一百个专属动作图门槛，以及 generated/user 图共同阻止后续内置图关联的规则
- 上游依据：[PRD 042](../prd/042-user-controlled-recovery-message-feedback-and-action-art.md)

## 背景

动作目录升级能纠正素材和补齐覆盖，但旧实现按 `createdAt` 取最后一张图。较新的生成图可能永久
遮住新版内置图，较新的内置图也可能误盖用户上传图；来源所有权没有形成明确产品规则。

## 决策

1. 动作图显示优先级固定为 `user > bundled > generated > fallback`；同一来源内部才取最新时间。
2. 目录激活时始终维护一个当前 bundled 引用：删除同 kind 的旧 bundled 引用并添加当前资源。
   generated 和 user 引用都不删除。
3. 没有用户图时，新版 bundled 图立即成为展示图；存在用户图时，用户图继续最高优先，不受 App
   升级和创建时间影响。
4. 本次为既有 69 个空缺目录项补图，并新增 31 个常见目录项与图片，合计新增 100 个有图动作；
   全目录专属图不少于 239。
5. 五个指定名称通过 canonicalName 或显式 alias 解析，不靠运行时模糊匹配。
6. Free Exercise DB 素材随 App 离线打包并保留 Unlicense 声明；运行时不联网取图。

## 结果

- App 升级可以纠正自己管理的动作图，不会覆盖用户选择。
- 包体积增加约 5.3 MB；资源存在性、覆盖数、别名和优先级由测试固定。

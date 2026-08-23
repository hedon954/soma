# ADR 0035：内置动作内容保持静默，图片只在动作激活后关联并按需生成

- 状态：部分已替代；通用肌群图素材与按需生成范围由 ADR 0044 替代
- 日期：2026-07-31
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：
  - [ADR 0094](0094-user-first-versioned-bundled-action-art.md) 明确用户图最高、新版内置图在无用户图时高于生成图，并把门槛提升到 239
  - [ADR 0066](0066-bundled-action-illustration-coverage.md) 把常见动作专属图覆盖门禁提升到至少一百个，静默 fill-only 保持不变
  - [ADR 0044](0044-programmatic-muscle-map-and-training-share-poster.md) 将 `muscleMap`
    改为程序化受力图渲染，退役肌群位图与其 AI 按需生成入口；`actionIllustration`
    与静默目录决策继续有效
- 上游依据：[动作库、训练计划、带练与视频复盘调研](../research/2026-07-31-exercise-library-plans-guided-training.md)
- 下游落地：[训练领域模型与运行时协议](../engineering/training-domain-model.md)
- 关联：
  - [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
  - [ADR 0028](0028-semantic-exercise-identity.md)

## 背景

用户的个人动作库应在自然聊天和真实训练中逐步形成，但动作详情又需要动作示意图、通用肌群图
与基础教练说明。如果启动时把一套全球动作表写入 SwiftData，用户会看到大量从未练过的动作，
`list_exercise_names` 也会把它们错误地当成个人事实；如果完全不准备内容，首次创建常见动作后又
只能显示空白。

此外，任何有限目录都无法覆盖用户的全部动作、变式和个人命名，因此需要用户主动触发的图片
生成作为兜底。生成调用会产生远程数据流和费用，不能成为打开页面或记录训练的隐式副作用。

## 决策

1. App 包内维护一个只读、版本随 App 发布的 `BundledExerciseCatalog`。它可以包含标准名称、
   别名、基础教练提示、主要/辅助肌群、动作模式、动作示意图和通用前后肌群图。
2. 内置目录不是 `ExerciseDefinition` 的来源，也不是用户动作库。App 启动和升级只为已经存在的
   `ExerciseDefinition` 补充内容，绝不因为目录条目创建动作。
3. `list_exercise_names`、聊天候选、动作列表和搜索只读取当前数据空间中 active 的
   `ExerciseDefinition`；未使用的内置动作始终不可见，也不进入模型上下文。
4. Agent 仍按 ADR 0028 基于完整 `{id,name}` 列表进行语义归一。新动作创建或旧动作改名后，
   本地仅以规范名称或目录别名做确定性内容关联，不建立第二套动作身份判断。
5. 激活内置内容采用 fill-only：只填充空字段和缺失图片，不覆盖用户编辑的提示、肌群、动作模式
   或 generated/user 图片。内置图片标记为 `bundled`，目录升级时可以替换自己管理的旧 bundled
   引用，以纠正素材映射，但不冒充用户媒体或个人测量。
6. 动作图片以 `ExerciseImageReference` 保存，区分：
   - `actionIllustration`：动作姿势或器械示意；
   - `muscleMap`：通用前后人体主要/辅助肌群图；
   - `bundled`、`generated`、`user` 三种来源。
7. 动作列表左侧显示首张动作示意图；详情支持多张动作图和肌群图。目录未命中时先显示中性的
   人体占位，不用其他具体动作冒充当前动作。
8. 用户可以上传图片，也可以分别点击生成动作示意图或通用肌群图。生成不在页面打开、训练
   记录、计划就绪检查或带练启动时自动发生。
9. 图片生成使用当前标准 Provider 的独立可配置 image model；请求只包含动作标准名称、已经
   保存的通用肌群/动作模式和风格约束，不自动上传用户照片、视频、训练历史或身体数据。
10. 生成与上传图片保存到 `PrivateMedia`，进入备份、恢复、清除、导出引用和合并/撤销语义；
    包内资源不复制为个人文件，也不进入开放数据导出。
11. 公共素材必须有可审计授权。当前动作照片选自公共领域 Free Exercise DB，并在包内和仓库
    根目录保留来源声明；Soma 生成的人体示意图作为项目素材随包发布。

## 未选择的方案

- 启动时把全部内置动作写入个人动作库：把产品库存伪装成用户历史，并污染 Agent 名称列表。
- 让 `list_exercise_names` 同时返回内置目录：破坏“只返回用户已有动作”的 Tool 合同。
- 每次打开详情自动生成图片：产生不可预期的费用、网络依赖和隐私数据流。
- 用相似的其他动作图片永久兜底：视觉上可能比空白更误导。
- 从 Keep、YouTube 或其他课程平台抓取图片：授权与再分发边界不可控。

## 结果

### 正向影响

- 用户仍然只看到自己实际形成的动作库，常见动作首次出现后立即拥有可用内容。
- 包内素材离线可用，不消耗 token，也不会因服务不可用造成详情空白。
- 长尾动作可以由用户显式生成或上传，且来源、删除和备份行为可审查。
- 动作身份、内容模板和个人媒体各自有唯一职责，不会互相污染。

### 成本与限制

- 包体会随内置素材数量增大，图片需要统一压缩并在发布前审计授权。
- 目录别名只用于已有动作的内容关联，不保证覆盖全部个人命名；未命中时需要用户生成或上传。
- AI 生成图可能不准确，必须允许删除、替换，并明确肌群图只表示通用参与肌群。

## 验证

- 空数据库启动后 `ExerciseDefinition` 与 `list_exercise_names` 都为空。
- 创建一个已知动作后只激活该动作；目录中的其他动作仍不可见。
- 激活只补空字段，不覆盖用户编辑内容；目录升级只迁移旧 bundled 图片引用。
- 列表缩略图、动作图和前后肌群图均能从 App 包加载。
- 生成请求使用独立 image model；只有显式点击才发起，并把结果保存为本地引用。
- 动作合并/撤销、备份/恢复和个人数据清除覆盖 generated/user 图片引用与文件。
- `make verify` 通过，并在真机检查列表、详情、上传和生成入口。

## 参考

- [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
- [ADR 0028](0028-semantic-exercise-identity.md)
- [OpenAI Image generation guide](https://developers.openai.com/api/docs/guides/image-generation)
- [Free Exercise DB](https://github.com/yuhonas/free-exercise-db)

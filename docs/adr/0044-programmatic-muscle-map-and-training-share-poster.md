# ADR 0044：程序化肌群受力图与本地训练分享海报

- 状态：已采纳
- 日期：2026-08-04
- 维护者：Soma maintainers
- 部分替代：[ADR 0035](0035-silent-bundled-exercise-content-and-on-demand-images.md) 的通用肌群图素材与按需生成范围
- 后续替代：暂无
- 上游依据：无
- 关联：[PRD 019](../prd/019-training-review-plan-management-and-muscle-map-share.md)

## 背景

当前动作的通用肌群图（`muscleMap`）来自两条路径：包内少量静态位图
（`soma_muscle_*.png`，按动作模式粗分）和用户显式触发的 AI 图片生成。实践暴露三个问题：

1. AI 生成的肌群图在解剖准确性、构图和配色上不稳定，同一动作两次生成结果不同；
2. 位图按动作模式粗分，不能表达“主肌群深、次肌群浅”，更不能表达多动作叠加；
3. 训练分享、单动作受力图和整次训练受力汇总需要同一套可组合的渲染能力，位图和
   生成图都无法组合。

对同类产品与开源实现（react-body-highlighter、body-muscles、MuscleMapJS、MuscleMap 等）
的调研显示，行业通用做法一致：正/背面人体底图加逐块肌肉的独立矢量路径（语义 ID），
按输入的肌群强度对路径上色，强度映射为颜色深浅或透明度。

同时，`ExerciseDefinition.primaryMuscles/secondaryMuscles` 是用户可编辑的自由文本数组
（如“股四头肌”“三角肌前束”），渲染需要一个稳定的规范肌群键空间。

## 决策

1. 新增规范肌群枚举 `MuscleGroup`：约二十到三十块，每块声明正面或背面归属与显示名。
   它只是渲染与统计的键空间，不替代自由文本字段。
2. `primaryMuscles/secondaryMuscles` 保持用户可编辑的自由文本事实来源。渲染前经包内
   确定性映射表（中文规范名与常见别名 → `MuscleGroup`）转换；映射不到的条目保持
   不点亮，不做模糊猜测（missing-is-nil）。
3. 人体正/背面轮廓与逐块肌肉矢量路径作为包内只读静态数据随 App 发布，移植自 MIT
   许可的开源肌肉图 SVG 路径（`react-native-body-highlighter`），在包内与仓库保留
   来源与许可声明。路径数据不是个人媒体，不进入备份、导出或清除。
4. 渲染由 SwiftUI 程序化完成（`MuscleMapView`）：
   - 正/背面分卡并标注「正面」「背面」，一眼可辨；
   - 单动作：主肌群高强度、次肌群低强度；
   - 多动作叠加（整次训练、分享海报）：按各动作有效组数向所属肌群累加强度，再对
     全图归一化映射为透明度/深浅分档；
   - 主要肌群以固定槽位引线标签标出；点亮项加粗并用主题色，未点亮保持浅灰；
   - 配色遵循 App 主题（Soma tint），浅色/深色外观下都可辨认。
5. 替代范围：`muscleMap` 类图片不再提供 AI 按需生成入口，动作详情与列表的通用肌群图
   改用程序化渲染；包内 `soma_muscle_*.png` 位图退役。ADR 0035 的其余决策——静默内置
   目录、fill-only 激活、`actionIllustration` 的 bundled/generated/user 三来源与显式生成
   边界——继续有效。已存在的 generated/user `muscleMap` 图片引用保留可查看与删除，
   不做迁移或删除。
6. 训练分享海报在本机由 `ImageRenderer` 渲染 SwiftUI 视图生成图片，经系统分享面板
   分享；不引入任何服务器参与、分享链接或新增远程数据流。海报主区为左受力图、右统计，
   并含日期、计划名、动作明细与 Soma 标识；不包含照片、视频帧、位置、头像或训练天数。
7. 受力图语义是“通用肌群参与示意”，不表达个人生理测量、疲劳或恢复状态；UI 不展示
   内部强度数值。首版不拆比 `MuscleGroup` 更细的解剖分区（如上胸/中下胸）。

## 未选择的方案

- 继续用 AI 按需生成肌群图：结果不稳定、有网络与费用依赖、无法程序化叠加，正是
  本决策要解决的问题。
- 自绘整套解剖矢量素材：工期与解剖准确性成本高，开源 MIT 路径数据已满足需要。
- 照片级底图加混合模式高亮（js-rich-body-highlighter 风格）：素材授权复杂，与 Soma
  克制的视觉语言不符。
- 内嵌 WebView 复用 JS 开源库：违反原生优先边界，引入不必要的运行时。
- 把 `MuscleGroup` 枚举直接写入 `ExerciseDefinition` 替代自由文本：破坏用户编辑自由与
  模型语义归一（ADR 0028），且目录升级时旧数据迁移成本高。
- 服务器渲染分享图或生成分享链接：违反本地优先，且 PRD 未授权新增远程数据流。

## 结果

### 正向影响

- 每个动作与每次训练都能离线、零成本、确定性地获得风格统一的受力图。
- 主/次肌群与多动作叠加可表达深浅层次，支撑分享海报与后续趋势可视化复用同一组件。
- 移除一类 AI 图片生成入口，减少费用、隐私面与结果不可控性。

### 成本与限制

- 需要一次性移植并审校矢量路径与中文肌群映射表；映射表随用户词汇长期维护。
- 自由文本映射不到时该肌群不点亮，粒度受映射表覆盖率限制。
- 首版单一中性人体模型，不区分性别与体型。
- 包体增加少量路径数据（远小于被退役的位图）。

## 验证

- 中文肌群名与别名映射、主/次强度、多动作叠加归一有确定性单元测试。
- 任选两个映射肌群不同的动作，渲染点亮区域不同且深浅可区分；映射不到的名称不点亮。
- 动作详情不再出现“AI 生成肌群图”入口；既有 generated/user 肌群图仍可查看、删除。
- 分享海报在飞行模式可生成；图片中无照片、视频帧或位置信息。
- 浅色/深色外观、Dynamic Type 与 VoiceOver 标签在 iPhone 模拟器检查通过。
- `make verify` 通过。

## 参考

- [PRD 019](../prd/019-training-review-plan-management-and-muscle-map-share.md)
- [ADR 0028](0028-semantic-exercise-identity.md)
- [ADR 0035](0035-silent-bundled-exercise-content-and-on-demand-images.md)
- [react-native-body-highlighter（MIT）](https://github.com/HichamELBSI/react-native-body-highlighter)
- [react-muscle-highlighter（MIT，同源 SVG）](https://github.com/soroojshehryar/react-muscle-highlighter)
- [react-body-highlighter（MIT，早期多边形谱系）](https://github.com/giavinh79/react-body-highlighter)
- [body-highlighter（MIT）](https://github.com/lahaxearnaud/body-highlighter)
- [MuscleMap（MIT）](https://github.com/Jsplice/MuscleMap)

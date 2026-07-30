# Soma

> Your body, understood.

一个以多模态对话为唯一操作入口、无账户、本地优先的 iOS 私人 AI 健身教练。

## 运行

```bash
open Soma.xcodeproj
```

选择 `Soma` Scheme 和 iOS 17+ 模拟器即可运行。`project.yml` 是 Xcode 工程唯一事实来源，生成的 `Soma.xcodeproj` 不进入 Git；首次克隆后运行 `make setup`，后续修改工程配置时运行 `make generate`。首次启动会生成一组仅用于演示的本地记录和五张虚构图片，方便直接查看统计和完整交互。图片生成说明见 [内置演示图片](docs/demo-media-prompts.md)。

## 产品结构

App 只保留两个界面：

- **教练**：直接聊天、使用系统语音输入，或一次发送多张照片、多个视频及其混合附件。远程模式由受限的 [ReAct Agent](docs/react-agent.md) 查询本地上下文、调用记录工具并根据执行结果继续决策；Tool/Skill 事件在对应回复中实时显示并持久保留。无 API Key 时使用明确标注的本地演示分析器。
- **进展**：集中展示训练、饮食和身体记录列表、GitHub 风格连续性热力图，以及可左右拖动并切换周/双周/月/季的体重和训练容量趋势。结构化记录由聊天创建，历史列表支持进入即编辑、修改后保存和左滑删除。

没有训练、饮食、身体或器械的传统“新增表单”。多个健身房及当前健身房也通过自然语言和照片维护。

主屏幕可以添加中尺寸 **Soma 快速记录** Widget，也可以通过系统快捷指令直接开始文字、
拍照或照片/视频输入。系统入口只负责打开教练和对应选择器，不会绕过聊天直接写入记录。

## 数据与 AI

- SwiftData 保存健身房、器械、饮食、身体、训练和教练对话。
- 图片与视频保存在 App 的 Application Support 私有目录；设置可把饮食与训练导出为普通
  年/月/日文件夹，或把完整个人空间加密备份到用户选择的“文件”目录。
- 默认使用本地演示分析器，不发送任何数据。
- 启用远程模式后使用最多 8 轮的流式 ReAct 循环；模型通过 OpenAI-compatible 原生 `tool_calls` 调用预定义的本地查询、训练、饮食、身体和健身房工具；只有用户当前消息明确要求时才能删除指定业务记录，不能执行任意代码。
- Agent 只先获得 Skill 目录，再通过 `load_skill` 按需加载健身房分析、训练计划、动作、饮食、体态、趋势、训练量或运动热量估算说明。每次模型推理、Skill、工具调用和最终输出都会形成可审查的 Trace Span。
- 在 App 设置中选择 OpenAI、DeepSeek、阿里云百炼、火山引擎或腾讯云；切换平台后，只要本机已保存对应 API Key，就会立即读取该平台当前返回的可用模型并提供下拉选择，同时始终保留模型 ID 手动输入。
- App 会预先提示已知的不支持多模态模型；能力未标注时，则在图片或视频调用失败后展示平台返回的具体原因。
- 启用远程 AI 后，才会把用户在对话中主动发送的压缩图片或视频关键帧交给当前模型。
- API Key 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 存入 Keychain。

## 当前能力

- 发送健身房照片，自动建立或更新电子健身房；支持多个场馆，并可在聊天中切换当前场馆。
- 发送食物照片或自然语言描述，自动估算大卡与宏量营养并记录。
- 发送体型、体重秤照片或文字数据，自动提取并加入身体趋势。
- 用文字、图片或视频描述训练，自动记录动作、组次、重量与间歇；视频在设备端抽取关键帧用于动作和负荷反馈。
- 使用 iOS 系统语音识别把口述内容直接填入同一个教练输入框；支持设备时优先使用端侧识别。
- AI 教练结合当前健身房器械与个人历史，给出训练、恢复和饮食建议。
- 训练、饮食和体重均可进入完整历史列表；连续性热力图带月份、星期和强度图例。
- 每条训练、饮食和身体记录都能进入详情页，审查原始文字、图片、训练视频与 AI 反馈；健身房也有照片和器械解析详情。
- 体重趋势支持左右拖动历史窗口，并切换周、双周、月和季度粒度。
- 训练容量按有证据的 `组数 × 次数 × 重量` 聚合，支持相同时间粒度、左右拖动和可比周期变化。
- 训练、饮食、身体、健身房及器械解析结果都可以审查、修改与删除；缺失训练字段保持为空，不用经验值补齐。
- “数据与备份”支持可脱离 Soma 阅读的饮食/训练开放导出、进入后台时尽力更新的外部加密
  备份与恢复，以及不触碰系统相册、Apple 健康和外部备份的个人数据清除。
- 开发者设置允许自定义角色、安全策略和八项 Skills，并支持 Markdown 编辑与预览；工具清单和参数 Schema 由 App 通过 API 原生注册，不进入提示词且不允许覆盖。
- 执行日志按一条用户消息保存一条完整 Trace，区分成功和失败，并展示输入、结果或错误、模型 Token、相对耗时、Skill 与工具 Span。

完整的需求—证据矩阵与验收命令见 [验收清单](docs/acceptance.md)。

## 产品文档

- [PRD：产品需求与演进](docs/prd/README.md)
- [ADR：架构与交互决策](docs/adr/README.md)
- [Changelog：按阶段重建的迭代日志](docs/changelog/README.md)
- [工程与 GitHub 工作流](docs/engineering/README.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [Apache 2.0 许可证](LICENSE)

## 开发

```bash
make setup
make check
make verify

# 连接已开启开发者模式的 iPhone 后
DEVELOPMENT_TEAM=你的TeamID make install-device
```

`make check` 是本地、pre-commit 和日常 GitHub CI 使用的快速静态门禁，包含格式、lint、
仓库与隐私契约，不启动 Simulator。`make verify` 在此基础上增加无签名构建和模拟器单元
测试，供本地完整交付和 `v*` release tag 使用。项目的 coding agent 统一遵循
[CLAUDE.md](CLAUDE.md)，Codex 和 Cursor 通过同一组项目 Skills 获取日常 SOP。

## 真机与 TestFlight

项目占位 Bundle ID 为 `top.hedon.soma`，使用 Automatic Signing。模拟器无需开发者账号；真机与 TestFlight 必须在 Xcode 中登录真实 Apple Developer 账号，并选择自己的 Team。

连线安装使用 `make install-device`。选择 Team 后可以在 Xcode 中执行 Product → Archive，
或在终端执行：

```bash
DEVELOPMENT_TEAM=你的10位TeamID make archive
```

归档位于 `build/Soma.xcarchive`，App Store Connect 导出内容位于 `build/TestFlight`。上传前还需要在 App Store Connect 创建同 Bundle ID 的 App 记录。

> AI 反馈是一般性健身建议，不提供医疗诊断。

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

- **教练**：直接聊天、使用系统语音输入，或一次发送多张照片、多个视频及其混合附件。受限的 [ReAct Agent](docs/react-agent.md) 查询本地确定性上下文包、调用记录工具并根据执行结果继续决策；每次发送先进入持久 Job/Event，再由 UI、Trace、Live Activity 和通知分别投影。处理被中断后同一条回复气泡可从检查点续跑。模型服务不可用时消息不会被拒绝，而是本地暂存、恢复后按发送顺序自动继续。输入动作名称片段时，建议行一次给出「动作名 + 最近一次训练数据」，点一次即得到完整草稿。
- **进展**：集中展示训练、饮食和身体记录列表、GitHub 风格连续性热力图，以及可左右拖动并切换周/双周/月/季的体重和训练容量趋势。结构化记录由聊天创建，历史列表支持进入即编辑、修改后保存和左滑删除。

没有训练、饮食、身体或器械的传统“新增表单”。多个健身房及当前健身房也通过自然语言和照片维护。

主屏幕可以添加中尺寸 **Soma 快速记录** Widget，也可以通过系统快捷指令直接开始文字、
拍照或照片/视频输入。系统入口只负责打开教练和对应选择器，不会绕过聊天直接写入记录。

## 数据与 AI

- SwiftData 保存健身房、器械、饮食、身体、训练和教练对话。
- 图片与视频保存在 App 的 Application Support 私有目录；设置可把饮食与训练导出为普通
  年/月/日文件夹，或把完整个人空间加密备份到用户选择的“文件”目录。
- 聊天使用可配置步数上限（默认 100）的流式 ReAct 循环；模型通过 OpenAI-compatible 原生 `tool_calls` 调用预定义的本地查询、训练、饮食、身体和健身房工具；每轮按信号预选工具组并可并行返回调用，本机仍顺序执行与规范化幂等去重。只有用户当前消息明确要求时才能删除指定业务记录，不能执行任意代码。
- Agent 的 System 只获得 Skill 元数据目录；用户可预选快捷 Skill，使首轮直接注入完整指令、专属上下文和最小 Tool 集。未预选时仍可通过 `load_skill` 按需加载。每次模型推理、Skill、工具调用和最终输出都会形成可审查的 Trace Span。
- 在设置的「LLM 配置」中选择 OpenAI、DeepSeek、阿里云百炼、火山引擎、腾讯云、opencode 或其他 OpenAI-compatible 服务；每个平台的 Base URL 都可改写。模型是可自由输入的文本框，平台 `/models` 返回的列表以输入历史式建议出现在输入框下方。
- 模型服务缺凭据、被限流或返回服务端错误时，消息与媒体照常落盘并标记「已暂存」；保存 Key、切换平台、修改模型或回到前台后按先进先出自动补偿消费，同一回合的业务写入仍然只发生一次。暂存队列只保存在本机。
- 填好模型后会用一行说明该模型的多模态能力；已知不支持的模型在上传前阻止，未标注能力则在图片或视频调用失败后展示平台返回的具体原因。
- 只有用户主动发送时，才会把当前输入、同一 Session 最近十个来回，以及视觉额度内的压缩
  图片、视频或关键帧交给当前模型。
- API Key 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 存入 Keychain。
- “后台持续处理”默认关闭；用户明确开启后，可把当前文字、图片或视频关键帧与最小上下文
  投递给可选 [Soma Agent Server](Server/README.md)。服务器使用匿名设备身份和 Soma 管理的
  Provider 凭据，用户 BYOK、原始视频与完整身体数据库不上传。

## 当前能力

- 发送健身房照片，自动建立或更新电子健身房；支持多个场馆，并可在聊天中切换当前场馆。
- 发送食物照片或自然语言描述，自动估算大卡与宏量营养并记录。
- 发送体型、体重秤照片或文字数据，自动提取并加入身体趋势。
- 用文字、图片或视频描述训练，自动记录动作、组次、重量与间歇；视频在设备端抽取关键帧用于动作和负荷反馈。
- 训练动作使用稳定 ID 形成个人动作库；支持改名、归档、合并、撤销、统一历史、容量趋势、
  多段个人示范与可编辑动作说明。
- 包内静默准备常见动作说明、动作示意图和前后人体肌群图；只有用户实际形成的动作才显示对应
  素材，长尾动作可由用户上传或显式调用 AI 图片生成兜底。
- 训练计划使用不可变模板版本；既可由聊天生成，也可在 GUI 中选择、排序动作并配置处方，随后
  启动离线可用的逐组带练。
- 带练支持暂停、恢复、跳过、实际值确认和持久休息计时；可显式开启前置摄像头，为每个动作
  自动录制一组，麦克风默认关闭。
- 训练完成先生成本地确定性总结；计划优化、动作内容和视频复盘只在用户主动点击后调用 AI，
  复盘结果保留证据、局限和可编辑建议。
- 使用 iOS 系统语音识别把口述内容直接填入同一个教练输入框；支持设备时优先使用端侧识别。
- AI 教练结合当前健身房器械与个人历史，给出训练、恢复和饮食建议。
- 模型服务失效时训练现场仍可连续记录：消息标记「已暂存」，输入区显示暂存条数与配置入口，
  恢复后按发送顺序自动继续，不需要逐条重试。
- 训练、饮食和体重均可进入完整历史列表；连续性热力图带月份、星期和强度图例。
- 每条训练、饮食和身体记录都能进入详情页，审查原始文字、图片、训练视频与 AI 反馈；健身房也有照片和器械解析详情。
- 体重趋势支持左右拖动历史窗口，并切换周、双周、月和季度粒度。
- 训练容量按有证据的 `组数 × 次数 × 重量` 聚合，支持相同时间粒度、左右拖动和可比周期变化。
- 训练、饮食、身体、健身房及器械解析结果都可以审查、修改与删除；缺失训练字段保持为空，不用经验值补齐。
- “数据与备份”支持可脱离 Soma 阅读的饮食/训练开放导出、进入后台时尽力更新的外部加密
  备份与恢复，以及不触碰系统相册、Apple 健康和外部备份的个人数据清除。
- 开发者设置允许编辑 Agent 人格、管理内置 override 与自定义 Skill、配置权限白名单和快捷按钮；固定安全契约只读。工具清单和参数 Schema 由 App 通过 API 原生注册，不进入提示词且不允许覆盖。
- 执行日志按一次 Agent Attempt 保存一条完整 Trace，区分成功和失败，并展示输入、结果或错误、模型 Token、相对耗时、Skill 与工具 Span。

完整的需求—证据矩阵与验收命令见 [验收清单](docs/acceptance.md)。

## 产品文档

- [PRD：产品需求与演进](docs/prd/README.md)
- [ADR：架构与交互决策](docs/adr/README.md)
- [关键 Bug：根因复盘与回归门禁](docs/bugs/README.md)
- [Research：产品与技术证据](docs/research/README.md)
- [Changelog：按阶段重建的迭代日志](docs/changelog/README.md)
- [工程与 GitHub 工作流](docs/engineering/README.md)
- [可选 Agent Server 部署与运维](Server/README.md)
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

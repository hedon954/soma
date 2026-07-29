# Changelog

Soma 使用 [Semantic Versioning](https://semver.org/)。这里只记录可发布、用户可感知的
版本变化；详细产品演进见 `docs/changelog/`。

## [Unreleased]

### Planned

- 在真实设备完成 HealthKit、语音、照片、视频和 TestFlight 签名验收。

## [1.0.0] - 2026-07-29

### Added

- 以文字、图片、视频和系统语音为统一入口的私人 AI 健身教练。
- 多健身房与当前场馆管理，支持环境照片、器械识别和审查。
- 训练、饮食、体重与体态记录，保留原始媒体并支持编辑和删除。
- GitHub 风格训练连续性，以及可拖动的体重与训练容量趋势。
- OpenAI、DeepSeek、阿里云百炼、火山引擎和腾讯云配置与动态模型列表。
- 原生流式 ReAct Tool Calling、渐进式 Skills 和完整 Trace/Span 执行日志。
- 身体信息、本地 MET 运动热量估算和 Apple 健康增量导入。
- 完全隔离的演示与个人数据空间。

### Privacy

- 无账户、无 CloudKit；数据库和媒体保存在 App 沙盒。
- API Key 使用 ThisDeviceOnly Keychain。
- 用户未明确提供的数据保持为空，远程 AI 默认关闭。

### Known limitations

- App 被系统终止后，在途 Agent 不保证继续执行。
- Keep 与 COROS 当前只在数据写入 Apple 健康后间接导入。
- TestFlight 需要维护者自己的 Apple Developer Team 与签名资产。

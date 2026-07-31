# Security Policy

## Supported version

当前只维护 `main` 和最新 GitHub Release 对应的版本。

## Reporting a vulnerability

请不要用公开 Issue 报告以下问题：

- API Key、Keychain、签名或凭据泄漏；
- 沙盒、媒体或健康数据越权访问；
- Agent Tool 越权、提示词覆盖系统 Tool Schema 或任意代码执行；
- Trace、日志或外部同步暴露个人数据；
- 匿名设备鉴权绕过、签名重放、跨设备读取 Agent Job 或伪造 Tool Result；
- 远程 Job/Event、临时媒体、APNs 或 ActivityKit token 越权访问或超期保留；
- 可导致记录错误合并、跨数据空间读取或重复导入的漏洞。

优先使用 GitHub 仓库 **Security → Report a vulnerability** 的私密报告入口。若仓库尚未
启用 Private Vulnerability Reporting，请通过维护者 GitHub 主页上的私密联系方式联系，
不要附真实用户数据，只提供最小虚构复现。

报告应包含受影响版本、攻击前提、影响、最小复现和建议修复方向。维护者会先确认收到，
在完成影响评估和修复方案前不会要求公开披露。

## Sensitive test data

安全复现不得包含真实身体照片、健康记录、生产 API Key、证书、Provisioning Profile、
App Store Connect 凭据或完整用户 Trace。请使用虚构媒体和替代 token。

## Remote execution security gates

[PRD 011](docs/prd/011-durable-agent-jobs-remote-continuity.md) 的远程执行尚未实现。进入生产前
至少满足：

- 每次安装使用独立匿名设备签名密钥；服务端 challenge、短期 token、nonce 和 body digest
  防止重放；
- 每个 Job、Event、upload、Tool Result 和 push token 都按 device 授权，禁止仅凭可猜 ID
  访问；
- 用户自带 Provider API Key 不上传服务器；Soma 管理凭据只进入 secret manager；
- 服务器普通日志不得包含用户原文、健康上下文、Tool 参数/结果、媒体 URL 或 push token；
- 上传限制大小、类型、digest、短期签名和归属，不允许按用户 URL 进行服务器抓取；
- 本地 Tool 名称和 Schema 由 App 固定，服务器不能新增任意代码或绕过 SwiftData 数据空间；
- 内容终态确认后 24 小时内删除、7 天硬过期，非内容元数据最多 30 天；
- App Attest、配额、滥用检测、密钥轮换、APNs 凭据和对象存储清理有独立测试与告警；
- 远程服务失陷时，本地业务数据库、ThisDeviceOnly Keychain 和未上传媒体仍不可被直接读取。

# Security Policy

## Supported version

当前只维护 `main` 和最新 GitHub Release 对应的版本。

## Reporting a vulnerability

请不要用公开 Issue 报告以下问题：

- API Key、Keychain、签名或凭据泄漏；
- 沙盒、媒体或健康数据越权访问；
- Agent Tool 越权、提示词覆盖系统 Tool Schema 或任意代码执行；
- Trace、日志或外部同步暴露个人数据；
- 可导致记录错误合并、跨数据空间读取或重复导入的漏洞。

优先使用 GitHub 仓库 **Security → Report a vulnerability** 的私密报告入口。若仓库尚未
启用 Private Vulnerability Reporting，请通过维护者 GitHub 主页上的私密联系方式联系，
不要附真实用户数据，只提供最小虚构复现。

报告应包含受影响版本、攻击前提、影响、最小复现和建议修复方向。维护者会先确认收到，
在完成影响评估和修复方案前不会要求公开披露。

## Sensitive test data

安全复现不得包含真实身体照片、健康记录、生产 API Key、证书、Provisioning Profile、
App Store Connect 凭据或完整用户 Trace。请使用虚构媒体和替代 token。

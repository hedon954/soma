# GitHub 仓库设置

文件进入 GitHub 后，还需要在仓库 Settings 完成以下一次性设置。它们无法仅靠提交文件
可靠启用。

## General

- Default branch：`main`
- 合并策略：保留 Squash merge，关闭不需要的 merge commit/rebase merge
- 自动删除已合并分支
- 启用 Issues

## Branch protection / ruleset

为 `main` 建立 ruleset：

- Require a pull request before merging
- Require status checks to pass
- 必需检查：`Build, test, and quality gates`
- Require branches to be up to date before merging
- Require conversation resolution
- Block force pushes and branch deletion

个人仓库可以先不要求审批人数，但不要允许绕过失败的 CI。

## Actions

- Workflow permissions 默认设为 **Read repository contents**
- 只让 `release.yml` 通过文件内 `contents: write` 创建 Release
- 不在 Actions secrets 中保存 LLM API Key 或真实健康数据
- 当前 GitHub workflow 不保存 Apple 签名资产；TestFlight 从受控本机归档

## Security

- 启用 Dependency graph
- 启用 Dependabot alerts、security updates 和 version updates
- 如果仓库公开，启用 Code scanning；`security.yml` 会运行 Swift CodeQL
- 启用 Secret scanning 与 Push protection（仓库计划支持时）
- 启用 Private Vulnerability Reporting

私有个人仓库没有 GitHub Advanced Security 时，Dependency Review/CodeQL job 会跳过，
本地 `make check` 静态门禁和 CI 的 `make verify` 构建、测试门禁仍然执行。

## Labels

建议至少建立：

- `bug`
- `enhancement`
- `privacy`
- `agent`
- `data`
- `ui`
- `dependencies`
- `ci`

Issue 模板已经禁止上传真实身体照片、健康记录和密钥。

# ADR 0021：分离开放导出、加密备份与个人数据清除

- 状态：已采纳
- 日期：2026-07-30
- 关联：[PRD 007](../prd/007-data-export-backup-and-erasure.md)

## 背景

Soma 的 SwiftData 数据库和 `PrivateMedia` 默认位于 App 沙盒。卸载会移除沙盒，而当前
Personal Team 无法依赖需要付费计划的 iCloud capability。用户既需要离开 Soma 后仍能
阅读自己的记录，也需要在设备损坏、卸载或重装后完整恢复；这两种用途对格式、隐私和兼容性
的要求不同。

直接复制 SwiftData SQLite 文件会同时受到 WAL 一致性、容器路径、schema 迁移和运行中
写入影响，也无法形成长期可读格式。把明文导出当成自动备份则会持续在外部目录暴露精确位置、
健康文字和身体媒体。

## 决策

1. **开放导出与恢复备份使用两种格式。**
   - 导出是明文、人类可读、按本地 `年/月/日` 分层的饮食与训练资料；
   - 备份是机器可恢复、全个人空间、版本化的逻辑快照。
2. 导出目录先写入同级临时目录，manifest、文字、JSON 和媒体全部完成后再改名为最终目录。
   单个源媒体缺失属于可报告降级，目标目录写入失败属于整次失败。
3. 备份不复制 SwiftData 数据库文件，而是把每种模型显式映射为 Codable DTO。恢复时先
   解码和验证，再在一个 SwiftData transaction 中替换个人空间。
4. 备份根目录包含不含个人数据的明文 `header.json`，记录格式版本、生成时间、KDF 参数和
   随机 salt；`snapshot.json.enc` 与每个媒体文件分别使用 AES-256-GCM 加密。
5. 用户密码通过 PBKDF2-HMAC-SHA256 派生 256-bit 密钥。首次配置后仅把派生密钥放入
   `WhenUnlockedThisDeviceOnly` Keychain，用于后台自动备份；明文密码不持久化。
6. 每份备份写入新的带时间戳 `.somabackup` 目录。只有所有密文和校验通过后才写完成标志；
   自动备份保留最近两份完整快照，未完成目录可以安全忽略。
7. 外部目录由系统 document picker 选择。iOS 将选择结果作为 security-scoped URL 交给
   App；Soma 保存其 bookmark，在每次访问时解析、调用
   `startAccessingSecurityScopedResource()`，完成后成对释放。
8. App 进入 SwiftUI `ScenePhase.background` 时触发尽力而为的自动备份，并使用有限的系统
   background task 完成正在写入的本地文件操作。系统可能随时终止 App，所以备份协议不依赖
   后台任务必然完成；个人快照指纹没有变化时跳过重复媒体写入。
9. 恢复采用替换语义：
   - 完整验证 header、密码、snapshot、媒体数量和 SHA-256；
   - 将媒体写入新的随机沙盒路径并建立旧路径到新路径映射；
   - transaction 内删除个人模型并插入恢复模型；
   - 成功后再回收旧个人媒体，失败则回收新媒体并保留当前数据。
10. 清除和恢复回收媒体前，分别收集个人与演示空间所有媒体引用，只删除不再被任何保留空间
    引用的 `PrivateMedia` 文件。
11. 清除个人数据时同时删除备份目录 bookmark 与本机派生密钥，但不触碰外部备份。API Key
    使用独立 Keychain account，继续保留。

## 未选择的方案

- **只提供手动备份**：用户通常不会形成备份习惯，无法覆盖意外卸载和设备故障。
- **只提供明文导出**：适合长期持有，不适合自动、高频保存完整位置、聊天和身体媒体。
- **只提供系统设备备份**：恢复粒度、可见性和跨安装路径由系统控制，无法满足离开 App 后
  持有开放资料。
- **复制 SQLite/WAL**：难以保证运行时一致和跨 schema 恢复，也会绑定内部实现。
- **CloudKit/iCloud 容器**：当前签名团队不可用，并会引入新的云端数据流和 capability。
- **固定全局加密密钥**：卸载后无法恢复或所有用户共享同一秘密，均不可接受。
- **清除时同步删除外部备份**：扩大 destructive action，且违背保留离线恢复点的目的。

## 结果

### 正向影响

- 用户离开 Soma 后仍拥有普通文件，不被专有数据库格式锁定。
- 自动备份不依赖账户或付费 Apple capability，且外部明文暴露面小。
- 每个模型和媒体引用显式版本化，恢复行为可测试、可迁移。
- 清除、恢复和演示空间共用媒体保留规则，不会由不同 View 复制删除逻辑。

### 成本与限制

- 完整逻辑快照会重复写入媒体，备份时间与空间随资料增长。
- iOS 后台执行和第三方文件 Provider 不保证成功，只能尽力备份并保留上次状态。
- 用户忘记密码时 Soma 无法解密备份；更换备份密码需要创建新快照。
- 新增或改变持久模型字段时，必须同步更新 DTO、schema 版本、迁移和恢复测试。

## 验证

- 单元测试覆盖年月日路径、可读 JSON、媒体顺序、KDF 稳定向量、AES-GCM 篡改失败、DTO
  round trip、错误密码、备份完成标志、恢复原子性和跨数据空间媒体回收。
- `make verify` 通过。
- 真机在本机“文件”和至少一个启用的文件 Provider 验证目录授权、重新启动后的 bookmark、
  后台备份、卸载重装恢复与清除。

## 参考

- [Apple ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)
- [Apple AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Apple Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Apple Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers/)
- [PRD 007](../prd/007-data-export-backup-and-erasure.md)

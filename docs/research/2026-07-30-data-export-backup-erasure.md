# 数据导出、备份恢复与清除技术调研

- 日期：2026-07-30
- 结论：开放导出与加密逻辑备份分离；外部目录由系统授权；备份使用可中断的版本化快照；
  清除与恢复共用跨数据空间媒体引用回收规则。

## 当前数据事实

Soma 使用两个独立 SwiftData `ModelContainer`：默认配置承载演示空间，
`PersonalData` 承载个人空间，均关闭 CloudKit。个人空间包含资料、健身房、身体、饮食、
训练、Session、聊天、Trace、Agent 幂等回执和外部同步游标。

媒体不在 SwiftData 内。图片会归一化为最长边 1600 的 JPEG，视频复制原文件，两者都存入
`Library/Application Support/PrivateMedia`，模型只保存相对路径。演示和个人数据库逻辑隔离，
但物理上共用该目录。因此数据库删除不能直接等价为文件删除，必须先计算两个空间的引用集合。

## 为什么导出不是备份

开放导出的消费者是用户和其他工具，需要稳定目录、普通文字、JSON 与原媒体副本；它应该
尽量少包含内部实现。备份的消费者是 Soma，需要完整保留所有模型字段、ID、原始二进制
Data、幂等状态和媒体引用；它应该优先完整性、认证加密和 schema 迁移。

强行统一格式会得到两种坏结果之一：要么导出暴露大量内部 Trace 且难以阅读，要么备份丢失
恢复所需状态。当前采用两套明确版本的格式，共享底层媒体枚举与校验能力。

## 系统文件访问

`UIDocumentPickerViewController`/SwiftUI file importer 可以让用户选择文件或文件夹，并返回
安全作用域 URL。iOS 的 bookmark 默认可以包含由系统交互授予的隐式安全作用域；保存 bookmark
后，后续启动解析 URL，访问前调用 `startAccessingSecurityScopedResource()`，结束后调用
`stopAccessingSecurityScopedResource()`。

文件 Provider 可能离线、拒绝写入或在后台不可用。实现不能把目标路径字符串当成永久权限，
也不能覆盖唯一旧备份。导出和备份均写临时/新目录，完成后才发布结果。

## 后台自动备份

Apple 明确说明进入 `ScenePhase.background` 后应预期 App 很快终止。它适合作为“开始一次
尽力备份”的信号，不是可靠调度器。Soma 使用系统有限 background task 保护已启动的文件
操作，并通过以下协议承受任意中断：

1. 新建唯一 `.partial` 目录；
2. 写 header、加密 snapshot 和逐个加密媒体；
3. 校验预期数量；
4. 最后写 `complete.json`；
5. 只有完整快照参与恢复和历史轮换。

进入后台前对去除生成时间、按稳定 ID 排序的逻辑快照计算 SHA-256；指纹未变化时不重复写
媒体。媒体文件采用不可变 UUID 路径，因此逻辑路径未变化也代表内容未被原位替换。

没有账户或常驻服务时，iOS 也不会允许 App 在卸载前拦截系统删除确认框。自动备份只能降低
风险，不能承诺每次数据变化都已经离开沙盒；设置页必须展示最后成功时间。

## 加密与密钥

CryptoKit 的 AES-GCM 同时提供机密性和认证标签，密文或附加数据被修改时解密失败。备份为
每个文件生成独立 nonce，避免把所有视频一次加载到内存，也把损坏定位到单个对象。

密码不能直接作为 AES key。采用带随机 salt 和可版本化迭代次数的
PBKDF2-HMAC-SHA256 派生 256-bit key。salt 和参数不需要保密，存入 header；密码和派生 key
不能进入备份。为自动备份缓存的派生 key 使用 `WhenUnlockedThisDeviceOnly` Keychain；
重装后用户通过 header 参数和原密码重新派生。

## 逻辑快照与恢复

SwiftData store 正在运行时可能还有 WAL，直接复制并不等价于一致备份，也把恢复绑定到文件
路径和当前 schema。逻辑快照为每种 `@Model` 定义 Codable DTO，保留稳定 ID、时间、
raw enum、可选值和 Data。媒体在 snapshot 中仍引用备份前的逻辑路径，恢复复制成功后统一
映射到新的随机 `PrivateMedia` 路径。

恢复先在数据库外完成解密、JSON 解码、媒体哈希验证和临时写入。只有这些步骤都成功，才在
`ModelContext.transaction` 中替换个人模型。提交成功后再删除不再被个人或演示空间引用的
旧媒体；数据库失败时删除新媒体并保留原数据。

## 清除边界

主动清除不是“恢复出厂设置”：它删除个人业务空间和专属媒体，但保留 App、演示空间、AI
Provider/API Key、系统相册和 Apple 健康源样本。外部导出与备份也不在 App 沙盒，默认保留。

清除后如果仍保留自动备份 bookmark，下一次后台可能生成空快照并轮换掉最后有效备份。因此
清除必须同时断开自动备份并删除本机派生 key，但不能删除外部备份目录。

## 参考

- [Apple ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)
- [Apple ScenePhase.background](https://developer.apple.com/documentation/swiftui/scenephase/background)
- [Apple AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Apple AES.GCM.SealedBox](https://developer.apple.com/documentation/cryptokit/aes/gcm/sealedbox)
- [Apple Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Apple fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(isPresented:allowedContentTypes:onCompletion:))
- [Apple Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers/)

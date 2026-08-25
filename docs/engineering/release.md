# 版本、GitHub Release 与 TestFlight

Soma 将源码发布和 iOS 分发分开处理。

## 连线真机安装

免费 Personal Team 或付费 Developer Team 都可以完成本机连线安装。先在 Xcode 登录 Apple
ID，连接已信任且开启开发者模式的 iPhone，然后运行：

```bash
DEVELOPMENT_TEAM=你的TeamID make install-device
```

可以用 `SOMA_DEVICE_ID=设备UDID` 指定设备；未指定时脚本选择第一个可用的物理 iPhone。
脚本为 Soma App 和 Widget Extension 使用同一个 Team 自动签名，安装后直接启动 Soma。
如果安装时设备处于锁屏状态，安装仍视为成功；解锁 iPhone 后手动打开 Soma 即可。
同一 Bundle ID 的覆盖安装保留 App 沙盒数据。Personal Team 的签名会定期过期，需要重新
连线安装。

Release 真机安装成功后会写入可复用的产品指纹。性能录制使用
[一次安装、多次复用的真机协议](device-performance-profiling.md)，不会在每次 Trace 前重新构建或安装。

## GitHub Release

1. 在 `project.yml` 更新 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
2. 在根 `CHANGELOG.md` 建立相同版本的用户可感知说明。
3. 运行：

   ```bash
   make verify
   ./scripts/verify-release.sh v1.0.0
   ```

4. 提交 release metadata。
5. 创建 annotated tag：

   ```bash
   git tag -a v1.0.0 -m "Soma v1.0.0

   完成聊天驱动的私人训练、饮食、身体与趋势闭环。

   完整变更见 CHANGELOG.md。"
   ```

6. 推送 commit 和 tag。`release.yml` 会先验证 tag、版本和 Changelog，再运行包含构建和
   模拟器测试的完整质量门禁，并使用对应 Changelog section 创建 GitHub Release；公开仓库
   同时由 `security.yml` 执行 Swift CodeQL。

GitHub Release 不附未签名 IPA。

## TestFlight

本机 Xcode 登录真实 Apple Developer Team 后：

```bash
DEVELOPMENT_TEAM=你的10位TeamID make archive
```

脚本会：

1. 从 `project.yml` 生成工程；
2. 使用 Automatic Signing 创建 `build/Soma.xcarchive`；
3. 使用 `ExportOptions.plist` 导出到 `build/TestFlight`。

在 Xcode Organizer 验证 archive 后，通过受控的 App Store Connect 流程上传。

## 禁止进入 GitHub 的内容

- `.p12`、`.p8`、`.cer`、`.mobileprovision` 和私钥；
- App Store Connect API Key；
- Apple ID 密码或 session；
- 生产 LLM API Key；
- 真实身体媒体、健康记录和私有 Trace；
- xcarchive、IPA、DerivedData 和导出日志。

如果未来需要 GitHub Actions 自动上传 TestFlight，必须先新增 ADR，定义最小权限、
密钥轮换、证书生命周期、环境保护和审计策略。

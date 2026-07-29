# 版本、GitHub Release 与 TestFlight

Soma 将源码发布和 iOS 分发分开处理。

## GitHub Release

1. 在 `project.yml` 更新 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
2. 在根 `CHANGELOG.md` 建立相同版本的用户可感知说明。
3. 运行：

   ```bash
   make check
   ./scripts/verify-release.sh v1.0.0
   ```

4. 提交 release metadata。
5. 创建 annotated tag：

   ```bash
   git tag -a v1.0.0 -m "Soma v1.0.0

   完成聊天驱动的私人训练、饮食、身体与趋势闭环。

   完整变更见 CHANGELOG.md。"
   ```

6. 推送 commit 和 tag。`release.yml` 会重新运行质量门禁，并使用对应 Changelog
   section 创建 GitHub Release。

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

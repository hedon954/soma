# 个人设备 QQ 邮箱反馈配置

本指南只适用于 Soma 仍由维护者本人安装使用的阶段。QQ 邮箱地址和 SMTP 授权码会随个人
安装包携带，不得用于 TestFlight、App Store、Ad Hoc 分发或交给其他用户。

## 获取两个配置值

1. 登录 [QQ 邮箱网页版](https://wx.mail.qq.com/)。
2. 打开“设置 → 账号”。
3. 找到“POP3/IMAP/SMTP/Exchange/CardDAV/CalDAV 服务”，开启 IMAP/SMTP 或 POP3/SMTP。
4. 按页面要求完成安全验证并生成授权码。这个授权码不是 QQ 登录密码。

对应到配置文件：

- `SenderAddress`：完整 QQ 邮箱地址，例如 `123456@qq.com`；
- `SMTPAuthorizationCode`：开启 SMTP 时生成的授权码。

QQ 邮箱官方帮助说明客户端服务默认关闭，需要在“设置 → 账号”中开启：
[POP/IMAP 和 Exchange 服务的设置方法](https://service.mail.qq.com/detail/119/141)。

## 本机配置

本地文件已经建立在：

```text
Soma/Resources/FeedbackCredentials.plist
```

填写两个值后重新生成工程并安装：

```bash
DEVELOPMENT_TEAM=6C6NQVDA4M make install-device
```

该文件已被 Git 忽略。不要把真实邮箱授权码粘贴到源码、Issue、PR、日志或文档。App 会通过
`smtp.qq.com:465` 的 TLS SMTP 连接，从该 QQ 邮箱发送到代码中固定的
`hedonwang@gmail.com`。

使用虚构文字和演示媒体发送一次反馈，确认 QQ 邮箱“已发送”和 Gmail 收件箱都出现邮件。

## 对外开放前

```bash
make online-check
```

当前个人直连实现下，这条命令应当失败并阻止 TestFlight 归档。对外开放前必须迁移到认证的
服务端或 Serverless 函数，从 App 删除凭据并轮换 SMTP 授权码。

# ADR 0124：反馈 SMTP 失败分类与 IPv4 优先

- 状态：已采纳
- 日期：2026-09-07
- 维护者：Soma maintainers
- 上游依据：[PRD 058](../prd/058-feedback-duration-and-editable-calories.md)
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 第 25 条仅补充「失败一律暂时无法发送」的呈现；仍使用本机 QQ SMTP，不改收件人
- 后续替代：暂无

## 背景

本机 `FeedbackCredentials.plist` 有效，Mac 上 `smtp.qq.com:465` AUTH LOGIN 成功，但真机 5G
发送失败。失败被收成一句「反馈暂时无法发送」，无法判断是凭据、授权还是蜂窝拦截 SMTP。

## 决策

- 缺少或占位凭据报配置缺失；SMTP 535/534/530 报授权失效；连接失败或 4xx 报网络不可用，并提示
  蜂窝常拦截 SMTP、请改用 Wi-Fi。
- 投递先解析 IPv4 再回退主机名；连 IP 时仍用 `smtp.qq.com` 做 TLS 主机名校验。AUTH LOGIN
  失败后再试 AUTH PLAIN。
- 回复解析必须等到 `code ` 终止行，兼容 `\n` 与 `\r\n`。
- 不实现 STARTTLS 587：Network.framework 升级 TLS 成本高，且运营商也可能拦截 587。

## 未选择的方案

- 继续只报「稍后重试」：无法指导维护者换网或更新授权码。
- 引入服务端代发：超出个人阶段范围，且 `make online-check` 仍禁止外发凭据。

## 结果

### 正向影响

- 失败能区分配置、授权和网络，蜂窝拦截时可改用 Wi-Fi，不再只看到「稍后重试」。

### 成本与限制

- 仍走本机 QQ SMTP 465；部分蜂窝网络会继续拦截，不提供 587 回退。

## 验证

`FeedbackSubmissionTests` 覆盖凭据占位与 SMTP 终止行。真机在 Wi-Fi 与 5G 各发一次虚构反馈。

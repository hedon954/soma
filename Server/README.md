# Soma Agent Server

`Server/` 是 Soma 可选“后台持续处理”的参考服务端。它只保存短期 Agent Job、Event、设备
Tool handoff、临时媒体和系统活动 token，不是训练、饮食、身体、健身房或聊天的云端主库。

## 进程与依赖

- `src/main.ts`：HTTPS 入口后的 HTTP/SSE API；
- `src/worker-main.ts`：Agent Worker、事务 Outbox、APNs 投影和数据清理；
- PostgreSQL：Job、Event、Tool Request、幂等键和 Outbox 的唯一事实来源；
- S3-compatible 对象存储：用户明确选择的图片或视频关键帧；
- OpenAI-compatible Provider：只使用 Soma 管理的凭据；
- App Attest verifier：生产注册的独立验证适配器。

API 与 Worker 必须共享 PostgreSQL、对象存储、token 加密密钥和协议版本。可以横向启动多个
Worker；数据库租约、epoch、唯一约束和 `FOR UPDATE SKIP LOCKED` 负责收敛并发。

## 本地验证

```bash
npm ci
npm run check
npm test
```

真实 PostgreSQL 集成测试需要一个专用空数据库；测试会自行执行
`migrations/001_initial.sql`：

```bash
SOMA_TEST_DATABASE_URL=postgresql://localhost/soma_test npm run test:postgres
```

不要把该变量指向包含其他数据的数据库。仓库根目录的 `make check` 会执行 TypeScript
类型检查，`make verify` 还会执行服务器单元测试、iOS 构建与模拟器测试。

## 部署

1. 复制 `.env.example` 的变量到部署平台的 secret/config 管理，不创建可提交的 `.env`。
2. 在空 PostgreSQL 数据库执行：

   ```bash
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial.sql
   ```

3. 构建 TypeScript：

   ```bash
   npm ci
   npm run build
   ```

4. 分别启动 API 和 Worker：

   ```bash
   npm start
   npm run worker
   ```

5. TLS 在受信任的反向代理或平台入口终止；iOS Release 只接受 HTTPS 服务地址。
6. 为对象存储配置生命周期规则作为第二道删除保护。应用层仍会主动删除已消费终态内容、
   过期 Job 和撤销设备的对象。

生产环境必须启用受信任 CA 的 PostgreSQL TLS。API 和 Worker 都会在
`NODE_ENV=production` 时验证服务器证书。

## 配置

| 变量 | 进程 | 用途 |
| --- | --- | --- |
| `DATABASE_URL` | API/Worker | PostgreSQL 连接 |
| `PORT` | API | HTTP 监听端口，默认 `8080` |
| `SOMA_TOKEN_SECRET` | API | 签发匿名设备短期 token，至少 32 字符 |
| `SOMA_TOKEN_ENCRYPTION_KEY` | API/Worker | 加密 ActivityKit token 的 32-byte Base64 key |
| `SOMA_APP_ATTEST_VERIFIER_URL` | API production | App Attest 验证服务 |
| `SOMA_APP_ATTEST_VERIFIER_TOKEN` | API production | 验证服务的 server-to-server secret |
| `SOMA_OBJECT_BUCKET` | API/Worker | 临时对象 bucket |
| `SOMA_OBJECT_REGION` | API/Worker | 对象存储 region |
| `SOMA_OBJECT_ENDPOINT` | API/Worker | 可选 S3-compatible endpoint |
| `SOMA_PROVIDER_BASE_URL` | Worker | Soma 管理 Provider 的 OpenAI-compatible Base URL |
| `SOMA_PROVIDER_API_KEY` | Worker | Soma 管理 Provider 凭据 |
| `SOMA_PROVIDER_MODEL` | Worker | 远程 Agent 模型 |
| `SOMA_APNS_TEAM_ID` | Worker | Apple Team ID |
| `SOMA_APNS_KEY_ID` | Worker | APNs key ID |
| `SOMA_APNS_PRIVATE_KEY` | Worker | APNs `.p8` 内容；不得写入文件或日志 |
| `SOMA_BUNDLE_ID` | Worker | App Bundle ID，默认 `top.hedon.soma` |

没有 APNs 私钥时 Worker 使用 No-op Provider；Job 仍执行，系统活动由 App 下次同步纠正。
生产环境缺少 App Attest verifier 时 API 会拒绝启动，不能退回开发放行适配器。

## 协议与数据边界

主要端点：

- 匿名设备 challenge、注册和 token 轮换；
- 临时上传 grant、完成校验和删除；
- 幂等 Agent Job 提交、查询、取消和确认；
- Event 分页补拉与 SSE；
- Provider 原生流式 Tool Calling，以及按语义边界合并的 text Event；
- PostgreSQL `LISTEN/NOTIFY` 驱动的 Worker、Event stream 与 Tool Result 即时唤醒；
- 设备 Tool Request/Result；
- ActivityKit token 登记与删除；
- 当前匿名设备全部远端数据删除。

所有认证请求都绑定 method、path、timestamp、nonce 和 body digest。服务器不接受用户提供的
URL 去抓取媒体，不接收用户 BYOK，不把请求正文、token、IP、模型 payload 或健康内容写入
普通运行日志。

远端图片使用短期签名 URL 传给 Provider。视频只由 iOS 抽取关键帧后以图片上传，原始视频
不进入 Soma Server。终态 Job 经设备确认后清除内容；未完成内容有 7 天硬上限；只含状态、
时间、错误类别和用量的非内容元数据最多保留 30 天。

## 运维与恢复

- API ACK 丢失：客户端使用同一 `clientJobID` 重投，返回同一 Job。
- SSE 断开：客户端按最后 sequence 补拉；Event 读取不删除记录；连接健康时由 Event commit
  即时唤醒，不依赖固定轮询。
- Worker 退出：租约到期后其他 Worker 使用新 epoch 领取；旧 Worker 的迟到写入被拒绝。
- 设备 Tool：Job 停在 `waitingForDevice`，设备恢复后按 `toolCallID` 幂等返回结果。
- Provider 失败：Job 记录稳定错误类别；本地消息和已经完成的设备 Tool 事实不回滚。
- APNs 失败：事务 Outbox 指数退避；无效 token 删除；App 下次同步纠正系统表面。
- 清理失败：Worker 输出不含业务内容的 `retention_cleanup_failed` 结构化告警，下一轮重试。
- 设备撤销：取消/删除该设备 Job、Event、Tool、Outbox、token 和对象引用，并立即拒绝旧 token。

部署后的健康监控只按错误类别、队列数量、租约滞留、Outbox 重试和清理数量聚合，不采集
用户原文、动作名称、身体数据或媒体地址。

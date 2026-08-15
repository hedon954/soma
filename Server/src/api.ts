import { randomUUID } from "node:crypto";
import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { URL } from "node:url";
import { canonicalJSON } from "./canonical-json.js";
import {
  isTerminal,
  protocolVersion,
  ProtocolError,
  type AgentJobInput,
  type AgentMediaBinding,
  type AgentModelInput,
} from "./domain.js";
import {
  feedbackFilename,
  maximumFeedbackAttachmentBytes,
  maximumFeedbackAttachmentCount,
  maximumFeedbackMessageCharacters,
  type FeedbackEmailAttachment,
  type FeedbackEmailProvider,
} from "./feedback.js";
import {
  allowedUploadTypes,
  maximumUploadBytes,
  type TemporaryObjectStore,
} from "./object-store.js";
import { logOperationalError } from "./operational-log.js";
import {
  DeviceIdentityService,
  sha256,
  TokenCipher,
} from "./security.js";
import type { SomaStore } from "./store.js";

interface Dependencies {
  store: SomaStore;
  identity: DeviceIdentityService;
  objects: TemporaryObjectStore;
  tokenCipher: TokenCipher;
  feedback?: FeedbackEmailProvider;
  directVideoEnabled?: boolean;
  now?: () => Date;
}

export function createSomaServer(dependencies: Dependencies) {
  return createServer(async (request, response) => {
    const requestID = randomUUID();
    const now = dependencies.now?.() ?? new Date();
    try {
      await route(request, response, dependencies, requestID, now);
    } catch (error) {
      if (!(error instanceof ProtocolError)) {
        logOperationalError("api_request_failed", error);
      }
      const resolved =
        error instanceof ProtocolError
          ? error
          : new ProtocolError(
              "invalid_request",
              "请求无法处理。",
              500,
            );
      sendJSON(response, resolved.status, envelope(requestID, now, {
        error: {
          code: resolved.code,
          message: resolved.message,
        },
      }));
    }
  });
}

async function route(
  request: IncomingMessage,
  response: ServerResponse,
  dependencies: Dependencies,
  requestID: string,
  now: Date,
): Promise<void> {
  const url = new URL(request.url ?? "/", "http://localhost");
  const method = request.method ?? "GET";
  const rawBody = await readBody(request);

  if (method === "POST" && url.pathname === "/v1/device-registration-challenges") {
    const challenge = await dependencies.identity.createChallenge(now);
    sendJSON(response, 201, envelope(requestID, now, challenge));
    return;
  }

  if (method === "POST" && url.pathname === "/v1/devices") {
    const input = parseObject(rawBody);
    const tokens = await dependencies.identity.register(
      {
        challengeID: requiredString(input, "challengeID"),
        deviceID: requiredString(input, "deviceID"),
        publicKeyPem: requiredString(input, "publicKeyPem"),
        signature: requiredString(input, "signature"),
        timestamp: requiredNumber(input, "timestamp"),
        protocolVersion: requiredNumber(input, "protocolVersion"),
        ...optionalStringEntry(input, "attestationObject"),
        ...optionalStringEntry(input, "attestationKeyID"),
      },
      now,
    );
    sendJSON(response, 201, envelope(requestID, now, tokens));
    return;
  }

  if (method === "POST" && url.pathname === "/v1/device-tokens/refresh") {
    const input = parseObject(rawBody);
    const tokens = await dependencies.identity.rotate(
      requiredString(input, "rotationToken"),
      now,
    );
    sendJSON(response, 200, envelope(requestID, now, tokens));
    return;
  }

  const deviceID = await authenticate(
    request,
    url,
    rawBody,
    dependencies.identity,
    now,
  );

  if (method === "GET" && url.pathname === "/v1/capabilities") {
    sendJSON(response, 200, envelope(requestID, now, {
      directVideo: dependencies.directVideoEnabled ?? false,
    }));
    return;
  }

  if (method === "DELETE" && url.pathname === "/v1/device-data") {
    const keys = await dependencies.store.deleteDeviceData(deviceID, now);
    await dependencies.objects.deleteObjects(keys);
    sendJSON(response, 200, envelope(requestID, now, { deleted: true }));
    return;
  }

  if (method === "POST" && url.pathname === "/v1/uploads") {
    const input = parseObject(rawBody);
    const contentType = requiredString(input, "contentType");
    const contentLength = requiredNumber(input, "contentLength");
    const digest = requiredString(input, "sha256");
    if (
      !allowedUploadTypes.has(contentType) ||
      contentLength <= 0 ||
      contentLength > maximumUploadBytes ||
      !/^[a-f0-9]{64}$/.test(digest)
    ) {
      throw new ProtocolError(
        "invalid_request",
        "媒体类型、大小或摘要不合法。",
        400,
      );
    }
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1_000);
    const grant = await dependencies.objects.createUploadGrant({
      contentType,
      contentLength,
      digest,
      expiresAt,
    });
    const uploadID = randomUUID();
    await dependencies.store.saveUpload({
      id: uploadID,
      deviceID,
      contentType,
      expectedBytes: contentLength,
      expectedDigest: digest,
      objectKey: grant.objectKey,
      createdAt: now,
    });
    sendJSON(response, 201, envelope(requestID, now, {
      uploadID,
      uploadURL: grant.uploadURL,
      expiresAt: grant.expiresAt,
      requiredHeaders: grant.requiredHeaders,
    }));
    return;
  }

  if (method === "POST" && url.pathname === "/v1/feedback") {
    const feedback = dependencies.feedback;
    if (feedback === undefined) {
      throw new ProtocolError(
        "provider_unavailable",
        "反馈服务尚未配置。",
        503,
      );
    }
    const input = parseObject(rawBody);
    const feedbackID = requiredString(input, "feedbackID");
    const idempotencyKey = singleHeader(request, "idempotency-key");
    if (
      idempotencyKey !== feedbackID ||
      requiredNumber(input, "protocolVersion") !== protocolVersion
    ) {
      throw new ProtocolError(
        "invalid_request",
        "协议版本或 Idempotency-Key 不合法。",
        400,
      );
    }
    const rawMessage = input.message;
    if (typeof rawMessage !== "string") {
      throw new ProtocolError("invalid_request", "message 无效。", 400);
    }
    const message = rawMessage.trim();
    if (message.length > maximumFeedbackMessageCharacters) {
      throw new ProtocolError("invalid_request", "反馈文字过长。", 400);
    }
    const uploadIDs = requiredStringArray(input, "uploadIDs");
    if (
      uploadIDs.length > maximumFeedbackAttachmentCount ||
      new Set(uploadIDs).size !== uploadIDs.length ||
      (message.length === 0 && uploadIDs.length === 0)
    ) {
      throw new ProtocolError("invalid_request", "反馈内容或附件无效。", 400);
    }
    const uploads = await dependencies.store.getUploads(deviceID, uploadIDs);
    const uploadsByID = new Map(uploads.map((upload) => [upload.id, upload]));
    const orderedUploads = uploadIDs.map((uploadID) => uploadsByID.get(uploadID));
    if (
      orderedUploads.some(
        (upload) => upload === undefined || upload.completedAt === undefined,
      )
    ) {
      throw new ProtocolError(
        "upload_incomplete",
        "反馈媒体尚未上传完成。",
        409,
      );
    }
    const totalBytes = orderedUploads.reduce(
      (total, upload) => total + (upload?.expectedBytes ?? 0),
      0,
    );
    if (totalBytes > maximumFeedbackAttachmentBytes) {
      throw new ProtocolError("invalid_request", "反馈附件总大小超过限制。", 413);
    }
    const attachments: FeedbackEmailAttachment[] = [];
    for (const [index, upload] of orderedUploads.entries()) {
      if (upload === undefined) continue;
      const content = await dependencies.objects.readObject(upload.objectKey);
      if (
        content.length !== upload.expectedBytes ||
        sha256(content) !== upload.expectedDigest
      ) {
        throw new ProtocolError(
          "upload_incomplete",
          "反馈媒体校验失败。",
          409,
        );
      }
      attachments.push({
        filename: feedbackFilename(index + 1, upload.contentType),
        contentType: upload.contentType,
        content,
      });
    }
    await feedback.send({
      idempotencyKey: `feedback/${deviceID}/${feedbackID}`,
      message,
      attachments,
    });
    const objectKeys = (
      await Promise.all(
        uploadIDs.map((uploadID) =>
          dependencies.store.deleteUpload(deviceID, uploadID, now)
        ),
      )
    ).filter((key): key is string => key !== undefined);
    try {
      await dependencies.objects.deleteObjects(objectKeys);
    } catch (error) {
      logOperationalError("feedback_attachment_cleanup_failed", error);
    }
    sendJSON(response, 201, envelope(requestID, now, {
      feedbackID,
      accepted: true,
    }));
    return;
  }

  const uploadComplete = url.pathname.match(/^\/v1\/uploads\/([^/]+)\/complete$/);
  if (method === "POST" && uploadComplete?.[1] !== undefined) {
    const input = parseObject(rawBody);
    const bytes = requiredNumber(input, "bytes");
    const digest = requiredString(input, "sha256");
    const upload = (
      await dependencies.store.getUploads(
        deviceID,
        [uploadComplete[1]],
      )
    )[0];
    if (
      upload === undefined ||
      !(await dependencies.objects.verifyUpload({
        objectKey: upload.objectKey,
        contentType: upload.contentType,
        contentLength: bytes,
        digest,
      }))
    ) {
      throw new ProtocolError(
        "upload_incomplete",
        "对象存储尚未确认媒体上传。",
        409,
      );
    }
    const completed = await dependencies.store.completeUpload(
      deviceID,
      uploadComplete[1],
      bytes,
      digest,
      now,
    );
    sendJSON(response, 200, envelope(requestID, now, {
      uploadID: completed.id,
      completed: true,
    }));
    return;
  }
  const uploadMatch = url.pathname.match(/^\/v1\/uploads\/([^/]+)$/);
  if (method === "DELETE" && uploadMatch?.[1] !== undefined) {
    const objectKey = await dependencies.store.deleteUpload(
      deviceID,
      uploadMatch[1],
      now,
    );
    if (objectKey !== undefined) {
      await dependencies.objects.deleteObjects([objectKey]);
    }
    sendJSON(response, 200, envelope(requestID, now, { deleted: true }));
    return;
  }

  if (method === "POST" && url.pathname === "/v1/agent-jobs") {
    const idempotencyKey = request.headers["idempotency-key"];
    const input = parseJobInput(rawBody);
    if (
      idempotencyKey !== input.clientJobID ||
      input.protocolVersion !== protocolVersion
    ) {
      throw new ProtocolError(
        input.protocolVersion !== protocolVersion
          ? "protocol_unsupported"
          : "invalid_request",
        "协议版本或 Idempotency-Key 不合法。",
        400,
      );
    }
    const job = await dependencies.store.submitJob({
      deviceID,
      input,
      bodyDigest: sha256(rawBody),
      now,
    });
    sendJSON(response, 201, envelope(requestID, now, publicJob(job)));
    return;
  }

  const jobMatch = url.pathname.match(/^\/v1\/agent-jobs\/([^/]+)$/);
  if (method === "GET" && jobMatch?.[1] !== undefined) {
    const job = await requiredJob(dependencies.store, deviceID, jobMatch[1]);
    sendJSON(response, 200, envelope(requestID, now, publicJob(job)));
    return;
  }

  const eventsMatch = url.pathname.match(
    /^\/v1\/agent-jobs\/([^/]+)\/events$/,
  );
  if (method === "GET" && eventsMatch?.[1] !== undefined) {
    const job = await requiredJob(
      dependencies.store,
      deviceID,
      eventsMatch[1],
    );
    const after = safeInteger(url.searchParams.get("after"), 0, 0, 1_000_000);
    const limit = safeInteger(url.searchParams.get("limit"), 100, 1, 500);
    const events = await dependencies.store.events(job.id, after, limit);
    sendJSON(response, 200, envelope(requestID, now, {
      jobID: job.id,
      events,
      nextSequence: events.at(-1)?.sequence ?? after,
      terminal: isTerminal(job.state),
    }));
    return;
  }

  const streamMatch = url.pathname.match(
    /^\/v1\/agent-jobs\/([^/]+)\/events\/stream$/,
  );
  if (method === "GET" && streamMatch?.[1] !== undefined) {
    const job = await requiredJob(
      dependencies.store,
      deviceID,
      streamMatch[1],
    );
    const after = safeInteger(url.searchParams.get("after"), 0, 0, 1_000_000);
    await streamEvents(
      response,
      dependencies.store,
      deviceID,
      job.id,
      after,
    );
    return;
  }

  const cancelMatch = url.pathname.match(
    /^\/v1\/agent-jobs\/([^/]+)\/cancel$/,
  );
  if (method === "POST" && cancelMatch?.[1] !== undefined) {
    const job = await dependencies.store.cancelJob(
      deviceID,
      cancelMatch[1],
      now,
    );
    sendJSON(response, 200, envelope(requestID, now, publicJob(job)));
    return;
  }

  const ackMatch = url.pathname.match(/^\/v1\/agent-jobs\/([^/]+)\/ack$/);
  if (method === "POST" && ackMatch?.[1] !== undefined) {
    const input = parseObject(rawBody);
    await dependencies.store.acknowledge(
      deviceID,
      ackMatch[1],
      requiredNumber(input, "throughSequence"),
    );
    sendJSON(response, 200, envelope(requestID, now, { acknowledged: true }));
    return;
  }

  const toolResultMatch = url.pathname.match(
    /^\/v1\/agent-jobs\/([^/]+)\/tool-results$/,
  );
  if (method === "POST" && toolResultMatch?.[1] !== undefined) {
    const input = parseObject(rawBody);
    const result = requiredObject(input, "result");
    const request = await dependencies.store.submitToolResult(
      deviceID,
      toolResultMatch[1],
      {
        toolCallID: requiredString(input, "toolCallID"),
        digest: sha256(Buffer.from(canonicalJSON(result))),
        result,
      },
      now,
    );
    sendJSON(response, 200, envelope(requestID, now, {
      toolCallID: request.toolCallID,
      accepted: true,
    }));
    return;
  }

  if (method === "GET" && url.pathname === "/v1/device-tool-requests") {
    const requests = await dependencies.store.pendingToolRequests(deviceID);
    sendJSON(response, 200, envelope(requestID, now, { requests }));
    return;
  }

  const activityMatch = url.pathname.match(
    /^\/v1\/agent-jobs\/([^/]+)\/live-activity-token$/,
  );
  if (activityMatch?.[1] !== undefined) {
    const job = await requiredJob(
      dependencies.store,
      deviceID,
      activityMatch[1],
    );
    if (method === "PUT") {
      const input = parseObject(rawBody);
      const environment = requiredString(input, "environment");
      if (environment !== "development" && environment !== "production") {
        throw new ProtocolError(
          "invalid_request",
          "APNs environment 不合法。",
          400,
        );
      }
      await dependencies.store.saveActivityToken({
        jobID: job.id,
        deviceID,
        environment,
        encryptedToken: dependencies.tokenCipher.encrypt(
          requiredString(input, "token"),
        ),
        lastPushedSequence: 0,
        createdAt: now,
      });
      sendJSON(response, 200, envelope(requestID, now, { registered: true }));
      return;
    }
    if (method === "DELETE") {
      await dependencies.store.deleteActivityToken(job.id);
      sendJSON(response, 200, envelope(requestID, now, { deleted: true }));
      return;
    }
  }

  throw new ProtocolError("not_found", "接口不存在。", 404);
}

async function authenticate(
  request: IncomingMessage,
  url: URL,
  rawBody: Buffer,
  identity: DeviceIdentityService,
  now: Date,
): Promise<string> {
  return identity.authenticate(
    {
      ...optionalHeader(request, "authorization", "authorization"),
      ...optionalHeader(request, "x-soma-device-id", "deviceID"),
      ...optionalHeader(request, "x-soma-timestamp", "timestamp"),
      ...optionalHeader(request, "x-soma-nonce", "nonce"),
      ...optionalHeader(request, "x-soma-body-sha256", "bodyDigest"),
      ...optionalHeader(request, "x-soma-signature", "signature"),
      method: request.method ?? "GET",
      path: `${url.pathname}${url.search}`,
      rawBody,
    },
    now,
  );
}

async function streamEvents(
  response: ServerResponse,
  store: SomaStore,
  deviceID: string,
  jobID: string,
  initialAfter: number,
): Promise<void> {
  response.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
  });
  let cursor = initialAfter;
  let closed = false;
  response.on("close", () => {
    closed = true;
  });
  while (!closed) {
    const rows = await store.events(jobID, cursor, 100);
    for (const event of rows) {
      response.write(`id: ${event.sequence}\n`);
      response.write("event: agent_event\n");
      response.write(`data: ${JSON.stringify(event)}\n\n`);
      cursor = event.sequence;
    }
    if (rows.length === 0) {
      const job = await store.getJob(deviceID, jobID);
      if (job === undefined || isTerminal(job.state)) {
        response.end();
        return;
      }
      await store.waitForEventSignal(jobID, cursor, 15_000);
      if (!closed) response.write(": keep-alive\n\n");
    }
  }
}

async function requiredJob(
  store: SomaStore,
  deviceID: string,
  jobID: string,
) {
  const job = await store.getJob(deviceID, jobID);
  if (job === undefined) {
    throw new ProtocolError("not_found", "任务不存在。", 404);
  }
  return job;
}

function parseJobInput(rawBody: Buffer): AgentJobInput {
  const value = parseObject(rawBody);
  const modelInput = parseModelInput(requiredObject(value, "modelInput"));
  const mediaBindings = parseMediaBindings(value.mediaBindings);
  const uploadIDs = requiredStringArray(value, "uploadIDs");
  const allowedDeviceTools = requiredStringArray(value, "allowedDeviceTools");
  const allowedRemoteTools = requiredStringArray(value, "allowedRemoteTools");
  const allowedDeviceToolSchemas = optionalToolSchemas(
    value,
    "allowedDeviceToolSchemas",
  );
  if (
    allowedDeviceToolSchemas.length > 0 &&
    (
      allowedDeviceToolSchemas.length !== allowedDeviceTools.length ||
      allowedDeviceToolSchemas.some(
        (item) => !allowedDeviceTools.includes(item.name),
      )
    )
  ) {
    throw new ProtocolError(
      "invalid_request",
      "allowedDeviceTools 与 Schema 清单不一致。",
      400,
    );
  }
  const rawMediaMode = value.mediaMode;
  const mediaMode = rawMediaMode === undefined ? "text" : rawMediaMode;
  if (
    typeof mediaMode !== "string" ||
    !["text", "images", "keyframes", "direct_video"].includes(mediaMode)
  ) {
    throw new ProtocolError("invalid_request", "mediaMode 无效。", 400);
  }
  const requestAttempt = value.requestAttempt === undefined
    ? 1
    : requiredNumber(value, "requestAttempt");
  if (!Number.isInteger(requestAttempt) || requestAttempt < 1 || requestAttempt > 2) {
    throw new ProtocolError("invalid_request", "requestAttempt 无效。", 400);
  }
  const toolNames = modelInput.tools.map((tool) => tool.name);
  const allowedNames = [...allowedRemoteTools, ...allowedDeviceTools];
  if (
    new Set(toolNames).size !== toolNames.length ||
    new Set(modelInput.activeTools).size !== modelInput.activeTools.length ||
    new Set(modelInput.skills.map((skill) => skill.id)).size !==
      modelInput.skills.length ||
    new Set(allowedNames).size !== allowedNames.length ||
    toolNames.length !== allowedNames.length ||
    toolNames.some((name) => !allowedNames.includes(name)) ||
    modelInput.activeTools.some((name) => !toolNames.includes(name))
  ) {
    throw new ProtocolError(
      "invalid_request",
      "模型 Tool 清单与执行边界不一致。",
      400,
    );
  }
  if (
    mediaBindings.length !== uploadIDs.length ||
    new Set(mediaBindings.map((binding) => binding.id)).size !== mediaBindings.length ||
    new Set(mediaBindings.map((binding) => binding.uploadID)).size !== mediaBindings.length ||
    mediaBindings.some((binding) => !uploadIDs.includes(binding.uploadID)) ||
    modelInput.messages.some((message) =>
      message.mediaIDs.some((id) => !mediaBindings.some((binding) => binding.id === id))
    )
  ) {
    throw new ProtocolError("invalid_request", "模型媒体绑定无效。", 400);
  }
  return {
    clientJobID: requiredString(value, "clientJobID"),
    turnID: requiredString(value, "turnID"),
    sessionID: requiredString(value, "sessionID"),
    protocolVersion: requiredNumber(value, "protocolVersion"),
    modelInput,
    mediaBindings,
    uploadIDs,
    mediaMode: mediaMode as NonNullable<AgentJobInput["mediaMode"]>,
    requestAttempt,
    allowedRemoteTools,
    allowedDeviceTools,
    allowedDeviceToolSchemas,
    liveActivityEnabled: requiredBoolean(value, "liveActivityEnabled"),
  };
}

function parseModelInput(value: Record<string, unknown>): AgentModelInput {
  const schemaVersion = requiredNumber(value, "schemaVersion");
  const rawMessages = value.messages;
  const rawSkills = value.skills;
  const rawTools = value.tools;
  const runtime = requiredObject(value, "runtime");
  const deadlines = requiredObject(runtime, "deadlines");
  if (
    schemaVersion !== 1 ||
    !Array.isArray(rawMessages) ||
    rawMessages.length < 2 ||
    !Array.isArray(rawSkills) ||
    !Array.isArray(rawTools) ||
    runtime.toolChoice !== "auto" ||
    runtime.parallelToolCalls !== true
  ) {
    throw new ProtocolError("invalid_request", "模型输入协议无效。", 400);
  }
  const messages = rawMessages.map((raw) => {
    const message = asObject(raw, "模型消息");
    const role = requiredString(message, "role");
    if (!['system', 'user', 'assistant'].includes(role)) {
      throw new ProtocolError("invalid_request", "模型消息角色无效。", 400);
    }
    return {
      role: role as "system" | "user" | "assistant",
      text: requiredString(message, "text"),
      mediaIDs: requiredStringArray(message, "mediaIDs"),
    };
  });
  if (messages[0]?.role !== "system" || messages.at(-1)?.role !== "user") {
    throw new ProtocolError("invalid_request", "模型消息顺序无效。", 400);
  }
  const skills = rawSkills.map((raw) => {
    const skill = asObject(raw, "Skill 快照");
    return {
      id: requiredString(skill, "id"),
      content: requiredString(skill, "content"),
    };
  });
  const tools = rawTools.map((raw) => {
    const tool = asObject(raw, "模型 Tool");
    const name = requiredString(tool, "name");
    const definition = requiredObject(tool, "definition");
    const functionValue = requiredObject(definition, "function");
    if (requiredString(functionValue, "name") !== name) {
      throw new ProtocolError("invalid_request", "模型 Tool 定义名称无效。", 400);
    }
    requiredObject(functionValue, "parameters");
    return {
      name,
      schemaVersion: requiredNumber(tool, "schemaVersion"),
      definition,
    };
  });
  const maxSteps = requiredNumber(runtime, "maxSteps");
  if (!Number.isInteger(maxSteps) || maxSteps < 1 || maxSteps > 500) {
    throw new ProtocolError("invalid_request", "模型步数上限无效。", 400);
  }
  const deadline = (key: string): number => {
    const result = requiredNumber(deadlines, key);
    if (result <= 0 || result > 3_600) {
      throw new ProtocolError("invalid_request", "模型超时策略无效。", 400);
    }
    return result;
  };
  return {
    schemaVersion: 1,
    messages,
    skills,
    tools,
    activeTools: requiredStringArray(value, "activeTools"),
    runtime: {
      toolChoice: "auto",
      parallelToolCalls: true,
      maxSteps,
      deadlines: {
        textTTFT: deadline("textTTFT"),
        imageTTFT: deadline("imageTTFT"),
        directVideoTTFT: deadline("directVideoTTFT"),
        textLoopTotal: deadline("textLoopTotal"),
        imageLoopTotal: deadline("imageLoopTotal"),
        videoLoopTotal: deadline("videoLoopTotal"),
      },
    },
  };
}

function parseMediaBindings(value: unknown): AgentMediaBinding[] {
  if (!Array.isArray(value)) {
    throw new ProtocolError("invalid_request", "mediaBindings 无效。", 400);
  }
  return value.map((raw) => {
    const binding = asObject(raw, "媒体绑定");
    return {
      id: requiredString(binding, "id"),
      uploadID: requiredString(binding, "uploadID"),
    };
  });
}

function asObject(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ProtocolError("invalid_request", `${label}无效。`, 400);
  }
  return value as Record<string, unknown>;
}

function optionalToolSchemas(
  value: Record<string, unknown>,
  key: string,
): { name: string; schemaVersion: number }[] {
  const resolved = value[key];
  if (resolved === undefined) return [];
  if (!Array.isArray(resolved)) {
    throw new ProtocolError("invalid_request", key + " 无效。", 400);
  }
  return resolved.map((item) => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      throw new ProtocolError("invalid_request", key + " 无效。", 400);
    }
    const object = item as Record<string, unknown>;
    const name = object.name;
    const schemaVersion = object.schemaVersion;
    if (
      typeof name !== "string" ||
      name.length === 0 ||
      typeof schemaVersion !== "number" ||
      !Number.isInteger(schemaVersion)
    ) {
      throw new ProtocolError("invalid_request", key + " 无效。", 400);
    }
    return { name, schemaVersion };
  });
}

function publicJob(job: Awaited<ReturnType<typeof requiredJob>>) {
  return {
    id: job.id,
    clientJobID: job.clientJobID,
    turnID: job.turnID,
    sessionID: job.sessionID,
    state: job.state,
    lastSequence: job.lastSequence,
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
    ...(job.errorCode === undefined ? {} : { errorCode: job.errorCode }),
  };
}

function envelope(
  requestID: string,
  now: Date,
  body: Record<string, unknown>,
): Record<string, unknown> {
  return {
    protocolVersion,
    requestID,
    serverTime: now.toISOString(),
    ...body,
  };
}

function parseObject(rawBody: Buffer): Record<string, unknown> {
  try {
    const value = JSON.parse(
      rawBody.length === 0 ? "{}" : rawBody.toString("utf8"),
    ) as unknown;
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("not an object");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ProtocolError("invalid_request", "JSON 请求无效。", 400);
  }
}

function requiredString(
  value: Record<string, unknown>,
  key: string,
): string {
  const resolved = value[key];
  if (typeof resolved !== "string" || resolved.length === 0) {
    throw new ProtocolError("invalid_request", `${key} 无效。`, 400);
  }
  return resolved;
}

function requiredNumber(
  value: Record<string, unknown>,
  key: string,
): number {
  const resolved = value[key];
  if (typeof resolved !== "number" || !Number.isFinite(resolved)) {
    throw new ProtocolError("invalid_request", `${key} 无效。`, 400);
  }
  return resolved;
}

function requiredBoolean(
  value: Record<string, unknown>,
  key: string,
): boolean {
  const resolved = value[key];
  if (typeof resolved !== "boolean") {
    throw new ProtocolError("invalid_request", `${key} 无效。`, 400);
  }
  return resolved;
}

function requiredStringArray(
  value: Record<string, unknown>,
  key: string,
): string[] {
  const resolved = value[key];
  if (
    !Array.isArray(resolved) ||
    !resolved.every((item) => typeof item === "string")
  ) {
    throw new ProtocolError("invalid_request", `${key} 无效。`, 400);
  }
  return resolved;
}

function requiredObject(
  value: Record<string, unknown>,
  key: string,
): Record<string, unknown> {
  const resolved = value[key];
  if (
    resolved === null ||
    typeof resolved !== "object" ||
    Array.isArray(resolved)
  ) {
    throw new ProtocolError("invalid_request", `${key} 无效。`, 400);
  }
  return resolved as Record<string, unknown>;
}

function optionalStringEntry(
  value: Record<string, unknown>,
  key: string,
): Record<string, string> {
  const resolved = value[key];
  return typeof resolved === "string" ? { [key]: resolved } : {};
}

function safeInteger(
  raw: string | null,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (raw === null) return fallback;
  const value = Number(raw);
  return Number.isInteger(value)
    ? Math.min(Math.max(value, minimum), maximum)
    : fallback;
}

function singleHeader(
  request: IncomingMessage,
  name: string,
): string | undefined {
  const value = request.headers[name];
  return Array.isArray(value) ? value[0] : value;
}

function optionalHeader(
  request: IncomingMessage,
  headerName: string,
  propertyName: string,
): Record<string, string> {
  const value = singleHeader(request, headerName);
  return value === undefined ? {} : { [propertyName]: value };
}

async function readBody(request: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > 1_024 * 1_024) {
      throw new ProtocolError("invalid_request", "请求正文过大。", 413);
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks);
}

function sendJSON(
  response: ServerResponse,
  status: number,
  value: Record<string, unknown>,
): void {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": String(body.length),
    "cache-control": "no-store",
  });
  response.end(body);
}

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
} from "./domain.js";
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
      response.write(": keep-alive\n\n");
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
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
  return {
    clientJobID: requiredString(value, "clientJobID"),
    turnID: requiredString(value, "turnID"),
    sessionID: requiredString(value, "sessionID"),
    protocolVersion: requiredNumber(value, "protocolVersion"),
    text: requiredString(value, "text"),
    contextSnapshot: requiredString(value, "contextSnapshot"),
    uploadIDs: requiredStringArray(value, "uploadIDs"),
    allowedRemoteTools: requiredStringArray(value, "allowedRemoteTools"),
    allowedDeviceTools: requiredStringArray(value, "allowedDeviceTools"),
    liveActivityEnabled: requiredBoolean(value, "liveActivityEnabled"),
  };
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

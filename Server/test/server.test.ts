import assert from "node:assert/strict";
import {
  generateKeyPairSync,
  randomUUID,
  sign,
} from "node:crypto";
import { readFile } from "node:fs/promises";
import { afterEach, test } from "node:test";
import type { AddressInfo } from "node:net";
import {
  ActivityPushProjector,
  type APNsProvider,
  OutboxDispatcher,
} from "../src/apns.js";
import { createSomaServer } from "../src/api.js";
import type {
  ActivityToken,
  AgentJobInput,
} from "../src/domain.js";
import {
  InMemoryObjectStore,
} from "../src/object-store.js";
import { OpenAICompatibleManagedProvider } from "../src/provider.js";
import {
  AllowDevelopmentAttestation,
  DeviceIdentityService,
  sha256,
  TokenCipher,
} from "../src/security.js";
import { InMemorySomaStore } from "../src/store.js";
import { validateDeviceTool } from "../src/tool-registry.js";
import {
  AgentWorker,
  DeterministicTestProvider,
} from "../src/worker.js";

const servers: ReturnType<typeof createSomaServer>[] = [];

afterEach(async () => {
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise<void>((resolve, reject) => {
          server.close((error) => {
            if (error) reject(error);
            else resolve();
          });
        }),
    ),
  );
});

test("anonymous device signature rejects nonce replay", async () => {
  const store = new InMemorySomaStore();
  const identity = new DeviceIdentityService(
    store,
    "test-secret-that-is-at-least-thirty-two-characters",
    new AllowDevelopmentAttestation(),
  );
  const now = new Date("2026-07-31T00:00:00Z");
  const device = await registerDevice(store, identity, now);
  const rawBody = Buffer.from("{}");
  const timestamp = String(Math.floor(now.getTime() / 1_000));
  const nonce = randomUUID();
  const digest = sha256(rawBody);
  const canonical = ["GET", "/v1/example", timestamp, nonce, digest].join(
    "\n",
  );
  const signature = sign(
    "sha256",
    Buffer.from(canonical),
    device.privateKey,
  ).toString("base64");
  const input = {
    authorization: `Bearer ${device.accessToken}`,
    deviceID: device.id,
    timestamp,
    nonce,
    bodyDigest: digest,
    signature,
    method: "GET",
    path: "/v1/example",
    rawBody,
  };

  assert.equal(await identity.authenticate(input, now), device.id);
  await assert.rejects(
    identity.authenticate(input, now),
    (error: unknown) =>
      error instanceof Error && error.message.includes("nonce"),
  );
});

test("concurrent duplicate submissions converge on one server job", async () => {
  const store = new InMemorySomaStore();
  const input = makeJobInput();
  const submission = {
    deviceID: randomUUID(),
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  };

  const jobs = await Promise.all(
    Array.from({ length: 10 }, () => store.submitJob(submission)),
  );

  assert.equal(new Set(jobs.map((job) => job.id)).size, 1);
  await assert.rejects(
    store.submitJob({
      ...submission,
      bodyDigest: sha256("different"),
    }),
    (error: unknown) =>
      error instanceof Error && error.message.includes("不同内容"),
  );
});

test("event cursor replay is ordered and non-destructive", async () => {
  const store = new InMemorySomaStore();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput(),
    bodyDigest: sha256("job"),
    now: new Date(),
  });
  const lease = await store.claimJob("worker-a", new Date(), 30);
  assert.ok(lease);
  await store.appendEvent(job.id, lease.epoch, {
    kind: "text",
    phase: "updated",
    payloadVersion: 1,
    payload: { text: "完成" },
    createdAt: new Date(),
  });

  const first = await store.events(job.id, 0, 100);
  const replay = await store.events(job.id, 1, 100);

  assert.deepEqual(
    first.map((event) => event.sequence),
    [1, 2],
  );
  assert.deepEqual(
    replay.map((event) => event.sequence),
    [2],
  );
  assert.equal((await store.events(job.id, 0, 100)).length, 2);
});

test("worker survives process replacement and device tool result is idempotent", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const input = makeJobInput({
    allowedDeviceTools: ["record_workout"],
  });
  const job = await store.submitJob({
    deviceID,
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  const firstWorker = new AgentWorker(
    store,
    new DeterministicTestProvider({
      kind: "deviceTool",
      toolName: "record_workout",
      schemaVersion: 1,
      arguments: { exercise_id: randomUUID() },
      mutation: true,
    }),
    "worker-before-restart",
  );
  const waiting = await firstWorker.runOnce();
  assert.equal(waiting?.state, "waitingForDevice");
  const request = (await store.pendingToolRequests(deviceID))[0];
  assert.ok(request);
  const result = {
    toolCallID: request.toolCallID,
    digest: sha256('{"ok":true}'),
    result: { ok: true },
  };
  await store.submitToolResult(deviceID, job.id, result, new Date());
  await store.submitToolResult(deviceID, job.id, result, new Date());

  const replacementWorker = new AgentWorker(
    store,
    new DeterministicTestProvider(),
    "worker-after-restart",
  );
  const completed = await replacementWorker.runOnce();

  assert.equal(completed?.state, "completed");
  assert.equal((await store.pendingToolRequests(deviceID)).length, 0);
});

test("first terminal state wins cancellation race", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const job = await store.submitJob({
    deviceID,
    input: makeJobInput(),
    bodyDigest: sha256("race"),
    now: new Date(),
  });
  await store.cancelJob(deviceID, job.id, new Date());
  const afterLateCompletion = await store.transition(
    job.id,
    "completed",
    new Date(),
  );

  assert.equal(afterLateCompletion.state, "cancelled");
});

test("retention clears content at hard limit and metadata at thirty days", async () => {
  const store = new InMemorySomaStore();
  const createdAt = new Date("2026-07-01T00:00:00Z");
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput(),
    bodyDigest: sha256("retention"),
    now: createdAt,
  });

  const eightDays = await store.cleanup(
    new Date("2026-07-09T00:00:00Z"),
  );
  assert.deepEqual(eightDays.expiredJobIDs, [job.id]);
  assert.deepEqual(eightDays.deletedContentJobIDs, [job.id]);
  assert.deepEqual(await store.events(job.id, 0, 100), []);
  const thirtyOneDays = await store.cleanup(
    new Date("2026-08-02T00:00:00Z"),
  );
  assert.deepEqual(thirtyOneDays.deletedMetadataJobIDs, [job.id]);
});

test("activity push ignores stale sequence and deletes terminal token", async () => {
  const store = new InMemorySomaStore();
  const cipher = new TokenCipher(Buffer.alloc(32, 9).toString("base64"));
  const token: ActivityToken = {
    jobID: randomUUID(),
    deviceID: randomUUID(),
    environment: "development",
    encryptedToken: cipher.encrypt("activity-token"),
    lastPushedSequence: 4,
    createdAt: new Date(),
  };
  await store.saveActivityToken(token);
  const calls: number[] = [];
  const provider: APNsProvider = {
    async sendActivityUpdate(input) {
      calls.push(input.sequence);
      return "accepted";
    },
  };
  const projector = new ActivityPushProjector(store, provider, cipher);
  const event = {
    id: randomUUID(),
    jobID: token.jobID,
    sequence: 3,
    kind: "output" as const,
    phase: "completed" as const,
    payloadVersion: 1 as const,
    payload: {},
    createdAt: new Date(),
  };
  await projector.project(token.jobID, event);
  await projector.project(token.jobID, { ...event, sequence: 5 });

  assert.deepEqual(calls, [5]);
  assert.equal(await store.activityToken(token.jobID), undefined);
});

test("APNs retry remains in outbox with backoff until accepted", async () => {
  const store = new InMemorySomaStore();
  const now = new Date("2026-07-31T00:00:00Z");
  const deviceID = randomUUID();
  const job = await store.submitJob({
    deviceID,
    input: makeJobInput(),
    bodyDigest: sha256("retry"),
    now,
  });
  const lease = await store.claimJob("worker", now, 30);
  assert.ok(lease);
  const event = await store.appendEvent(job.id, lease.epoch, {
    kind: "model",
    phase: "updated",
    payloadVersion: 1,
    payload: {},
    createdAt: now,
  });
  const cipher = new TokenCipher(Buffer.alloc(32, 7).toString("base64"));
  await store.saveActivityToken({
    jobID: job.id,
    deviceID,
    environment: "development",
    encryptedToken: cipher.encrypt("activity-token"),
    lastPushedSequence: 0,
    createdAt: now,
  });
  let result: "accepted" | "retry" = "retry";
  const calls: number[] = [];
  const provider: APNsProvider = {
    async sendActivityUpdate(input) {
      calls.push(input.sequence);
      return result;
    },
  };
  const dispatcher = new OutboxDispatcher(
    store,
    new ActivityPushProjector(store, provider, cipher),
  );

  assert.equal(await dispatcher.runBatch(now), 2);
  assert.deepEqual(calls, [event.sequence]);
  assert.equal(
    await dispatcher.runBatch(new Date(now.getTime() + 1_000)),
    0,
  );
  result = "accepted";
  assert.equal(
    await dispatcher.runBatch(new Date(now.getTime() + 3_000)),
    1,
  );
  assert.deepEqual(calls, [event.sequence, event.sequence]);
  assert.equal(
    (await store.activityToken(job.id))?.lastPushedSequence,
    event.sequence,
  );
});

test("tool validation rejects paths URLs and unsupported schemas", () => {
  assert.throws(() =>
    validateDeviceTool({
      name: "record_workout",
      schemaVersion: 1,
      arguments: { local_path: "/private/file" },
      allowedNames: ["record_workout"],
    }),
  );
  assert.throws(() =>
    validateDeviceTool({
      name: "unknown",
      schemaVersion: 1,
      arguments: {},
      allowedNames: ["unknown"],
    }),
  );
});

test("managed provider sends only signed image inputs and visible limitations", async () => {
  const store = new InMemorySomaStore();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput(),
    bodyDigest: sha256("media"),
    now: new Date(),
  });
  let captured: Record<string, unknown> | undefined;
  const provider = new OpenAICompatibleManagedProvider(
    "https://provider.invalid/v1",
    "test-key",
    "test-model",
    async (_input, init) => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return new Response(JSON.stringify({
        choices: [{ message: { content: "已分析可见关键帧。" } }],
      }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  );

  await provider.run(job, [], [
    { contentType: "image/jpeg", url: "https://signed.invalid/frame.jpg" },
    { contentType: "video/mp4", url: "https://signed.invalid/original.mp4" },
  ]);

  const messages = captured?.messages as Record<string, unknown>[];
  const content = messages[1]?.content as Record<string, unknown>[];
  assert.equal(
    content.filter((part) => part.type === "image_url").length,
    1,
  );
  assert.match(
    String(content[0]?.text),
    /关键帧不足以证明完整动作轨迹/,
  );
  assert.doesNotMatch(JSON.stringify(captured), /original\.mp4/);
});

test("HTTP idempotent submission returns one job and no body log surface", async () => {
  const store = new InMemorySomaStore();
  const now = new Date("2026-07-31T00:00:00Z");
  const identity = new DeviceIdentityService(
    store,
    "test-secret-that-is-at-least-thirty-two-characters",
    new AllowDevelopmentAttestation(),
  );
  const device = await registerDevice(store, identity, now);
  const server = createSomaServer({
    store,
    identity,
    objects: new InMemoryObjectStore(),
    tokenCipher: new TokenCipher(Buffer.alloc(32, 7).toString("base64")),
    now: () => now,
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  const input = makeJobInput();
  const body = Buffer.from(JSON.stringify(input));
  const first = await signedFetch(
    `http://127.0.0.1:${port}/v1/agent-jobs`,
    body,
    device,
    now,
    input.clientJobID,
  );
  const second = await signedFetch(
    `http://127.0.0.1:${port}/v1/agent-jobs`,
    body,
    device,
    now,
    input.clientJobID,
  );
  const firstJSON = (await first.json()) as { id: string };
  const secondJSON = (await second.json()) as { id: string };

  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  assert.equal(firstJSON.id, secondJSON.id);
});

test("migration defines database uniqueness and transactional outbox", async () => {
  const migration = await readFile(
    new URL("../migrations/001_initial.sql", import.meta.url),
    "utf8",
  );

  assert.match(migration, /UNIQUE \(device_id, client_job_id\)/);
  assert.match(migration, /UNIQUE \(job_id, sequence\)/);
  assert.match(migration, /UNIQUE \(job_id, tool_call_id\)/);
  assert.match(migration, /CREATE TABLE transactional_outbox/);
  assert.doesNotMatch(migration, /user_api_key|authorization_header/i);
});

function makeJobInput(
  overrides: Partial<AgentJobInput> = {},
): AgentJobInput {
  return {
    clientJobID: randomUUID(),
    turnID: randomUUID(),
    sessionID: randomUUID(),
    protocolVersion: 1,
    text: "虚构远程任务",
    contextSnapshot: "最小虚构上下文",
    uploadIDs: [],
    allowedRemoteTools: [],
    allowedDeviceTools: [],
    liveActivityEnabled: true,
    ...overrides,
  };
}

async function registerDevice(
  store: InMemorySomaStore,
  identity: DeviceIdentityService,
  now: Date,
) {
  const keys = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const id = randomUUID();
  const challenge = await identity.createChallenge(now);
  const timestamp = Math.floor(now.getTime() / 1_000);
  const signed = [
    challenge.challenge,
    id,
    "top.hedon.soma",
    "1",
    String(timestamp),
  ].join("\n");
  const tokens = await identity.register(
    {
      challengeID: challenge.challengeID,
      deviceID: id,
      publicKeyPem: keys.publicKey.export({
        type: "spki",
        format: "pem",
      }).toString(),
      signature: sign(
        "sha256",
        Buffer.from(signed),
        keys.privateKey,
      ).toString("base64"),
      timestamp,
      protocolVersion: 1,
    },
    now,
  );
  return {
    id,
    privateKey: keys.privateKey,
    accessToken: tokens.accessToken,
  };
}

async function signedFetch(
  rawURL: string,
  body: Buffer,
  device: Awaited<ReturnType<typeof registerDevice>>,
  now: Date,
  idempotencyKey: string,
) {
  const url = new URL(rawURL);
  const timestamp = String(Math.floor(now.getTime() / 1_000));
  const nonce = randomUUID();
  const digest = sha256(body);
  const canonical = [
    "POST",
    `${url.pathname}${url.search}`,
    timestamp,
    nonce,
    digest,
  ].join("\n");
  return fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${device.accessToken}`,
      "content-type": "application/json",
      "idempotency-key": idempotencyKey,
      "x-soma-device-id": device.id,
      "x-soma-timestamp": timestamp,
      "x-soma-nonce": nonce,
      "x-soma-body-sha256": digest,
      "x-soma-signature": sign(
        "sha256",
        Buffer.from(canonical),
        device.privateKey,
      ).toString("base64"),
    },
    body,
  });
}

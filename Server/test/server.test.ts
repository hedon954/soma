import assert from "node:assert/strict";
import {
  generateKeyPairSync,
  randomUUID,
  sign,
} from "node:crypto";
import { readFile } from "node:fs/promises";
import { afterEach, test } from "node:test";
import { createServer as createHTTPServer } from "node:http";
import type { AddressInfo } from "node:net";
import {
  ActivityPushProjector,
  type APNsProvider,
  OutboxDispatcher,
} from "../src/apns.js";
import { createSomaServer } from "../src/api.js";
import {
  buildGmailMessage,
  feedbackRecipient,
  feedbackSender,
  GmailFeedbackEmailProvider,
  type FeedbackEmailInput,
  type FeedbackEmailProvider,
} from "../src/feedback.js";
import type {
  ActivityToken,
  AgentJobInput,
} from "../src/domain.js";
import {
  InMemoryObjectStore,
} from "../src/object-store.js";
import {
  defaultProviderExtraConfig,
  modelStepRetryDelaysSeconds,
  OpenAICompatibleManagedProvider,
  parseProviderExtraConfig,
} from "../src/provider.js";
import {
  AllowDevelopmentAttestation,
  DeviceIdentityService,
  sha256,
  TokenCipher,
} from "../src/security.js";
import { InMemorySomaStore } from "../src/in-memory-store.js";
import {
  deviceToolRegistry,
  effectiveAllowedDeviceTools,
  normalizeToolArguments,
  validateDeviceTool,
} from "../src/tool-registry.js";
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

test("job and event commits wake waiters without polling", async () => {
  const store = new InMemorySomaStore();
  const jobSignal = store.waitForJobSignal(1_000);
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput(),
    bodyDigest: sha256("wake-job"),
    now: new Date(),
  });
  await jobSignal;

  const lease = await store.claimJob("worker", new Date(), 30);
  assert.ok(lease);
  const eventSignal = store.waitForEventSignal(job.id, 1, 1_000);
  await store.appendEvent(job.id, lease.epoch, {
    kind: "text",
    phase: "updated",
    payloadVersion: 1,
    payload: { delta: "首段" },
    createdAt: new Date(),
  });
  await eventSignal;
});

test("worker projects provider deltas before the terminal output", async () => {
  const store = new InMemorySomaStore();
  const input = makeJobInput();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  const worker = new AgentWorker(store, {
    async run(_job, _events, _media, onTextDelta) {
      await onTextDelta?.("第一段");
      await onTextDelta?.("完成。");
      return { kind: "completed", answer: "第一段完成。" };
    },
  });

  await worker.runOnce();
  const events = await store.events(job.id, 0, 100);

  assert.deepEqual(
    events.filter((event) => event.kind === "text").map((event) => [
      event.phase,
      event.payload.delta ?? null,
    ]),
    [
      ["updated", "第一段"],
      ["updated", "完成。"],
      ["completed", null],
    ],
  );
  assert.equal(events.at(-1)?.kind, "output");
});

test("worker projects reasoning as one stable lifecycle before answer text", async () => {
  const store = new InMemorySomaStore();
  const input = makeJobInput();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  const worker = new AgentWorker(store, {
    async run(_job, _events, _media, onTextDelta, onReasoningDelta) {
      await onReasoningDelta?.("先核对事实，");
      await onReasoningDelta?.("再生成答案。");
      await onTextDelta?.("最终答案。\n");
      return { kind: "completed", answer: "最终答案。" };
    },
  });

  await worker.runOnce();
  const events = await store.events(job.id, 0, 100);
  const reasoning = events.filter((event) => event.kind === "reasoning");

  assert.deepEqual(reasoning.map((event) => event.phase), [
    "updated",
    "updated",
    "completed",
  ]);
  assert.equal(reasoning[0]?.payload.itemID, reasoning[2]?.payload.itemID);
  assert.equal(reasoning[2]?.payload.text, "先核对事实，再生成答案。");
  assert.ok(
    (events.findIndex((event) => event.kind === "reasoning" && event.phase === "completed")) <
      events.findIndex((event) => event.kind === "text" && event.phase === "completed"),
  );
});

test("worker model start records every exposed tool", async () => {
  const store = new InMemorySomaStore();
  const input = makeJobInput({
    allowedRemoteTools: ["load_skill"],
    allowedDeviceTools: ["list_workouts"],
  });
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  const worker = new AgentWorker(store, new DeterministicTestProvider());

  await worker.runOnce();
  const events = await store.events(job.id, 0, 100);
  const modelStart = events.find((event) =>
    event.kind === "model" && event.phase === "started"
  );

  assert.deepEqual(modelStart?.payload.exposedToolNames, [
    "load_skill",
    "list_workouts",
  ]);
  assert.equal(modelStart?.payload.exposedToolCount, 2);
});

test("worker survives process replacement and device tool result is idempotent", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const input = makeJobInput({
    allowedDeviceTools: ["create_workout"],
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
      kind: "toolCalls",
      assistantText: "",
      calls: [{
        toolName: "create_workout",
        schemaVersion: 3,
        arguments: { workouts: [{ exercise_id: 1 }] },
      }],
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

test("queued schema 2 plan tool remains executable after schema 3 becomes current", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const input = makeJobInput({ allowedDeviceTools: ["create_program"] });
  const legacyParameters = {
    type: "object",
    properties: {
      program_name: { type: "string" },
      goal: { type: "string" },
      schedule_hint: { type: "string" },
      template_exercises: {
        type: "array",
        items: {
          type: "object",
          properties: {
            exercise_id: { type: "integer" },
            order: { type: "integer" },
            target_sets: { type: "integer" },
            target_reps: { type: "integer" },
          },
          required: ["exercise_id", "order"],
          additionalProperties: false,
        },
      },
    },
    required: ["program_name", "template_exercises"],
    additionalProperties: false,
  };
  input.modelInput.tools = [{
    name: "create_program",
    schemaVersion: 2,
    definition: {
      type: "function",
      function: {
        name: "create_program",
        parameters: legacyParameters,
      },
    },
  }];
  input.allowedDeviceToolSchemas = [{ name: "create_program", schemaVersion: 2 }];
  const job = await store.submitJob({
    deviceID,
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  const worker = new AgentWorker(store, new DeterministicTestProvider({
    kind: "toolCalls",
    assistantText: "",
    calls: [{
      toolName: "create_program",
      schemaVersion: 2,
      arguments: {
        program_name: "虚构旧计划",
        goal: "兼容恢复",
        schedule_hint: "每周两次",
        template_exercises: [{
          exercise_id: 42,
          order: 1,
          target_sets: 3,
          target_reps: 8,
        }],
      },
    }],
  }));

  assert.equal((await worker.runOnce())?.state, "waitingForDevice");
  const request = (await store.pendingToolRequests(deviceID))[0];
  assert.equal(request?.jobID, job.id);
  assert.equal(request?.schemaVersion, 2);
  assert.equal(request?.toolName, "create_program");
});

test("worker executes submitted custom skills without delegating runtime tools", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const input = makeJobInput({
    allowedRemoteTools: ["load_skill"],
  });
  input.modelInput.skills = [{
    id: "training_plan",
    content: "设备提交的自定义训练计划 Skill",
  }];
  input.modelInput.activeTools = ["load_skill"];
  const job = await store.submitJob({
    deviceID,
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  let run = 0;
  const worker = new AgentWorker(store, {
    async run() {
      run += 1;
      return run === 1
        ? {
            kind: "toolCalls" as const,
            assistantText: "",
            calls: [{
              toolName: "load_skill",
              schemaVersion: 2,
              arguments: { skill_id: "training_plan" },
            }],
          }
        : { kind: "completed" as const, answer: "已使用自定义 Skill。" };
    },
  });

  const queued = await worker.runOnce();
  assert.equal(queued?.state, "queued");
  assert.equal((await store.pendingToolRequests(deviceID)).length, 0);
  const events = await store.events(job.id, 0, 100);
  assert.deepEqual(
    events.filter((event) => event.kind === "tool").map((event) => event.phase),
    ["started", "updated", "completed"],
  );
  const result = events.find((event) =>
    event.kind === "tool" && event.phase === "completed"
  );
  assert.equal(
    (result?.payload.result as { message?: string } | undefined)?.message,
    "设备提交的自定义训练计划 Skill",
  );
  assert.equal((await worker.runOnce())?.state, "completed");
});

test("parallel device tools remain waiting until every result arrives", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const input = makeJobInput({
    allowedDeviceTools: ["search_exercises", "list_programs"],
  });
  const job = await store.submitJob({
    deviceID,
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  const worker = new AgentWorker(
    store,
    new DeterministicTestProvider({
      kind: "toolCalls",
      assistantText: "",
      calls: [
        {
          toolCallID: "call-first",
          toolName: "search_exercises",
          schemaVersion: 2,
          arguments: { query: "深蹲" },
        },
        {
          toolCallID: "call-second",
          toolName: "list_programs",
          schemaVersion: 2,
          arguments: {},
        },
      ],
    }),
  );

  assert.equal((await worker.runOnce())?.state, "waitingForDevice");
  assert.equal((await store.pendingToolRequests(deviceID)).length, 2);
  await store.submitToolResult(deviceID, job.id, {
    toolCallID: "call-second",
    digest: sha256("second"),
    result: { ok: true, code: "ok", message: "second" },
  }, new Date());
  assert.equal((await store.getJob(deviceID, job.id))?.state, "waitingForDevice");
  assert.equal((await store.pendingToolRequests(deviceID)).length, 1);
  await store.submitToolResult(deviceID, job.id, {
    toolCallID: "call-first",
    digest: sha256("first"),
    result: { ok: true, code: "ok", message: "first" },
  }, new Date());
  assert.equal((await store.getJob(deviceID, job.id))?.state, "queued");
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
  assert.equal(
    validateDeviceTool({
      name: "create_meal",
      schemaVersion: 2,
      arguments: {
        title: "虚构午餐",
        total_sugar: 8,
        glycemic_speed: "moderate",
        glycemic_assessment: "混合餐，仅作定性估算。",
        items: [{ name: "虚构豆腐", protein: 12, total_sugar: 1 }],
      },
      allowedNames: ["create_meal"],
    }).mutation,
    true,
  );
  assert.throws(() =>
    validateDeviceTool({
      name: "create_meal",
      schemaVersion: 2,
      arguments: {
        title: "虚构午餐",
        glycemic_speed: "certain-spike",
      },
      allowedNames: ["create_meal"],
    }),
  );
  assert.equal(
    validateDeviceTool({
      name: "submit_feedback",
      schemaVersion: 1,
      arguments: {},
      allowedNames: ["submit_feedback"],
    }).mutation,
    true,
  );
  assert.throws(() =>
    validateDeviceTool({
      name: "submit_feedback",
      schemaVersion: 1,
      arguments: { message: "模型不得提供反馈正文" },
      allowedNames: ["submit_feedback"],
    }),
  );
  assert.throws(() =>
    validateDeviceTool({
      name: "create_workout",
      schemaVersion: 3,
      arguments: { local_path: "/private/file" },
      allowedNames: ["create_workout"],
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

test("numeric tool strings and simple fractions normalize by submitted schema", () => {
  const normalized = normalizeToolArguments({
    record_id: "42",
    protein: "1/3",
    items: [{ name: "虚构食物", fat: "2.5" }],
  }, testToolParameters("update_meal"));

  assert.equal(normalized.record_id, 42);
  assert.equal(normalized.protein, 1 / 3);
  assert.deepEqual(normalized.items, [{ name: "虚构食物", fat: 2.5 }]);

  const conservative = normalizeToolArguments({
    record_id: "1 2",
    protein: "1 / 3",
  }, testToolParameters("update_meal"));
  assert.equal(conservative.record_id, "1 2");
  assert.equal(conservative.protein, 1 / 3);
});

test("worker returns invalid tool arguments to the model for correction", async () => {
  const store = new InMemorySomaStore();
  const deviceID = randomUUID();
  const input = makeJobInput({ allowedDeviceTools: ["update_meal"] });
  const job = await store.submitJob({
    deviceID,
    input,
    bodyDigest: sha256(JSON.stringify(input)),
    now: new Date(),
  });
  let run = 0;
  const worker = new AgentWorker(store, {
    async run(_job, events) {
      run += 1;
      if (run === 1) {
        return {
          kind: "toolCalls" as const,
          assistantText: "",
          calls: [{
            toolCallID: "invalid-call",
            toolName: "update_meal",
            schemaVersion: 2,
            arguments: { record_id: "不是数字", protein: "1/3" },
          }],
        };
      }
      const failedTool = events.find((event) =>
        event.kind === "tool" && event.phase === "failed"
      );
      const result = failedTool?.payload.result as Record<string, unknown>;
      assert.equal(result.code, "invalid_tool_arguments");
      assert.equal(result.retryable, true);
      return { kind: "completed" as const, answer: "已自行修正参数。" };
    },
  });

  assert.equal((await worker.runOnce())?.state, "queued");
  assert.equal((await store.pendingToolRequests(deviceID)).length, 0);
  const firstPassEvents = await store.events(job.id, 0, 100);
  assert.deepEqual(
    firstPassEvents
      .filter((event) => event.kind === "tool")
      .map((event) => event.phase),
    ["started", "failed"],
  );
  assert.equal((await worker.runOnce())?.state, "completed");
  const events = await store.events(job.id, 0, 100);
  assert.equal(
    (events.find((event) => event.kind === "output")?.payload.answer),
    "已自行修正参数。",
  );
});

test("plan schema 3 validates nested prescriptions and keeps schema 2 registered", () => {
  assert.equal(deviceToolRegistry.get("get_program")?.schemaVersion, 3);
  assert.equal(deviceToolRegistry.get("create_program")?.schemaVersion, 3);
  assert.equal(deviceToolRegistry.get("update_program")?.schemaVersion, 3);
  assert.equal(deviceToolRegistry.get("start_program")?.schemaVersion, 2);

  assert.equal(validateDeviceTool({
    name: "create_program",
    schemaVersion: 3,
    arguments: validPlanV3Arguments(),
    allowedNames: ["create_program"],
  }).schemaVersion, 3);
  assert.equal(validateDeviceTool({
    name: "create_program",
    schemaVersion: 2,
    arguments: {
      program_name: "虚构旧计划",
      goal: "旧目标",
      schedule_hint: "每周两次",
      template_exercises: [{
        exercise_id: 7,
        order: 1,
        target_sets: 2,
        target_reps: 8,
      }],
    },
    allowedNames: ["create_program"],
  }).schemaVersion, 2);

  const invalidValues: Record<string, unknown>[] = [
    {
      ...validPlanV3Arguments(),
      template_exercises: [{
        ...validPlanV3Exercise(),
        set_prescriptions: [{
          ...validPlanV3Set(),
          hidden_guess: true,
        }],
      }],
    },
    {
      ...validPlanV3Arguments(),
      template_exercises: [{
        ...validPlanV3Exercise(),
        set_prescriptions: [{ order: 1, kind: "working", target_kind: "repetitions" }],
      }],
    },
    {
      ...validPlanV3Arguments(),
      template_exercises: [{
        ...validPlanV3Exercise(),
        laterality: "alternating",
      }],
    },
    {
      ...validPlanV3Arguments(),
      template_exercises: [{
        ...validPlanV3Exercise(),
        set_prescriptions: [{ ...validPlanV3Set(), target_reps: 0 }],
      }],
    },
    {
      ...validPlanV3Arguments(),
      template_exercises: [{
        ...validPlanV3Exercise(),
        set_prescriptions: [{
          ...validPlanV3Set(),
          target_duration_seconds: 30,
        }],
      }],
    },
    {
      ...validPlanV3Arguments(),
      template_exercises: [{
        ...validPlanV3Exercise(),
        order: "1",
      }],
    },
  ];
  for (const argumentsValue of invalidValues) {
    assert.throws(() => validateDeviceTool({
      name: "create_program",
      schemaVersion: 3,
      arguments: argumentsValue,
      allowedNames: ["create_program"],
    }));
  }
});

test("schema 4 carries workout laterality and keeps schemas 2 and 3 registered", () => {
  assert.equal(deviceToolRegistry.get("search_exercises")?.schemaVersion, 4);
  assert.equal(deviceToolRegistry.get("create_exercise")?.schemaVersion, 4);
  assert.equal(deviceToolRegistry.get("update_exercise")?.schemaVersion, 4);
  assert.equal(deviceToolRegistry.get("create_workout")?.schemaVersion, 4);
  assert.equal(deviceToolRegistry.get("update_workout")?.schemaVersion, 4);

  assert.equal(validateDeviceTool({
    name: "create_exercise",
    schemaVersion: 3,
    arguments: { exercise_names: ["虚构硬拉", "虚构弹力带抗旋"] },
    allowedNames: ["create_exercise"],
  }).schemaVersion, 3);
  assert.equal(validateDeviceTool({
    name: "create_exercise",
    schemaVersion: 2,
    arguments: { exercise_name: "虚构硬拉" },
    allowedNames: ["create_exercise"],
  }).schemaVersion, 2);
  assert.equal(validateDeviceTool({
    name: "create_exercise",
    schemaVersion: 4,
    arguments: {
      exercises: [{
        exercise_name: "虚构保加利亚分腿蹲",
        target_kind: "repetitions",
        laterality: "both",
      }],
    },
    allowedNames: ["create_exercise"],
  }).schemaVersion, 4);
  const pairedWorkout = {
    workouts: [{
      exercise_id: 7,
      target_kind: "repetitions",
      laterality: "both",
      set_entries: [
        {
          logical_set_index: 1,
          side: "left",
          target_kind: "repetitions",
          reps: 12,
          external_weight_kg: 0,
          rest_seconds: 30,
        },
        {
          logical_set_index: 1,
          side: "right",
          target_kind: "repetitions",
          reps: 12,
          external_weight_kg: 0,
          rest_seconds: 60,
        },
      ],
    }],
  };
  assert.equal(validateDeviceTool({
    name: "create_workout",
    schemaVersion: 4,
    arguments: pairedWorkout,
    allowedNames: ["create_workout"],
  }).schemaVersion, 4);
  assert.throws(() => validateDeviceTool({
    name: "create_workout",
    schemaVersion: 4,
    arguments: {
      workouts: [{ ...pairedWorkout.workouts[0], laterality: "none" }],
    },
    allowedNames: ["create_workout"],
  }));
  assert.equal(validateDeviceTool({
    name: "create_workout",
    schemaVersion: 3,
    arguments: {
      workouts: [{
        exercise_id: 7,
        set_entries: [{ reps: 5, external_weight_kg: 60 }],
      }],
    },
    allowedNames: ["create_workout"],
  }).schemaVersion, 3);
  assert.equal(validateDeviceTool({
    name: "create_workout",
    schemaVersion: 2,
    arguments: {
      exercise_id: 7,
      set_entries: [{ reps: 8, external_weight_kg: 20 }],
    },
    allowedNames: ["create_workout"],
  }).schemaVersion, 2);

  assert.throws(() => validateDeviceTool({
    name: "create_workout",
    schemaVersion: 3,
    arguments: { exercise_id: 7 },
    allowedNames: ["create_workout"],
  }));
  assert.throws(() => validateDeviceTool({
    name: "create_workout",
    schemaVersion: 3,
    arguments: { workouts: [{ exercise_id: 7, record_id: 99 }] },
    allowedNames: ["create_workout"],
  }));
  assert.throws(() => validateDeviceTool({
    name: "create_workout",
    schemaVersion: 3,
    arguments: { workouts: [] },
    allowedNames: ["create_workout"],
  }));
});

test("envelope active tools stay as submitted", () => {
  const toolCallID = randomUUID();
  const now = new Date();
  const active = effectiveAllowedDeviceTools(
    ["load_skill", "list_workouts"],
    [
      {
        id: randomUUID(),
        jobID: randomUUID(),
        sequence: 1,
        kind: "tool",
        phase: "completed",
        payloadVersion: 1,
        payload: {
          toolCallID,
          toolName: "update_gym",
          arguments: {},
        },
        createdAt: now,
      },
    ],
  );

  assert.deepEqual(active, ["load_skill", "list_workouts"]);
  assert.ok(!active.includes("update_gym"));
});

test("managed provider streams text before completion and limits media", async () => {
  const store = new InMemorySomaStore();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput({
      allowedDeviceTools: ["search_exercises"],
      modelInput: makeModelInput(
        ["current-image-0"],
        ["search_exercises"],
      ),
    }),
    bodyDigest: sha256("media"),
    now: new Date(),
  });
  let captured: Record<string, unknown> | undefined;
  const deltas: string[] = [];
  const provider = new OpenAICompatibleManagedProvider(
    "https://provider.invalid/v1",
    "test-key",
    "test-model",
    async (_input, init) => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      const encoder = new TextEncoder();
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(encoder.encode(
            'data: {"choices":[{"delta":{"content":"已分析"}}]}\n\n',
          ));
          controller.enqueue(encoder.encode(
            'data: {"choices":[{"delta":{"content":"可见关键帧。"},"finish_reason":"stop"}],"usage":{"prompt_tokens":4,"completion_tokens":3}}\n\n',
          ));
          controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          controller.close();
        },
      });
      return new Response(body, {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
    },
  );

  const step = await provider.run(
    job,
    [],
    [
      { id: "current-image-0", contentType: "image/jpeg", url: "https://signed.invalid/frame.jpg" },
      { id: "unused-video", contentType: "video/mp4", url: "https://signed.invalid/original.mp4" },
    ],
    async (delta) => {
      deltas.push(delta);
    },
  );

  const messages = captured?.messages as Record<string, unknown>[];
  const content = messages[1]?.content as Record<string, unknown>[];
  assert.equal(messages[0]?.content, "统一系统提示词");
  const tools = captured?.tools as Record<string, unknown>[];
  assert.match(JSON.stringify(tools), /统一 search_exercises 定义/);
  assert.equal(captured?.tool_choice, "auto");
  assert.equal(captured?.parallel_tool_calls, true);
  assert.equal(
    content.filter((part) => part.type === "image_url").length,
    1,
  );
  assert.match(
    String(content[0]?.text),
    /关键帧不足以证明完整动作轨迹/,
  );
  assert.doesNotMatch(JSON.stringify(captured), /original\.mp4/);
  assert.equal(captured?.stream, true);
  assert.deepEqual(deltas, ["已分析", "可见关键帧。"]);
  assert.deepEqual(step, {
    kind: "completed",
    answer: "已分析可见关键帧。",
    usage: { input: 4, output: 3 },
  });
});

test("managed provider streams reasoning separately from answer text", async () => {
  const store = new InMemorySomaStore();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput(),
    bodyDigest: sha256("reasoning-stream"),
    now: new Date(),
  });
  let captured: Record<string, unknown> | undefined;
  const provider = new OpenAICompatibleManagedProvider(
    "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "test-key",
    "qwen3.5-plus",
    async (_input, init) => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      const encoder = new TextEncoder();
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(encoder.encode(
            'data: {"choices":[{"delta":{"reasoning_content":"分析中。"}}]}\n\n',
          ));
          controller.enqueue(encoder.encode(
            'data: {"choices":[{"delta":{"content":"答案。"},"finish_reason":"stop"}]}\n\n',
          ));
          controller.enqueue(encoder.encode("data: [DONE]\n\n"));
          controller.close();
        },
      });
      return new Response(body, {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
    },
  );
  const text: string[] = [];
  const reasoning: string[] = [];

  const step = await provider.run(
    job,
    [],
    [],
    async (delta) => {
      text.push(delta);
    },
    async (delta) => {
      reasoning.push(delta);
    },
  );

  assert.deepEqual(reasoning, ["分析中。"]);
  assert.deepEqual(text, ["答案。"]);
  assert.equal(captured?.enable_thinking, false);
  assert.deepEqual(step, {
    kind: "completed",
    answer: "答案。",
    usage: { input: 0, output: 0 },
  });
});

test("managed provider extra config defaults and validation stay provider-specific", () => {
  assert.deepEqual(
    defaultProviderExtraConfig("https://openrouter.ai/api/v1", "provider/model"),
    { reasoning: { enabled: false } },
  );
  assert.deepEqual(
    parseProviderExtraConfig('{"reasoning":{"enabled":true},"top_k":32}'),
    { reasoning: { enabled: true }, top_k: 32 },
  );
  assert.throws(() => parseProviderExtraConfig('{"stream":false}'));
  assert.throws(() => parseProviderExtraConfig("[]"));
});

test("explicit direct-video capability sends video without duplicate frames", async () => {
  const store = new InMemorySomaStore();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput({
      modelInput: makeModelInput(["current-video-0"]),
    }),
    bodyDigest: sha256("direct-video"),
    now: new Date(),
  });
  let captured: Record<string, unknown> | undefined;
  const provider = new OpenAICompatibleManagedProvider(
    "https://provider.invalid/v1",
    "test-key",
    "qwen3-vl-plus",
    async (_input, init) => {
      captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(
            'data: {"choices":[{"delta":{"content":"完整视频结果"},"finish_reason":"stop"}]}\n\n',
          ));
          controller.close();
        },
      });
      return new Response(body, {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
    },
    undefined,
    true,
  );

  await provider.run(job, [], [
    { id: "current-video-0", contentType: "video/mp4", url: "https://signed.invalid/video.mp4" },
    { id: "unused-frame", contentType: "image/jpeg", url: "https://signed.invalid/frame.jpg" },
  ]);

  const messages = captured?.messages as Record<string, unknown>[];
  const content = messages[1]?.content as Record<string, unknown>[];
  assert.equal(content.filter((part) => part.type === "video_url").length, 1);
  assert.equal(content.filter((part) => part.type === "image_url").length, 0);
  assert.match(JSON.stringify(captured), /video\.mp4/);
  assert.doesNotMatch(JSON.stringify(captured), /frame\.jpg/);
});

test("remote model step uses three retries and video fallback stays in that budget", async () => {
  const store = new InMemorySomaStore();
  const directJob = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput({
      mediaMode: "direct_video",
      requestAttempt: 1,
      modelInput: makeModelInput(["current-video-0", "current-video-frame-0"]),
    }),
    bodyDigest: sha256("direct-video-failure"),
    now: new Date(),
  });
  const capturedBodies: Record<string, unknown>[] = [];
  const retryDelays: number[] = [];
  const directProvider = new OpenAICompatibleManagedProvider(
    "https://provider.invalid/v1",
    "test-key",
    "qwen3-vl-plus",
    async (_input, init) => {
      capturedBodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      if (capturedBodies.length <= modelStepRetryDelaysSeconds.length) {
        return new Response("unavailable", { status: 503 });
      }
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(
            'data: {"choices":[{"delta":{"content":"关键帧结果"},"finish_reason":"stop"}]}\n\n',
          ));
          controller.close();
        },
      });
      return new Response(body, {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
    },
    async (seconds) => {
      retryDelays.push(seconds);
    },
    true,
  );

  const step = await directProvider.run(directJob, [], [
    { id: "current-video-0", contentType: "video/mp4", url: "https://signed.invalid/video.mp4" },
    { id: "current-video-frame-0", contentType: "image/jpeg", url: "https://signed.invalid/frame.jpg" },
  ]);

  assert.equal(capturedBodies.length, 4);
  assert.deepEqual(retryDelays, [1, 2, 4]);
  assert.deepEqual(step, {
    kind: "completed",
    answer: "关键帧结果",
    usage: { input: 0, output: 0 },
  });
  assert.match(JSON.stringify(capturedBodies[0]), /video\.mp4/);
  assert.doesNotMatch(JSON.stringify(capturedBodies[0]), /frame\.jpg/);
  for (const body of capturedBodies.slice(1)) {
    assert.match(JSON.stringify(body), /frame\.jpg/);
    assert.doesNotMatch(JSON.stringify(body), /video\.mp4/);
  }
});

test("remote model step stops after the third retry", async () => {
  const store = new InMemorySomaStore();
  const job = await store.submitJob({
    deviceID: randomUUID(),
    input: makeJobInput(),
    bodyDigest: sha256("remote-retry-exhausted"),
    now: new Date(),
  });
  let calls = 0;
  const retryDelays: number[] = [];
  const provider = new OpenAICompatibleManagedProvider(
    "https://provider.invalid/v1",
    "test-key",
    "test-model",
    async () => {
      calls += 1;
      return new Response("unavailable", { status: 503 });
    },
    async (seconds) => {
      retryDelays.push(seconds);
    },
  );

  await assert.rejects(provider.run(job, [], []));
  assert.equal(calls, 4);
  assert.deepEqual(retryDelays, [1, 2, 4]);
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

test("authenticated feedback sends exact text and media then deletes upload", async () => {
  const store = new InMemorySomaStore();
  const now = new Date("2026-08-09T00:00:00Z");
  const identity = new DeviceIdentityService(
    store,
    "test-secret-that-is-at-least-thirty-two-characters",
    new AllowDevelopmentAttestation(),
  );
  const device = await registerDevice(store, identity, now);
  const content = Buffer.from("synthetic feedback image");
  const uploadID = randomUUID();
  const objectKey = `temporary/${uploadID}`;
  await store.saveUpload({
    id: uploadID,
    deviceID: device.id,
    contentType: "image/png",
    expectedBytes: content.length,
    expectedDigest: sha256(content),
    objectKey,
    createdAt: now,
  });
  await store.completeUpload(
    device.id,
    uploadID,
    content.length,
    sha256(content),
    now,
  );
  const objects = new FeedbackObjectStore(
    new Map([[objectKey, content]]),
  );
  const feedback = new CapturingFeedbackProvider();
  const server = createSomaServer({
    store,
    identity,
    objects,
    feedback,
    tokenCipher: new TokenCipher(Buffer.alloc(32, 7).toString("base64")),
    now: () => now,
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  const feedbackID = randomUUID();
  const body = Buffer.from(JSON.stringify({
    feedbackID,
    protocolVersion: 1,
    message: "  这是虚构反馈。  ",
    uploadIDs: [uploadID],
  }));
  const response = await signedFetch(
    `http://127.0.0.1:${port}/v1/feedback`,
    body,
    device,
    now,
    feedbackID,
  );
  const result = (await response.json()) as {
    feedbackID: string;
    accepted: boolean;
  };

  assert.equal(response.status, 201);
  assert.equal(result.feedbackID, feedbackID);
  assert.equal(result.accepted, true);
  assert.equal(feedback.inputs.length, 1);
  assert.equal(feedback.inputs[0]?.message, "这是虚构反馈。");
  assert.equal(
    feedback.inputs[0]?.idempotencyKey,
    `feedback/${device.id}/${feedbackID}`,
  );
  assert.equal(feedback.inputs[0]?.attachments[0]?.filename, "feedback-1.png");
  assert.deepEqual(feedback.inputs[0]?.attachments[0]?.content, content);
  assert.deepEqual(objects.deletedKeys, [objectKey]);
  assert.equal((await store.getUploads(device.id, [uploadID])).length, 0);
});

test("Gmail feedback delivery refreshes OAuth and sends from the fixed mailbox", async () => {
  let capturedTokenBody = "";
  let capturedHeaders: Record<string, string | string[] | undefined> = {};
  let capturedMessage = Buffer.alloc(0);
  const deliveryServer = createHTTPServer(async (request, response) => {
    const chunks: Buffer[] = [];
    for await (const chunk of request) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    if (request.url === "/token") {
      capturedTokenBody = Buffer.concat(chunks).toString("utf8");
      response.writeHead(200, { "content-type": "application/json" });
      response.end('{"access_token":"gmail-access-token"}');
      return;
    }
    capturedHeaders = request.headers;
    capturedMessage = Buffer.concat(chunks);
    response.writeHead(200, { "content-type": "application/json" });
    response.end('{"id":"gmail-message-id"}');
  });
  servers.push(deliveryServer);
  await new Promise<void>((resolve) =>
    deliveryServer.listen(0, "127.0.0.1", resolve)
  );
  const port = (deliveryServer.address() as AddressInfo).port;
  const provider = new GmailFeedbackEmailProvider(
    "test-client-id",
    "test-client-secret",
    "test-refresh-token",
    `http://127.0.0.1:${port}/token`,
    `http://127.0.0.1:${port}/send?uploadType=media`,
  );

  const input: FeedbackEmailInput = {
    idempotencyKey: "feedback/device/id",
    message: "虚构反馈",
    attachments: [{
      filename: "feedback-1.jpg",
      contentType: "image/jpeg",
      content: Buffer.from("image"),
    }],
  };
  await provider.send(input);

  const tokenForm = new URLSearchParams(capturedTokenBody);
  assert.equal(tokenForm.get("client_id"), "test-client-id");
  assert.equal(tokenForm.get("client_secret"), "test-client-secret");
  assert.equal(tokenForm.get("refresh_token"), "test-refresh-token");
  assert.equal(tokenForm.get("grant_type"), "refresh_token");
  assert.equal(capturedHeaders.authorization, "Bearer gmail-access-token");
  assert.equal(capturedHeaders["content-type"], "message/rfc822");
  const mime = capturedMessage.toString("utf8");
  assert.match(mime, new RegExp(`^From: ${feedbackSender}\\r$`, "m"));
  assert.match(mime, new RegExp(`^To: ${feedbackRecipient}\\r$`, "m"));
  assert.match(mime, /^Subject: =\?UTF-8\?B\?.+\?=\r$/m);
  assert.match(mime, /filename="feedback-1.jpg"/);
  assert.ok(mime.includes(Buffer.from("虚构反馈").toString("base64")));
  assert.ok(mime.includes(Buffer.from("image").toString("base64")));
  assert.deepEqual(buildGmailMessage(input), capturedMessage);
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

test("performance migration indexes cleanup and erasure paths without duplicate cursor index", async () => {
  const migration = await readFile(
    new URL("../migrations/002_performance_indexes.sql", import.meta.url),
    "utf8",
  );

  assert.match(migration, /request_nonces \(expires_at\)/);
  assert.match(migration, /device_registration_challenges \(expires_at\)/);
  assert.match(migration, /devices \(revoked_at\)[\s\S]*WHERE revoked_at IS NOT NULL/);
  assert.match(migration, /activity_tokens \(device_id\)/);
  assert.match(migration, /transactional_outbox \(aggregate_id\)/);
  assert.match(migration, /DROP INDEX IF EXISTS agent_events_cursor_idx/);
  assert.doesNotMatch(migration, /agent_tool_requests \(expires_at\)/);
});

function makeJobInput(
  overrides: Partial<AgentJobInput> = {},
): AgentJobInput {
  const allowedRemoteTools = overrides.allowedRemoteTools ?? [];
  const allowedDeviceTools = overrides.allowedDeviceTools ?? [];
  const input: AgentJobInput = {
    clientJobID: randomUUID(),
    turnID: randomUUID(),
    sessionID: randomUUID(),
    protocolVersion: 1,
    modelInput: overrides.modelInput ?? makeModelInput(
      [],
      [...allowedRemoteTools, ...allowedDeviceTools],
    ),
    mediaBindings: [],
    uploadIDs: [],
    mediaMode: "text",
    requestAttempt: 1,
    allowedRemoteTools,
    allowedDeviceTools,
    allowedDeviceToolSchemas: allowedDeviceTools.map((name) => ({
      name,
      schemaVersion: testToolSchemaVersion(name),
    })),
    liveActivityEnabled: true,
    ...overrides,
  };
  return input;
}

function makeModelInput(
  mediaIDs: string[] = [],
  toolNames: string[] = [],
): AgentJobInput["modelInput"] {
  return {
    schemaVersion: 2,
    messages: [
      { role: "system", text: "统一系统提示词", mediaIDs: [] },
      {
        role: "user",
        text: "[SOMA CURRENT TURN v1]\n虚构远程任务\n关键帧不足以证明完整动作轨迹。",
        mediaIDs,
      },
    ],
    skills: [{ id: "training_plan", content: "自定义训练计划 Skill" }],
    tools: toolNames.map((name) => ({
      name,
      schemaVersion: testToolSchemaVersion(name),
      definition: {
        type: "function",
        function: {
          name,
          description: `统一 ${name} 定义`,
          parameters: testToolParameters(name),
        },
      },
    })),
    activeTools: toolNames,
    runtime: {
      toolChoice: "auto",
      parallelToolCalls: true,
      maxSteps: 100,
      deadlines: {
        textTTFT: 20,
        imageTTFT: 40,
        directVideoTTFT: 60,
        textLoopTotal: 180,
        imageLoopTotal: 300,
        videoLoopTotal: 600,
      },
    },
  };
}

function testToolSchemaVersion(name: string): number {
  if ([
    "get_program",
    "create_program",
    "update_program",
    "create_exercise",
    "create_workout",
  ].includes(name)) {
    return 3;
  }
  return 2;
}

function testToolParameters(name: string): Record<string, unknown> {
  if (name === "get_program") {
    return {
      type: "object",
      properties: { program_id: { type: "integer" } },
      required: ["program_id"],
      additionalProperties: false,
    };
  }
  if (["create_program", "update_program"].includes(name)) {
    return {
      type: "object",
      properties: {
        ...(name === "create_program"
          ? { program_name: { type: "string" } }
          : { program_id: { type: "integer" } }),
        schedule_hint: { type: "string" },
        template_exercises: {
          type: "array",
          items: {
            type: "object",
            properties: {
              exercise_id: { type: "integer" },
              order: { type: "integer" },
              laterality: { type: "string", enum: ["none", "both", "left", "right"] },
              set_prescriptions: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    order: { type: "integer" },
                    kind: { type: "string", enum: ["warmup", "working"] },
                    target_kind: { type: "string", enum: ["repetitions", "duration"] },
                    target_reps: { type: "integer" },
                    target_duration_seconds: { type: "integer" },
                  },
                  required: ["order", "kind", "target_kind"],
                  additionalProperties: false,
                },
              },
            },
            required: ["exercise_id", "order", "laterality", "set_prescriptions"],
            additionalProperties: false,
          },
        },
      },
      required: [
        name === "create_program" ? "program_name" : "program_id",
        "template_exercises",
      ],
      additionalProperties: false,
    };
  }
  if (name === "create_workout") {
    return {
      type: "object",
      properties: {
        workouts: {
          type: "array",
          items: {
            type: "object",
            properties: { exercise_id: { type: "integer" } },
            required: ["exercise_id"],
            additionalProperties: false,
          },
        },
      },
      required: ["workouts"],
      additionalProperties: false,
    };
  }
  if (name === "search_exercises") {
    return {
      type: "object",
      properties: {
        query: { type: "string" },
        limit: { type: "integer" },
      },
      required: ["query"],
      additionalProperties: false,
    };
  }
  if (name === "update_meal") {
    return {
      type: "object",
      properties: {
        record_id: { type: "integer" },
        protein: { type: "number" },
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              fat: { type: "number" },
            },
            required: ["name"],
            additionalProperties: false,
          },
        },
      },
      required: ["record_id"],
      additionalProperties: false,
    };
  }
  if (name === "load_skill") {
    return {
      type: "object",
      properties: { skill_id: { type: "string" } },
      required: ["skill_id"],
    };
  }
  return { type: "object", properties: {} };
}

function validPlanV3Set(): Record<string, unknown> {
  return {
    order: 1,
    kind: "working",
    target_kind: "repetitions",
    target_reps: 8,
    left_weight_kg: 20,
    right_weight_kg: 22.5,
  };
}

function validPlanV3Exercise(): Record<string, unknown> {
  return {
    exercise_id: 7,
    order: 1,
    laterality: "both",
    target_rest_seconds: 90,
    rest_between_sides_seconds: 15,
    set_prescriptions: [validPlanV3Set()],
  };
}

function validPlanV3Arguments(): Record<string, unknown> {
  return {
    program_name: "虚构逐组计划",
    overview: "左右独立，保持缺失事实为空。",
    schedule_hint: "每周两次",
    template_exercises: [validPlanV3Exercise()],
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

class FeedbackObjectStore extends InMemoryObjectStore {
  constructor(private readonly contents: Map<string, Buffer>) {
    super();
  }

  override async readObject(objectKey: string): Promise<Buffer> {
    const content = this.contents.get(objectKey);
    assert.ok(content);
    return content;
  }
}

class CapturingFeedbackProvider implements FeedbackEmailProvider {
  readonly inputs: FeedbackEmailInput[] = [];

  async send(input: FeedbackEmailInput): Promise<void> {
    this.inputs.push(input);
  }
}

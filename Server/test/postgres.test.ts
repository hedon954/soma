import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { after, test } from "node:test";
import { Pool } from "pg";
import type { AgentJobInput } from "../src/domain.js";
import { PostgresSomaStore } from "../src/postgres-store.js";
import { sha256 } from "../src/security.js";

const databaseURL = process.env.SOMA_TEST_DATABASE_URL;
const pool = databaseURL === undefined
  ? undefined
  : new Pool({ connectionString: databaseURL, max: 12 });

after(async () => {
  await pool?.end();
});

test(
  "PostgreSQL store preserves idempotency, leases, events and terminal races",
  { skip: databaseURL === undefined ? "SOMA_TEST_DATABASE_URL 未设置" : false },
  async () => {
    assert.ok(pool);
    const migration = await readFile(
      new URL("../migrations/001_initial.sql", import.meta.url),
      "utf8",
    );
    await pool.query(migration);
    const store = new PostgresSomaStore(pool);
    const now = new Date("2026-07-31T00:00:00Z");
    const deviceID = randomUUID();
    await store.saveDevice(deviceID, "test-public-key", undefined, now);

    const uploadID = randomUUID();
    const uploadDigest = sha256("temporary-media");
    await store.saveUpload({
      id: uploadID,
      deviceID,
      contentType: "image/jpeg",
      expectedBytes: 15,
      expectedDigest: uploadDigest,
      objectKey: `temporary/${uploadID}`,
      createdAt: now,
    });
    await store.completeUpload(
      deviceID,
      uploadID,
      15,
      uploadDigest,
      now,
    );
    const input = makeJobInput({ uploadIDs: [uploadID] });
    const submission = {
      deviceID,
      input,
      bodyDigest: sha256(JSON.stringify(input)),
      now,
    };
    const duplicateJobs = await Promise.all(
      Array.from({ length: 12 }, () => store.submitJob(submission)),
    );
    assert.equal(new Set(duplicateJobs.map((job) => job.id)).size, 1);
    const job = duplicateJobs[0];
    assert.ok(job);
    await assert.rejects(
      store.submitJob({ ...submission, bodyDigest: sha256("different") }),
      /不同内容/,
    );

    const lease = await store.claimJob("integration-worker", now, 30);
    assert.ok(lease);
    assert.equal(lease.job.id, job.id);
    const modelEvent = await store.appendEvent(job.id, lease.epoch, {
      kind: "model",
      phase: "started",
      payloadVersion: 1,
      payload: { provider: "test" },
      createdAt: now,
    });
    assert.equal(modelEvent.sequence, 2);

    const toolCallID = randomUUID();
    const tool = await store.saveToolRequest(
      {
        jobID: job.id,
        toolCallID,
        toolName: "list_exercise_names",
        schemaVersion: 1,
        arguments: {},
        mutation: false,
        expiresAt: new Date(now.getTime() + 60_000),
      },
      now,
      lease.epoch,
    );
    assert.equal(tool.toolCallID, toolCallID);
    await assert.rejects(
      store.saveToolRequest(
        {
          ...tool,
          toolName: "record_workout",
        },
        now,
        lease.epoch,
      ),
      /不同请求/,
    );

    const result = {
      toolCallID,
      digest: sha256("{}"),
      result: {},
    };
    await store.submitToolResult(deviceID, job.id, result, now);
    const replay = await store.submitToolResult(
      deviceID,
      job.id,
      result,
      now,
    );
    assert.equal(replay.resultDigest, result.digest);
    const resumed = await store.claimJob("replacement-worker", now, 30);
    assert.ok(resumed);
    assert.equal(resumed.job.id, job.id);
    await store.appendEvent(job.id, resumed.epoch, {
      kind: "output",
      phase: "completed",
      payloadVersion: 1,
      payload: { answer: "完成" },
      createdAt: now,
    });
    const completed = await store.transition(
      job.id,
      "completed",
      now,
      resumed.epoch,
    );
    assert.equal(completed.state, "completed");

    const raceInput = makeJobInput();
    const raceJob = await store.submitJob({
      deviceID,
      input: raceInput,
      bodyDigest: sha256(JSON.stringify(raceInput)),
      now: new Date(now.getTime() + 1),
    });
    const raceLease = await store.claimJob(
      "race-worker",
      new Date(now.getTime() + 1),
      30,
    );
    assert.ok(raceLease);
    const terminalResults = await Promise.all([
      store.cancelJob(deviceID, raceJob.id, new Date(now.getTime() + 2)),
      store.transition(
        raceJob.id,
        "completed",
        new Date(now.getTime() + 2),
        raceLease.epoch,
      ),
    ]);
    assert.equal(new Set(terminalResults.map((value) => value.state)).size, 1);
    const terminalEvents = await store.events(raceJob.id, 0, 100);
    assert.ok(
      terminalEvents.filter((event) => event.phase === "cancelled").length <= 1,
    );

    const firstClaim = await store.outboxBatch(
      new Date(now.getTime() + 10_000),
      100,
    );
    const secondClaim = await store.outboxBatch(
      new Date(now.getTime() + 10_000),
      100,
    );
    const allIDs = [...firstClaim, ...secondClaim].map((message) => message.id);
    assert.equal(new Set(allIDs).size, allIDs.length);
    assert.ok(firstClaim.every((message) => message.attemptCount === 1));

    await store.acknowledge(deviceID, job.id, 10_000);
    const cleanup = await store.cleanup(
      new Date(now.getTime() + 25 * 60 * 60 * 1_000),
    );
    assert.ok(cleanup.deletedContentJobIDs.includes(job.id));
    assert.deepEqual(cleanup.objectKeys, [`temporary/${uploadID}`]);
    assert.deepEqual(await store.events(job.id, 0, 100), []);
    assert.equal((await store.getJob(deviceID, job.id))?.input, undefined);
  },
);

function makeJobInput(
  overrides: Partial<AgentJobInput> = {},
): AgentJobInput {
  return {
    clientJobID: randomUUID(),
    turnID: randomUUID(),
    sessionID: randomUUID(),
    protocolVersion: 1,
    text: "虚构 PostgreSQL 集成任务",
    contextSnapshot: "最小虚构上下文",
    uploadIDs: [],
    allowedRemoteTools: [],
    allowedDeviceTools: ["list_exercise_names"],
    liveActivityEnabled: true,
    ...overrides,
  };
}

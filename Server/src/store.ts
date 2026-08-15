import { randomUUID } from "node:crypto";
import { canonicalJSON } from "./canonical-json.js";
import type {
  ActivityToken,
  AgentEvent,
  AgentJob,
  JobLease,
  JobSubmission,
  OutboxMessage,
  RegistrationChallenge,
  TerminalJobState,
  ToolRequest,
  ToolResultSubmission,
  Upload,
} from "./domain.js";
import { isTerminal, ProtocolError } from "./domain.js";

export interface CleanupResult {
  deletedContentJobIDs: string[];
  expiredJobIDs: string[];
  deletedMetadataJobIDs: string[];
  objectKeys: string[];
}

export interface SomaStore {
  saveChallenge(challenge: RegistrationChallenge): Promise<void>;
  consumeChallenge(id: string, now: Date): Promise<RegistrationChallenge>;
  saveDevice(
    id: string,
    publicKeyPem: string,
    attestationKeyID: string | undefined,
    now: Date,
  ): Promise<void>;
  devicePublicKey(id: string): Promise<string | undefined>;
  revokeDevice(id: string, now: Date): Promise<void>;
  consumeNonce(deviceID: string, nonce: string, expiresAt: Date): Promise<boolean>;
  submitJob(submission: JobSubmission): Promise<AgentJob>;
  getJob(deviceID: string, jobID: string): Promise<AgentJob | undefined>;
  events(jobID: string, after: number, limit: number): Promise<AgentEvent[]>;
  waitForJobSignal(timeoutMilliseconds: number): Promise<void>;
  waitForEventSignal(
    jobID: string,
    afterSequence: number,
    timeoutMilliseconds: number,
  ): Promise<void>;
  claimJob(owner: string, now: Date, leaseSeconds: number): Promise<JobLease | undefined>;
  renewLease(
    jobID: string,
    owner: string,
    epoch: number,
    now: Date,
    leaseSeconds: number,
  ): Promise<boolean>;
  appendEvent(
    jobID: string,
    leaseEpoch: number | undefined,
    event: Omit<AgentEvent, "id" | "jobID" | "sequence">,
  ): Promise<AgentEvent>;
  transition(
    jobID: string,
    state: AgentJob["state"],
    now: Date,
    leaseEpoch?: number,
    errorCode?: string,
  ): Promise<AgentJob>;
  saveToolRequest(
    request: Omit<ToolRequest, "id">,
    now: Date,
    leaseEpoch: number,
  ): Promise<ToolRequest>;
  pendingToolRequests(deviceID: string): Promise<ToolRequest[]>;
  submitToolResult(
    deviceID: string,
    jobID: string,
    submission: ToolResultSubmission,
    now: Date,
  ): Promise<ToolRequest>;
  cancelJob(deviceID: string, jobID: string, now: Date): Promise<AgentJob>;
  acknowledge(deviceID: string, jobID: string, sequence: number): Promise<void>;
  saveUpload(upload: Upload): Promise<void>;
  completeUpload(
    deviceID: string,
    uploadID: string,
    bytes: number,
    digest: string,
    now: Date,
  ): Promise<Upload>;
  getUploads(deviceID: string, ids: string[]): Promise<Upload[]>;
  deleteUpload(
    deviceID: string,
    uploadID: string,
    now: Date,
  ): Promise<string | undefined>;
  saveActivityToken(token: ActivityToken): Promise<void>;
  activityToken(jobID: string): Promise<ActivityToken | undefined>;
  deleteActivityToken(jobID: string): Promise<void>;
  outboxBatch(now: Date, limit: number): Promise<OutboxMessage[]>;
  markOutboxPublished(id: string, now: Date): Promise<void>;
  markOutboxRetry(id: string, nextAttemptAt: Date): Promise<void>;
  cleanup(now: Date): Promise<CleanupResult>;
  deleteDeviceData(deviceID: string, now: Date): Promise<string[]>;
}

export class InMemorySomaStore implements SomaStore {
  private challenges = new Map<string, RegistrationChallenge>();
  private devices = new Map<
    string,
    {
      publicKeyPem: string;
      attestationKeyID?: string;
      revokedAt?: Date;
    }
  >();
  private nonces = new Set<string>();
  private jobs = new Map<string, AgentJob>();
  private jobByClientKey = new Map<string, string>();
  private eventRows = new Map<string, AgentEvent[]>();
  private tools = new Map<string, ToolRequest>();
  private uploads = new Map<string, Upload>();
  private activityTokens = new Map<string, ActivityToken>();
  private outbox = new Map<string, OutboxMessage>();
  private jobWaiters = new Set<() => void>();
  private eventWaiters = new Map<
    string,
    Set<{ afterSequence: number; resolve: () => void }>
  >();

  async saveChallenge(challenge: RegistrationChallenge): Promise<void> {
    this.challenges.set(challenge.id, structuredClone(challenge));
  }

  async consumeChallenge(id: string, now: Date): Promise<RegistrationChallenge> {
    const challenge = this.challenges.get(id);
    if (
      challenge === undefined ||
      challenge.consumedAt !== undefined ||
      challenge.expiresAt <= now
    ) {
      throw new ProtocolError("invalid_request", "注册挑战无效或已过期。", 400);
    }
    challenge.consumedAt = now;
    return structuredClone(challenge);
  }

  async saveDevice(
    id: string,
    publicKeyPem: string,
    attestationKeyID: string | undefined,
    _now: Date,
  ): Promise<void> {
    this.devices.set(id, {
      publicKeyPem,
      ...(attestationKeyID === undefined ? {} : { attestationKeyID }),
    });
  }

  async devicePublicKey(id: string): Promise<string | undefined> {
    const device = this.devices.get(id);
    return device?.revokedAt === undefined ? device?.publicKeyPem : undefined;
  }

  async revokeDevice(id: string, now: Date): Promise<void> {
    const device = this.devices.get(id);
    if (device !== undefined) device.revokedAt = now;
  }

  async consumeNonce(
    deviceID: string,
    nonce: string,
    _expiresAt: Date,
  ): Promise<boolean> {
    const key = `${deviceID}|${nonce}`;
    if (this.nonces.has(key)) return false;
    this.nonces.add(key);
    return true;
  }

  async submitJob(submission: JobSubmission): Promise<AgentJob> {
    const clientKey = `${submission.deviceID}|${submission.input.clientJobID}`;
    const existingID = this.jobByClientKey.get(clientKey);
    if (existingID !== undefined) {
      const existing = this.jobs.get(existingID);
      if (existing === undefined) throw new Error("job index corruption");
      if (existing.bodyDigest !== submission.bodyDigest) {
        throw new ProtocolError(
          "idempotency_conflict",
          "相同 clientJobID 对应了不同内容。",
          409,
        );
      }
      return structuredClone(existing);
    }
    const uploads = await this.getUploads(
      submission.deviceID,
      submission.input.uploadIDs,
    );
    if (
      uploads.length !== submission.input.uploadIDs.length ||
      uploads.some((upload) => upload.completedAt === undefined)
    ) {
      throw new ProtocolError("upload_incomplete", "任务媒体尚未上传完成。", 409);
    }
    // `getUploads` is an async boundary. Another concurrent submission may
    // have installed the same client key while this call was suspended.
    const concurrentID = this.jobByClientKey.get(clientKey);
    if (concurrentID !== undefined) {
      const concurrent = this.jobs.get(concurrentID);
      if (concurrent === undefined) throw new Error("job index corruption");
      if (concurrent.bodyDigest !== submission.bodyDigest) {
        throw new ProtocolError(
          "idempotency_conflict",
          "相同 clientJobID 对应了不同内容。",
          409,
        );
      }
      return structuredClone(concurrent);
    }
    const job: AgentJob = {
      id: randomUUID(),
      deviceID: submission.deviceID,
      clientJobID: submission.input.clientJobID,
      turnID: submission.input.turnID,
      sessionID: submission.input.sessionID,
      state: "queued",
      bodyDigest: submission.bodyDigest,
      input: structuredClone(submission.input),
      lastSequence: 1,
      acknowledgedSequence: 0,
      leaseEpoch: 0,
      createdAt: submission.now,
      updatedAt: submission.now,
    };
    this.jobs.set(job.id, job);
    this.jobByClientKey.set(clientKey, job.id);
    this.eventRows.set(job.id, [
      {
        id: randomUUID(),
        jobID: job.id,
        sequence: 1,
        kind: "job",
        phase: "started",
        payloadVersion: 1,
        payload: { state: "accepted" },
        createdAt: submission.now,
      },
    ]);
    this.insertOutbox("job", job.id, { state: "queued" }, submission.now);
    this.emitEventSignal(job.id, 1);
    this.emitJobSignal();
    return structuredClone(job);
  }

  async getJob(
    deviceID: string,
    jobID: string,
  ): Promise<AgentJob | undefined> {
    const job = this.jobs.get(jobID);
    return job?.deviceID === deviceID ? structuredClone(job) : undefined;
  }

  async events(
    jobID: string,
    after: number,
    limit: number,
  ): Promise<AgentEvent[]> {
    return (this.eventRows.get(jobID) ?? [])
      .filter((event) => event.sequence > after)
      .slice(0, limit)
      .map((event) => structuredClone(event));
  }

  async waitForJobSignal(timeoutMilliseconds: number): Promise<void> {
    if ([...this.jobs.values()].some((job) => job.state === "queued")) return;
    await this.waitWithTimeout(this.jobWaiters, timeoutMilliseconds);
  }

  async waitForEventSignal(
    jobID: string,
    afterSequence: number,
    timeoutMilliseconds: number,
  ): Promise<void> {
    if ((this.jobs.get(jobID)?.lastSequence ?? 0) > afterSequence) return;
    await new Promise<void>((resolve) => {
      const waiters = this.eventWaiters.get(jobID) ?? new Set();
      let timeout: ReturnType<typeof setTimeout>;
      const waiter = {
        afterSequence,
        resolve: () => {
          clearTimeout(timeout);
          waiters.delete(waiter);
          if (waiters.size === 0) this.eventWaiters.delete(jobID);
          resolve();
        },
      };
      waiters.add(waiter);
      this.eventWaiters.set(jobID, waiters);
      timeout = setTimeout(waiter.resolve, Math.max(0, timeoutMilliseconds));
      if ((this.jobs.get(jobID)?.lastSequence ?? 0) > afterSequence) {
        waiter.resolve();
      }
    });
  }

  async claimJob(
    owner: string,
    now: Date,
    leaseSeconds: number,
  ): Promise<JobLease | undefined> {
    const job = [...this.jobs.values()]
      .filter(
        (candidate) =>
          candidate.state === "queued" ||
          (candidate.state === "running" &&
            (candidate.leaseExpiresAt ?? new Date(0)) <= now),
      )
      .sort((lhs, rhs) => lhs.createdAt.getTime() - rhs.createdAt.getTime())[0];
    if (job === undefined) return undefined;
    job.state = "running";
    job.leaseOwner = owner;
    job.leaseEpoch += 1;
    job.leaseExpiresAt = new Date(now.getTime() + leaseSeconds * 1_000);
    job.updatedAt = now;
    return {
      job: structuredClone(job),
      owner,
      epoch: job.leaseEpoch,
    };
  }

  async renewLease(
    jobID: string,
    owner: string,
    epoch: number,
    now: Date,
    leaseSeconds: number,
  ): Promise<boolean> {
    const job = this.jobs.get(jobID);
    if (
      job === undefined ||
      job.state !== "running" ||
      job.leaseOwner !== owner ||
      job.leaseEpoch !== epoch
    ) {
      return false;
    }
    job.leaseExpiresAt = new Date(now.getTime() + leaseSeconds * 1_000);
    job.updatedAt = now;
    return true;
  }

  async appendEvent(
    jobID: string,
    leaseEpoch: number | undefined,
    event: Omit<AgentEvent, "id" | "jobID" | "sequence">,
  ): Promise<AgentEvent> {
    const job = this.requiredJob(jobID);
    if (
      leaseEpoch !== undefined &&
      (job.leaseEpoch !== leaseEpoch || job.state !== "running")
    ) {
      throw new ProtocolError("invalid_request", "Worker lease 已失效。", 409);
    }
    job.lastSequence += 1;
    job.updatedAt = event.createdAt;
    const row: AgentEvent = {
      ...structuredClone(event),
      id: randomUUID(),
      jobID,
      sequence: job.lastSequence,
    };
    const rows = this.eventRows.get(jobID) ?? [];
    rows.push(row);
    this.eventRows.set(jobID, rows);
    this.insertOutbox("apns", jobID, {
      sequence: row.sequence,
      phase: row.phase,
    }, event.createdAt);
    this.emitEventSignal(jobID, row.sequence);
    return structuredClone(row);
  }

  async transition(
    jobID: string,
    state: AgentJob["state"],
    now: Date,
    leaseEpoch?: number,
    errorCode?: string,
  ): Promise<AgentJob> {
    const job = this.requiredJob(jobID);
    if (isTerminal(job.state)) return structuredClone(job);
    if (leaseEpoch !== undefined && job.leaseEpoch !== leaseEpoch) {
      throw new ProtocolError("invalid_request", "Worker lease 已失效。", 409);
    }
    job.state = state;
    job.updatedAt = now;
    if (errorCode !== undefined) job.errorCode = errorCode;
    if (isTerminal(state)) {
      job.terminalAt = now;
      delete job.leaseOwner;
      delete job.leaseExpiresAt;
    }
    return structuredClone(job);
  }

  async saveToolRequest(
    request: Omit<ToolRequest, "id">,
    now: Date,
    leaseEpoch: number,
  ): Promise<ToolRequest> {
    const key = `${request.jobID}|${request.toolCallID}`;
    const existing = this.tools.get(key);
    if (existing !== undefined) {
      if (!sameToolRequest(existing, request)) {
        throw new ProtocolError(
          "idempotency_conflict",
          "相同 toolCallID 对应了不同请求。",
          409,
        );
      }
      return structuredClone(existing);
    }
    const job = this.requiredJob(request.jobID);
    if (
      job.leaseEpoch !== leaseEpoch ||
      (job.state !== "running" && job.state !== "waitingForDevice")
    ) {
      throw new ProtocolError("invalid_request", "Worker lease 已失效。", 409);
    }
    const saved: ToolRequest = { ...structuredClone(request), id: randomUUID() };
    this.tools.set(key, saved);
    if (job.state === "running") {
      await this.transition(request.jobID, "waitingForDevice", now, leaseEpoch);
    }
    await this.appendEvent(request.jobID, undefined, {
      kind: "tool",
      phase: "suspended",
      payloadVersion: 1,
      payload: {
        toolCallID: request.toolCallID,
        toolName: request.toolName,
        schemaVersion: request.schemaVersion,
        arguments: request.arguments,
        mutation: request.mutation,
        expiresAt: request.expiresAt.toISOString(),
      },
      createdAt: now,
    });
    return structuredClone(saved);
  }

  async pendingToolRequests(deviceID: string): Promise<ToolRequest[]> {
    return [...this.tools.values()]
      .filter((request) => {
        const job = this.jobs.get(request.jobID);
        return (
          job?.deviceID === deviceID &&
          job.state === "waitingForDevice" &&
          request.completedAt === undefined
        );
      })
      .map((request) => structuredClone(request));
  }

  async submitToolResult(
    deviceID: string,
    jobID: string,
    submission: ToolResultSubmission,
    now: Date,
  ): Promise<ToolRequest> {
    const job = this.requiredOwnedJob(deviceID, jobID);
    if (isTerminal(job.state)) {
      throw new ProtocolError("job_cancelled", "任务已经结束。", 409);
    }
    const key = `${jobID}|${submission.toolCallID}`;
    const request = this.tools.get(key);
    if (request === undefined) {
      throw new ProtocolError("not_found", "Tool Request 不存在。", 404);
    }
    if (request.resultDigest !== undefined) {
      if (request.resultDigest !== submission.digest) {
        throw new ProtocolError(
          "idempotency_conflict",
          "相同 toolCallID 对应不同结果。",
          409,
        );
      }
      return structuredClone(request);
    }
    request.resultDigest = submission.digest;
    request.result = structuredClone(submission.result);
    request.completedAt = now;
    job.updatedAt = now;
    await this.appendEvent(jobID, undefined, {
      kind: "tool",
      phase: "completed",
      payloadVersion: 1,
      payload: {
        toolCallID: submission.toolCallID,
        result: submission.result,
      },
      createdAt: now,
    });
    const hasPending = [...this.tools.values()].some(
      (candidate) =>
        candidate.jobID === jobID && candidate.completedAt === undefined,
    );
    if (!hasPending) {
      job.state = "queued";
      this.insertOutbox("job", jobID, { state: "queued" }, now);
      this.emitJobSignal();
    }
    return structuredClone(request);
  }

  async cancelJob(
    deviceID: string,
    jobID: string,
    now: Date,
  ): Promise<AgentJob> {
    const job = this.requiredOwnedJob(deviceID, jobID);
    if (isTerminal(job.state)) return structuredClone(job);
    await this.transition(jobID, "cancelled", now);
    await this.appendEvent(jobID, undefined, {
      kind: "job",
      phase: "cancelled",
      payloadVersion: 1,
      payload: {},
      createdAt: now,
    });
    return structuredClone(job);
  }

  async acknowledge(
    deviceID: string,
    jobID: string,
    sequence: number,
  ): Promise<void> {
    const job = this.requiredOwnedJob(deviceID, jobID);
    job.acknowledgedSequence = Math.min(
      Math.max(job.acknowledgedSequence, sequence),
      job.lastSequence,
    );
  }

  async saveUpload(upload: Upload): Promise<void> {
    this.uploads.set(upload.id, structuredClone(upload));
  }

  async completeUpload(
    deviceID: string,
    uploadID: string,
    bytes: number,
    digest: string,
    now: Date,
  ): Promise<Upload> {
    const upload = this.uploads.get(uploadID);
    if (upload?.deviceID !== deviceID) {
      throw new ProtocolError("not_found", "上传不存在。", 404);
    }
    if (upload.expectedBytes !== bytes || upload.expectedDigest !== digest) {
      throw new ProtocolError("invalid_request", "上传大小或摘要不匹配。", 400);
    }
    upload.completedAt = now;
    return structuredClone(upload);
  }

  async getUploads(deviceID: string, ids: string[]): Promise<Upload[]> {
    return ids
      .map((id) => this.uploads.get(id))
      .filter(
        (upload): upload is Upload =>
          upload !== undefined &&
          upload.deviceID === deviceID &&
          upload.deletedAt === undefined,
      )
      .map((upload) => structuredClone(upload));
  }

  async deleteUpload(
    deviceID: string,
    uploadID: string,
    now: Date,
  ): Promise<string | undefined> {
    const upload = this.uploads.get(uploadID);
    if (
      upload === undefined ||
      upload.deviceID !== deviceID ||
      upload.deletedAt !== undefined
    ) {
      return undefined;
    }
    upload.deletedAt = now;
    return upload.objectKey;
  }

  async saveActivityToken(token: ActivityToken): Promise<void> {
    this.activityTokens.set(token.jobID, structuredClone(token));
  }

  async activityToken(jobID: string): Promise<ActivityToken | undefined> {
    const token = this.activityTokens.get(jobID);
    return token === undefined ? undefined : structuredClone(token);
  }

  async deleteActivityToken(jobID: string): Promise<void> {
    this.activityTokens.delete(jobID);
  }

  async outboxBatch(now: Date, limit: number): Promise<OutboxMessage[]> {
    const messages = [...this.outbox.values()]
      .filter(
        (message) =>
          message.publishedAt === undefined &&
          message.nextAttemptAt <= now,
      )
      .sort((lhs, rhs) => lhs.createdAt.getTime() - rhs.createdAt.getTime())
      .slice(0, limit);
    for (const message of messages) {
      message.attemptCount += 1;
      message.nextAttemptAt = new Date(now.getTime() + 30_000);
    }
    return messages.map((message) => structuredClone(message));
  }

  async markOutboxPublished(id: string, now: Date): Promise<void> {
    const message = this.outbox.get(id);
    if (message !== undefined) message.publishedAt = now;
  }

  async markOutboxRetry(id: string, nextAttemptAt: Date): Promise<void> {
    const message = this.outbox.get(id);
    if (message !== undefined && message.publishedAt === undefined) {
      message.nextAttemptAt = nextAttemptAt;
    }
  }

  async cleanup(now: Date): Promise<CleanupResult> {
    const result: CleanupResult = {
      deletedContentJobIDs: [],
      expiredJobIDs: [],
      deletedMetadataJobIDs: [],
      objectKeys: [],
    };
    const day = 24 * 60 * 60 * 1_000;
    for (const job of [...this.jobs.values()]) {
      const age = now.getTime() - job.createdAt.getTime();
      const terminalAge =
        job.terminalAt === undefined
          ? undefined
          : now.getTime() - job.terminalAt.getTime();
      if (!isTerminal(job.state) && age >= 7 * day) {
        job.state = "expired";
        job.terminalAt = now;
        job.updatedAt = now;
        result.expiredJobIDs.push(job.id);
      }
      if (
        job.contentDeletedAt === undefined &&
        ((job.acknowledgedSequence >= job.lastSequence &&
          terminalAge !== undefined &&
          terminalAge >= day) ||
          age >= 7 * day)
      ) {
        for (const uploadID of job.input?.uploadIDs ?? []) {
          const upload = this.uploads.get(uploadID);
          if (upload !== undefined && upload.deletedAt === undefined) {
            upload.deletedAt = now;
            result.objectKeys.push(upload.objectKey);
          }
        }
        delete job.input;
        job.contentDeletedAt = now;
        this.eventRows.delete(job.id);
        this.tools.forEach((request, key) => {
          if (request.jobID === job.id) this.tools.delete(key);
        });
        this.activityTokens.delete(job.id);
        this.outbox.forEach((message, key) => {
          if (message.aggregateID === job.id) this.outbox.delete(key);
        });
        result.deletedContentJobIDs.push(job.id);
      }
      if (age >= 30 * day) {
        this.jobs.delete(job.id);
        this.jobByClientKey.delete(`${job.deviceID}|${job.clientJobID}`);
        this.eventRows.delete(job.id);
        result.deletedMetadataJobIDs.push(job.id);
      }
    }
    for (const upload of this.uploads.values()) {
      if (
        upload.deletedAt === undefined &&
        now.getTime() - upload.createdAt.getTime() >= 7 * day
      ) {
        upload.deletedAt = now;
        result.objectKeys.push(upload.objectKey);
      }
      if (now.getTime() - upload.createdAt.getTime() >= 30 * day) {
        this.uploads.delete(upload.id);
      }
    }
    return result;
  }

  async deleteDeviceData(deviceID: string, now: Date): Promise<string[]> {
    const objectKeys: string[] = [];
    for (const job of this.jobs.values()) {
      if (job.deviceID !== deviceID) continue;
      if (!isTerminal(job.state)) {
        await this.cancelJob(deviceID, job.id, now);
      }
      delete job.input;
      job.contentDeletedAt = now;
      this.eventRows.delete(job.id);
      this.tools.forEach((request, key) => {
        if (request.jobID === job.id) this.tools.delete(key);
      });
      this.activityTokens.delete(job.id);
      this.outbox.forEach((message, key) => {
        if (message.aggregateID === job.id) this.outbox.delete(key);
      });
    }
    for (const [id, upload] of this.uploads) {
      if (upload.deviceID === deviceID) {
        if (upload.deletedAt === undefined) {
          objectKeys.push(upload.objectKey);
        }
        this.uploads.delete(id);
      }
    }
    await this.revokeDevice(deviceID, now);
    return objectKeys;
  }

  private requiredJob(id: string): AgentJob {
    const job = this.jobs.get(id);
    if (job === undefined) {
      throw new ProtocolError("not_found", "任务不存在。", 404);
    }
    return job;
  }

  private requiredOwnedJob(deviceID: string, id: string): AgentJob {
    const job = this.requiredJob(id);
    if (job.deviceID !== deviceID) {
      throw new ProtocolError("not_found", "任务不存在。", 404);
    }
    return job;
  }

  private insertOutbox(
    topic: OutboxMessage["topic"],
    aggregateID: string,
    payload: Record<string, unknown>,
    now: Date,
  ): void {
    const row: OutboxMessage = {
      id: randomUUID(),
      topic,
      aggregateID,
      payload,
      createdAt: now,
      nextAttemptAt: now,
      attemptCount: 0,
    };
    this.outbox.set(row.id, row);
  }

  private async waitWithTimeout(
    waiters: Set<() => void>,
    timeoutMilliseconds: number,
  ): Promise<void> {
    await new Promise<void>((resolve) => {
      let timeout: ReturnType<typeof setTimeout>;
      const wake = () => {
        clearTimeout(timeout);
        waiters.delete(wake);
        resolve();
      };
      waiters.add(wake);
      timeout = setTimeout(wake, Math.max(0, timeoutMilliseconds));
    });
  }

  private emitJobSignal(): void {
    for (const wake of [...this.jobWaiters]) wake();
  }

  private emitEventSignal(jobID: string, sequence: number): void {
    const waiters = this.eventWaiters.get(jobID);
    if (waiters === undefined) return;
    for (const waiter of [...waiters]) {
      if (sequence > waiter.afterSequence) waiter.resolve();
    }
  }
}

function sameToolRequest(
  lhs: ToolRequest,
  rhs: Omit<ToolRequest, "id">,
): boolean {
  return (
    lhs.toolName === rhs.toolName &&
    lhs.schemaVersion === rhs.schemaVersion &&
    lhs.mutation === rhs.mutation &&
    canonicalJSON(lhs.arguments) === canonicalJSON(rhs.arguments)
  );
}

import { randomUUID } from "node:crypto";
import { canonicalJSON } from "./canonical-json.js";
import {
  Pool,
  type Notification,
  type PoolClient,
  type QueryResultRow,
} from "pg";
import type {
  ActivityToken,
  AgentEvent,
  AgentJob,
  JobLease,
  JobSubmission,
  OutboxMessage,
  RegistrationChallenge,
  ToolRequest,
  ToolResultSubmission,
  Upload,
} from "./domain.js";
import { isTerminal, ProtocolError } from "./domain.js";
import type { CleanupResult, SomaStore } from "./store.js";

export class PostgresSomaStore implements SomaStore {
  private listenerPromise: Promise<PoolClient> | undefined;
  private jobWaiters = new Set<() => void>();
  private eventWaiters = new Map<
    string,
    Set<{ afterSequence: number; resolve: () => void }>
  >();

  constructor(readonly pool: Pool) {}

  async saveChallenge(challenge: RegistrationChallenge): Promise<void> {
    await this.pool.query(
      `INSERT INTO device_registration_challenges
       (id, challenge, expires_at) VALUES ($1, $2, $3)`,
      [challenge.id, challenge.challenge, challenge.expiresAt],
    );
  }

  async consumeChallenge(
    id: string,
    now: Date,
  ): Promise<RegistrationChallenge> {
    const result = await this.pool.query<ChallengeRow>(
      `UPDATE device_registration_challenges
       SET consumed_at = $2
       WHERE id = $1 AND consumed_at IS NULL AND expires_at > $2
       RETURNING *`,
      [id, now],
    );
    const row = result.rows[0];
    if (row === undefined) {
      throw new ProtocolError("invalid_request", "注册挑战无效或已过期。", 400);
    }
    return {
      id: row.id,
      challenge: row.challenge,
      expiresAt: row.expires_at,
      consumedAt: row.consumed_at,
    };
  }

  async saveDevice(
    id: string,
    publicKeyPem: string,
    attestationKeyID: string | undefined,
    now: Date,
  ): Promise<void> {
    await this.pool.query(
      `INSERT INTO devices
       (id, public_key_pem, attestation_key_id, created_at)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (id) DO UPDATE SET
         public_key_pem = EXCLUDED.public_key_pem,
         attestation_key_id = EXCLUDED.attestation_key_id,
         revoked_at = NULL`,
      [id, publicKeyPem, attestationKeyID ?? null, now],
    );
  }

  async devicePublicKey(id: string): Promise<string | undefined> {
    const result = await this.pool.query<{ public_key_pem: string }>(
      `SELECT public_key_pem FROM devices
       WHERE id = $1 AND revoked_at IS NULL`,
      [id],
    );
    return result.rows[0]?.public_key_pem;
  }

  async revokeDevice(id: string, now: Date): Promise<void> {
    await this.pool.query(
      "UPDATE devices SET revoked_at = $2 WHERE id = $1",
      [id, now],
    );
  }

  async consumeNonce(
    deviceID: string,
    nonce: string,
    expiresAt: Date,
  ): Promise<boolean> {
    const result = await this.pool.query(
      `INSERT INTO request_nonces (device_id, nonce, expires_at)
       VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [deviceID, nonce, expiresAt],
    );
    return result.rowCount === 1;
  }

  async submitJob(submission: JobSubmission): Promise<AgentJob> {
    return this.transaction(async (client) => {
      // A missing row cannot be locked with SELECT ... FOR UPDATE. Serialize
      // concurrent creates for the same anonymous device/client key so both
      // callers deterministically observe one job instead of one receiving a
      // database uniqueness error.
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`${submission.deviceID}|${submission.input.clientJobID}`],
      );
      const existing = await client.query<JobRow>(
        `SELECT * FROM agent_jobs
         WHERE device_id = $1 AND client_job_id = $2
         FOR UPDATE`,
        [submission.deviceID, submission.input.clientJobID],
      );
      const row = existing.rows[0];
      if (row !== undefined) {
        if (row.body_digest !== submission.bodyDigest) {
          throw new ProtocolError(
            "idempotency_conflict",
            "相同 clientJobID 对应了不同内容。",
            409,
          );
        }
        return mapJob(row);
      }
      if (submission.input.uploadIDs.length > 0) {
        const uploads = await client.query<{ id: string }>(
          `SELECT id FROM temporary_uploads
           WHERE device_id = $1
             AND id = ANY($2::uuid[])
             AND completed_at IS NOT NULL
             AND deleted_at IS NULL`,
          [submission.deviceID, submission.input.uploadIDs],
        );
        if (uploads.rowCount !== submission.input.uploadIDs.length) {
          throw new ProtocolError(
            "upload_incomplete",
            "任务媒体尚未上传完成。",
            409,
          );
        }
      }
      const jobID = randomUUID();
      const eventID = randomUUID();
      const outboxID = randomUUID();
      const inserted = await client.query<JobRow>(
        `INSERT INTO agent_jobs
         (id, device_id, client_job_id, turn_id, session_id, state,
          body_digest, input_json, last_sequence, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, 'queued', $6, $7, 1, $8, $8)
         RETURNING *`,
        [
          jobID,
          submission.deviceID,
          submission.input.clientJobID,
          submission.input.turnID,
          submission.input.sessionID,
          submission.bodyDigest,
          submission.input,
          submission.now,
        ],
      );
      if (submission.input.uploadIDs.length > 0) {
        await client.query(
          `INSERT INTO agent_job_uploads (job_id, upload_id)
           SELECT $1, unnest($2::uuid[])`,
          [jobID, submission.input.uploadIDs],
        );
      }
      await client.query(
        `INSERT INTO agent_events
         (id, job_id, sequence, kind, phase, payload_json, created_at)
         VALUES ($1, $2, 1, 'job', 'started', $3, $4)`,
        [eventID, jobID, { state: "accepted" }, submission.now],
      );
      await client.query(
        `INSERT INTO transactional_outbox
         (id, topic, aggregate_id, payload_json, created_at)
         VALUES ($1, 'job', $2, $3, $4)`,
        [outboxID, jobID, { state: "queued" }, submission.now],
      );
      await client.query("SELECT pg_notify('soma_agent_event', $1)", [
        JSON.stringify({ jobID, sequence: 1 }),
      ]);
      await client.query("SELECT pg_notify('soma_agent_job_ready', $1)", [
        jobID,
      ]);
      return mapJob(requiredRow(inserted.rows[0]));
    });
  }

  async getJob(
    deviceID: string,
    jobID: string,
  ): Promise<AgentJob | undefined> {
    const result = await this.pool.query<JobRow>(
      "SELECT * FROM agent_jobs WHERE id = $1 AND device_id = $2",
      [jobID, deviceID],
    );
    const row = result.rows[0];
    return row === undefined ? undefined : mapJob(row);
  }

  async events(
    jobID: string,
    after: number,
    limit: number,
  ): Promise<AgentEvent[]> {
    const result = await this.pool.query<EventRow>(
      `SELECT * FROM agent_events
       WHERE job_id = $1 AND sequence > $2
       ORDER BY sequence ASC LIMIT $3`,
      [jobID, after, limit],
    );
    return result.rows.map(mapEvent);
  }

  async waitForJobSignal(timeoutMilliseconds: number): Promise<void> {
    if (await this.hasReadyJob()) return;
    await this.ensureListener();
    await new Promise<void>(async (resolve) => {
      let timeout: ReturnType<typeof setTimeout>;
      const wake = () => {
        clearTimeout(timeout);
        this.jobWaiters.delete(wake);
        resolve();
      };
      this.jobWaiters.add(wake);
      timeout = setTimeout(wake, Math.max(0, timeoutMilliseconds));
      try {
        if (await this.hasReadyJob()) wake();
      } catch {
        wake();
      }
    });
  }

  async waitForEventSignal(
    jobID: string,
    afterSequence: number,
    timeoutMilliseconds: number,
  ): Promise<void> {
    if ((await this.currentSequence(jobID)) > afterSequence) return;
    await this.ensureListener();
    await new Promise<void>(async (resolve) => {
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
      try {
        if ((await this.currentSequence(jobID)) > afterSequence) {
          waiter.resolve();
        }
      } catch {
        waiter.resolve();
      }
    });
  }

  async claimJob(
    owner: string,
    now: Date,
    leaseSeconds: number,
  ): Promise<JobLease | undefined> {
    return this.transaction(async (client) => {
      const selected = await client.query<JobRow>(
        `SELECT * FROM agent_jobs
         WHERE state = 'queued'
            OR (state = 'running' AND lease_expires_at <= $1)
         ORDER BY created_at
         FOR UPDATE SKIP LOCKED
         LIMIT 1`,
        [now],
      );
      const row = selected.rows[0];
      if (row === undefined) return undefined;
      const updated = await client.query<JobRow>(
        `UPDATE agent_jobs SET
           state = 'running',
           lease_owner = $2,
           lease_epoch = lease_epoch + 1,
           lease_expires_at =
             $1::timestamptz + ($3::double precision * interval '1 second'),
           updated_at = $1
         WHERE id = $4 RETURNING *`,
        [now, owner, leaseSeconds, row.id],
      );
      const job = mapJob(requiredRow(updated.rows[0]));
      return { job, owner, epoch: job.leaseEpoch };
    });
  }

  async renewLease(
    jobID: string,
    owner: string,
    epoch: number,
    now: Date,
    leaseSeconds: number,
  ): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE agent_jobs SET
         lease_expires_at =
           $4::timestamptz + ($5::double precision * interval '1 second'),
         updated_at = $4
       WHERE id = $1 AND lease_owner = $2 AND lease_epoch = $3
         AND state = 'running'`,
      [jobID, owner, epoch, now, leaseSeconds],
    );
    return result.rowCount === 1;
  }

  async appendEvent(
    jobID: string,
    leaseEpoch: number | undefined,
    event: Omit<AgentEvent, "id" | "jobID" | "sequence">,
  ): Promise<AgentEvent> {
    return this.transaction(async (client) => {
      const parameters: unknown[] = [jobID, event.createdAt];
      let leaseSQL = "";
      if (leaseEpoch !== undefined) {
        parameters.push(leaseEpoch);
        leaseSQL = " AND lease_epoch = $3 AND state = 'running'";
      }
      const job = await client.query<{ last_sequence: number }>(
        `UPDATE agent_jobs SET
           last_sequence = last_sequence + 1,
           updated_at = $2
         WHERE id = $1${leaseSQL}
         RETURNING last_sequence`,
        parameters,
      );
      const sequence = job.rows[0]?.last_sequence;
      if (sequence === undefined) {
        throw new ProtocolError("invalid_request", "Worker lease 已失效。", 409);
      }
      const inserted = await client.query<EventRow>(
        `INSERT INTO agent_events
         (id, job_id, sequence, kind, phase, payload_version,
          payload_json, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING *`,
        [
          randomUUID(),
          jobID,
          sequence,
          event.kind,
          event.phase,
          event.payloadVersion,
          event.payload,
          event.createdAt,
        ],
      );
      await client.query(
        `INSERT INTO transactional_outbox
         (id, topic, aggregate_id, payload_json, created_at)
         VALUES ($1, 'apns', $2, $3, $4)`,
        [
          randomUUID(),
          jobID,
          { sequence, phase: event.phase },
          event.createdAt,
        ],
      );
      await client.query("SELECT pg_notify('soma_agent_event', $1)", [
        JSON.stringify({ jobID, sequence }),
      ]);
      return mapEvent(requiredRow(inserted.rows[0]));
    });
  }

  async transition(
    jobID: string,
    state: AgentJob["state"],
    now: Date,
    leaseEpoch?: number,
    errorCode?: string,
  ): Promise<AgentJob> {
    const current = await this.pool.query<JobRow>(
      "SELECT * FROM agent_jobs WHERE id = $1",
      [jobID],
    );
    const existing = mapJob(requiredRow(current.rows[0]));
    if (isTerminal(existing.state)) return existing;
    const result = await this.pool.query<JobRow>(
      `UPDATE agent_jobs SET
         state = $2::agent_job_state,
         updated_at = $3,
         terminal_at = CASE
           WHEN $2::agent_job_state IN
             ('completed','failed','cancelled','expired') THEN $3
           ELSE terminal_at END,
         lease_owner = CASE
           WHEN $2::agent_job_state IN
             ('completed','failed','cancelled','expired') THEN NULL
           ELSE lease_owner END,
         lease_expires_at = CASE
           WHEN $2::agent_job_state IN
             ('completed','failed','cancelled','expired') THEN NULL
           ELSE lease_expires_at END,
         error_code = COALESCE($5, error_code)
       WHERE id = $1
         AND state NOT IN ('completed','failed','cancelled','expired')
         AND ($4::integer IS NULL OR lease_epoch = $4)
       RETURNING *`,
      [jobID, state, now, leaseEpoch ?? null, errorCode ?? null],
    );
    const row = result.rows[0];
    if (row === undefined) {
      const winner = await this.pool.query<JobRow>(
        "SELECT * FROM agent_jobs WHERE id = $1",
        [jobID],
      );
      const terminal = winner.rows[0];
      if (terminal !== undefined && isTerminal(terminal.state)) {
        return mapJob(terminal);
      }
      throw new ProtocolError("invalid_request", "Worker lease 已失效。", 409);
    }
    return mapJob(row);
  }

  async saveToolRequest(
    request: Omit<ToolRequest, "id">,
    now: Date,
    leaseEpoch: number,
  ): Promise<ToolRequest> {
    return this.transaction(async (client) => {
      const existing = await client.query<ToolRow>(
        `SELECT * FROM agent_tool_requests
         WHERE job_id = $1 AND tool_call_id = $2`,
        [request.jobID, request.toolCallID],
      );
      if (existing.rows[0] !== undefined) {
        const saved = mapTool(existing.rows[0]);
        if (!sameToolRequest(saved, request)) {
          throw new ProtocolError(
            "idempotency_conflict",
            "相同 toolCallID 对应了不同请求。",
            409,
          );
        }
        return saved;
      }
      const updated = await client.query(
        `UPDATE agent_jobs SET
           state = 'waitingForDevice',
           updated_at = $3
         WHERE id = $1 AND lease_epoch = $2 AND state = 'running'`,
        [request.jobID, leaseEpoch, now],
      );
      if (updated.rowCount !== 1) {
        throw new ProtocolError("invalid_request", "Worker lease 已失效。", 409);
      }
      const inserted = await client.query<ToolRow>(
        `INSERT INTO agent_tool_requests
         (id, job_id, tool_call_id, tool_name, schema_version,
          arguments_json, mutation, expires_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING *`,
        [
          randomUUID(),
          request.jobID,
          request.toolCallID,
          request.toolName,
          request.schemaVersion,
          request.arguments,
          request.mutation,
          request.expiresAt,
        ],
      );
      const sequenceResult = await client.query<{ last_sequence: number }>(
        `UPDATE agent_jobs SET last_sequence = last_sequence + 1
         WHERE id = $1 RETURNING last_sequence`,
        [request.jobID],
      );
      const sequence = requiredRow(sequenceResult.rows[0]).last_sequence;
      await client.query(
        `INSERT INTO agent_events
         (id, job_id, sequence, kind, phase, payload_version,
          payload_json, created_at)
         VALUES ($1,$2,$3,'tool','suspended',1,$4,$5)`,
        [
          randomUUID(),
          request.jobID,
          sequence,
          {
            toolCallID: request.toolCallID,
            toolName: request.toolName,
            schemaVersion: request.schemaVersion,
            arguments: request.arguments,
            mutation: request.mutation,
            expiresAt: request.expiresAt.toISOString(),
          },
          now,
        ],
      );
      await client.query(
        `INSERT INTO transactional_outbox
         (id, topic, aggregate_id, payload_json, created_at)
         VALUES ($1, 'apns', $2, $3, $4)`,
        [
          randomUUID(),
          request.jobID,
          { sequence, phase: "suspended" },
          now,
        ],
      );
      await client.query("SELECT pg_notify('soma_agent_event', $1)", [
        JSON.stringify({ jobID: request.jobID, sequence }),
      ]);
      return mapTool(requiredRow(inserted.rows[0]));
    });
  }

  async pendingToolRequests(deviceID: string): Promise<ToolRequest[]> {
    const result = await this.pool.query<ToolRow>(
      `SELECT request.* FROM agent_tool_requests request
       JOIN agent_jobs job ON job.id = request.job_id
       WHERE job.device_id = $1
         AND job.state = 'waitingForDevice'
         AND request.completed_at IS NULL
       ORDER BY request.expires_at`,
      [deviceID],
    );
    return result.rows.map(mapTool);
  }

  async submitToolResult(
    deviceID: string,
    jobID: string,
    submission: ToolResultSubmission,
    now: Date,
  ): Promise<ToolRequest> {
    return this.transaction(async (client) => {
      const selected = await client.query<ToolRow & { state: AgentJob["state"] }>(
        `SELECT request.*, job.state FROM agent_tool_requests request
         JOIN agent_jobs job ON job.id = request.job_id
         WHERE request.job_id = $1
           AND request.tool_call_id = $2
           AND job.device_id = $3
         FOR UPDATE`,
        [jobID, submission.toolCallID, deviceID],
      );
      const row = selected.rows[0];
      if (row === undefined) {
        throw new ProtocolError("not_found", "Tool Request 不存在。", 404);
      }
      if (isTerminal(row.state)) {
        throw new ProtocolError("job_cancelled", "任务已经结束。", 409);
      }
      if (row.result_digest !== null) {
        if (row.result_digest !== submission.digest) {
          throw new ProtocolError(
            "idempotency_conflict",
            "相同 toolCallID 对应不同结果。",
            409,
          );
        }
        return mapTool(row);
      }
      const updated = await client.query<ToolRow>(
        `UPDATE agent_tool_requests SET
           result_digest = $3,
           result_json = $4,
           completed_at = $5
         WHERE job_id = $1 AND tool_call_id = $2
         RETURNING *`,
        [
          jobID,
          submission.toolCallID,
          submission.digest,
          submission.result,
          now,
        ],
      );
      await client.query(
        `UPDATE agent_jobs SET
           state = 'queued',
           updated_at = $2,
           last_sequence = last_sequence + 1
         WHERE id = $1`,
        [jobID, now],
      );
      const sequenceResult = await client.query<{ last_sequence: number }>(
        "SELECT last_sequence FROM agent_jobs WHERE id = $1",
        [jobID],
      );
      const sequence = requiredRow(sequenceResult.rows[0]).last_sequence;
      await client.query(
        `INSERT INTO agent_events
         (id, job_id, sequence, kind, phase, payload_version,
          payload_json, created_at)
         VALUES ($1,$2,$3,'tool','completed',1,$4,$5)`,
        [
          randomUUID(),
          jobID,
          sequence,
          {
            toolCallID: submission.toolCallID,
            result: submission.result,
          },
          now,
        ],
      );
      await client.query(
        `INSERT INTO transactional_outbox
         (id, topic, aggregate_id, payload_json, created_at)
         VALUES ($1, 'job', $2, $3, $4)`,
        [randomUUID(), jobID, { state: "queued" }, now],
      );
      await client.query(
        `INSERT INTO transactional_outbox
         (id, topic, aggregate_id, payload_json, created_at)
         VALUES ($1, 'apns', $2, $3, $4)`,
        [
          randomUUID(),
          jobID,
          { sequence, phase: "completed" },
          now,
        ],
      );
      await client.query("SELECT pg_notify('soma_agent_event', $1)", [
        JSON.stringify({ jobID, sequence }),
      ]);
      await client.query("SELECT pg_notify('soma_agent_job_ready', $1)", [
        jobID,
      ]);
      return mapTool(requiredRow(updated.rows[0]));
    });
  }

  async cancelJob(
    deviceID: string,
    jobID: string,
    now: Date,
  ): Promise<AgentJob> {
    return this.transaction(async (client) => {
      const selected = await client.query<JobRow>(
        `SELECT * FROM agent_jobs
         WHERE id = $1 AND device_id = $2
         FOR UPDATE`,
        [jobID, deviceID],
      );
      const current = selected.rows[0];
      if (current === undefined) {
        throw new ProtocolError("not_found", "任务不存在。", 404);
      }
      if (isTerminal(current.state)) return mapJob(current);
      const updated = await client.query<JobRow>(
        `UPDATE agent_jobs SET
           state = 'cancelled',
           terminal_at = $3,
           updated_at = $3,
           lease_owner = NULL,
           lease_expires_at = NULL,
           last_sequence = last_sequence + 1
         WHERE id = $1 AND device_id = $2
         RETURNING *`,
        [jobID, deviceID, now],
      );
      const row = requiredRow(updated.rows[0]);
      await client.query(
        `INSERT INTO agent_events
         (id, job_id, sequence, kind, phase, payload_version,
          payload_json, created_at)
         VALUES ($1,$2,$3,'job','cancelled',1,'{}'::jsonb,$4)`,
        [randomUUID(), jobID, row.last_sequence, now],
      );
      await client.query(
        `INSERT INTO transactional_outbox
         (id, topic, aggregate_id, payload_json, created_at)
         VALUES ($1, 'apns', $2, $3, $4)`,
        [
          randomUUID(),
          jobID,
          { sequence: row.last_sequence, phase: "cancelled" },
          now,
        ],
      );
      await client.query("SELECT pg_notify('soma_agent_event', $1)", [
        JSON.stringify({ jobID, sequence: row.last_sequence }),
      ]);
      return mapJob(row);
    });
  }

  async acknowledge(
    deviceID: string,
    jobID: string,
    sequence: number,
  ): Promise<void> {
    await this.pool.query(
      `UPDATE agent_jobs SET acknowledged_sequence =
         LEAST(last_sequence, GREATEST(acknowledged_sequence, $3))
       WHERE id = $1 AND device_id = $2`,
      [jobID, deviceID, sequence],
    );
  }

  async saveUpload(upload: Upload): Promise<void> {
    await this.pool.query(
      `INSERT INTO temporary_uploads
       (id, device_id, content_type, expected_bytes, expected_digest,
        object_key, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [
        upload.id,
        upload.deviceID,
        upload.contentType,
        upload.expectedBytes,
        upload.expectedDigest,
        upload.objectKey,
        upload.createdAt,
      ],
    );
  }

  async completeUpload(
    deviceID: string,
    uploadID: string,
    bytes: number,
    digest: string,
    now: Date,
  ): Promise<Upload> {
    const result = await this.pool.query<UploadRow>(
      `UPDATE temporary_uploads SET completed_at = $5
       WHERE id = $1 AND device_id = $2
         AND expected_bytes = $3 AND expected_digest = $4
         AND deleted_at IS NULL
       RETURNING *`,
      [uploadID, deviceID, bytes, digest, now],
    );
    const row = result.rows[0];
    if (row === undefined) {
      throw new ProtocolError("invalid_request", "上传大小或摘要不匹配。", 400);
    }
    return mapUpload(row);
  }

  async getUploads(deviceID: string, ids: string[]): Promise<Upload[]> {
    if (ids.length === 0) return [];
    const result = await this.pool.query<UploadRow>(
      `SELECT * FROM temporary_uploads
       WHERE device_id = $1 AND id = ANY($2::uuid[]) AND deleted_at IS NULL`,
      [deviceID, ids],
    );
    return result.rows.map(mapUpload);
  }

  async deleteUpload(
    deviceID: string,
    uploadID: string,
    now: Date,
  ): Promise<string | undefined> {
    const result = await this.pool.query<{ object_key: string }>(
      `UPDATE temporary_uploads SET deleted_at = $3
       WHERE id = $1 AND device_id = $2 AND deleted_at IS NULL
       RETURNING object_key`,
      [uploadID, deviceID, now],
    );
    return result.rows[0]?.object_key;
  }

  async saveActivityToken(token: ActivityToken): Promise<void> {
    await this.pool.query(
      `INSERT INTO activity_tokens
       (job_id, device_id, environment, encrypted_token,
        last_pushed_sequence, created_at)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (job_id) DO UPDATE SET
         encrypted_token = EXCLUDED.encrypted_token,
         environment = EXCLUDED.environment,
         last_pushed_sequence = EXCLUDED.last_pushed_sequence,
         created_at = EXCLUDED.created_at`,
      [
        token.jobID,
        token.deviceID,
        token.environment,
        token.encryptedToken,
        token.lastPushedSequence,
        token.createdAt,
      ],
    );
  }

  async activityToken(jobID: string): Promise<ActivityToken | undefined> {
    const result = await this.pool.query<ActivityTokenRow>(
      "SELECT * FROM activity_tokens WHERE job_id = $1",
      [jobID],
    );
    const row = result.rows[0];
    return row === undefined ? undefined : mapActivityToken(row);
  }

  async deleteActivityToken(jobID: string): Promise<void> {
    await this.pool.query("DELETE FROM activity_tokens WHERE job_id = $1", [
      jobID,
    ]);
  }

  async outboxBatch(now: Date, limit: number): Promise<OutboxMessage[]> {
    return this.transaction(async (client) => {
      const result = await client.query<OutboxRow>(
        `WITH claimed AS (
           SELECT id FROM transactional_outbox
           WHERE published_at IS NULL AND next_attempt_at <= $1
           ORDER BY created_at
           FOR UPDATE SKIP LOCKED
           LIMIT $2
         )
         UPDATE transactional_outbox AS message SET
           attempt_count = message.attempt_count + 1,
           next_attempt_at = $1 + interval '30 seconds'
         FROM claimed
         WHERE message.id = claimed.id
         RETURNING message.*`,
        [now, limit],
      );
      return result.rows.map(mapOutbox);
    });
  }

  async markOutboxPublished(id: string, now: Date): Promise<void> {
    await this.pool.query(
      `UPDATE transactional_outbox
       SET published_at = $2 WHERE id = $1`,
      [id, now],
    );
  }

  async markOutboxRetry(id: string, nextAttemptAt: Date): Promise<void> {
    await this.pool.query(
      `UPDATE transactional_outbox SET next_attempt_at = $2
       WHERE id = $1 AND published_at IS NULL`,
      [id, nextAttemptAt],
    );
  }

  async cleanup(now: Date): Promise<CleanupResult> {
    return this.transaction(async (client) => {
      const expired = await client.query<{ id: string }>(
        `UPDATE agent_jobs SET
           state = 'expired', terminal_at = $1, updated_at = $1
         WHERE state NOT IN ('completed','failed','cancelled','expired')
           AND created_at <= $1::timestamptz - interval '7 days'
         RETURNING id`,
        [now],
      );
      const content = await client.query<{ id: string }>(
        `UPDATE agent_jobs SET
           input_json = NULL, content_deleted_at = $1
         WHERE content_deleted_at IS NULL
           AND (
             created_at <= $1::timestamptz - interval '7 days'
             OR (
               terminal_at <= $1::timestamptz - interval '24 hours'
               AND acknowledged_sequence >= last_sequence
             )
           )
         RETURNING id`,
        [now],
      );
      const objects = await client.query<{ object_key: string }>(
        `UPDATE temporary_uploads AS upload SET deleted_at = $1
         FROM agent_job_uploads AS relation
         WHERE relation.upload_id = upload.id
           AND relation.job_id = ANY($2::uuid[])
           AND upload.deleted_at IS NULL
         RETURNING upload.object_key`,
        [now, content.rows.map((row) => row.id)],
      );
      const staleObjects = await client.query<{ object_key: string }>(
        `UPDATE temporary_uploads SET deleted_at = $1
         WHERE deleted_at IS NULL
           AND created_at <= $1::timestamptz - interval '7 days'
         RETURNING object_key`,
        [now],
      );
      await client.query(
        `DELETE FROM agent_events
         WHERE job_id = ANY($1::uuid[])`,
        [content.rows.map((row) => row.id)],
      );
      await client.query(
        `DELETE FROM agent_tool_requests
         WHERE job_id = ANY($1::uuid[])`,
        [content.rows.map((row) => row.id)],
      );
      await client.query(
        `DELETE FROM activity_tokens
         WHERE job_id = ANY($1::uuid[])`,
        [content.rows.map((row) => row.id)],
      );
      await client.query(
        `DELETE FROM transactional_outbox
         WHERE aggregate_id = ANY($1::uuid[])`,
        [content.rows.map((row) => row.id)],
      );
      const metadata = await client.query<{ id: string }>(
        `DELETE FROM agent_jobs
         WHERE created_at <= $1::timestamptz - interval '30 days'
         RETURNING id`,
        [now],
      );
      await client.query(
        "DELETE FROM request_nonces WHERE expires_at <= $1",
        [now],
      );
      await client.query(
        "DELETE FROM device_registration_challenges WHERE expires_at <= $1",
        [now],
      );
      await client.query(
        `DELETE FROM temporary_uploads
         WHERE created_at <= $1::timestamptz - interval '30 days'`,
        [now],
      );
      await client.query(
        `DELETE FROM devices
         WHERE revoked_at <= $1::timestamptz - interval '30 days'`,
        [now],
      );
      return {
        deletedContentJobIDs: content.rows.map((row) => row.id),
        expiredJobIDs: expired.rows.map((row) => row.id),
        deletedMetadataJobIDs: metadata.rows.map((row) => row.id),
        objectKeys: [...objects.rows, ...staleObjects.rows].map(
          (row) => row.object_key,
        ),
      };
    });
  }

  async deleteDeviceData(deviceID: string, now: Date): Promise<string[]> {
    return this.transaction(async (client) => {
      await client.query(
        `UPDATE agent_jobs SET
           state = CASE
             WHEN state IN ('completed','failed','cancelled','expired') THEN state
             ELSE 'cancelled'::agent_job_state END,
           terminal_at = COALESCE(terminal_at, $2),
           input_json = NULL,
           content_deleted_at = $2,
           updated_at = $2
         WHERE device_id = $1`,
        [deviceID, now],
      );
      await client.query(
        `DELETE FROM activity_tokens WHERE device_id = $1`,
        [deviceID],
      );
      await client.query(
        `DELETE FROM agent_events
         WHERE job_id IN (
           SELECT id FROM agent_jobs WHERE device_id = $1
         )`,
        [deviceID],
      );
      await client.query(
        `DELETE FROM agent_tool_requests
         WHERE job_id IN (
           SELECT id FROM agent_jobs WHERE device_id = $1
         )`,
        [deviceID],
      );
      await client.query(
        `DELETE FROM transactional_outbox
         WHERE aggregate_id IN (
           SELECT id FROM agent_jobs WHERE device_id = $1
         )`,
        [deviceID],
      );
      const objects = await client.query<{ object_key: string }>(
        `DELETE FROM temporary_uploads
         WHERE device_id = $1
         RETURNING object_key`,
        [deviceID],
      );
      await client.query(
        "UPDATE devices SET revoked_at = $2 WHERE id = $1",
        [deviceID, now],
      );
      return objects.rows.map((row) => row.object_key);
    });
  }

  private async transaction<T>(
    operation: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const value = await operation(client);
      await client.query("COMMIT");
      return value;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  private async ensureListener(): Promise<PoolClient> {
    if (this.listenerPromise !== undefined) return this.listenerPromise;
    this.listenerPromise = this.pool.connect().then(async (client) => {
      let released = false;
      const releaseBrokenClient = () => {
        if (released) return;
        released = true;
        client.release(true);
      };
      try {
        client.on("notification", (notification: Notification) => {
          this.handleNotification(notification);
        });
        client.on("error", () => {
          this.listenerPromise = undefined;
          this.wakeAllListeners();
          releaseBrokenClient();
        });
        await client.query("LISTEN soma_agent_job_ready");
        await client.query("LISTEN soma_agent_event");
        return client;
      } catch (error) {
        releaseBrokenClient();
        throw error;
      }
    });
    try {
      return await this.listenerPromise;
    } catch (error) {
      this.listenerPromise = undefined;
      this.wakeAllListeners();
      throw error;
    }
  }

  private async hasReadyJob(): Promise<boolean> {
    const result = await this.pool.query(
      `SELECT 1 FROM agent_jobs
       WHERE state = 'queued'
          OR (state = 'running' AND lease_expires_at <= now())
       LIMIT 1`,
    );
    return result.rowCount === 1;
  }

  private async currentSequence(jobID: string): Promise<number> {
    const result = await this.pool.query<{ last_sequence: number }>(
      "SELECT last_sequence FROM agent_jobs WHERE id = $1",
      [jobID],
    );
    return result.rows[0]?.last_sequence ?? 0;
  }

  private handleNotification(notification: Notification): void {
    if (notification.channel === "soma_agent_job_ready") {
      for (const wake of [...this.jobWaiters]) wake();
      return;
    }
    if (notification.channel !== "soma_agent_event") return;
    try {
      const payload = JSON.parse(notification.payload ?? "{}") as {
        jobID?: unknown;
        sequence?: unknown;
      };
      if (
        typeof payload.jobID !== "string" ||
        typeof payload.sequence !== "number"
      ) {
        return;
      }
      const waiters = this.eventWaiters.get(payload.jobID);
      if (waiters === undefined) return;
      for (const waiter of [...waiters]) {
        if (payload.sequence > waiter.afterSequence) waiter.resolve();
      }
    } catch {
      // NOTIFY is only a wake-up hint; timeout and cursor replay remain valid.
    }
  }

  private wakeAllListeners(): void {
    for (const wake of [...this.jobWaiters]) wake();
    for (const waiters of this.eventWaiters.values()) {
      for (const waiter of [...waiters]) waiter.resolve();
    }
  }
}

interface ChallengeRow extends QueryResultRow {
  id: string;
  challenge: string;
  expires_at: Date;
  consumed_at: Date;
}

interface JobRow extends QueryResultRow {
  id: string;
  device_id: string;
  client_job_id: string;
  turn_id: string;
  session_id: string;
  state: AgentJob["state"];
  body_digest: string;
  input_json: JobSubmission["input"] | null;
  last_sequence: number;
  acknowledged_sequence: number;
  lease_owner: string | null;
  lease_epoch: number;
  lease_expires_at: Date | null;
  created_at: Date;
  updated_at: Date;
  terminal_at: Date | null;
  content_deleted_at: Date | null;
  error_code: string | null;
}

interface EventRow extends QueryResultRow {
  id: string;
  job_id: string;
  sequence: number;
  kind: AgentEvent["kind"];
  phase: AgentEvent["phase"];
  payload_version: 1;
  payload_json: Record<string, unknown>;
  created_at: Date;
}

interface ToolRow extends QueryResultRow {
  id: string;
  job_id: string;
  tool_call_id: string;
  tool_name: string;
  schema_version: number;
  arguments_json: Record<string, unknown>;
  mutation: boolean;
  expires_at: Date;
  result_digest: string | null;
  result_json: Record<string, unknown> | null;
  completed_at: Date | null;
}

interface UploadRow extends QueryResultRow {
  id: string;
  device_id: string;
  content_type: string;
  expected_bytes: number;
  expected_digest: string;
  object_key: string;
  completed_at: Date | null;
  created_at: Date;
  deleted_at: Date | null;
}

interface ActivityTokenRow extends QueryResultRow {
  job_id: string;
  device_id: string;
  environment: ActivityToken["environment"];
  encrypted_token: string;
  last_pushed_sequence: number;
  created_at: Date;
}

interface OutboxRow extends QueryResultRow {
  id: string;
  topic: OutboxMessage["topic"];
  aggregate_id: string;
  payload_json: Record<string, unknown>;
  created_at: Date;
  next_attempt_at: Date;
  published_at: Date | null;
  attempt_count: number;
}

function mapJob(row: JobRow): AgentJob {
  return {
    id: row.id,
    deviceID: row.device_id,
    clientJobID: row.client_job_id,
    turnID: row.turn_id,
    sessionID: row.session_id,
    state: row.state,
    bodyDigest: row.body_digest,
    ...(row.input_json === null ? {} : { input: row.input_json }),
    lastSequence: row.last_sequence,
    acknowledgedSequence: row.acknowledged_sequence,
    ...(row.lease_owner === null ? {} : { leaseOwner: row.lease_owner }),
    leaseEpoch: row.lease_epoch,
    ...(row.lease_expires_at === null
      ? {}
      : { leaseExpiresAt: row.lease_expires_at }),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    ...(row.terminal_at === null ? {} : { terminalAt: row.terminal_at }),
    ...(row.content_deleted_at === null
      ? {}
      : { contentDeletedAt: row.content_deleted_at }),
    ...(row.error_code === null ? {} : { errorCode: row.error_code }),
  };
}

function mapEvent(row: EventRow): AgentEvent {
  return {
    id: row.id,
    jobID: row.job_id,
    sequence: row.sequence,
    kind: row.kind,
    phase: row.phase,
    payloadVersion: row.payload_version,
    payload: row.payload_json,
    createdAt: row.created_at,
  };
}

function mapTool(row: ToolRow): ToolRequest {
  return {
    id: row.id,
    jobID: row.job_id,
    toolCallID: row.tool_call_id,
    toolName: row.tool_name,
    schemaVersion: row.schema_version,
    arguments: row.arguments_json,
    mutation: row.mutation,
    expiresAt: row.expires_at,
    ...(row.result_digest === null
      ? {}
      : { resultDigest: row.result_digest }),
    ...(row.result_json === null ? {} : { result: row.result_json }),
    ...(row.completed_at === null ? {} : { completedAt: row.completed_at }),
  };
}

function mapUpload(row: UploadRow): Upload {
  return {
    id: row.id,
    deviceID: row.device_id,
    contentType: row.content_type,
    expectedBytes: Number(row.expected_bytes),
    expectedDigest: row.expected_digest,
    objectKey: row.object_key,
    ...(row.completed_at === null ? {} : { completedAt: row.completed_at }),
    createdAt: row.created_at,
    ...(row.deleted_at === null ? {} : { deletedAt: row.deleted_at }),
  };
}

function mapActivityToken(row: ActivityTokenRow): ActivityToken {
  return {
    jobID: row.job_id,
    deviceID: row.device_id,
    environment: row.environment,
    encryptedToken: row.encrypted_token,
    lastPushedSequence: row.last_pushed_sequence,
    createdAt: row.created_at,
  };
}

function mapOutbox(row: OutboxRow): OutboxMessage {
  return {
    id: row.id,
    topic: row.topic,
    aggregateID: row.aggregate_id,
    payload: row.payload_json,
    createdAt: row.created_at,
    nextAttemptAt: row.next_attempt_at,
    ...(row.published_at === null ? {} : { publishedAt: row.published_at }),
    attemptCount: row.attempt_count,
  };
}

function requiredRow<T>(row: T | undefined): T {
  if (row === undefined) throw new Error("database row missing");
  return row;
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

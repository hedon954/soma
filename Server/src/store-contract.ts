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

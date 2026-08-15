export const protocolVersion = 1;

export type JobState =
  | "accepted"
  | "queued"
  | "running"
  | "waitingForDevice"
  | "completed"
  | "failed"
  | "cancelled"
  | "expired";

export type TerminalJobState =
  | "completed"
  | "failed"
  | "cancelled"
  | "expired";

export interface Device {
  id: string;
  publicKeyPem: string;
  attestationKeyID?: string;
  createdAt: Date;
  revokedAt?: Date;
}

export interface RegistrationChallenge {
  id: string;
  challenge: string;
  expiresAt: Date;
  consumedAt?: Date;
}

export interface AgentJobInput {
  clientJobID: string;
  turnID: string;
  sessionID: string;
  protocolVersion: number;
  modelInput: AgentModelInput;
  mediaBindings: AgentMediaBinding[];
  uploadIDs: string[];
  mediaMode?: "text" | "images" | "keyframes" | "direct_video";
  requestAttempt?: number;
  allowedRemoteTools: string[];
  allowedDeviceTools: string[];
  allowedDeviceToolSchemas?: {
    name: string;
    schemaVersion: number;
  }[];
  liveActivityEnabled: boolean;
}

export interface AgentModelMessage {
  role: "system" | "user" | "assistant";
  text: string;
  mediaIDs: string[];
}

export interface AgentModelSkillSnapshot {
  id: string;
  name?: string;
  description?: string;
  whenToUse?: string;
  content: string;
}

export interface AgentModelTool {
  name: string;
  schemaVersion: number;
  definition: Record<string, unknown>;
}

export interface AgentModelInput {
  schemaVersion: 2;
  messages: AgentModelMessage[];
  skills: AgentModelSkillSnapshot[];
  tools: AgentModelTool[];
  activeTools: string[];
  selectedSkillID?: string;
  runtime: {
    toolChoice: "auto";
    parallelToolCalls: true;
    maxSteps: number;
    deadlines: {
      textTTFT: number;
      imageTTFT: number;
      directVideoTTFT: number;
      textLoopTotal: number;
      imageLoopTotal: number;
      videoLoopTotal: number;
    };
  };
}

export interface AgentMediaBinding {
  id: string;
  uploadID: string;
}

export interface AgentJob {
  id: string;
  deviceID: string;
  clientJobID: string;
  turnID: string;
  sessionID: string;
  state: JobState;
  bodyDigest: string;
  input?: AgentJobInput;
  lastSequence: number;
  acknowledgedSequence: number;
  leaseOwner?: string;
  leaseEpoch: number;
  leaseExpiresAt?: Date;
  createdAt: Date;
  updatedAt: Date;
  terminalAt?: Date;
  contentDeletedAt?: Date;
  errorCode?: string;
}

export interface AgentEvent {
  id: string;
  jobID: string;
  sequence: number;
  kind: "job" | "model" | "tool" | "text" | "output" | "error";
  phase:
    | "started"
    | "updated"
    | "completed"
    | "failed"
    | "cancelled"
    | "suspended";
  payloadVersion: 1;
  payload: Record<string, unknown>;
  createdAt: Date;
}

export interface ToolRequest {
  id: string;
  jobID: string;
  toolCallID: string;
  toolName: string;
  schemaVersion: number;
  arguments: Record<string, unknown>;
  mutation: boolean;
  expiresAt: Date;
  resultDigest?: string;
  result?: Record<string, unknown>;
  completedAt?: Date;
}

export interface Upload {
  id: string;
  deviceID: string;
  contentType: string;
  expectedBytes: number;
  expectedDigest: string;
  objectKey: string;
  completedAt?: Date;
  createdAt: Date;
  deletedAt?: Date;
}

export interface OutboxMessage {
  id: string;
  topic: "job" | "apns" | "cleanup";
  aggregateID: string;
  payload: Record<string, unknown>;
  createdAt: Date;
  nextAttemptAt: Date;
  publishedAt?: Date;
  attemptCount: number;
}

export interface ActivityToken {
  jobID: string;
  deviceID: string;
  environment: "development" | "production";
  encryptedToken: string;
  lastPushedSequence: number;
  createdAt: Date;
}

export interface JobSubmission {
  deviceID: string;
  input: AgentJobInput;
  bodyDigest: string;
  now: Date;
}

export interface JobLease {
  job: AgentJob;
  owner: string;
  epoch: number;
}

export interface ToolResultSubmission {
  toolCallID: string;
  digest: string;
  result: Record<string, unknown>;
}

export class ProtocolError extends Error {
  constructor(
    readonly code:
      | "unauthorized_device"
      | "protocol_unsupported"
      | "idempotency_conflict"
      | "upload_incomplete"
      | "provider_unavailable"
      | "provider_timeout"
      | "waiting_for_device"
      | "tool_schema_unsupported"
      | "job_cancelled"
      | "job_expired"
      | "replay_detected"
      | "invalid_request"
      | "not_found",
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export function isTerminal(state: JobState): state is TerminalJobState {
  return (
    state === "completed" ||
    state === "failed" ||
    state === "cancelled" ||
    state === "expired"
  );
}

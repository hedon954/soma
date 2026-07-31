BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE device_registration_challenges (
    id UUID PRIMARY KEY,
    challenge TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ
);

CREATE TABLE devices (
    id UUID PRIMARY KEY,
    public_key_pem TEXT NOT NULL,
    attestation_key_id TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE TABLE request_nonces (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    nonce TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (device_id, nonce)
);

CREATE TYPE agent_job_state AS ENUM (
    'accepted',
    'queued',
    'running',
    'waitingForDevice',
    'completed',
    'failed',
    'cancelled',
    'expired'
);

CREATE TABLE agent_jobs (
    id UUID PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    client_job_id UUID NOT NULL,
    turn_id UUID NOT NULL,
    session_id UUID NOT NULL,
    state agent_job_state NOT NULL,
    body_digest TEXT NOT NULL CHECK (length(body_digest) = 64),
    input_json JSONB,
    last_sequence INTEGER NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
    acknowledged_sequence INTEGER NOT NULL DEFAULT 0 CHECK (acknowledged_sequence >= 0),
    lease_owner TEXT,
    lease_epoch INTEGER NOT NULL DEFAULT 0 CHECK (lease_epoch >= 0),
    lease_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    terminal_at TIMESTAMPTZ,
    content_deleted_at TIMESTAMPTZ,
    error_code TEXT,
    UNIQUE (device_id, client_job_id)
);

CREATE INDEX agent_jobs_worker_idx
    ON agent_jobs (state, lease_expires_at, created_at);
CREATE INDEX agent_jobs_retention_idx
    ON agent_jobs (created_at, terminal_at, content_deleted_at);

CREATE TABLE agent_events (
    id UUID PRIMARY KEY,
    job_id UUID NOT NULL REFERENCES agent_jobs(id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL CHECK (sequence > 0),
    kind TEXT NOT NULL,
    phase TEXT NOT NULL,
    payload_version INTEGER NOT NULL DEFAULT 1,
    payload_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (job_id, sequence)
);

CREATE INDEX agent_events_cursor_idx
    ON agent_events (job_id, sequence);

CREATE TABLE agent_tool_requests (
    id UUID PRIMARY KEY,
    job_id UUID NOT NULL REFERENCES agent_jobs(id) ON DELETE CASCADE,
    tool_call_id UUID NOT NULL,
    tool_name TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    arguments_json JSONB NOT NULL,
    mutation BOOLEAN NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    result_digest TEXT,
    result_json JSONB,
    completed_at TIMESTAMPTZ,
    UNIQUE (job_id, tool_call_id)
);

CREATE TABLE temporary_uploads (
    id UUID PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL,
    expected_bytes BIGINT NOT NULL CHECK (expected_bytes > 0),
    expected_digest TEXT NOT NULL CHECK (length(expected_digest) = 64),
    object_key TEXT NOT NULL UNIQUE,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX temporary_uploads_retention_idx
    ON temporary_uploads (created_at, deleted_at);

CREATE TABLE agent_job_uploads (
    job_id UUID NOT NULL REFERENCES agent_jobs(id) ON DELETE CASCADE,
    upload_id UUID NOT NULL REFERENCES temporary_uploads(id) ON DELETE CASCADE,
    PRIMARY KEY (job_id, upload_id)
);

CREATE TABLE activity_tokens (
    job_id UUID PRIMARY KEY REFERENCES agent_jobs(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    environment TEXT NOT NULL CHECK (environment IN ('development', 'production')),
    encrypted_token TEXT NOT NULL,
    last_pushed_sequence INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE transactional_outbox (
    id UUID PRIMARY KEY,
    topic TEXT NOT NULL CHECK (topic IN ('job', 'apns', 'cleanup')),
    aggregate_id UUID NOT NULL,
    payload_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX transactional_outbox_pending_idx
    ON transactional_outbox (next_attempt_at, created_at)
    WHERE published_at IS NULL;

COMMIT;

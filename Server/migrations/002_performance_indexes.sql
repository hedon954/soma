BEGIN;

-- Cleanup scans operate on expiry/revocation timestamps rather than primary keys.
CREATE INDEX request_nonces_expiry_idx
    ON request_nonces (expires_at);
CREATE INDEX device_registration_challenges_expiry_idx
    ON device_registration_challenges (expires_at);
CREATE INDEX devices_revoked_idx
    ON devices (revoked_at)
    WHERE revoked_at IS NOT NULL;

-- Device erasure and Job-content cleanup address these tables by foreign or
-- application-level aggregate keys.
CREATE INDEX activity_tokens_device_idx
    ON activity_tokens (device_id);
CREATE INDEX transactional_outbox_aggregate_idx
    ON transactional_outbox (aggregate_id);

-- UNIQUE (job_id, sequence) already owns an equivalent btree index and serves
-- the cursor query's equality-plus-range access path.
DROP INDEX IF EXISTS agent_events_cursor_idx;

COMMIT;

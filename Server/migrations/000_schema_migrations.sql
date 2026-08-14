CREATE TABLE IF NOT EXISTS soma_schema_migrations (
    filename TEXT PRIMARY KEY,
    checksum TEXT NOT NULL CHECK (length(checksum) = 64),
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

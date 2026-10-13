-- Design migration for the separately deployed APNs service. Not used by the app.
-- The authenticated API must encrypt tokens and validate targets before writing.
CREATE TABLE activity_subscriptions (
    installation_id uuid NOT NULL,
    activity_id text NOT NULL,
    environment text NOT NULL CHECK (environment IN ('sandbox', 'production')),
    token_ciphertext bytea NOT NULL,
    token_generation bigint NOT NULL DEFAULT 1,
    target jsonb NOT NULL,
    query_hash bytea NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    next_poll_at timestamptz NOT NULL DEFAULT now(),
    lease_until timestamptz,
    last_content jsonb,
    last_sent_epoch bigint,
    failure_count integer NOT NULL DEFAULT 0,
    PRIMARY KEY (installation_id, activity_id),
    CHECK (expires_at > created_at AND expires_at <= created_at + interval '1 hour')
);
CREATE INDEX activity_due ON activity_subscriptions (next_poll_at)
    WHERE revoked_at IS NULL;
CREATE INDEX activity_expiry ON activity_subscriptions (expires_at);

-- Registration is an authenticated transaction. Reject an existing tombstone.
-- Rotation updates token_ciphertext and increments token_generation atomically.
-- Worker delivery must verify the leased generation still matches before sending.
-- DELETE sets revoked_at, clears encrypted tokens, and retains the row until cleanup.
-- Server validates every target field and computes query_hash; never trust client hashes.

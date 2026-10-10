-- Let the expired-auth sweep seek revoked credentials instead of scanning the
-- table. Partial, so only revoked rows have entries: issuing a credential and
-- the hourly last_used_at update add no index writes.
CREATE INDEX credentials_revoked ON credentials(revoked_at) WHERE revoked_at IS NOT NULL;

-- A reviewer code is not an app or MCP bearer credential. Only the OAuth
-- sign-in form can exchange it for a normal, consented MCP authorization.
CREATE TABLE review_credentials (
  token_hash TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX review_credentials_tenant ON review_credentials(tenant_id, expires_at);

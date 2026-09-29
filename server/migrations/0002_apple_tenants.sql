-- Preserve data from the original single-user prototype in an unclaimed
-- legacy tenant. Production had no data when this migration was introduced.
CREATE TABLE tenants (
  id TEXT PRIMARY KEY,
  apple_subject TEXT UNIQUE,
  email TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

INSERT INTO tenants (id, apple_subject, email, created_at, updated_at)
VALUES ('00000000-0000-4000-8000-000000000000', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

ALTER TABLE projects ADD COLUMN tenant_id TEXT REFERENCES tenants(id);
ALTER TABLE tasks ADD COLUMN tenant_id TEXT REFERENCES tenants(id);
UPDATE projects SET tenant_id = '00000000-0000-4000-8000-000000000000';
UPDATE tasks SET tenant_id = '00000000-0000-4000-8000-000000000000';

DROP INDEX tasks_project_order;
DROP INDEX tasks_open_start;
CREATE INDEX projects_tenant_name ON projects(tenant_id, name COLLATE NOCASE);
CREATE INDEX tasks_tenant_project_order ON tasks(tenant_id, project_id, completed_at, sort_order, created_at);
CREATE INDEX tasks_tenant_open_start ON tasks(tenant_id, completed_at, start_date, due_date);

-- SQLite's project_id foreign key checks existence, while these triggers
-- enforce that a task and its project have the same owner.
CREATE TRIGGER projects_require_tenant_insert BEFORE INSERT ON projects
WHEN NEW.tenant_id IS NULL
BEGIN SELECT RAISE(ABORT, 'tenant required'); END;
CREATE TRIGGER projects_require_tenant_update BEFORE UPDATE OF tenant_id ON projects
WHEN NEW.tenant_id IS NULL OR NEW.tenant_id != OLD.tenant_id
BEGIN SELECT RAISE(ABORT, 'tenant cannot change'); END;
CREATE TRIGGER tasks_tenant_project_insert BEFORE INSERT ON tasks
WHEN NEW.tenant_id IS NULL OR
  (NEW.project_id IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM projects WHERE id = NEW.project_id AND tenant_id = NEW.tenant_id))
BEGIN SELECT RAISE(ABORT, 'task tenant or project mismatch'); END;
CREATE TRIGGER tasks_tenant_project_update BEFORE UPDATE OF tenant_id, project_id ON tasks
WHEN NEW.tenant_id IS NULL OR NEW.tenant_id != OLD.tenant_id OR
  (NEW.project_id IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM projects WHERE id = NEW.project_id AND tenant_id = NEW.tenant_id))
BEGIN SELECT RAISE(ABORT, 'task tenant or project mismatch'); END;

CREATE TABLE credentials (
  token_hash TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('app', 'mcp')),
  audience TEXT NOT NULL,
  scopes TEXT NOT NULL,
  label TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX credentials_tenant ON credentials(tenant_id, kind, created_at);

CREATE TABLE oauth_flows (
  id_hash TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  client_name TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  client_state TEXT,
  resource TEXT NOT NULL,
  scopes TEXT NOT NULL,
  apple_nonce TEXT NOT NULL,
  tenant_id TEXT REFERENCES tenants(id),
  consent_hash TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE oauth_codes (
  code_hash TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  client_id TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  resource TEXT NOT NULL,
  scopes TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  redeemed_at TEXT
);

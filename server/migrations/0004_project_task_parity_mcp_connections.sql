-- Projects are completable top-level items with the same scheduling and notes
-- as tasks; tasks with a project_id are their subtasks.
ALTER TABLE projects ADD COLUMN notes TEXT NOT NULL DEFAULT '';
ALTER TABLE projects ADD COLUMN completed_at TEXT;
ALTER TABLE projects ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
CREATE INDEX projects_tenant_open_order ON projects(tenant_id, completed_at, start_date, due_date, sort_order);

-- Opaque public IDs let the app manage MCP grants without exposing token
-- hashes or raw bearer credentials.
ALTER TABLE credentials ADD COLUMN id TEXT;
UPDATE credentials SET id = lower(hex(randomblob(16))) WHERE id IS NULL;
CREATE UNIQUE INDEX credentials_public_id ON credentials(id);
ALTER TABLE credentials ADD COLUMN last_used_at TEXT;

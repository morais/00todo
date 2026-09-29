ALTER TABLE projects ADD COLUMN start_date TEXT;
ALTER TABLE projects ADD COLUMN due_date TEXT;
CREATE INDEX projects_tenant_start ON projects(tenant_id, start_date, due_date);

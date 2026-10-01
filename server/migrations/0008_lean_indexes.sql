-- D1 bills every index entry a write touches. Every query filters by
-- tenant_id or looks up a primary key, so the composite indexes on dates,
-- completion, sort order, and name only added writes when a task was
-- completed or rescheduled. Keep one tenant index per table, plus
-- tasks(project_id) for the ON DELETE SET NULL action when a project goes.
DROP INDEX tasks_tenant_project_order;
DROP INDEX tasks_tenant_open_start;
DROP INDEX projects_tenant_name;
DROP INDEX projects_tenant_start;
DROP INDEX projects_tenant_open_order;
CREATE INDEX tasks_tenant ON tasks(tenant_id);
CREATE INDEX tasks_project ON tasks(project_id);
CREATE INDEX projects_tenant ON projects(tenant_id);

-- A per-tenant revision lets GET /v1/snapshot answer 304 Not Modified after
-- reading one row, instead of re-reading every task and project. Every change
-- to a tenant's tasks or projects bumps it.
ALTER TABLE tenants ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;

CREATE TRIGGER tasks_revision_insert AFTER INSERT ON tasks
BEGIN UPDATE tenants SET revision = revision + 1 WHERE id = NEW.tenant_id; END;
CREATE TRIGGER tasks_revision_update AFTER UPDATE ON tasks
BEGIN UPDATE tenants SET revision = revision + 1 WHERE id = NEW.tenant_id; END;
CREATE TRIGGER tasks_revision_delete AFTER DELETE ON tasks
BEGIN UPDATE tenants SET revision = revision + 1 WHERE id = OLD.tenant_id; END;
CREATE TRIGGER projects_revision_insert AFTER INSERT ON projects
BEGIN UPDATE tenants SET revision = revision + 1 WHERE id = NEW.tenant_id; END;
CREATE TRIGGER projects_revision_update AFTER UPDATE ON projects
BEGIN UPDATE tenants SET revision = revision + 1 WHERE id = NEW.tenant_id; END;
CREATE TRIGGER projects_revision_delete AFTER DELETE ON projects
BEGIN UPDATE tenants SET revision = revision + 1 WHERE id = OLD.tenant_id; END;

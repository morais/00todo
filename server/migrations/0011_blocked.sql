-- Blocked is a second explicit holding state. Existing items remain unblocked.
ALTER TABLE projects ADD COLUMN blocked INTEGER NOT NULL DEFAULT 0 CHECK (blocked IN (0, 1));
ALTER TABLE tasks ADD COLUMN blocked INTEGER NOT NULL DEFAULT 0 CHECK (blocked IN (0, 1));

-- Deleting a blocked project must not silently release open subtasks.
CREATE TRIGGER projects_preserve_blocked_children BEFORE DELETE ON projects
WHEN OLD.blocked = 1
BEGIN
  UPDATE tasks SET blocked = 1
  WHERE tenant_id = OLD.tenant_id AND project_id = OLD.id AND completed_at IS NULL;
END;

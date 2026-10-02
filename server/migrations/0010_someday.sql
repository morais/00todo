-- Someday is an explicit, unscheduled holding area. Existing rows stay active.
ALTER TABLE projects ADD COLUMN someday INTEGER NOT NULL DEFAULT 0 CHECK (someday IN (0, 1));
ALTER TABLE tasks ADD COLUMN someday INTEGER NOT NULL DEFAULT 0 CHECK (someday IN (0, 1));

-- Deleting a Someday project makes its open subtasks standalone without
-- unexpectedly releasing them into Available.
CREATE TRIGGER projects_preserve_someday_children BEFORE DELETE ON projects
WHEN OLD.someday = 1
BEGIN
  UPDATE tasks SET someday = 1
  WHERE tenant_id = OLD.tenant_id AND project_id = OLD.id AND completed_at IS NULL;
END;

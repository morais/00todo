-- A start time is an optional local wall-clock time paired with start_date.
ALTER TABLE projects ADD COLUMN start_time TEXT CHECK (start_time IS NULL OR start_date IS NOT NULL);
ALTER TABLE tasks ADD COLUMN start_time TEXT CHECK (start_time IS NULL OR start_date IS NOT NULL);

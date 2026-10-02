import { z } from "zod";

const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value) => {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}, "Use a real YYYY-MM-DD calendar date");
const timeOnly = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use a 24-hour HH:mm time");

export const ProjectInput = z.strictObject({
  id: z.uuid().optional(),
  name: z.string().trim().min(1).max(120),
  notes: z.string().max(20000).default(""),
  startDate: dateOnly.nullable().default(null),
  startTime: timeOnly.nullable().default(null),
  dueDate: dateOnly.nullable().default(null),
  someday: z.boolean().default(false),
  sortOrder: z.number().int().min(-1000000).max(1000000).default(0),
});

export const ProjectPatch = z.strictObject({
  name: z.string().trim().min(1).max(120).optional(),
  notes: z.string().max(20000).optional(),
  startDate: dateOnly.nullable().optional(),
  startTime: timeOnly.nullable().optional(),
  dueDate: dateOnly.nullable().optional(),
  someday: z.boolean().optional(),
  sortOrder: z.number().int().min(-1000000).max(1000000).optional(),
  completed: z.boolean().optional(),
});

export const TaskInput = z.strictObject({
  id: z.uuid().optional(),
  title: z.string().trim().min(1).max(240),
  notes: z.string().max(20000).default(""),
  projectId: z.uuid().nullable().default(null),
  startDate: dateOnly.nullable().default(null),
  startTime: timeOnly.nullable().default(null),
  dueDate: dateOnly.nullable().default(null),
  someday: z.boolean().default(false),
  sortOrder: z.number().int().min(-1000000).max(1000000).default(0),
});

export const ProjectWithTasksInput = z.strictObject({
  project: ProjectInput,
  tasks: z.array(TaskInput.omit({ projectId: true })).max(50),
});

export const TaskPatch = z.strictObject({
  title: z.string().trim().min(1).max(240).optional(),
  notes: z.string().max(20000).optional(),
  projectId: z.uuid().nullable().optional(),
  startDate: dateOnly.nullable().optional(),
  startTime: timeOnly.nullable().optional(),
  dueDate: dateOnly.nullable().optional(),
  someday: z.boolean().optional(),
  sortOrder: z.number().int().min(-1000000).max(1000000).optional(),
  completed: z.boolean().optional(),
});

export type Task = {
  id: string;
  title: string;
  notes: string;
  projectId: string | null;
  startDate: string | null;
  startTime: string | null;
  dueDate: string | null;
  someday: boolean;
  completedAt: string | null;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
};

export type Project = {
  id: string;
  name: string;
  notes: string;
  startDate: string | null;
  startTime: string | null;
  dueDate: string | null;
  someday: boolean;
  completedAt: string | null;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
};

export type TaskView = "available" | "upcoming" | "someday" | "completed" | "all";
export type ProjectView = "available" | "upcoming" | "someday" | "completed" | "all";

export function startsLater(startDate: string | null, startTime: string | null, today: string, nowTime = "23:59"): boolean {
  return startDate !== null && (startDate > today || (startDate === today && startTime !== null && startTime > nowTime));
}

export function projectInView(project: Project, view: ProjectView, today: string, nowTime = "23:59"): boolean {
  if (view === "someday") return project.completedAt === null && project.someday;
  if (project.someday) return false;
  if (view === "all") return true;
  if (view === "completed") return project.completedAt !== null;
  if (project.completedAt !== null) return false;
  const future = startsLater(project.startDate, project.startTime, today, nowTime);
  return view === "upcoming" ? future : !future;
}

export function inView(task: Task, view: TaskView, today: string, projectStartDate: string | null = null, projectCompletedAt: string | null = null, nowTime = "23:59", projectStartTime: string | null = null, projectSomeday = false): boolean {
  if (view === "someday") return task.completedAt === null && projectCompletedAt === null && (task.someday || projectSomeday);
  if (task.someday || projectSomeday) return false;
  if (view === "all") return true;
  if (view === "completed") return task.completedAt !== null;
  if (task.completedAt !== null || projectCompletedAt !== null) return false;
  const future = startsLater(task.startDate, task.startTime, today, nowTime)
    || startsLater(projectStartDate, projectStartTime, today, nowTime);
  return view === "upcoming" ? future : !future;
}

export function parseToday(value: string | null): string | null {
  return value && dateOnly.safeParse(value).success ? value : null;
}

export function parseTime(value: string | null): string | null {
  return value && timeOnly.safeParse(value).success ? value : null;
}

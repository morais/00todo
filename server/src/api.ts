import { ProjectInput, ProjectPatch, ProjectWithTasksInput, TaskInput, TaskPatch, inView, projectInView, parseToday, parseTime, type Project, type ProjectView, type Task, type TaskView } from "./model";
import { ZodError } from "zod";
import { tenantForPrincipal, type Principal } from "./auth";
import { capacityProblem, tenantLimits } from "./rateLimit";

export interface Env {
  DB: D1Database;
  PUBLIC_ORIGIN: string;
  DEFAULT_TIME_ZONE?: string;
  APPLE_APP_CLIENT_ID?: string;
  APPLE_WEB_CLIENT_ID?: string;
  APPLE_WEB_REDIRECT_URI?: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  OAUTH_SIGNING_SECRET?: string;
  MCP_VERIFIED_CLIENTS?: string;
  SOURCE_LIMITER?: RateLimit;
  SIGN_IN_LIMITER?: RateLimit;
  TENANT_LIMITER?: RateLimit;
}

type ProjectRow = {
  id: string; name: string; notes: string; start_date: string | null;
  start_time: string | null; due_date: string | null; completed_at: string | null; sort_order: number;
  created_at: string; updated_at: string;
};
type TaskRow = {
  id: string; title: string; notes: string; project_id: string | null;
  start_date: string | null; start_time: string | null; due_date: string | null; completed_at: string | null;
  sort_order: number; created_at: string; updated_at: string;
};

const project = (row: ProjectRow): Project => ({
  id: row.id, name: row.name, notes: row.notes, startDate: row.start_date,
  startTime: row.start_time,
  dueDate: row.due_date, completedAt: row.completed_at, sortOrder: row.sort_order,
  createdAt: row.created_at, updatedAt: row.updated_at,
});
const task = (row: TaskRow): Task => ({
  id: row.id, title: row.title, notes: row.notes, projectId: row.project_id,
  startDate: row.start_date, startTime: row.start_time, dueDate: row.due_date, completedAt: row.completed_at,
  sortOrder: row.sort_order, createdAt: row.created_at, updatedAt: row.updated_at,
});

export const json = (value: unknown, status = 200): Response => Response.json(value, {
  status,
  headers: { "Cache-Control": "no-store" },
});

export function dateInZone(instant: Date, zone: string): string {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(instant);
    const value = (part: string) => parts.find((item) => item.type === part)?.value ?? "";
    return `${value("year")}-${value("month")}-${value("day")}`;
  } catch {
    return instant.toISOString().slice(0, 10);
  }
}

export function timeInZone(instant: Date, zone: string): string {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: zone, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
    }).formatToParts(instant);
    const value = (part: string) => parts.find((item) => item.type === part)?.value ?? "";
    return `${value("hour")}:${value("minute")}`;
  } catch {
    return instant.toISOString().slice(11, 16);
  }
}

const snapshotCompletedDays = 90;

function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

async function body(req: Request): Promise<unknown> {
  if (Number(req.headers.get("content-length") ?? 0) > 25000) throw new HttpError(413, "Request too large");
  const raw = await req.text();
  if (raw.length > 25000) throw new HttpError(413, "Request too large");
  try { return JSON.parse(raw); } catch { throw new HttpError(400, "Expected a JSON object"); }
}

class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

function ensureProject(rows: ProjectRow | null): ProjectRow {
  if (!rows) throw new HttpError(404, "Project not found");
  return rows;
}
function ensureTask(rows: TaskRow | null): TaskRow {
  if (!rows) throw new HttpError(404, "Task not found");
  return rows;
}

function ensureStartTime(startDate: string | null, startTime: string | null): void {
  if (startTime !== null && startDate === null) throw new HttpError(400, "Start time requires a start date");
}

async function findProject(db: D1Database, id: string, tenantId: string): Promise<ProjectRow | null> {
  return db.prepare("SELECT * FROM projects WHERE id = ? AND tenant_id = ?").bind(id, tenantId).first<ProjectRow>();
}
async function findTask(db: D1Database, id: string, tenantId: string): Promise<TaskRow | null> {
  return db.prepare("SELECT * FROM tasks WHERE id = ? AND tenant_id = ?").bind(id, tenantId).first<TaskRow>();
}

async function ensureCapacity(db: D1Database, tenantId: string, adding: { tasks?: number; projects?: number }): Promise<void> {
  const problem = await capacityProblem(db, tenantId, adding);
  if (problem) throw new HttpError(403, problem);
}

/// Each write is one statement that validates through D1's own constraints
/// and returns the saved row, instead of a read before and after. This maps
/// those constraint failures back to the API's errors.
async function write<T>(run: () => Promise<T>): Promise<T> {
  try { return await run(); }
  catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    if (message.includes("task tenant or project mismatch")) throw new HttpError(404, "Project not found");
    if (message.includes("start_date IS NOT NULL")) throw new HttpError(400, "Start time requires a start date");
    throw cause;
  }
}

/// Explains a create that returned no row: an idempotent retry, a full
/// account, or an ID another account already uses.
async function createConflict(db: D1Database, tenantId: string, kind: "tasks" | "projects"): Promise<HttpError> {
  const problem = await capacityProblem(db, tenantId, { [kind]: 1 });
  if (problem) return new HttpError(403, problem);
  return new HttpError(409, `${kind === "tasks" ? "Task" : "Project"} ID belongs to another account`);
}

export async function routeApi(req: Request, env: Env, principal: Principal): Promise<Response> {
  try {
    const required = req.method === "GET" ? "todo:read" : "todo:write";
    if (!principal.scopes.includes(required)) return error("Insufficient scope", 403);
    return await dispatch(req, env, principal);
  } catch (cause) {
    if (cause instanceof HttpError) return error(cause.message, cause.status);
    if (cause instanceof ZodError) return json({ error: "Invalid input", issues: cause.issues }, 400);
    console.error("00Todo API error", cause);
    return error("Internal server error", 500);
  }
}

async function dispatch(req: Request, env: Env, principal: Principal): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const now = new Date().toISOString();
  const method = req.method;
  const tenantId = principal.tenantId;

  if (path === "/v1/me" && method === "GET") {
    const tenant = await tenantForPrincipal(env, principal);
    if (!tenant) return error("Account not found", 404);
    return json({ tenant: { id: tenant.id, email: tenant.email } });
  }

  if (path === "/v1/snapshot" && method === "GET") {
    // The revision is read before the rows, so a write landing in between can
    // only make the ETag older than the data, which costs one extra download
    // later and never hides a change.
    const revision = await env.DB.prepare("SELECT revision FROM tenants WHERE id = ?")
      .bind(tenantId).first<number>("revision");
    const etag = revision === null ? null : `"r${revision}"`;
    if (etag && req.headers.get("if-none-match") === etag) {
      return new Response(null, { status: 304, headers: { ETag: etag, "Cache-Control": "no-store" } });
    }
    // Completed history older than the window stays in D1 and in the list
    // endpoints, but is left out of the app's snapshot so the payload stays
    // proportional to what is current. Tasks of a project completed before
    // the window go with it.
    const completedSince = new Date(Date.parse(now) - snapshotCompletedDays * 86400000).toISOString();
    const [projects, tasks] = await env.DB.batch<ProjectRow | TaskRow>([
      env.DB.prepare(`SELECT * FROM projects WHERE tenant_id = ?1
        AND (completed_at IS NULL OR completed_at >= ?2) ORDER BY sort_order, created_at, id`).bind(tenantId, completedSince),
      env.DB.prepare(`SELECT * FROM tasks WHERE tenant_id = ?1
        AND (completed_at IS NULL OR completed_at >= ?2)
        AND (project_id IS NULL OR project_id NOT IN
          (SELECT id FROM projects WHERE tenant_id = ?1 AND completed_at < ?2))
        ORDER BY sort_order, created_at, id`).bind(tenantId, completedSince),
    ]);
    const response = json({
      projects: (projects.results as ProjectRow[]).map(project),
      tasks: (tasks.results as TaskRow[]).map(task),
      serverTime: now,
      completedSince,
    });
    if (etag) response.headers.set("ETag", etag);
    return response;
  }

  if (path === "/v1/projects" && method === "GET") {
    const viewParam = url.searchParams.get("view") ?? "all";
    if (!["available", "upcoming", "completed", "all"].includes(viewParam)) throw new HttpError(400, "Invalid view");
    const todayInput = url.searchParams.get("today");
    if (url.searchParams.has("today") && !parseToday(todayInput)) throw new HttpError(400, "Invalid today date");
    const timeInput = url.searchParams.get("time");
    if (url.searchParams.has("time") && !parseTime(timeInput)) throw new HttpError(400, "Invalid time");
    const today = parseToday(todayInput) ?? dateInZone(new Date(now), env.DEFAULT_TIME_ZONE ?? "UTC");
    const currentTime = parseTime(timeInput) ?? timeInZone(new Date(now), env.DEFAULT_TIME_ZONE ?? "UTC");
    const rows = await env.DB.prepare("SELECT * FROM projects WHERE tenant_id = ? ORDER BY sort_order, created_at, id").bind(tenantId).all<ProjectRow>();
    return json({ projects: rows.results.map(project).filter((item) => projectInView(item, viewParam as ProjectView, today, currentTime)), today });
  }
  if (path === "/v1/projects" && method === "POST") {
    const input = ProjectInput.parse(await body(req));
    ensureStartTime(input.startDate, input.startTime);
    const id = input.id ?? crypto.randomUUID();
    const saved = await write(() => env.DB.prepare(`INSERT INTO projects
      (id, tenant_id, name, notes, start_date, start_time, due_date, sort_order, created_at, updated_at)
      SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9
      WHERE (SELECT COUNT(*) FROM projects WHERE tenant_id = ?2) < ?10
      ON CONFLICT(id) DO NOTHING RETURNING *`)
      .bind(id, tenantId, input.name, input.notes, input.startDate, input.startTime, input.dueDate, input.sortOrder, now,
        tenantLimits.projects).first<ProjectRow>());
    if (saved) return json({ project: project(saved) }, 201);
    const existing = await findProject(env.DB, id, tenantId);
    if (existing) return json({ project: project(existing) });
    throw await createConflict(env.DB, tenantId, "projects");
  }
  if (path === "/v1/projects-with-tasks" && method === "POST") {
    const input = ProjectWithTasksInput.parse(await body(req));
    ensureStartTime(input.project.startDate, input.project.startTime);
    for (const item of input.tasks) ensureStartTime(item.startDate, item.startTime);
    const projectId = input.project.id ?? crypto.randomUUID();
    const taskIds = input.tasks.map((item) => item.id ?? crypto.randomUUID());
    const existing = await findProject(env.DB, projectId, tenantId);
    if (existing) {
      const savedTasks = await Promise.all(taskIds.map((id) => findTask(env.DB, id, tenantId)));
      if (savedTasks.some((item) => item === null || item.project_id !== projectId)) {
        throw new HttpError(409, "Project ID already exists");
      }
      return json({ project: project(existing), tasks: savedTasks.map((item) => task(item!)) });
    }
    await ensureCapacity(env.DB, tenantId, { projects: 1, tasks: input.tasks.length });
    const statements = [
      env.DB.prepare(`INSERT INTO projects
        (id, tenant_id, name, notes, start_date, start_time, due_date, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`)
        .bind(projectId, tenantId, input.project.name, input.project.notes, input.project.startDate,
          input.project.startTime, input.project.dueDate, input.project.sortOrder, now, now),
      ...input.tasks.map((item, index) => env.DB.prepare(`INSERT INTO tasks
        (id, tenant_id, title, notes, project_id, start_date, start_time, due_date, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`)
        .bind(taskIds[index], tenantId, item.title, item.notes, projectId, item.startDate,
          item.startTime, item.dueDate, item.sortOrder, now, now)),
    ];
    let results: D1Result<ProjectRow | TaskRow>[];
    try { results = await env.DB.batch<ProjectRow | TaskRow>(statements); }
    catch (cause) {
      if (await findProject(env.DB, projectId, tenantId)) {
        const savedTasks = await Promise.all(taskIds.map((id) => findTask(env.DB, id, tenantId)));
        if (savedTasks.every((item) => item !== null && item.project_id === projectId)) {
          return json({ project: project(ensureProject(await findProject(env.DB, projectId, tenantId))),
            tasks: savedTasks.map((item) => task(item!)) });
        }
      }
      throw cause;
    }
    const [savedProject, ...savedTasks] = results.map((result) => result.results[0]);
    return json({
      project: project(savedProject as ProjectRow),
      tasks: (savedTasks as TaskRow[]).map(task),
    }, 201);
  }
  const projectMatch = /^\/v1\/projects\/([a-f0-9-]{36})$/.exec(path);
  if (projectMatch) {
    const id = projectMatch[1];
    if (method === "GET") return json({ project: project(ensureProject(await findProject(env.DB, id, tenantId))) });
    if (method === "PATCH") {
      const input = ProjectPatch.parse(await body(req));
      if (!Object.keys(input).length) throw new HttpError(400, "No changes supplied");
      if (input.startDate === null && input.startTime) ensureStartTime(null, input.startTime);
      const assignments: string[] = [];
      const values: Array<string | number | null> = [];
      if (input.name !== undefined) { assignments.push("name = ?"); values.push(input.name); }
      if (input.notes !== undefined) { assignments.push("notes = ?"); values.push(input.notes); }
      if (input.startDate !== undefined) { assignments.push("start_date = ?"); values.push(input.startDate); }
      if (input.startTime !== undefined) { assignments.push("start_time = ?"); values.push(input.startTime); }
      if (input.dueDate !== undefined) { assignments.push("due_date = ?"); values.push(input.dueDate); }
      if (input.sortOrder !== undefined) { assignments.push("sort_order = ?"); values.push(input.sortOrder); }
      if (input.completed === true) { assignments.push("completed_at = COALESCE(completed_at, ?)"); values.push(now); }
      else if (input.completed === false) assignments.push("completed_at = NULL");
      assignments.push("updated_at = ?");
      values.push(now);
      const saved = await write(() => env.DB.prepare(`UPDATE projects SET ${assignments.join(", ")}
        WHERE id = ? AND tenant_id = ? RETURNING *`).bind(...values, id, tenantId).first<ProjectRow>());
      return json({ project: project(ensureProject(saved)) });
    }
    if (method === "DELETE") {
      const deleted = await env.DB.prepare("DELETE FROM projects WHERE id = ? AND tenant_id = ? RETURNING id")
        .bind(id, tenantId).first<{ id: string }>();
      if (!deleted) throw new HttpError(404, "Project not found");
      return json({ ok: true });
    }
  }

  if (path === "/v1/tasks" && method === "GET") {
    const viewParam = url.searchParams.get("view") ?? "available";
    if (!["available", "upcoming", "completed", "all"].includes(viewParam)) throw new HttpError(400, "Invalid view");
    const todayInput = url.searchParams.get("today");
    if (url.searchParams.has("today") && !parseToday(todayInput)) throw new HttpError(400, "Invalid today date");
    const timeInput = url.searchParams.get("time");
    if (url.searchParams.has("time") && !parseTime(timeInput)) throw new HttpError(400, "Invalid time");
    const today = parseToday(todayInput) ?? dateInZone(new Date(now), env.DEFAULT_TIME_ZONE ?? "UTC");
    const currentTime = parseTime(timeInput) ?? timeInZone(new Date(now), env.DEFAULT_TIME_ZONE ?? "UTC");
    const [rows, projectRows] = await Promise.all([
      env.DB.prepare("SELECT * FROM tasks WHERE tenant_id = ? ORDER BY sort_order, created_at, id").bind(tenantId).all<TaskRow>(),
      env.DB.prepare("SELECT id, start_date, start_time, completed_at FROM projects WHERE tenant_id = ?")
        .bind(tenantId).all<Pick<ProjectRow, "id" | "start_date" | "start_time" | "completed_at">>(),
    ]);
    const parentProjects = new Map(projectRows.results.map((item) => [item.id, item]));
    return json({ tasks: rows.results.map(task).filter((item) => {
      const parent = parentProjects.get(item.projectId ?? "");
      return inView(item, viewParam as TaskView, today, parent?.start_date, parent?.completed_at, currentTime, parent?.start_time);
    }), today });
  }
  if (path === "/v1/tasks" && method === "POST") {
    const input = TaskInput.parse(await body(req));
    ensureStartTime(input.startDate, input.startTime);
    const id = input.id ?? crypto.randomUUID();
    // The project's owner is checked by a D1 trigger and the item cap by the
    // WHERE clause, so a new task costs one statement.
    const saved = await write(() => env.DB.prepare(`INSERT INTO tasks
      (id, tenant_id, title, notes, project_id, start_date, start_time, due_date, sort_order, created_at, updated_at)
      SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10
      WHERE (SELECT COUNT(*) FROM tasks WHERE tenant_id = ?2) < ?11
      ON CONFLICT(id) DO NOTHING RETURNING *`).bind(
      id, tenantId, input.title, input.notes, input.projectId, input.startDate, input.startTime, input.dueDate,
      input.sortOrder, now, tenantLimits.tasks,
    ).first<TaskRow>());
    if (saved) return json({ task: task(saved) }, 201);
    const existing = await findTask(env.DB, id, tenantId);
    if (existing) return json({ task: task(existing) });
    throw await createConflict(env.DB, tenantId, "tasks");
  }
  const taskMatch = /^\/v1\/tasks\/([a-f0-9-]{36})$/.exec(path);
  if (taskMatch) {
    const id = taskMatch[1];
    if (method === "GET") return json({ task: task(ensureTask(await findTask(env.DB, id, tenantId))) });
    if (method === "PATCH") {
      const input = TaskPatch.parse(await body(req));
      if (!Object.keys(input).length) throw new HttpError(400, "No changes supplied");
      if (input.startDate === null && input.startTime) ensureStartTime(null, input.startTime);
      const assignments: string[] = [];
      const values: Array<string | number | null> = [];
      const set = (column: string, value: string | number | null) => {
        assignments.push(`${column} = ?`);
        values.push(value);
      };
      if (input.title !== undefined) set("title", input.title);
      if (input.notes !== undefined) set("notes", input.notes);
      if (input.projectId !== undefined) set("project_id", input.projectId);
      if (input.startDate !== undefined) set("start_date", input.startDate);
      if (input.startTime !== undefined) set("start_time", input.startTime);
      if (input.dueDate !== undefined) set("due_date", input.dueDate);
      if (input.sortOrder !== undefined) set("sort_order", input.sortOrder);
      if (input.completed === true) {
        assignments.push("completed_at = COALESCE(completed_at, ?)");
        values.push(now);
      } else if (input.completed === false) {
        assignments.push("completed_at = NULL");
      }
      set("updated_at", now);
      const saved = await write(() => env.DB.prepare(`UPDATE tasks SET ${assignments.join(", ")}
        WHERE id = ? AND tenant_id = ? RETURNING *`).bind(...values, id, tenantId).first<TaskRow>());
      return json({ task: task(ensureTask(saved)) });
    }
    if (method === "DELETE") {
      const deleted = await env.DB.prepare("DELETE FROM tasks WHERE id = ? AND tenant_id = ? RETURNING id")
        .bind(id, tenantId).first<{ id: string }>();
      if (!deleted) throw new HttpError(404, "Task not found");
      return json({ ok: true });
    }
  }
  return error("Not found", 404);
}

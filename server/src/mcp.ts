import { z } from "zod";
import { appName, routeApi, json, type Env } from "./api";
import { ProjectInput, ProjectPatch, TaskInput, TaskPatch } from "./model";
import { type Principal } from "./auth";
import { authChallenge } from "./oauth";

type Tool = {
  name: string;
  description: string;
  schema: z.ZodType<Record<string, unknown>>;
  method: string;
  path: (args: Record<string, unknown>) => string;
  payload?: (args: Record<string, unknown>) => unknown;
  readOnly: boolean;
  destructive?: boolean;
};

const id = z.uuid();
const protocolVersions = new Set(["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26"]);
const tools: Tool[] = [
  {
    name: "list_tasks", description: "List tasks. Available hides incomplete tasks whose own or parent project's start date/time is in the future. Pass today (YYYY-MM-DD) and time (local 24-hour HH:mm) together to use your local clock, or omit both for the server's default time zone.",
    schema: z.object({ view: z.enum(["available", "upcoming", "completed", "all"]).default("available"), today: z.string().optional(), time: z.string().optional() }),
    method: "GET", path: (a) => `/v1/tasks?view=${encodeURIComponent(String(a.view))}${a.today ? `&today=${encodeURIComponent(String(a.today))}` : ""}${a.time ? `&time=${encodeURIComponent(String(a.time))}` : ""}`, readOnly: true,
  },
  { name: "list_projects", description: "List completable projects with their dates and notes. Available hides projects with a future start date/time. Pass today and time together for your local clock.",
    schema: z.object({ view: z.enum(["available", "upcoming", "completed", "all"]).default("available"), today: z.string().optional(), time: z.string().optional() }),
    method: "GET", path: (a) => `/v1/projects?view=${encodeURIComponent(String(a.view))}${a.today ? `&today=${encodeURIComponent(String(a.today))}` : ""}${a.time ? `&time=${encodeURIComponent(String(a.time))}` : ""}`, readOnly: true },
  { name: "create_task", description: "Create a task with independent start and due dates in YYYY-MM-DD format. Optional startTime is local 24-hour HH:mm and requires startDate. A future start date/time hides it from Available.", schema: TaskInput,
    method: "POST", path: () => "/v1/tasks", payload: (a) => a, readOnly: false },
  { name: "update_task", description: "Edit a task's title, notes, project, start date/time, due date, sort order, or completion.",
    schema: TaskPatch.extend({ id }), method: "PATCH", path: (a) => `/v1/tasks/${a.id}`,
    payload: ({ id: _id, ...a }) => a, readOnly: false },
  { name: "delete_task", description: "Permanently delete a task.", schema: z.object({ id }), method: "DELETE", path: (a) => `/v1/tasks/${a.id}`, readOnly: false, destructive: true },
  { name: "create_project", description: "Create a project with notes, independent start and due dates, optional local startTime (HH:mm, requires startDate), and subtasks added with create_task/projectId.", schema: ProjectInput,
    method: "POST", path: () => "/v1/projects", payload: (a) => a, readOnly: false },
  { name: "update_project", description: "Edit a project's name, notes, start date/time, due date, sort order, or completion.", schema: ProjectPatch.extend({ id }),
    method: "PATCH", path: (a) => `/v1/projects/${a.id}`, payload: ({ id: _id, ...a }) => a, readOnly: false },
  { name: "delete_project", description: "Delete a project. Its subtasks become standalone tasks.", schema: z.object({ id }),
    method: "DELETE", path: (a) => `/v1/projects/${a.id}`, readOnly: false, destructive: true },
];

// Tool schemas never change at runtime, so convert them once per isolate
// rather than on every tools/list.
let toolList: unknown[] | undefined;
function listTools(): unknown[] {
  toolList ??= tools.map((tool) => ({
    name: tool.name,
    description: tool.description,
    inputSchema: z.toJSONSchema(tool.schema, { io: "input" }),
    annotations: { readOnlyHint: tool.readOnly, destructiveHint: Boolean(tool.destructive), idempotentHint: tool.method !== "POST" },
  }));
  return toolList;
}

function rpcResult(id: unknown, result: unknown): Response {
  return json({ jsonrpc: "2.0", id, result });
}

function rpcError(id: unknown, code: number, message: string): Response {
  return json({ jsonrpc: "2.0", id, error: { code, message } });
}

export async function routeMcp(req: Request, env: Env, principal: Principal): Promise<Response> {
  if (req.method === "GET") return new Response(null, { status: 405, headers: { Allow: "POST" } });
  if (req.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });
  if (Number(req.headers.get("content-length") ?? 0) > 25000) return rpcError(null, -32600, "Request too large");
  const raw = await req.text();
  if (raw.length > 25000) return rpcError(null, -32600, "Request too large");
  let request: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw Error();
    request = parsed as Record<string, unknown>;
  } catch { return rpcError(null, -32700, "Invalid JSON"); }
  if (request.jsonrpc !== "2.0" || typeof request.method !== "string") return rpcError(request.id ?? null, -32600, "Invalid JSON-RPC request");
  if (request.method === "notifications/initialized" || request.method.startsWith("notifications/")) return new Response(null, { status: 202 });
  const requestId = request.id ?? null;
  if (requestId === null) return rpcError(null, -32600, "Request id required");

  if (request.method === "initialize") {
    const asked = (request.params as { protocolVersion?: unknown } | undefined)?.protocolVersion;
    return rpcResult(requestId, {
      protocolVersion: typeof asked === "string" && protocolVersions.has(asked) ? asked : "2026-07-28",
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: appName(env), version: "1.0.0" },
    });
  }
  if (request.method === "ping") return rpcResult(requestId, {});
  if (request.method === "tools/list") {
    return rpcResult(requestId, { tools: listTools() });
  }
  if (request.method !== "tools/call") return rpcError(requestId, -32601, "Method not found");
  const params = request.params;
  if (!params || typeof params !== "object" || Array.isArray(params)) return rpcError(requestId, -32602, "Missing tool parameters");
  const { name, arguments: args } = params as { name?: unknown; arguments?: unknown };
  const tool = tools.find((candidate) => candidate.name === name);
  if (!tool) return rpcError(requestId, -32602, "Unknown tool");
  const required = tool.readOnly ? "todo:read" : "todo:write";
  if (!principal.scopes.includes(required)) return authChallenge(env, 403, [required]);
  const parsed = tool.schema.safeParse(args ?? {});
  if (!parsed.success) return rpcError(requestId, -32602, "Invalid tool arguments: " + parsed.error.issues.map((issue) => issue.path.join(".") + " " + issue.message).join("; "));

  const target = new URL(tool.path(parsed.data), req.url);
  const restRequest = new Request(target, {
    method: tool.method,
    headers: tool.payload ? { "content-type": "application/json" } : undefined,
    body: tool.payload ? JSON.stringify(tool.payload(parsed.data)) : undefined,
  });
  const response = await routeApi(restRequest, env, principal);
  const value = await response.json() as Record<string, unknown>;
  if (!response.ok) return rpcResult(requestId, { content: [{ type: "text", text: String(value.error ?? "Request failed") }], isError: true });
  return rpcResult(requestId, { content: [{ type: "text", text: JSON.stringify(value) }], structuredContent: value });
}

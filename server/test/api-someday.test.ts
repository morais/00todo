import { describe, expect, it } from "vitest";
import { routeApi, type Env } from "../src/api";
import type { Principal } from "../src/auth";

const tenantId = "11111111-1111-4111-8111-111111111111";
const principal: Principal = { tenantId, kind: "app", scopes: ["todo:read", "todo:write"], tokenHash: "test" };
const created = "2026-10-02T12:00:00Z";
const activeProject = { id: "active", name: "Active", notes: "", start_date: null, start_time: null,
  due_date: null, someday: 0, completed_at: null, sort_order: 0, created_at: created, updated_at: created };
const heldProject = { ...activeProject, id: "held", name: "Someday project", someday: 1 };
const activeTask = { id: "active-task", title: "Active task", notes: "", project_id: null,
  start_date: null, start_time: null, due_date: null, someday: 0, completed_at: null,
  sort_order: 0, created_at: created, updated_at: created };
const heldTask = { ...activeTask, id: "held-task", title: "Someday task", someday: 1 };
const inheritedTask = { ...activeTask, id: "inherited-task", title: "Held by project", project_id: "held" };

function environment() {
  const queries: string[] = [];
  const projects = [activeProject, heldProject];
  const tasks = [activeTask, heldTask, inheritedTask];
  type Statement = { sql: string; args: unknown[] };
  const db = {
    prepare(sql: string) {
      queries.push(sql);
      return {
        bind(...args: unknown[]) {
          const statement: Statement = { sql, args };
          return {
            ...statement,
            async first() { return sql.includes("SELECT revision") ? 7 : null; },
            async all() {
              if (sql.includes("FROM projects")) return { results: projects };
              if (sql.includes("FROM tasks")) return { results: tasks };
              return { results: [] };
            },
          };
        },
      };
    },
    async batch(statements: Statement[]) {
      const includeSomeday = statements[0].args[2] === 1;
      return [
        { results: includeSomeday ? projects : [activeProject] },
        { results: includeSomeday ? tasks : [activeTask] },
      ];
    },
  } as unknown as D1Database;
  return { env: { DB: db, PUBLIC_ORIGIN: "https://api.00todo.com" } as Env, queries };
}

describe("Someday compatibility", () => {
  it("keeps legacy snapshots active-only and gives 1.1 snapshots a separate ETag", async () => {
    const { env, queries } = environment();
    const old = await routeApi(new Request("https://api.00todo.com/v1/snapshot"), env, principal);
    expect(old.status).toBe(200);
    expect(old.headers.get("etag")).toBe('"r7"');
    expect((await old.json() as { projects: unknown[]; tasks: unknown[] })).toMatchObject({
      projects: [{ name: "Active", someday: false }], tasks: [{ title: "Active task", someday: false }],
    });
    const upgraded = await routeApi(new Request("https://api.00todo.com/v1/snapshot?includeSomeday=1", {
      headers: { "if-none-match": '"r7"' },
    }), env, principal);
    expect(upgraded.status).toBe(200);
    expect(upgraded.headers.get("etag")).toBe('"r7-s1"');
    const body = await upgraded.json() as { projects: Array<{ name: string }>; tasks: Array<{ title: string }> };
    expect(body.projects.map((item) => item.name)).toEqual(["Active", "Someday project"]);
    expect(body.tasks.map((item) => item.title)).toEqual(["Active task", "Someday task", "Held by project"]);
    expect(queries.join("\n")).toContain("someday = 0");
    expect(queries.join("\n")).toContain("project_id NOT IN");
    const unchanged = await routeApi(new Request("https://api.00todo.com/v1/snapshot?includeSomeday=1", {
      headers: { "if-none-match": '"r7-s1"' },
    }), env, principal);
    expect(unchanged.status).toBe(304);
  });

  it("exposes an explicit Someday view without changing the old all view", async () => {
    const { env } = environment();
    const tasks = async (view: string) => {
      const response = await routeApi(new Request(`https://api.00todo.com/v1/tasks?view=${view}`), env, principal);
      return (await response.json() as { tasks: Array<{ title: string }> }).tasks.map((item) => item.title);
    };
    expect(await tasks("all")).toEqual(["Active task"]);
    expect(await tasks("someday")).toEqual(["Someday task", "Held by project"]);
    const projects = async (view: string) => {
      const response = await routeApi(new Request(`https://api.00todo.com/v1/projects?view=${view}`), env, principal);
      return (await response.json() as { projects: Array<{ name: string }> }).projects.map((item) => item.name);
    };
    expect(await projects("all")).toEqual(["Active"]);
    expect(await projects("someday")).toEqual(["Someday project"]);
  });
});

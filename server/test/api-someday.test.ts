import { describe, expect, it } from "vitest";
import { routeApi, type Env } from "../src/api";
import type { Principal } from "../src/auth";

const tenantId = "11111111-1111-4111-8111-111111111111";
const principal: Principal = { tenantId, kind: "app", scopes: ["todo:read", "todo:write"], tokenHash: "test" };
const created = "2026-10-02T12:00:00Z";
const activeProject = { id: "active", name: "Active", notes: "", start_date: null, start_time: null,
  due_date: null, someday: 0, blocked: 0, completed_at: null, sort_order: 0, created_at: created, updated_at: created };
const heldProject = { ...activeProject, id: "held", name: "Someday project", someday: 1 };
const blockedProject = { ...activeProject, id: "blocked", name: "Blocked project", blocked: 1 };
const activeTask = { id: "active-task", title: "Active task", notes: "", project_id: null,
  start_date: null, start_time: null, due_date: null, someday: 0, blocked: 0, completed_at: null,
  sort_order: 0, created_at: created, updated_at: created };
const heldTask = { ...activeTask, id: "held-task", title: "Someday task", someday: 1 };
const inheritedTask = { ...activeTask, id: "inherited-task", title: "Held by project", project_id: "held" };
const blockedTask = { ...activeTask, id: "blocked-task", title: "Blocked task", blocked: 1 };
const inheritedBlockedTask = { ...activeTask, id: "inherited-blocked-task", title: "Blocked by project", project_id: "blocked" };

function environment() {
  const queries: string[] = [];
  const projects = [activeProject, heldProject, blockedProject];
  const tasks = [activeTask, heldTask, inheritedTask, blockedTask, inheritedBlockedTask];
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
      const includeBlocked = statements[0].args[3] === 1;
      return [
        { results: projects.filter((item) => (includeSomeday || !item.someday) && (includeBlocked || !item.blocked)) },
        { results: tasks.filter((item) => (includeSomeday || (!item.someday && item.project_id !== "held"))
          && (includeBlocked || (!item.blocked && item.project_id !== "blocked"))) },
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

  it("keeps older snapshots free of Blocked items and gives the new app its own ETag", async () => {
    const { env } = environment();
    const old = await routeApi(new Request("https://api.00todo.com/v1/snapshot?includeSomeday=1"), env, principal);
    const oldBody = await old.json() as { projects: Array<{ name: string }>; tasks: Array<{ title: string }> };
    expect(oldBody.projects.map((item) => item.name)).toEqual(["Active", "Someday project"]);
    expect(oldBody.tasks.map((item) => item.title)).toEqual(["Active task", "Someday task", "Held by project"]);
    const upgraded = await routeApi(new Request("https://api.00todo.com/v1/snapshot?includeSomeday=1&includeBlocked=1", {
      headers: { "if-none-match": '"r7-s1"' },
    }), env, principal);
    expect(upgraded.status).toBe(200);
    expect(upgraded.headers.get("etag")).toBe('"r7-s1-b1"');
    const body = await upgraded.json() as { projects: Array<{ name: string; blocked: boolean }>; tasks: Array<{ title: string; blocked: boolean }> };
    expect(body.projects.map((item) => item.name)).toEqual(["Active", "Someday project", "Blocked project"]);
    expect(body.tasks.map((item) => item.title)).toEqual(["Active task", "Someday task", "Held by project", "Blocked task", "Blocked by project"]);
    expect(body.tasks.find((item) => item.title === "Blocked task")?.blocked).toBe(true);
  });

  it("exposes an explicit Someday view without changing the old all view", async () => {
    const { env } = environment();
    const tasks = async (view: string) => {
      const response = await routeApi(new Request(`https://api.00todo.com/v1/tasks?view=${view}`), env, principal);
      return (await response.json() as { tasks: Array<{ title: string }> }).tasks.map((item) => item.title);
    };
    expect(await tasks("all")).toEqual(["Active task"]);
    expect(await tasks("someday")).toEqual(["Someday task", "Held by project"]);
    expect(await tasks("blocked")).toEqual(["Blocked task", "Blocked by project"]);
    const projects = async (view: string) => {
      const response = await routeApi(new Request(`https://api.00todo.com/v1/projects?view=${view}`), env, principal);
      return (await response.json() as { projects: Array<{ name: string }> }).projects.map((item) => item.name);
    };
    expect(await projects("all")).toEqual(["Active"]);
    expect(await projects("someday")).toEqual(["Someday project"]);
    expect(await projects("blocked")).toEqual(["Blocked project"]);
  });

  it("rejects an item marked Blocked and Someday at the same time", async () => {
    const { env } = environment();
    for (const [path, body] of [
      ["/v1/tasks", { title: "Conflicted", blocked: true, someday: true }],
      ["/v1/projects", { name: "Conflicted", blocked: true, someday: true }],
    ] as const) {
      const response = await routeApi(new Request(`https://api.00todo.com${path}`, {
        method: "POST", body: JSON.stringify(body),
      }), env, principal);
      expect(response.status).toBe(400);
    }
  });
});

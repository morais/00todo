import { expect, it } from "vitest";
import { routeMcp } from "../src/mcp";
import type { Env } from "../src/api";
import type { Principal } from "../src/auth";

const env = {} as Env;
const principal = { tenantId: "test", kind: "mcp", scopes: ["todo:read", "todo:write"], tokenHash: "test" } as Principal;

it("exposes task and project tools with JSON schemas", async () => {
  const request = new Request("https://example.com/mcp", {
    method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
  });
  const response = await routeMcp(request, env, principal);
  const body = await response.json() as { result: { tools: Array<{ name: string; inputSchema: object }> } };
  expect(body.result.tools.map((tool) => tool.name)).toContain("create_task");
  expect(body.result.tools.map((tool) => tool.name)).toContain("list_projects");
  expect(body.result.tools[0].inputSchema).toHaveProperty("type", "object");
  const createTask = body.result.tools.find((tool) => tool.name === "create_task") as { inputSchema: { required?: string[] } };
  const updateTask = body.result.tools.find((tool) => tool.name === "update_task") as { inputSchema: { required?: string[] } };
  expect(createTask.inputSchema.required).toEqual(["title"]);
  expect(updateTask.inputSchema.required).toEqual(["id"]);
});

it("rejects invalid tool arguments before any data write", async () => {
  const request = new Request("https://example.com/mcp", {
    method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/call", params: {
      name: "create_task", arguments: { title: "", startDate: "tomorrow" },
    } }),
  });
  const response = await routeMcp(request, env, principal);
  const body = await response.json() as { error: { code: number } };
  expect(body.error.code).toBe(-32602);
});

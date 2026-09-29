import { describe, expect, it } from "vitest";
import { disconnectMcpConnection, listMcpConnections } from "../src/mcpConnections";
import type { Env } from "../src/api";
import type { Principal } from "../src/auth";

type Grant = {
  id: string; tenant_id: string; kind: string; label: string; scopes: string;
  created_at: string; last_used_at: string | null; expires_at: string;
  revoked_at: string | null; token_hash: string;
};

const now = new Date();
const future = new Date(now.getTime() + 86_400_000).toISOString();
const past = new Date(now.getTime() - 86_400_000).toISOString();
const principal: Principal = { tenantId: "tenant-a", kind: "app", scopes: ["todo:read", "todo:write"], tokenHash: "app-hash" };
const grantId = "22222222-2222-4222-8222-222222222222";

function environment(): { env: Env; grants: Grant[] } {
  const grants: Grant[] = [
    { id: grantId, tenant_id: "tenant-a", kind: "mcp", label: "MCP · Claude", scopes: "todo:read todo:write",
      created_at: past, last_used_at: null, expires_at: future, revoked_at: null, token_hash: "secret-hash" },
    { id: "33333333-3333-4333-8333-333333333333", tenant_id: "tenant-b", kind: "mcp", label: "MCP · Other",
      scopes: "todo:read", created_at: past, last_used_at: null, expires_at: future, revoked_at: null, token_hash: "other-hash" },
    { id: "44444444-4444-4444-8444-444444444444", tenant_id: "tenant-a", kind: "app", label: "Phone",
      scopes: "todo:read todo:write", created_at: past, last_used_at: null, expires_at: future, revoked_at: null, token_hash: "phone-hash" },
  ];
  const env = {
    PUBLIC_ORIGIN: "https://api.00todo.com",
    DB: { prepare(sql: string) {
      return { bind(...args: string[]) {
        return {
          async all() {
            expect(sql).toContain("tenant_id = ? AND kind = 'mcp'");
            return { results: grants.filter((grant) => grant.tenant_id === args[0] && grant.kind === "mcp"
              && grant.revoked_at === null && grant.expires_at > args[1]) };
          },
          async run() {
            expect(sql).toContain("tenant_id = ? AND kind = 'mcp'");
            const grant = grants.find((item) => item.id === args[1] && item.tenant_id === args[2]
              && item.kind === "mcp" && item.revoked_at === null && item.expires_at > args[3]);
            if (grant) grant.revoked_at = args[0];
            return { meta: { changes: grant ? 1 : 0 } };
          },
        };
      } };
    } } as unknown as D1Database,
  } as Env;
  return { env, grants };
}

describe("app-owned MCP connections", () => {
  it("lists only active grants for this tenant without exposing credential hashes", async () => {
    const { env } = environment();
    const response = await listMcpConnections(env, principal);
    const payload = await response.json() as { connections: Array<Record<string, unknown>> };
    expect(payload.connections).toHaveLength(1);
    expect(payload.connections[0]).toMatchObject({ id: grantId, clientName: "Claude", scopes: ["todo:read", "todo:write"] });
    expect(JSON.stringify(payload)).not.toContain("secret-hash");
  });

  it("cannot disconnect another tenant's grant and revokes its own immediately", async () => {
    const { env, grants } = environment();
    expect((await disconnectMcpConnection(env, principal, grants[1].id)).status).toBe(404);
    expect(grants[1].revoked_at).toBeNull();
    expect((await disconnectMcpConnection(env, principal, grantId)).status).toBe(200);
    expect(grants[0].revoked_at).not.toBeNull();
    expect((await listMcpConnections(env, principal).then((response) => response.json()) as { connections: unknown[] }).connections).toEqual([]);
  });

  it("does not let an MCP principal manage app connections", async () => {
    const { env } = environment();
    const mcp: Principal = { ...principal, kind: "mcp" };
    expect((await listMcpConnections(env, mcp)).status).toBe(403);
    expect((await disconnectMcpConnection(env, mcp, grantId)).status).toBe(403);
  });
});

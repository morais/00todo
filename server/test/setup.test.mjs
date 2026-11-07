import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync } from "node:fs";
import { signInWithApple } from "../src/appAuth";
import { accountSetup } from "../src/setup";
import { findOrCreateTenant, issueCredential } from "../src/auth";
import { routeApi } from "../src/api";
import { routeMcp } from "../src/mcp";
import { sweepExpiredAuthData } from "../src/cleanup";
import { verifyNativeAppleLogin } from "../src/apple";

vi.mock("../src/apple", async (original) => ({
  ...await original(), verifyNativeAppleLogin: vi.fn(),
}));

const origin = "https://api.00todo.com";
const first = "2026-11-07T12:00:00.000Z";
const migrations = new URL("../migrations/", import.meta.url);
const migrationNames = readdirSync(migrations).filter((name) => name.endsWith(".sql")).sort();
let sqlite;
let env;

// Exercise the real SQL and migrations, including D1 batch atomicity.
function statement(sql, args = []) {
  return {
    bind: (...values) => statement(sql, values),
    async first(column) {
      const row = sqlite.prepare(sql).get(...args);
      return column ? row?.[column] ?? null : row ?? null;
    },
    async all() { return { results: sqlite.prepare(sql).all(...args) }; },
    async run() {
      const result = sqlite.prepare(sql).run(...args);
      return { meta: { changes: Number(result.changes) } };
    },
  };
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(first);
  sqlite = new DatabaseSync(":memory:");
  sqlite.exec("PRAGMA foreign_keys = ON");
  for (const name of migrationNames.filter((name) => !name.startsWith("0014_"))) {
    sqlite.exec(readFileSync(new URL(name, migrations), "utf8"));
  }
  env = {
    PUBLIC_ORIGIN: origin, APP_NAME: "00Todo", APPLE_APP_CLIENT_ID: "com.00todo.app", APPLE_PRIVATE_KEY: "test",
    DB: {
      prepare: statement,
      async batch(statements) {
        sqlite.exec("BEGIN");
        try {
          const results = [];
          for (const query of statements) results.push(await query.run());
          sqlite.exec("COMMIT");
          return results;
        } catch (error) { sqlite.exec("ROLLBACK"); throw error; }
      },
    },
  };
});

afterEach(() => {
  sqlite.close();
  vi.restoreAllMocks();
  vi.resetAllMocks();
  vi.useRealTimers();
});

function migrate() {
  sqlite.exec(readFileSync(new URL("0014_native_sign_in.sql", migrations), "utf8"));
}

function tenant(id) {
  sqlite.prepare("INSERT INTO tenants (id, apple_subject, email, created_at, updated_at) VALUES (?, ?, ?, ?, ?)")
    .run(id, `subject-${id}`, `${id}@example.com`, first, first);
  return { tenantId: id, kind: "mcp", scopes: ["todo:read", "todo:write"], tokenHash: "test" };
}

function marker(id) {
  return sqlite.prepare("SELECT native_first_signed_in_at AS value FROM tenants WHERE id = ?").get(id).value;
}

function nativeRequest() {
  return new Request(`${origin}/v1/auth/apple`, { method: "POST", body: JSON.stringify({
    identityToken: "t".repeat(100), authorizationCode: "code", nonce: "n".repeat(32),
  }) });
}

async function rpc(principal, method, params) {
  return routeMcp(new Request(`${origin}/mcp`, { method: "POST", body: JSON.stringify({
    jsonrpc: "2.0", id: 1, method, params,
  }) }), env, principal);
}

describe("account setup evidence", () => {
  it("backfills only the earliest reliable native credential, including expired/revoked records", async () => {
    tenant("native"); tenant("web"); tenant("swept"); tenant("invalid");
    const seed = sqlite.prepare(`INSERT INTO credentials
      (token_hash, tenant_id, kind, audience, scopes, label, created_at, expires_at, revoked_at)
      VALUES (?, ?, ?, ?, 'todo:read', 'iOS app', ?, ?, ?)`);
    seed.run("n1", "native", "app", `${origin}/v1`, "2026-10-02T00:00:00.000Z", "2026-10-03T00:00:00.000Z", null);
    seed.run("n2", "native", "app", `${origin}/v1`, "2026-10-01T00:00:00.000Z", "2027-01-01T00:00:00.000Z", first);
    seed.run("w1", "web", "mcp", `${origin}/mcp`, "2026-09-01T00:00:00.000Z", "2027-01-01T00:00:00.000Z", null);
    seed.run("bad", "invalid", "app", `${origin}/v1`, "not-a-date", "2027-01-01T00:00:00.000Z", null);
    migrate();
    expect(marker("native")).toBe("2026-10-01T00:00:00.000Z");
    for (const id of ["web", "swept", "invalid"]) expect(marker(id)).toBeNull();
  });

  it("moves only the verified native account from unknown to ready and preserves its first sign-in", async () => {
    migrate();
    const native = tenant("native");
    const other = tenant("other");
    expect((await accountSetup(env, native, "list_tasks")).status).toBe("unknown");
    verifyNativeAppleLogin.mockResolvedValue({ claims: { sub: "subject-native" } });
    expect((await signInWithApple(nativeRequest(), env)).status).toBe(201);
    expect(marker("native")).toBe(first);
    expect(await accountSetup(env, native, "list_tasks")).toEqual({ status: "ready", optional: true });
    expect((await accountSetup(env, other, "list_tasks")).status).toBe("unknown");
    vi.setSystemTime("2026-11-08T12:00:00.000Z");
    expect((await signInWithApple(nativeRequest(), env)).status).toBe(201);
    expect(marker("native")).toBe(first);
    sqlite.exec("UPDATE credentials SET revoked_at = '2026-11-08T12:00:00.000Z'");
    await sweepExpiredAuthData(env);
    expect(marker("native")).toBe(first);
  });

  it("does not mark failed Apple verification or a failed credential transaction", async () => {
    migrate(); tenant("native");
    vi.spyOn(console, "warn").mockImplementation(() => {});
    verifyNativeAppleLogin.mockRejectedValueOnce(new Error("invalid native token"));
    expect((await signInWithApple(nativeRequest(), env)).status).toBe(401);
    expect(marker("native")).toBeNull();
    verifyNativeAppleLogin.mockResolvedValue({ claims: { sub: "subject-native" } });
    sqlite.exec(`CREATE TRIGGER fail_marker BEFORE UPDATE OF native_first_signed_in_at ON tenants
      BEGIN SELECT RAISE(ABORT, 'test failure'); END;`);
    expect((await signInWithApple(nativeRequest(), env)).status).toBe(401);
    expect(marker("native")).toBeNull();
    expect(sqlite.prepare("SELECT count(*) AS count FROM credentials").get().count).toBe(0);
  });

  it("leaves dashboard and plugin sign-ins unknown, even when the account contains tasks", async () => {
    migrate();
    for (const source of ["dashboard", "mcp"]) {
      const user = await findOrCreateTenant(env, `subject-${source}`, null, { source });
      if (source === "mcp") await issueCredential(env, user.id, "mcp", "ChatGPT");
      expect(marker(user.id)).toBeNull();
    }
    const user = tenant("tasks");
    await routeApi(new Request(`${origin}/v1/tasks`, { method: "POST", body: JSON.stringify({ title: "Chat-created" }) }), env, user);
    expect((await accountSetup(env, user, "list_tasks")).status).toBe("unknown");
  });

  it("recognises only allowlisted reviewers with an active reviewer credential", async () => {
    migrate();
    const reviewer = tenant("reviewer");
    env.REVIEW_TENANT_IDS = "other, reviewer ";
    expect((await accountSetup(env, reviewer, "list_tasks")).status).toBe("unknown");
    sqlite.prepare(`INSERT INTO review_credentials (token_hash, tenant_id, label, created_at, expires_at)
      VALUES ('review', 'reviewer', 'Prepared reviewer', ?, '2027-01-01T00:00:00.000Z')`).run(first);
    expect((await accountSetup(env, reviewer, "list_tasks")).status).toBe("ready");
    expect(marker("reviewer")).toBeNull();
    env.REVIEW_TENANT_IDS = "other";
    expect((await accountSetup(env, reviewer, "list_tasks")).status).toBe("unknown");
    env.REVIEW_TENANT_IDS = "reviewer";
    sqlite.exec("UPDATE review_credentials SET expires_at = '2026-01-01T00:00:00.000Z'");
    expect((await accountSetup(env, reviewer, "list_tasks")).status).toBe("unknown");
    sqlite.exec("UPDATE review_credentials SET expires_at = '2027-01-01T00:00:00.000Z', revoked_at = '2026-11-07T00:00:00.000Z'");
    expect((await accountSetup(env, reviewer, "list_tasks")).status).toBe("unknown");
  });
});

describe("existing MCP read responses", () => {
  it("preserves tenant data and adds optional, private guidance to both response formats", async () => {
    migrate();
    const user = tenant("user");
    const other = tenant("other");
    for (const principal of [user, other]) {
      for (const [path, input] of [["tasks", { title: `${principal.tenantId} task` }], ["projects", { name: `${principal.tenantId} project` }]]) {
        const response = await routeApi(new Request(`${origin}/v1/${path}`, { method: "POST", body: JSON.stringify(input) }), env, principal);
        expect(response.status).toBe(201);
      }
    }
    for (const [tool, key] of [["list_tasks", "tasks"], ["list_projects", "projects"]]) {
      const response = await rpc(user, "tools/call", { name: tool, arguments: { view: "all" } });
      const { result } = await response.json();
      const rest = await routeApi(new Request(`${origin}/v1/${key}?view=all`), env, user);
      const { setup, ...data } = result.structuredContent;
      expect(data).toEqual(await rest.json());
      expect(data[key]).toHaveLength(1);
      expect(JSON.stringify(data)).not.toContain("other task");
      expect(JSON.stringify(data)).not.toContain("other project");
      expect(JSON.parse(result.content[0].text)).toEqual(result.structuredContent);
      expect(setup).toMatchObject({ status: "unknown", optional: true, appStoreUrl: "https://apps.apple.com/app/id6816729167" });
      expect(setup.question).toContain("already configured");
      expect(setup.instructions.join(" ")).toContain("same Apple account");
      expect(setup.instructions.join(" ")).toContain(`${tool} again`);
      expect(setup.instructions.join(" ")).toContain("Keep the plugin connected");
      expect(JSON.stringify(setup)).not.toMatch(/subject-user|user@example.com|tenantId|native_first_signed_in_at|token_hash/);
    }
    const { result } = await (await rpc(user, "tools/call", { name: "create_task", arguments: { title: "Still usable" } })).json();
    expect(result.structuredContent).not.toHaveProperty("setup");
    expect(result.structuredContent.task.title).toBe("Still usable");
    for (const method of ["initialize", "tools/list"]) {
      const body = await (await rpc(user, method, {})).json();
      expect(JSON.stringify(body)).not.toMatch(/appStoreUrl|finish_setup|native_first_signed_in_at/);
    }
    const denied = { ...user, scopes: ["todo:write"] };
    expect((await rpc(denied, "tools/call", { name: "list_tasks", arguments: {} })).status).toBe(403);
    const invalid = await (await rpc(user, "tools/call", { name: "list_tasks", arguments: { view: "bad" } })).json();
    expect(invalid.error.code).toBe(-32602);
    const failed = await (await rpc(user, "tools/call", { name: "list_tasks", arguments: { today: "bad-date" } })).json();
    expect(failed.result.isError).toBe(true);
    expect(failed.result).not.toHaveProperty("structuredContent");
    expect(JSON.stringify(failed)).not.toContain("appStoreUrl");
    verifyNativeAppleLogin.mockResolvedValue({ claims: { sub: "subject-user" } });
    expect((await signInWithApple(nativeRequest(), env)).status).toBe(201);
    // Recheck through the exact same tools and existing MCP principal.
    for (const tool of ["list_tasks", "list_projects"]) {
      const { result } = await (await rpc(user, "tools/call", { name: tool, arguments: {} })).json();
      expect(result.structuredContent.setup).toEqual({ status: "ready", optional: true });
      expect(JSON.parse(result.content[0].text)).toEqual(result.structuredContent);
    }
  });
});
